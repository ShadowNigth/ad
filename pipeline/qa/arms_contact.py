"""Does the merged arms mesh actually reach the weapon, in the built .blend?

`arms_bind.py` proves the mesh is *intact*; this proves it is in the right *place*.  Both are needed:
a rigid bind can be perfectly intact and floating 20 inches off the grip, which is exactly what the
archi arms SMDs do at rest (their bind pose is a spread A-pose, and the weapon's animation carries
the hands to the gun only in the middle of a clip).

Reads the evaluated (posed, modifier-applied) vertices out of the .blend -- never the rest bound --
and reports the nearest distance from each arms mesh to the weapon mesh.

    LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/qa/arms_contact.py \\
        --blend /tmp/dist/m_cs2_ak47/v_rif_ak47.blend

    [contact] ak47_reload f37
        Ct_Arms_ct_3: min  0.41  p10  1.02  median  12.31  frac<6in  21.4%
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

sys.argv[0] = "blender"
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import bpy                                           # noqa: E402


def verts(ob):
    """World-space, armature-modifier-applied vertices of `ob` at the current frame."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    n = len(me.vertices)
    if n == 0:
        ev.to_mesh_clear()
        return np.zeros((0, 3))
    P = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", P)
    P = P.reshape(n, 3)
    M = np.array(ev.matrix_world)
    ev.to_mesh_clear()
    return P @ M[:3, :3].T + M[:3, 3]


def is_arms(ob):
    """The builder tags every arms mesh with `arms_*` custom properties; that tag, not the vertex
    count or the name, is what tells arms from weapon.  "the densest mesh is the gun" was wrong
    twice over: the ak47's gun has 21 756 verts against the sleeves' 1 406 so it happened to work,
    but a weapon split across meshes counted its own other parts as arms and reported the
    meaningless 0.00 in a gun always sits next to itself."""
    if any(str(k).startswith("arms_") for k in ob.keys()):
        return True
    n = ob.name.lower()
    return "arms" in n or "glove" in n


def auto_frames():
    """Rest, plus this file's own idle / reload-or-fire / draw frames, via the fitter's rule."""
    try:
        import arm_fit
        score, holdout = arm_fit.pick_frames(score=True, holdout=True)
    except Exception:                                    # noqa: BLE001 - fall back to rest only
        score, holdout = None, None
    pairs = [("", 1)] + list(score or []) + list(holdout or [])
    return ",".join(f"{a}:{f}" for a, f in pairs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", required=True)
    ap.add_argument("--gun", default="", help="weapon mesh names, comma-separated "
                                              "(default: every mesh not tagged as arms)")
    ap.add_argument("--arms", default="", help="arms mesh names, comma-separated (default: by tag)")
    ap.add_argument("--frames", default="auto",
                    help="comma-separated ACTION:FRAME pairs, or 'auto' for this file's own clips; "
                         "an empty action name is the rest pose")
    ap.add_argument("--min-in", type=float, default=0.0,
                    help="fail if the closest arms vertex never comes within this many inches of "
                         "the weapon at any sampled frame (0 disables the gate)")
    a = ap.parse_args()

    blend = Path(a.blend).resolve()
    if not blend.is_file():
        raise SystemExit(f"no such .blend: {blend}")
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if arm is None or not meshes:
        raise SystemExit("the .blend has no armature or no meshes")
    named = lambda spec: [n for n in spec.split(",") if n.strip()]
    arms = [m for m in meshes if m.name in named(a.arms)] if a.arms else [m for m in meshes if is_arms(m)]
    guns = [m for m in meshes if m.name in named(a.gun)] if a.gun else \
        [m for m in meshes if m not in arms]
    if not arms:
        raise SystemExit("no mesh in this .blend is tagged as arms -- the pack was built --no-arms, "
                         "so there is nothing to place")
    print(f"[contact] {blend.name}: weapon = {len(guns)} mesh(es) "
          f"({sum(len(g.data.vertices) for g in guns)} verts), "
          f"arms = {len(arms)} mesh(es) ({sum(len(o.data.vertices) for o in arms)} verts)")
    if a.frames.strip() == "auto":
        a.frames = auto_frames()
        print(f"[contact] frames from the file's own clips: {a.frames}")
    closest = np.inf
    for spec in a.frames.split(","):
        act_name, _, fr = spec.partition(":")
        fr = int(fr or 1)
        if act_name:
            act = bpy.data.actions.get(act_name) or bpy.data.actions.get("@" + act_name)
            if act is None:
                print(f"[contact] no action {act_name!r}, skipping")
                continue
            arm.animation_data.action = act
            bpy.context.scene.frame_set(fr)
        else:
            arm.animation_data.action = None
            for pb in arm.pose.bones:
                pb.matrix_basis.identity()
        bpy.context.view_layer.update()
        G = np.concatenate([verts(g) for g in guns if len(verts(g))])
        if len(G) == 0:
            raise SystemExit("the weapon meshes evaluated to nothing -- the import is broken")
        Gsub = G[::17]
        print(f"[contact] {act_name or 'REST'} f{fr}")
        for ob in arms:
            A = verts(ob)
            if len(A) == 0:
                print(f"    {ob.name}: empty")
                continue
            d = np.linalg.norm(A[:, None, :] - Gsub[None, :, :], axis=2).min(1)
            closest = min(closest, float(d.min()))
            print(f"    {ob.name:24s} min {d.min():6.2f}  p10 {np.percentile(d, 10):6.2f}  "
                  f"median {np.median(d):7.2f}  frac<6in {np.mean(d < 6) * 100:5.1f}%")
    ok = not (a.min_in > 0 and closest > a.min_in)
    print(f"[contact] closest arms-to-weapon distance over all samples: {closest:.2f} in "
          f"-> {'PASS' if ok else 'FAIL'}")
    sys.stdout.flush()
    os._exit(0 if ok else 1)                         # bpy's atexit aborts headless on 4.5


if __name__ == "__main__":
    main()
