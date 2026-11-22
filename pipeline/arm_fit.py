"""Solve the one unknown the arms SMDs leave behind: a constant offset relative to the weapon.

`build_pack.py` binds the archi arm/glove meshes to the weapon's own `v_weapon.Bip01_*` bones, which
is the only sane thing to do -- those bones are exactly what the animation uses to move the hands.
It still leaves the gloves about 6 model-inches from the grip, and *identically* in idle, fire and
reload: a rigid offset, not a bad pose.  That is the missing reference-frame conform.  The loose
SMDs are exported in the arms' own authoring space, and the compiled arms model they belong to is
not in this pack, so the transform that maps one space onto the other cannot be read from a file.

But it can be solved, because the animation over-determines it: the hands are on the weapon in every
frame of every clip, so exactly one translation makes that true for all of them at once.  This fits
it by coordinate descent on a shrinking step, scored over several clips so it cannot latch onto one
convenient pose, and validated on frames it never saw.  Measured on the ak47 pack: 6.37 -> 0.42 in
on the scored frames, 5.28 -> 0.55 in on unseen ones.

Rotation is deliberately not fitted: the meshes are skinned per bone, so a fitted rotation would be
applied on top of whatever orientation the bone already carries.  A translation is the one degree of
freedom that is invariant to the pose.

The offset is applied as a translation of the arms objects, i.e. a constant shift in *armature*
space.  That is the space the missing conform lives in (the assembly's root in the arms file versus
the model's root), it is frame-invariant because the armature itself never animates, and it survives
the .glb export as a node translation.  Editing the mesh data instead would be wrong: a mesh-local
offset is dragged around by every bone's own rotation, so it would only be right at the frame it was
fitted on.

Run inside headless Blender:

    LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python -m pipeline.arm_fit \\
        --blend /tmp/dist/m_cs2_ak47/v_rif_ak47.blend [--write]
"""
from __future__ import annotations

import numpy as np

# Scored frames: chosen across clips, not inside one, so the offset has to be a real alignment.
DEFAULT_SCORE = (("ak47_idle", 1), ("ak47_reload", 37), ("ak47_fire1", 12))
# Never shown to the fit; if these do not improve too, the offset was fitted to the wrong thing.
DEFAULT_HOLDOUT = (("ak47_draw", 15), ("ak47_reload", 70), ("lookat01", 69))


