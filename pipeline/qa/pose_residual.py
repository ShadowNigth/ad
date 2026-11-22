"""Does a baked .blend reproduce the Source animation, bone by bone, at a posed frame?

This is the acceptance gate for the bake convention, and it exists because the convention was
wrong once: Blender composes

    pb.matrix = pb.parent.matrix @ inv(parent.bone.matrix_local) @ bone.matrix_local
                @ pb.matrix_basis

so a baked action has to key

    matrix_basis = inv(bone.matrix_local) @ parent.bone.matrix_local
                   @ inv(M[parent]) @ M[bone]

walking parents before children.  The tempting ``inv(bone.matrix_local) @ M`` is only correct for
root bones -- it put every hand bone 178 deg off while the gun (a root bone) looked perfect, which
is why the error needed a numeric gate rather than a look.

Run inside headless Blender (see ../headless_blender_stubs.py for the stub libs):

    LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/qa/pose_residual.py \\
        --blend /tmp/dist/m_cs2_ak47/v_rif_ak47.blend --anim ak47_reload --frame 37

Exit code 1 when the worst residual exceeds --max-deg (default 0.5 deg / 0.05 in).
"""
from __future__ import annotations

import argparse
import math
import os
import sys
from pathlib import Path

sys.argv[0] = "blender"
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
for cand in (str(HERE.parent.parent / "vendor"), "/tmp/bl-addons", os.environ.get("SIO_ADDONS", "")):
    if cand and Path(cand, "SourceIO").is_dir():
        sys.path.insert(0, cand)
        break

