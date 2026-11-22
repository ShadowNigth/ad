"""Work out which Euler order the arms SMD `skeleton` block uses, from geometry alone.

A Bip01 rig has a hard convention: a bone's local +X points down the bone, so
  (a) the child's head lies along the parent's +X axis, and
  (b) the vertices weighted to a bone sit near that bone's +X axis.
Both angles are order-sensitive, so the euler order that minimises them is the one the file
was written with.  Rotation-only comparison (position alone is order-independent).
"""
import math
import re
import sys
from pathlib import Path

import numpy as np

TOK = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")


def load(path):
    nodes, par, pose = [], [], {}
    tri_pose = []          # (bone_index, position) straight out of the inline triangles block
    sec = None
    for raw in Path(path).read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        low = line.lower()
        if low == "end":
            sec = None
            continue
        if low in ("nodes", "skeleton", "triangles", "vertices"):
            sec = low
            continue
        if sec == "nodes":
            m = re.match(r'(\d+)\s+"([^"]*)"\s+(-?\d+)', line)
            if m:
                nodes.append(m.group(2))
                par.append(int(m.group(3)))
        elif sec == "skeleton":
            if low.startswith("time"):
                continue
            v = [float(x) for x in TOK.findall(line)]
            if len(v) >= 7 and v[0] == int(v[0]):
                pose[int(v[0])] = (np.array(v[1:4]), np.array(v[4:7]))
        elif sec == "triangles":
            v = [float(x) for x in TOK.findall(line)]
            if len(v) >= 9 and v[0] == int(v[0]):
                tri_pose.append((int(v[0]), np.array(v[1:4])))
    return nodes, par, pose, tri_pose


def rotmat(e, order):
    cx, sx = math.cos(e[0]), math.sin(e[0])
    cy, sy = math.cos(e[1]), math.sin(e[1])
    cz, sz = math.cos(e[2]), math.sin(e[2])
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    by_axis = {"X": Rx, "Y": Ry, "Z": Rz}
    R = np.eye(3)
    for ax in order:                      # Blender 'XYZ' == Rz @ Ry @ Rx
        R = by_axis[ax] @ R
    return R


def world(nodes, par, pose, order):
    W = {}
    for k in range(len(nodes)):
        loc, eul = pose.get(k, (np.zeros(3), np.zeros(3)))
        M = np.eye(4)
        M[:3, :3] = rotmat(eul, order)
        M[:3, 3] = loc
        p = par[k]
        W[k] = M if (p < 0 or p not in W) else W[p] @ M
    return W


def angle(a, b):
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na < 1e-9 or nb < 1e-9:
        return None
    return math.degrees(math.acos(float(np.clip(abs(float(a @ b)) / (na * nb), -1.0, 1.0))))


def report(path):
    nodes, par, pose, tri = load(path)
    print(f"== {Path(path).name}: {len(nodes)} bones, {len(pose)} pose rows, "
          f"{len(tri)} inline verts")
    for order in ("XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX"):
        W = world(nodes, par, pose, order)
        chain, verts = [], []
        for k in range(len(nodes)):
            p = par[k]
            if 0 <= p < k:
                a = angle(W[k][:3, 3] - W[p][:3, 3], W[p][:3, 0])
                if a is not None:
                    chain.append(a)
        by_bone = {}
        for bi, pos in tri:
            by_bone.setdefault(bi, []).append(pos)
        for bi, pts in by_bone.items():
            if bi not in W:
                continue
            origin = W[bi][:3, 3]
            xaxis = W[bi][:3, 0]
            for pt in pts:
                a = angle(np.asarray(pt) - origin, xaxis)
                if a is not None:
                    verts.append(a)
        c = np.array(chain) if chain else np.zeros(1)
        v = np.array(verts) if verts else np.zeros(1)
        print(f"   {order}: bone-chain median {np.median(c):6.2f}deg  "
              f"| mesh-vs-bone median {np.median(v):6.2f}deg  mean {v.mean():6.2f}  "
              f"(n={len(v)})")


if __name__ == "__main__":
    for f in sys.argv[1:]:
        report(f)
