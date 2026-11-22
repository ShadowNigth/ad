"""Solve the one unknown the arms SMDs leave behind: a constant offset relative to the weapon.

`build_pack.py` binds the archi arm/glove meshes to the weapon's own `v_weapon.Bip01_*` bones, which
is the only sane thing to do -- those bones are exactly what the animation uses to move the hands.
It still leaves the gloves about 6 model-inches from the grip, and *identically* in idle, fire and
reload: a rigid offset, not a bad pose.  That is the missing reference-frame conform.  The loose
SMDs are exported in the arms' own authoring space, and the compiled arms model they belong to is
not in this pack, so the transform that maps one space onto the other cannot be read from a file.

But it can be solved, because the animation over-determines it: the hands are on the weapon in every
frame of every clip, so exactly one translation makes that true for all of them at once.  This fits
it by coordinate descent on a shrinking step.  The score is the mean, over the arms parts, of
`max(0, nearest_gap - clearance)` at a frame, and the *worst* frame counts -- averaging over frames
lets one clip be fixed by breaking another, and `min` over the whole assembly is trivially achieved by
the sleeve elbow sliding the gloves off.  `clearance` (0.5 in) is the hinge, not 0: fitted "as close
as possible" buries the gloves inside the rifle and every contact report still reads PASS.

Frames come from `pick_frames`, i.e. from the model's own clips (three: a reload mid-frame, a
fire/attack mid-frame, and the longest remaining clip), and three more are held back as a check that
the offset is a conform rather than a fit to what it saw.  Ak47 pack: 12.32 -> 2.54 in over the
scored frames, 11.72 -> 2.49 in over the unseen ones, `offset [11.60 -11.21 -0.04] in`.

Where a weapon's hands and its prop genuinely separate between clips, no translation reaches and
that is the answer -- the kukri's blade rides `weapon_hand_r` while the sleeve follows the arm chain,
so its best offset (`25.57 -> 11.79 in` scored) *worsens* the frames it never saw (20.23 -> 22.41),
and `build_pack` refuses to apply it.  Rotation is never fitted for the same reason in miniature: the
meshes are skinned per bone, so a fitted rotation would stack on top of whatever orientation the bone
already carries.  A translation is the one degree of freedom invariant to the pose.

Application is into the **mesh data** (`shift_meshes`), each offset rotated by the inverse world
rotation of its own mesh so it stays rigid against the bone the part is bound to -- right at every
frame, not just the fitted one.  It is not a `object.location`, and that is not a style choice: the
glTF exporter drops `translation` on any node carrying a `skin`, so an object-level shift looks correct
in the .blend (and in a Workbench render of it) and silently vanishes from the .glb.  Measured, not
assumed: the .blend kept `location [12.734 -10.0 -1.25]` while the exported node had
`translation: None`, which is how this bug was found.

Run inside headless Blender:

    LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/arm_fit.py \\
        --blend dist/m_cs2_ak47/v_rif_ak47.blend [--write]

`--write` re-measures the applied mesh and refuses to save if the file did not get better, so a dry
run and a written run cannot disagree.
"""
from __future__ import annotations

import numpy as np

# Only used as a fallback and in the docs: the real clip names differ per weapon (`@ak47_reload`
# vs `a_reload`), so `pick_frames` reads them out of the file instead.
DEFAULT_SCORE = (("ak47_idle", 1), ("ak47_reload", 37), ("ak47_fire1", 12))
DEFAULT_HOLDOUT = (("ak47_draw", 15), ("ak47_reload", 70), ("lookat01", 69))

# Which clips to score, by name, in order: an idle frame, a reload mid-frame and a firing frame are
# three genuinely different hand placements, which is what makes a single translation over-determined.
SCORE_KEYS = (("idle", "base"), ("reload",), ("fire", "shoot", "priming"))
# Held back from the fit.  If these do not improve too, the offset is real and not fitted to
# whichever three frames it saw.
HOLDOUT_KEYS = (("draw", "deploy", "finish"), ("lookat", "bullet", "inspect", "he"), ("idle",))


