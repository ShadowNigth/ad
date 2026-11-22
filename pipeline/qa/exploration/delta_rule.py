"""Which composition do CS2 delta (`@`) animations use for a bone's base pose?

`decode_block` seeds every bone with the `mstudiobone_t` pos/quat and then *replaces* it with the
stored value for the bones the block animates.  For an absolute anim that is the engine
behaviour.  For a delta anim the stored value is an *offset from the reference pose*, which the
engine applies on top of the bone's base transform, so simply replacing drops the base and
swings that bone's whole subtree around -- exactly how archi's glove fingers ended up flung
30 inches apart in the merged reload pose while the gun body still looked fine.

Scored per candidate rule:
  drift   worst world-rotation distance from the rest pose over all frames, restricted to the
          arm/hand/finger bones (a viewmodel hand moves, but not by 90+ degrees at once)
  grip    the distance from each hand bone to the gun's root bone over the anim: the hand holds
          the rifle, so this must stay near its rest value; a wrong rule throws the arm away
"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, "/home/user/ad/pipeline")
sys.path.insert(0, "/tmp/bl-addons")
import os
os.environ.setdefault("NO_BPY", "1")
import source_zanim as Z

MDL = Path(sys.argv[1] if len(sys.argv) > 1 else
           "/home/user/ad/build/content/CS2GO.Pack.Director.s.Cut.-.Rifles/"
           "m_cs2_ak47/models/weapons/v_rif_ak47.mdl")
ANIMS = sys.argv[2:] or ["@ak47_reload", "@ak47_fire1", "@ak47_draw", "a_base"]


def qmul(a, b):                                  # wxyz
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return np.array([aw * bw - ax * bx - ay * by - az * bz,
                     aw * bx + ax * bw + ay * bz - az * by,
                     aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw])


def q2R(q):
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def q2e(q):                                      # wxyz -> euler XYZ (matches q2R's convention)
    R = q2R(q)
    sy = float(np.clip(R[0, 2], -1.0, 1.0))
    y = math.asin(sy)
    if abs(sy) < 0.9999:
        return np.array([math.atan2(-R[1, 2], R[2, 2]), y, math.atan2(-R[0, 1], R[0, 0])])
    return np.array([math.atan2(R[2, 1], R[1, 1]), y, 0.0])


def _e2q(e):
    cz, sz = math.cos(e[2] / 2), math.sin(e[2] / 2)
    cy, sy = math.cos(e[1] / 2), math.sin(e[1] / 2)
    cx, sx = math.cos(e[0] / 2), math.sin(e[0] / 2)
    q = qmul(qmul(np.array([cz, 0, 0, sz]), np.array([cy, 0, sy, 0])),
             np.array([cx, sx, 0, 0]))
    return q / np.linalg.norm(q)


all_a = Z.load_model_animations(MDL, strict=False)
meta = all_a["_meta"]
names, par = meta["bone_names"], meta["parent_index"]
bp, br = np.array(meta["base_pos"]), np.array(meta["base_rot"])
n = len(names)
arm_bones = [i for i, nm in enumerate(names)
             if any(t in nm for t in ("Finger", "Hand", "Forearm", "UpperArm", "Clavicle"))]
gun_root = next((i for i, nm in enumerate(names) if nm.endswith("v_weapon")), None)
hands = [i for i, nm in enumerate(names) if nm.endswith("_L_Hand") or nm.endswith("_R_Hand")]

# rest world chain, and rest hand<->gun distance
W = {}
for i in range(n):
    m = np.eye(4)
    m[:3, :3] = q2R(br[i])
    m[:3, 3] = bp[i]
    W[i] = m if par[i] < 0 else W[par[i]] @ m
rest_W = dict(W)
rest_grip = [float(np.linalg.norm(W[h][:3, 3] - W[gun_root][:3, 3])) for h in hands]
print(f"{MDL.name}: {n} bones, {len(arm_bones)} arm/hand bones, "
      f"rest hand-gun distance {np.round(rest_grip,2)}")


def score(pos, rot, nf):
    drift = 0.0
    grip_err = 0.0
    for f in range(nf):
        Wf = {}
        for i in range(n):
            m = np.eye(4)
            m[:3, :3] = q2R(rot[f][i])
            m[:3, 3] = pos[f][i]
            Wf[i] = m if par[i] < 0 else Wf[par[i]] @ m
        for i in arm_bones:
            Ra, Rb = Wf[i][:3, :3], rest_W[i][:3, :3]
            drift = max(drift, math.degrees(math.acos(
                float(np.clip((np.trace(Ra @ Rb.T) - 1) / 2, -1.0, 1.0)))))
        for k, h in enumerate(hands):
            d = float(np.linalg.norm(Wf[h][:3, 3] - Wf[gun_root][:3, 3]))
            grip_err = max(grip_err, abs(d - rest_grip[k]))
    return drift, grip_err


for aname in ANIMS:
    v = all_a.get(aname)
    if v is None or "frames" not in v:
        print(f"  {aname}: unavailable")
        continue
    fr, nf = v["frames"], v["frames"].shape[0]
    delta = bool(v["delta"])
    moved_p = (np.abs(fr["pos"] - bp).max(0) > 1e-7).any(-1)          # bones this anim actually moves
    moved_r = np.array([[abs(1.0 - float(np.dot(fr["rot"][f][i], br[i]))) for i in range(n)]
                        for f in range(nf)]).max(0) > 1e-7
    combos = [("keep", "keep")]
    if delta:
        combos += [("base", "keep"), ("keep", "mul"), ("base", "mul"),
                   ("keep", "mulL"), ("base", "mulL"), ("keep", "euler"), ("base", "euler")]
    for pm, rm in combos:
        pos = np.where(moved_p[None, :, None], (bp + fr["pos"]), fr["pos"]) if pm == "base" \
            else fr["pos"].copy()
        rot = fr["rot"].copy()
        if rm != "keep":
            for f in range(nf):
                for i in range(n):
                    if not moved_r[i]:
                        continue
                    qb, qd = br[i], fr["rot"][f][i]
                    if rm == "mul":
                        q = qmul(qb, qd)
                    elif rm == "mulL":
                        q = qmul(qd, qb)
                    else:
                        q = _e2q(q2e(qb) + q2e(qd))
                    rot[f][i] = q / (np.linalg.norm(q) or 1.0)
        drift, grip = score(pos, rot, nf)
        print(f"  {aname:18s} pos={pm:4s} rot={rm:5s} | arm drift {drift:7.2f}deg | "
              f"hand-gun distance error {grip:7.2f}")
