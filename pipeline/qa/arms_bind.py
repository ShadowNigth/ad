"""Gate for `build_pack.py --arms-bind`: how far does each binding tear the arms mesh?

The archi arm/glove SMDs are decimated reference meshes: one hard bone per vertex, no weight list.
On the CS2 viewmodel rigs that is unskin-able as-is, because the bones named in the files move
against each other (`Bip01_L_ForeTwist` vs `Bip01_L_Forearm` diverge by 72 deg at frame 36 of
`@ak47_reload`; the twist bone is parented to the *root* beside the forearm instead of under it).
So the question is not which rule is correct -- none is -- but which one leaves the mesh intact.

This replays Blender's skinning (v' = sum_b w_b * M_pose[b] @ inv(M_rest[b]) @ v, with the matrices
from the weapon's own .mdl) for every mode and reports the longest triangle edge, which is the
sharpest signal available: an edge authored at 0.26 in that measures 47 in in the pose is a shard.

    LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/qa/arms_bind.py \\
        --arms-dir "/tmp/archi/Sport_gloves/Knife Rig/Ct Arms" --anim @ak47_reload --frame 36

Measured on the ak47 pack's `Ct Arms` folder, `@ak47_reload` frame 36 -- longest posed edge, with
the fraction of edges that grew past 3x their authored length in brackets (model inches):

    file       skinned   rigid    smooth12
    ct_1.smd     1.40     1.40      1.40          (sleeve segments: one bone, so nothing to tear)
    ct_3.smd     3.24     3.24      3.24
    g0.smd      47.98     0.96     10.98 [60.8%]
    g1.smd      48.16     0.59     10.84 [64.2%]
    g2.smd      47.65     2.08      9.61 [28.1%]

`rigid` reproduces each file's rest numbers exactly, because every connected part moves as one
rigid body; `skinned` is the file verbatim and tears the hands into 48-inch spikes; `smooth` spreads
the tear instead of removing it.  Exits 1 if the --check mode's posed edges grow past its rest
edges by more than --rel-tol.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
for cand in (str(HERE.parent.parent / "vendor"), "/tmp/bl-addons", os.environ.get("SIO_ADDONS", "")):
    if cand and Path(cand, "SourceIO").is_dir():
        sys.path.insert(0, cand)
        break
os.environ.setdefault("NO_BPY", "1")                # decode + SMD only, no importer

import arm_skin                                      # noqa: E402
import smd_import                                    # noqa: E402
import source_zanim as Z                             # noqa: E402


def q2R(q):
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def bone_world(bone_names, parent_index, pos, rot, base=False):
    n = len(bone_names)
    W = np.zeros((n, 4, 4))
    for i in range(n):
        M = np.eye(4)
        M[:3, :3] = q2R(rot[i])
        M[:3, 3] = pos[i]
        W[i] = M if parent_index[i] < 0 else W[parent_index[i]] @ M
    return W


def load_bones(mdl, anim, frame):
    all_a = Z.load_model_animations(mdl, strict=False)
    meta = all_a["_meta"]
    names, par = meta["bone_names"], meta["parent_index"]
    rest = bone_world(names, par, np.array(meta["base_pos"]), np.array(meta["base_rot"]))
    key = anim if anim in all_a else "@" + anim.strip("@")
    frames = all_a[key]["frames"]
    f = min(frame, frames.shape[0] - 1)
    pose = bone_world(names, par, frames["pos"][f], frames["rot"][f])
    depth = {}
    for i, nm in enumerate(names):
        d, p = 0, par[i]
        while p is not None and p >= 0:
            d, p = d + 1, par[p]
        depth[nm] = d
    return {b: pose[i] @ np.linalg.inv(rest[i]) for i, b in enumerate(names)}, names, depth, f


def skin(V, rows, delta):
    """Blender's armature modifier: v' = sum_b w_b * (M_pose[b] @ inv(M_rest[b])) @ v."""
    out = np.zeros_like(V)
    for vi, wr in enumerate(rows):
        for bn, w in wr:
            D = delta.get(bn)
            if D is not None and w:
                out[vi] += w * (D[:3, :3] @ V[vi] + D[:3, 3])
    return out


def edge_stats(V, Vp, tri):
    E = np.unique(np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]]), axis=0)
    l0 = np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1)
    l1 = np.linalg.norm(Vp[E[:, 0]] - Vp[E[:, 1]], axis=1)
    return (float(np.median(l0)), float(l0.max()), float(l1.max()),
            float((l1 / np.maximum(l0, 1e-6) > 3.0).mean()))


def rows_for(mode, smd, depth):
    V, tri, vw = smd.vert_pos.astype(np.float64), smd.tri_idx, smd.vert_weights
    if mode == "skinned":
        return vw
    if mode == "rigid":
        dom = arm_skin.bone_matrix(vw, arm_skin.components(len(V), tri), depth)
        return [[(b, 1.0)] if b else [] for b in dom]
    if mode == "side":
        return arm_skin.limb_rows(vw)[0]
    if mode.startswith("smooth"):
        it = int(mode[6:] or 12)
        W, bones = arm_skin.smooth_weights(vw, arm_skin.adjacency(len(V), tri), iters=it)
        return [list(zip(bones, W[vi])) for vi in range(len(V))]
    raise SystemExit(f"unknown mode {mode!r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mdl", default=str(Path("build/content/CS2GO.Pack.Director.s.Cut.-.Rifles/"
                                               "m_cs2_ak47/models/weapons/v_rif_ak47.mdl")))
    ap.add_argument("--arms-dir", required=True, help="an archi `<Rig>/<Side> Arms` folder")
    ap.add_argument("--anim", default="@ak47_reload")
    ap.add_argument("--frame", type=int, default=36)
    ap.add_argument("--modes", default="skinned,rigid,smooth12,side")
    ap.add_argument("--check", default="rigid", help="mode that must satisfy --rel-tol")
    ap.add_argument("--rel-tol", type=float, default=0.02,
                    help="the checked mode fails if any file's longest *posed* edge exceeds its "
                         "longest *rest* edge by more than this fraction -- a rigid bind cannot "
                         "change it at all, and these files' rest edges differ (2.08 in on g2, "
                         "3.24 in on ct_3), so an absolute bound would be meaningless")
    a = ap.parse_args()

    mdl = Path(a.mdl)
    if not mdl.is_absolute():
        mdl = HERE.parent.parent / mdl
    if not mdl.is_file():
        raise SystemExit(f"no such .mdl: {mdl}")
    delta, names, depth, f_used = load_bones(mdl, a.anim, a.frame)
    print(f"[arms-bind] {a.anim} frame {f_used} (asked {a.frame}) on {Path(a.arms_dir).name}, "
          f"model inches")

    files = {}
    for smd_file in sorted(Path(a.arms_dir).glob("*.smd")):
        smd = smd_import.read_smd(smd_file)
        smd.weld_unshared()
        files[smd_file.name] = smd
    modes = a.modes.split(",")
    head = f"{'file':10s} {'mode':9s} {'rest med':>9s} {'rest max':>9s} {'posed max':>10s} " \
           f"{'torn':>6s}"
    print(head)
    worst = (0.0, "")
    for name, smd in files.items():
        V = smd.vert_pos.astype(np.float64)
        for mode in modes:
            Vp = skin(V, rows_for(mode, smd, depth), delta)
            m0, x0, x1, frac = edge_stats(V, Vp, smd.tri_idx)
            print(f"{name:10s} {mode:9s} {m0:9.3f} {x0:9.3f} {x1:10.3f} {frac:5.1%}"
                  + ("   <- checked" if mode == a.check else ""))
            if mode == a.check and x1 > x0 * (1 + a.rel_tol) and x1 / max(x0, 1e-6) > worst[0]:
                worst = (x1 / max(x0, 1e-6), f"{name} posed {x1:.2f} in vs rest {x0:.2f} in")
    ok = not worst[1]
    print(f"[arms-bind] {a.check}: {'no edge grew beyond rest' if ok else worst[1]}"
          f" (tolerance x{1 + a.rel_tol:.2f}) -> {'PASS' if ok else 'FAIL'}")
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