def _file_clips():
    """`[(name, n_frames)]` for the real baked actions in the open file, longest first."""
    import bpy
    return sorted(((a.name, int(round(a.frame_range[1]))) for a in bpy.data.actions
                   if "_empty" not in a.name.lower() and a.frame_range[1] >= 1),
                  key=lambda x: (-x[1], x[0]))


# Roles, in order.  A reload and a firing pose put the hands somewhere genuinely different, which
# is what makes one translation over-determined; `attack`/`hit`/`miss` are the knife's, `deploy`
# the grenade's.  Static 1-3 frame clips are excluded from *clip* selection below, because fitting
# to one of those is fitting to a single pose.
ROLE_KEYS = (("reload", "mag", "clip"), ("fire", "shoot", "attack", "hit", "miss", "priming"),
             ("idle", "lookat", "base", "deploy", "draw"))


def pick_frames(score=True, holdout=False):
    """`(score_frames, holdout_frames)` chosen from the actions actually in the file.

    Hardcoding `ak47_*` names was wrong for every other weapon: the sampler silently kept the
    previously active action and re-used it at three arbitrary frames, so the "over-determined"
    fit was fitted to one pose.  Matching names alone was not enough either -- the kukri has no
    `reload`/`fire` clip and only a 1-frame `idle1`, so it scored exactly one frame and the offset
    that nails `idle1` pushes the gloves 20 in off in `lookat01` (the holdout said so, and
    `build_pack`'s re-measure refused to apply it).

    So the rule is about *frames*, not clips: three pairs, spread over as many distinct clips as the
    file has and over its timeline when it has only one.  Scored pairs come from role-matched clips
    where possible; holdout pairs are always a clip or a frame region the score did not touch.
    """
    clips = _file_clips()
    if not clips:
        return [], []
    moving = [(nm, fr) for nm, fr in clips if fr >= 4]
    pool = moving or clips

    def spread(fr, k):
        """`k` frame numbers inside a clip: 1 + the 1/4, 1/2, 3/4, last marks it has room for."""
        marks = [max(1, fr // 2), max(1, fr // 4), max(1, (3 * fr) // 4), 1, max(1, fr - 1)]
        out = []
        for f in marks:
            if f not in out:
                out.append(f)
        return out[:max(1, k)]

    # up to 3 clips, role-matched longest-first, then topped up by length
    chosen, used = [], set()
    for keys in ROLE_KEYS:
        for nm, fr in pool:
            if nm in used:
                continue
            if any(k in nm.lower() for k in keys):
                chosen.append((nm, fr))
                used.add(nm)
                break
        if len(chosen) >= 3:
            break
    for nm, fr in pool:
        if len(chosen) >= 3:
            break
        if nm not in used:
            chosen.append((nm, fr))
            used.add(nm)

    score_out, hold_out = [], []
    if score:
        # one frame from each of up to 3 clips; if that is fewer than 3 pairs, take more frames of
        # the longest clip rather than scoring one pose
        score_out = [(nm, spread(fr, 1)[0]) for nm, fr in chosen[:3]]
        if len(score_out) < 3 and chosen:
            nm, fr = chosen[0]
            for f in spread(fr, 4)[1:4]:
                if len(score_out) >= 3:
                    break
                score_out.append((nm, f))
    if holdout:
        held = {(a, f) for a, f in score_out}
        for nm, fr in clips:
            if len(hold_out) >= 3:
                break
            for f in spread(fr, 3):
                if (nm, f) not in held and all(nm != a for a, _ in hold_out):
                    hold_out.append((nm, f))
                    break
        if not hold_out:            # single-clip file: different frames of the same clip
            nm, fr = chosen[0]
            hold_out = [(nm, f) for f in spread(fr, 4)[1:4] if (nm, f) not in held][:2]
    return (score_out or None), (hold_out or None)

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
        """`gun` is one mesh or the whole weapon: the arms have to reach the *weapon*, and a model
        routinely splits its body across meshes (`ump45_cs2_new.smd` + `blank` + the mag-window
        shells), so picking the densest one would align the hands to a piece of it."""
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
        guns = gun if isinstance(gun, (list, tuple)) else [gun]
        self.gun = (np.concatenate([world_verts(g, subsample * 2) for g in guns
                                    if len(g.data.vertices)]) if len(guns) > 1
                    else world_verts(guns[0], subsample * 2))
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


def fit(blend=None, frames=None, holdout=None, verbose=True,
        coarse=5.0, subsample=400, pct=2.0, clearance=0.5, log=None, meshes=None, guns=None):
    """Returns (offset_world, before, after, (hold_before, hold_after))."""
    import bpy
    if blend is not None:
        bpy.ops.wm.open_mainfile(filepath=str(blend))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    all_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if meshes is None:
        meshes = [o for o in all_meshes if "arms" in o.name.lower() or "glove" in o.name.lower()]
    arms_names = {o.name for o in meshes}
    guns = [o for o in (guns or []) if o.name not in arms_names] or \
        [o for o in all_meshes if o.name not in arms_names]
    if not meshes:
        raise RuntimeError("no arms meshes to fit -- was the pack built with arms?")
    if not guns:
        raise RuntimeError("no weapon mesh to fit against")
    frames_d, holdout_d = pick_frames(score=frames is None, holdout=holdout is None)
    frames = frames or frames_d or DEFAULT_SCORE
    holdout = holdout if holdout is not None else (holdout_d or [])
    if not frames:
        raise RuntimeError("no baked actions in this file, so there is nothing to score against")
    say = log or ((lambda *a: print("[arm_fit]", *a)) if verbose else (lambda *a: None))
    scored = [Sample(arm, meshes, guns, a, f, subsample) for a, f in frames]
    held = [Sample(arm, meshes, guns, a, f, subsample) for a, f in (holdout or [])]

    def sc(off, s):
        # Worst frame, not the mean: a shift that nails idle and misses the reload is exactly the
        # over-fitting the hold-out frames exist to catch.
        return max(x.score(off, pct, clearance) for x in s) if s else float("inf")

    def gap_in(off, s, pct):
        """Plain distance (no hinge), for reporting."""
        return max(np.mean([nearest_low(P + off, x.gun, pct) for P, _n in x.parts]) for x in s)

    off, best = np.zeros(3), sc(np.zeros(3), scored)
    per_before = [x.per_part(np.zeros(3), pct) for x in scored]
    say(f"{len(meshes)} arms mesh(es) vs {len(guns)} weapon mesh(es): gap {best:.3f} in over "
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
    # the frames actually scored, so a manifest can record its own provenance: which
    # clips judged the offset is the first thing to know when the result looks wrong
    return off, (g0, g1), hold_res, meshes, guns, [x.label for x in scored]


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


def measure_gap(objs, gun, frames=None, subsample=400, pct=2.0, off=None):
    """The plain mean gap with the meshes as they are now (or shifted by `off`)."""
    import bpy
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    frames = frames or (pick_frames(score=True)[0] or DEFAULT_SCORE)
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
    off, (before, after), hold, meshes, guns, used = fit(blend=blend, pct=a.pct,
                                                          subsample=a.subsample,
                                                          clearance=a.clearance)
    if not a.write:
        print("[arm_fit] dry run (pass --write to store it)")
        raise SystemExit(0)
    # Apply, then re-measure on the *applied* mesh before committing the file: the fit scores a
    # world-space shift while the mesh carries a bone-relative one, and if that distinction ever
    # mattered more than it does, this is where it shows up.
    resid = None
    shift_meshes(meshes, off)
    resid = measure_gap(meshes, guns, None, a.subsample, a.pct)
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
    import blender_exit
    blender_exit.run_and_exit(main)