import bpy                                          # noqa: E402
import numpy as np                                   # noqa: E402
import mathutils                                     # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", required=True, help="a built <weapon>.blend from build_pack.py")
    ap.add_argument("--mdl", default="", help="source .mdl (default: the one recorded in manifest.json)")
    ap.add_argument("--manifest", default="", help="manifest.json next to the .blend (default: auto)")
    ap.add_argument("--anim", default="ak47_reload")
    ap.add_argument("--frame", type=int, default=37)
    ap.add_argument("--max-deg", type=float, default=0.5)
    ap.add_argument("--max-in", type=float, default=0.05)
    a = ap.parse_args()

    blend = Path(a.blend).resolve()
    if not blend.is_file():
        raise SystemExit(f"no such .blend: {blend}")
    # Two manifests exist and either is enough: `<out>/<pack>/manifest.json`, which travels with the
    # pack (`{"build": {...}}`), and the aggregate at the `--out` root (`{"built": [...]}`).  Prefer
    # the pack's own -- it needs the build tree not to be around any more.
    mdl = Path(a.mdl) if a.mdl else None
    man = Path(a.manifest) if a.manifest else None
    cands = [man] if man else [blend.parent / "manifest.json",
                               blend.parent.parent / "manifest.json"]
    for x in cands:
        if mdl is not None or not x or not x.is_file():
            continue
        import json
        doc = json.loads(x.read_text())
        recs = [doc["build"]] if "build" in doc else list(doc.get("built", []))
        if not recs:
            continue
        rec = next((r for r in recs
                    if r.get("model", "").endswith(blend.stem + ".mdl")
                    or Path(blend.parent, r.get("weapon", "") + ".blend").is_file()
                    or Path(blend.parent.parent, r.get("weapon", ""), blend.name).is_file()),
                   recs[0])
        rel = rec.get("mdl_abs") or ""
        if not (rel and Path(rel).is_file()):
            rel = str(Path(doc.get("src", ".")) / rec.get("model", "")) if rec.get("model") else ""
        mdl = Path(rel) if rel else None
    if mdl is None or not Path(mdl).is_file():
        raise SystemExit("could not locate the source .mdl; pass --mdl")

    bpy.ops.wm.open_mainfile(filepath=str(blend))
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        raise SystemExit("the .blend has no armature")
    # the .mdl spells delta clips "@lookat01" and build_pack names the action after it; accept
    # either form so a name copied out of the manifest works without editing
    stem = a.anim.strip("@")
    act = (bpy.data.actions.get(a.anim) or bpy.data.actions.get("@" + stem)
           or bpy.data.actions.get(stem))
    if act is None:
        raise SystemExit(f"no action {a.anim!r}; have {sorted(x.name for x in bpy.data.actions)[:12]}")
    arm.animation_data.action = act
    bpy.context.scene.frame_set(a.frame)
    bpy.context.view_layer.update()

    os.environ["NO_BPY"] = "1"                     # decode straight from the .mdl, no importer
    import source_zanim as Z
    all_a = Z.load_model_animations(mdl, strict=False)
    meta = all_a["_meta"]
    names, par = meta["bone_names"], meta["parent_index"]
    key = a.anim if a.anim in all_a else "@" + a.anim.strip("@")
    fr = all_a[key]["frames"]
    f = min(a.frame, fr.shape[0]) - 1
    pos, rot = fr["pos"][f], fr["rot"][f]
    M = {}
    for i in range(len(names)):
        q = rot[i]
        L = (mathutils.Matrix.Translation(mathutils.Vector(pos[i]))
             @ mathutils.Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4())
        M[i] = (M[par[i]] @ L) if 0 <= par[i] < len(names) and par[i] in M else L

    def ang(A, B):
        x, y = np.array(A)[:3, :3], np.array(B)[:3, :3]
        return math.degrees(math.acos(float(np.clip((np.trace(x @ y.T) - 1) / 2, -1, 1))))

    rows = []
    for i, nm in enumerate(names):
        pb = arm.pose.bones.get(nm) or arm.pose.bones.get(nm[:63])
        if pb is None:
            continue
        got, want = np.array(pb.matrix), np.array(M[i])
        parent_got = np.array(pb.parent.matrix) if pb.parent else np.eye(4)
        naive_parent_rel = parent_got @ np.array(pb.matrix_basis)   # the *other* wrong rule
        rows.append((nm, ang(got, want), float(np.linalg.norm(got[:3, 3] - want[:3, 3])),
                     ang(naive_parent_rel, want)))
    if not rows:
        raise SystemExit("no decoded bone matched an imported bone -- name mapping is broken")
    rows.sort(key=lambda r: -r[1])
    worst = rows[0]
    print(f"[residual] {key} frame {a.frame} ({f} zero-based): pb.matrix vs .mdl chain data, "
          f"{len(rows)} bones")
    for nm, ang_d, dist, alt in rows[:5]:
        print(f"   {nm:36s} as-baked {ang_d:7.3f} deg / {dist:7.4f} in   "
              f"naive-parent-relative {alt:7.2f} deg")
    print(f"[residual] worst as-baked {max(r[1] for r in rows):.3f} deg / "
          f"{max(r[2] for r in rows):.4f} in   (the naive rule would give "
          f"{max(r[3] for r in rows):.2f} deg)")

    # Second, independent check: a bone whose *local* translation is not animated keeps its
    # distance to its parent.  Bones that do carry a position channel (the twist/attachment ones)
    # legitimately change it, so they are counted separately instead of failing the run.
    bl, bad, moving = arm.data.bones, [], 0
    bp = np.array(meta["base_pos"])
    for i, nm in enumerate(names):
        p = par[i]
        if not (nm in bl and 0 <= p < len(names) and names[p] in bl):
            continue
        still = (np.allclose(pos[i], bp[i], atol=1e-6) and np.allclose(pos[p], bp[p], atol=1e-6))
        if not still:
            moving += 1
            continue
        d_rest = float(np.linalg.norm(np.array(bl[names[p]].matrix_local)[:3, 3]
                                      - np.array(bl[nm].matrix_local)[:3, 3]))
        d_pose = float(np.linalg.norm(np.array(M[p])[:3, 3] - np.array(M[i])[:3, 3]))
        if abs(d_rest - d_pose) > 0.02:
            bad.append((nm, names[p], d_rest, d_pose))
    print(f"[residual] parent-child lengths held ({len(names) - moving - len(bad)} bones), "
          f"{moving} with a position channel exempt, {len(bad)} broken")
    for nm, pn, d0, d1 in bad[:5]:
        print(f"   [broken] {nm} vs {pn}: rest {d0:.3f} -> posed {d1:.3f}")
    fail = worst[1] > a.max_deg or worst[2] > a.max_in or bad
    print(f"[residual] {'FAIL' if fail else 'PASS'} "
          f"(tolerance {a.max_deg} deg / {a.max_in} in)")
    sys.stdout.flush()
    os._exit(1 if fail else 0)                      # bpy's atexit aborts headless on 4.5


if __name__ == "__main__":
    sys.path.insert(0, str(HERE.parent))
    import blender_exit
    blender_exit.run_and_exit(main)
