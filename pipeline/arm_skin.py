"""Skin helpers for the archi arm/glove SMD meshes (see build_pack's ``--arms-bind``).

Why this exists
---------------
`Sport_gloves/<Rig>/<Side> Arms/*.smd` are *collapsed* exports: the `triangles` block carries
exactly three vertex lines per face, each with a single `bone weight` pair, so every vertex is
rigidly bound to one bone.  In the real game the arms are smoothly weighted along the forearm
and across the wrist; here the segmentation is hard.  On the CS2 viewmodel rig that is visible
damage: `Bip01_*_ForeTwist` and `Bip01_*_Forearm` are both parented to the root (their world
motion agrees) while `Bip01_*_Hand` hangs off `Forearm`, and any face straddling a hard seam
between two bones whose relative roll differs tears -- measured 47.7 model-inches on one edge of
`g2.smd` at frame 36 of `@ak47_reload`, against a 2.1-inch longest edge in the rest mesh.

`smooth_weights` fixes that the way a skin painter would: start from the authored bone
assignment (one-hot per vertex) and diffuse the weights over the mesh's edge graph.  Each seam
then blends over a handful of edges instead of snapping, which keeps every triangle's edges
close to their authored length while preserving the *meaning* of the original assignment (cuff
still mostly ForeTwist, glove still mostly Hand, fingers still their own bone).
"""
from __future__ import annotations

import re

import numpy as np

# Within one limb, these bones are interchangeable as the single driver, best first: the wrist
# carries the grip, the forearm carries the sleeve, and the twist corrector is last because on
# these rigs it is animated *absolute* (parented to the root beside the forearm, not under it),
# which is what tears a hard-weighted mesh.
LIMB_PRIORITY = ("Hand", "Forearm", "UpperArm", "ForeTwist", "Twist")
SIDE_RE = re.compile(r"[._](L|R)_([A-Za-z0-9]+)$")


def side_of(bone: str | None):
    """'L'/'R' from a bip01-style bone name (`v_weapon.Bip01_L_Hand` -> 'L'), else None."""
    m = SIDE_RE.search(bone or "")
    return m.group(1).upper() if m else None


def limb_rows(vert_weights: list, anchor_order=LIMB_PRIORITY):
    """One bone per limb, for every vertex: `[(bone, 1.0), ...]` rows.

    The arms SMDs ship one hard bone per vertex (see the module docstring), and the bones they
    pick are mutually inconsistent under the weapon's animation, so any per-vertex split drags
    the mesh apart.  Collapsing each side onto a single limb bone keeps the whole arm rigid: it
    then follows the hand that the animation puts on the grip, which is the part a first-person
    viewer is actually judged on.
    """
    present = {b for rows in vert_weights for b, _w in rows}
    by_side = {}
    for b in present:
        s = side_of(b)
        if not s:
            continue
        tail = SIDE_RE.search(b).group(2)
        rank = next((i for i, key in enumerate(anchor_order) if key.lower() in tail.lower()),
                    len(anchor_order))
        cur = by_side.get(s)
        if cur is None or rank < cur[0]:
            by_side[s] = (rank, b)
    anchor = {s: b for s, (rank, b) in by_side.items()}
    rows_out = []
    for rows in vert_weights:
        picked = None
        for b, _w in sorted(rows, key=lambda kv: -kv[1]):
            s = side_of(b)
            if s and s in anchor:
                picked = anchor[s]
                break
        if picked is None and rows:
            picked = max(rows, key=lambda kv: kv[1])[0]
        rows_out.append([(picked, 1.0)] if picked else [])
    return rows_out, anchor


def adjacency(n_vert: int, tri_idx: np.ndarray) -> list[np.ndarray]:
    """Neighbour index lists from the triangle soup (symmetric, de-duplicated, no self-loops)."""
    nbr = [set() for _ in range(n_vert)]
    for a, b, c in tri_idx:
        a, b, c = int(a), int(b), int(c)
        nbr[a].update((b, c))
        nbr[b].update((a, c))
        nbr[c].update((a, b))
    for s in nbr:
        s.discard(-1)
    return [np.array(sorted(s), dtype=np.int64) for s in nbr]


def components(n_vert: int, tri_idx: np.ndarray) -> np.ndarray:
    """Connected-component id per vertex (union-find over the triangle soup)."""
    parent = list(range(n_vert))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b, c in tri_idx:
        for x, y in ((a, b), (b, c), (c, a)):
            rx, ry = find(int(x)), find(int(y))
            if rx != ry:
                parent[rx] = ry
    _u, comp = np.unique(np.array([find(i) for i in range(n_vert)], dtype=np.int64),
                         return_inverse=True)
    return comp.astype(np.int64)


def bone_matrix(vert_weights: list, comp: np.ndarray | None = None, depth=None):
    """Dominant bone per component (or per vertex when `comp` is None).

    Ties break toward the shallowest bone in the hierarchy, and helper bones whose name carries
    `twist`/`roll`/`deform` are down-weighted: on these rigs the twist corrector is a sibling of
    the forearm rather than its parent, so a part that straddles both would follow the corrector
    and swing away from the limb it belongs to.
    """
    depth = depth or {}

    def score(kv):
        bone, w = kv
        return (0.3 if any(t in bone.lower() for t in ("twist", "roll", "deform", "aim"))
                else 1.0) * w

    def dom(rows):
        counts: dict[str, float] = {}
        for bone, w in rows:
            counts[bone] = counts.get(bone, 0.0) + w
        if not counts:
            return None
        return sorted(counts.items(), key=lambda kv: (-score(kv), depth.get(kv[0], 99), kv[0]))[0][0]

    n = len(vert_weights)
    if comp is None:
        return [dom(vert_weights[i]) for i in range(n)]
    out = {}
    for cid in np.unique(comp):
        sel = np.flatnonzero(comp == cid)
        rows = [w for i in sel for w in vert_weights[i]]
        out[int(cid)] = dom(rows)
    return [out.get(int(c)) for c in comp]


def smooth_weights(vert_weights: list, nbr: list[np.ndarray], iters: int = 4,
                   lam: float = 0.5, keep: float = 0.02):
    """Diffuse the one-hot authored weights over the edge graph.

    Returns (weights, bones): `weights` is a dense (n_vert, n_bone) row-stochastic array, so the
    caller can hand Blender an explicit, normalised weight set per bone.
    """
    bones = sorted({b for rows in vert_weights for b, _w in rows})
    if not bones:
        n = len(vert_weights)
        return np.zeros((n, 0), dtype=np.float64), []
    col = {b: i for i, b in enumerate(bones)}
    W = np.zeros((len(vert_weights), len(bones)), dtype=np.float64)
    for vi, rows in enumerate(vert_weights):
        tot = sum(w for _b, w in rows) or 1.0
        for b, w in rows:
            W[vi, col[b]] += w / tot
    rowsum = W.sum(1, keepdims=True)
    W = np.divide(W, rowsum, out=W, where=rowsum > 0)

    for _ in range(iters):
        acc = W.copy()
        cnt = np.ones(len(W))
        for vi, nb in enumerate(nbr):
            if len(nb):
                acc[vi] += lam * W[nb].sum(0)
                cnt[vi] += lam * len(nb)
        W = acc / cnt[:, None]
        # A bone that ended up negligible only adds vertex-group churn to the export.
        W[W < keep] = 0.0
        rs = W.sum(1, keepdims=True)
        W = np.divide(W, rs, out=W.copy(), where=rs > 0)
    live = W.sum(0) > 0
    return W[:, live], [b for b, on in zip(bones, live) if on]