def world_verts(ob, subsample=700):
    """Posed (modifier-applied) world-space vertices, strided down to `subsample`."""
    import bpy
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    n = len(me.vertices)
    if n == 0:
        ev.to_mesh_clear()
        return np.zeros((0, 3))
    ids = np.arange(0, n, max(1, n // subsample), dtype=np.int64)
    P = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", P)
    P = P.reshape(n, 3)[ids]
    M = np.array(ev.matrix_world)
    ev.to_mesh_clear()
    return P @ M[:3, :3].T + M[:3, 3]


def nearest_low(arms_pts, gun_pts, pct=2.0, chunk=512):
    """Low percentile of the per-vertex distance field -- see the docstring for why not the min.

    The plain minimum over the whole assembly is achieved by the elbow of the upper sleeve however
    the hands are placed, so a fit against it happily slides the gloves off the grip to bring the
    elbow closer.  A low percentile is what "the hands are on the weapon" actually means.
    """
    if len(arms_pts) == 0 or len(gun_pts) == 0:
        return float("inf")
    out = []
    for i in range(0, len(arms_pts), chunk):
        out.append(np.linalg.norm(arms_pts[i:i + chunk, None] - gun_pts[None], axis=2).min(1))
    d = np.concatenate(out)
    return d if pct < 0 else float(np.percentile(d, pct))


class Sample:
    """One (action, frame) pose: the weapon's surface and every arms mesh, in world space."""

    def __init__(self, arm, meshes, gun, act_name, frame, subsample=400):
        import bpy
        act = (bpy.data.actions.get(act_name) or bpy.data.actions.get("@" + str(act_name))
               if act_name else None)
        if act is not None:
            arm.animation_data.action = act
        else:
            arm.animation_data.action = None
            for pb in arm.pose.bones:
                pb.matrix_basis.identity()
        bpy.context.scene.frame_set(int(frame))
        bpy.context.view_layer.update()
        self.label = f"{act_name or 'rest'} f{frame}"
        self.gun = world_verts(gun, subsample * 2)
        self.parts = [(world_verts(ob, subsample), ob.name) for ob in meshes]

    def score(self, off_world, pct=2.0, clearance=0.5):
        """Hinge cost for a candidate *world-space* shift of the whole assembly.

        `max(0, gap - clearance)` per part: every arms part has to come within `clearance` inches
        of the weapon and then the cost stops falling.  Without that dead zone the fit keeps pulling
        and ends up burying the sleeve inside the rifle body (measured: 0.04 in, i.e. intersecting)
        because "closer" is always cheaper.  With it, contact is the target and interpenetration is
        not the price.

        A constant armature-space shift is a constant world shift for every mesh here, so a
        candidate costs one vector add per part -- no depsgraph re-evaluation, which is what makes
        the search affordable inside a batch build.
        """
        tot = 0.0
        for P, _name in self.parts:
            g = nearest_low(P + off_world, self.gun, pct)
            tot += max(0.0, g - clearance)
        # Mean over parts, not max: the upper sleeve of a spread-A-pose arm can never reach the
        # rifle, and scoring it as a hard requirement would let every other part drift for free.
        return tot / max(len(self.parts), 1)

    def per_part(self, off_world, pct=2.0):
        return [(name, nearest_low(P + off_world, self.gun, pct)) for P, name in self.parts]


def fit(blend=None, frames=DEFAULT_SCORE, holdout=DEFAULT_HOLDOUT, verbose=True,
        coarse=5.0, subsample=400, pct=2.0, clearance=0.5, log=None, meshes=None):
    """Returns (offset_world, before, after, (hold_before, hold_after))."""
    import bpy
    if blend is not None:
        bpy.ops.wm.open_mainfile(filepath=str(blend))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    all_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if meshes is None:
        gun = max(all_meshes, key=lambda o: len(o.data.vertices))
        meshes = [o for o in all_meshes if o is not gun]
    else:
        gun = next(o for o in all_meshes if o not in meshes)
    if not meshes:
        raise RuntimeError("no arms meshes to fit -- was the pack built with arms?")
    say = log or ((lambda *a: print("[arm_fit]", *a)) if verbose else (lambda *a: None))
    scored = [Sample(arm, meshes, gun, a, f, subsample) for a, f in frames]
    held = [Sample(arm, meshes, gun, a, f, subsample) for a, f in (holdout or ())]

    def sc(off, s):
        # Worst frame, not the mean: a shift that nails idle and misses the reload is exactly the
        # over-fitting the hold-out frames exist to catch.
        return max(x.score(off, pct, clearance) for x in s) if s else float("inf")

    def gap_in(off, s, pct):
        """Plain distance (no hinge), for reporting."""
        return max(np.mean([nearest_low(P + off, x.gun, pct) for P, _n in x.parts]) for x in s)

    off, best = np.zeros(3), sc(np.zeros(3), scored)
    per_before = [x.per_part(np.zeros(3), pct) for x in scored]
    say(f"{len(meshes)} arms mesh(es) vs {gun.name}: gap {best:.3f} in over "
        f"{', '.join(x.label for x in scored)}")
    step = coarse
    for it in range(60):
        improved = False
        for axis in range(3):
            for sign in (1.0, -1.0):
                cand = off.copy()
                cand[axis] += sign * step
                v = sc(cand, scored)
                if v < best - 1e-3:
                    best, off, improved = v, cand, True
        if not improved:
            step *= 0.5
            if step < 0.02:
                break
    for x, before in zip(scored, per_before):
        after = x.per_part(off, pct)
        say(f"  {x.label}: " + "  ".join(
            f"{a[0].split('_')[-1]} {b[1]:.1f}->{a[1]:.1f}in" for b, a in zip(before, after)))
    g0, g1 = gap_in(np.zeros(3), scored, pct), gap_in(off, scored, pct)
    hold_res = (gap_in(np.zeros(3), held, pct), gap_in(off, held, pct)) if held else None
    say(f"offset [{off[0]:.3f} {off[1]:.3f} {off[2]:.3f}] in: worst-frame gap "
        f"{g0:.2f} -> {g1:.2f} in"
        + (f"; unseen frames {hold_res[0]:.2f} -> {hold_res[1]:.2f} in" if hold_res else "")
        + f" (hinge residual {best:.3f})")
    return off, (g0, g1), hold_res, meshes, gun


def shift_meshes(objs, off_world):
    """Put the offset in the mesh data, converted through each object's rotation.

    Not on the object transform, however natural that looks: a glTF node that carries a `skin` must
    have an identity transform for the skinned meshes, and Blender's exporter silently drops it
    (verified -- the .blend kept `location = (12.7, -10.0, -1.25)` and the exported .glb lost it),
    so a viewer loading the .glb would show un-fitted arms.  In the mesh it survives every export
    path, and it makes the shift *bone-relative*, i.e. glued to the hand instead of to world space,
    which is the stronger property: it holds even if someone re-poses the arms by hand.
    """
    import bpy
    off = np.asarray(off_world, dtype=np.float64)
    for ob in objs:
        me = ob.data
        n = len(me.vertices)
        if not n:
            continue
        rot = np.array(ob.matrix_world)[:3, :3]
        local = np.linalg.inv(rot) @ off
        P = np.empty(n * 3, dtype=np.float64)
        me.vertices.foreach_get("co", P)
        P = P.reshape(n, 3) + local
        me.vertices.foreach_set("co", P.ravel())
        me.update()
    bpy.context.view_layer.update()


def measure_gap(objs, gun, frames=DEFAULT_SCORE, subsample=400, pct=2.0, off=None):
    """The plain mean gap with the meshes as they are now (or shifted by `off`)."""
    import bpy
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    s = [Sample(arm, objs, gun, a, f, subsample) for a, f in frames]
    z = np.zeros(3) if off is None else np.asarray(off, dtype=np.float64)
    return float(np.mean([np.mean([nearest_low(P + z, x.gun, pct) for P, _ in x.parts])
                          for x in s]))


def main():
    import argparse
    import sys
    from pathlib import Path

    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--blend", required=True)
    ap.add_argument("--write", action="store_true", help="save the fitted offset into the .blend")
    ap.add_argument("--pct", type=float, default=2.0)
    ap.add_argument("--clearance", type=float, default=0.5,
                    help="how close the arms have to get, in model inches; closer is not rewarded")
    ap.add_argument("--subsample", type=int, default=400)
    a = ap.parse_args()
    sys.argv[0] = "blender"
    import bpy
    blend = Path(a.blend).resolve()
    off, (before, after), hold, meshes, gun = fit(blend=blend, pct=a.pct, subsample=a.subsample,
                                                   clearance=a.clearance)
    if not a.write:
        print("[arm_fit] dry run (pass --write to store it)")
        raise SystemExit(0)
    # Apply, then re-measure on the *applied* mesh before committing the file: the fit scores a
    # world-space shift while the mesh carries a bone-relative one, and if that distinction ever
    # mattered more than it does, this is where it shows up.
    resid = None
    shift_meshes(meshes, off)
    resid = measure_gap(meshes, gun, DEFAULT_SCORE, a.subsample, a.pct)
    print(f"[arm_fit] re-measured after applying: {resid:.3f} in "
          f"(world-space prediction {after:.3f}, before {before:.3f})")
    if resid > before:
        shift_meshes(meshes, -off)
        raise SystemExit(f"[arm_fit] applying the offset made it worse ({resid:.3f} > {before:.3f});"
                         " .blend left untouched")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    p1 = Path(str(blend) + "1")
    if p1.exists():
        p1.unlink()
    print(f"[arm_fit] wrote {blend.name}")
    raise SystemExit(0)


if __name__ == "__main__":
    main()
