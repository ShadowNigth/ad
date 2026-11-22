"""Does an arms SMD's skeleton block describe the *knife* rig or the *rifle* rig?

For each Euler order, accumulate the SMD's world matrices and, per candidate .mdl, accumulate the
model's rest-pose world matrices (same recipe the .mdl itself uses).  Then fit the single global
transform C that best maps one onto the other and report the residual spread: if a rig matches
"up to one global transform" with a near-zero residual, that order is right and that model is the
one the arms were authored against.  A large residual means the two skeletons really are in
different poses, which is what makes a plain name-bind explode.
"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, "/home/user/ad/pipeline")
sys.path.insert(0, "/tmp/bl-addons")
sys.path.insert(0, "/tmp/gen")
import os
os.environ.setdefault("NO_BPY", "1")
import smd_euler as E
import source_zanim as Z

ORDERS = ("XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX")


def mdl_world(mdl_path):
    meta = Z.load_model_animations(str(mdl_path), strict=False)["_meta"]
    names, par, bp, br = (meta["bone_names"], meta["parent_index"],
                          meta["base_pos"], meta["base_rot"])
    W = {}
    for i, n in enumerate(names):
        q = br[i]
        w, x, y, z = float(q[3]), float(q[0]), float(q[1]), float(q[2])
        nn = math.sqrt(w * w + x * x + y * y + z * z) or 1.0
        w, x, y, z = w / nn, x / nn, y / nn, z / nn
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                      [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                      [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        M = np.eye(4)
        M[:3, :3] = R
        M[:3, 3] = bp[i]
        p = par[i]
        W[n] = M if (p < 0 or p not in W) else W[names[p]] @ M
    return W


def compare(smd_path, mdl_paths):
    nodes, par, pose, tri = E.load(smd_path)
    print(f"### {Path(smd_path).name}: {len(nodes)} bones")
    for order in ORDERS:
        W = E.world(nodes, par, pose, order)
        smd_by_name = {nodes[k]: W[k] for k in range(len(nodes))}
        for mp in mdl_paths:
            MW = mdl_world(mp)
            shared = [n for n in smd_by_name if n in MW]
            if len(shared) < 5:
                continue
            # fit C as the mean of D_b = M_mdl[b] . M_smd[b]^-1, then measure the spread
            Ds = [MW[n] @ np.linalg.inv(smd_by_name[n]) for n in shared]
            t = np.mean([D[:3, 3] for D in Ds], axis=0)
            Rr = np.mean([D[:3, :3] for D in Ds], axis=0)
            U, _S, Vt = np.linalg.svd(Rr)
            R = U @ Vt
            C = np.eye(4)
            C[:3, :3] = R
            C[:3, 3] = t
            res_t, res_a = [], []
            for n in shared:
                D = MW[n] @ np.linalg.inv(smd_by_name[n])
                res_t.append(np.linalg.norm(D[:3, 3] - t))
                Rd = D[:3, :3]
                RR = np.linalg.inv(R) @ Rd
                res_a.append(math.degrees(math.acos(float(np.clip((np.trace(RR) - 1) / 2,
                                                                   -1, 1)))))
            print(f"   {order} vs {Path(mp).stem:26s} shared {len(shared):3d} | "
                  f"residual pos median {np.median(res_t):8.4f} max {max(res_t):8.4f} | "
                  f"rot median {np.median(res_a):7.2f} max {max(res_a):7.2f}")


if __name__ == "__main__":
    mdl_paths = [Path(p) for p in sys.argv[2:]]
    compare(sys.argv[1], mdl_paths)
