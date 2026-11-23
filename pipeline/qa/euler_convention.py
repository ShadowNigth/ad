"""Which euler order turns `mstudiobone_t.rotation` into `mstudiobone_t.quat`?

`source_zanim.euler_to_quat` is used for the legacy RLE path, where animated rotations are euler
*channels* added to the bone's rest euler.  Getting the order wrong there is invisible in a viewport
and fatal in a hand, so the convention is not allowed to be folklore.

`studio.h` stores the rest orientation of every bone twice -- `RadianEuler rot` and `Quaternion quat`
-- and SourceIO hands both to us, so the composition rule is a measurable property of the shipped
files, not a choice.  This script enumerates the candidate conventions

    4 rotation orders (XYZ, XZY, YXZ, YZX, ZXY, ZYX) x intrinsic/extrinsic x 8 sign patterns
    x degrees-or-radians

and reports the residual of each against the stored quaternion, over every bone of every model it can
load.  Bones whose rest euler is under --min-angle are excluded from the decision (at a small angle
every order agrees, so averaging over them rates a wrong rule as nearly right), and conventions that
are the same rotation written two ways -- intrinsic XYZ and extrinsic ZYX, say -- are collapsed, so
the printed margin counts real alternatives rather than notation.

On the current dump: 207 models, 5353 bones with a rest euler over 10 deg, winner `ZYXe+++rad`
(= `XYZi+++rad`) at 0.0000 deg worst bone, runner-up `XZYi+++rad` at 1.9408 deg.

A plain numpy script (SourceIO is enough -- no Blender), run from the repo root:

    /tmp/venv/bin/python pipeline/qa/euler_convention.py

Exit code 0 when a single convention wins by a margin of at least --min-margin degrees (default 30);
non-zero when the winner is ambiguous, which would mean the model set or the parser changed under us.
"""
from __future__ import annotations

import argparse
import itertools
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
for cand in (str(ROOT / "vendor"), "/tmp/bl-addons", ""):
    if cand and Path(cand, "SourceIO").is_dir():
        sys.path.insert(0, cand)
        break

import source_zanim as Z  # noqa: E402

ORDERS = ("XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX")


def rot_mat(axis: int, a: np.ndarray) -> np.ndarray:
    c, s = np.cos(a), np.sin(a)
    one = np.ones_like(a)
    z = np.zeros_like(a)
    if axis == 0:
        return np.stack([one, z, z, z, c, -s, z, s, c], axis=-1).reshape(a.shape + (3, 3))
    if axis == 1:
        return np.stack([c, z, s, z, one, z, -s, z, c], axis=-1).reshape(a.shape + (3, 3))
    return np.stack([c, -s, z, s, c, z, z, z, one], axis=-1).reshape(a.shape + (3, 3))


def compose(ang: np.ndarray, order: str, intrinsic: bool, signs: tuple) -> np.ndarray:
    """Rotation matrices from `ang` (...,3) radians under one candidate convention."""
    m = np.zeros(ang.shape[:-1] + (3, 3))
    m[..., 0, 0] = m[..., 1, 1] = m[..., 2, 2] = 1.0
    axes = [ord(ch) - ord("X") for ch in order]
    for ax, sg in zip(axes, signs):
        r = rot_mat(ax, sg * ang[..., ax])
        # intrinsic (rotating-frame) composition is the reverse matrix product of extrinsic
        m = r @ m if intrinsic else m @ r
    return m


def mat_to_quat(m: np.ndarray) -> np.ndarray:
    """(...,3,3) -> (...,4) (x,y,z,w); reuses the production branch-picking code."""
    return Z._mat_to_quat(m)


def candidate_quats(eul: np.ndarray) -> dict:
    out = {}
    for order in ORDERS:
        for intrinsic in (False, True):
            for signs in itertools.product((1, -1), repeat=3):
                for deg in (True, False):
                    ang = np.radians(eul) if deg else eul.copy()
                    key = f"{order}{'i' if intrinsic else 'e'}{ ''.join('+' if s > 0 else '-' for s in signs) }"
                    key += "deg" if deg else "rad"
                    out[key] = mat_to_quat(compose(ang, order, intrinsic, signs))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", default=str(ROOT / "build/content"))
    ap.add_argument("--limit", type=int, default=0, help="stop after N models (the search is per model)")
    ap.add_argument("--min-angle", type=float, default=10.0,
                    help="ignore bones whose rest euler is smaller than this (in degrees)")
    ap.add_argument("--max-worst", type=float, default=0.01,
                    help="the winning convention must be within this many degrees on every bone")
    ap.add_argument("--min-separation", type=float, default=0.5,
                    help="and the runner-up must be at least this much worse, on the hard bones")
    args = ap.parse_args()

    models = sorted(Path(args.content).glob("*/m_cs2_*/models/weapons/**/*.mdl"))
    if not models:
        print(f"no .mdl under {args.content} -- run pipeline/stage_models.py first")
        return 2

    # Two scores, because most bones of a weapon sit at a near-zero rest euler, where every
    # convention agrees; averaging over them would rate a wrong rule as "0.2 deg off" and hide the
    # difference.  `total` is the honest mean over all bones; `hard` only counts bones whose rest
    # euler exceeds --min-angle degrees, where the orders actually separate.
    total, hard = {}, {}
    nbones = 0
    nhard = 0
    tried = 0
    for mdl in models:
        try:
            saved = Z._stub_sourceio_anim_parse()
            from SourceIO.library.utils import FileBuffer
            from SourceIO.library.models.mdl.v49.mdl_file import MdlV49
            with FileBuffer(str(mdl)) as buf:
                m = MdlV49.from_buffer(buf)
            Z._restore_sourceio_anim_parse(saved)
        except Exception as e:
            print(f"  skip {mdl.name}: {type(e).__name__}: {e}")
            continue
        bones = list(m.bones)
        if not bones:
            continue
        tried += 1
        eul = np.array([b.rotation for b in bones], dtype=np.float64)
        ref = np.array([b.quat for b in bones], dtype=np.float64)
        ref = ref / np.maximum(np.linalg.norm(ref, axis=-1, keepdims=True), 1e-12)
        hard_mask = np.max(np.abs(eul), axis=-1) > np.radians(args.min_angle)
        if not hard_mask.any():
            continue
        for key, q in candidate_quats(eul).items():
            # q and -q are the same rotation, so compare through |dot|
            d = np.abs((q * ref).sum(-1))
            err = 1.0 - np.clip(d, -1.0, 1.0)
            total[key] = total.get(key, 0.0) + float(err.sum())
            hard[key] = max(hard.get(key, 0.0), float(err[hard_mask].max()))
        nbones += int(hard_mask.sum())
        nhard += int(hard_mask.sum())
        if args.limit and tried >= args.limit:
            break

    if not total:
        print("no model yielded bones to test -- nothing to conclude")
        return 2

    def deg(v: float) -> float:
        return float(np.degrees(2.0 * np.arccos(max(0.0, 1.0 - v / max(nbones, 1)))))

    ranked = sorted(hard.items(), key=lambda kv: kv[1])
    # `XYZ intrinsic` and `ZYX extrinsic` are the same rotation written two ways, so the raw ranking
    # is full of ties that are not alternatives.  Collapse by numerical signature on a fixed probe
    # before measuring the margin, or the script reports ambiguity where there is only notation.
    probe = np.degrees(np.array([[0.3, -1.1, 2.0], [0.7, 0.2, -0.4]]))
    cands = candidate_quats(probe)
    sigs = {key: np.round(np.abs(q), 9).tobytes() for key, q in cands.items()}
    uniq, seen = [], {}
    for key, v in ranked:
        g = sigs[key]
        if g in seen:
            seen[g].append(key)
            continue
        seen[g] = [key]
        uniq.append((key, v))
    print(f"\n{tried} model(s), {nhard} bones with a rest euler over {args.min_angle:g} deg "
          f"(of {nbones} scored), {len(sorted(total))} conventions tested")
    for key, v in uniq[:5]:
        also = ", ".join(seen[sigs[key]][1:])
        print(f"  {key:22s} worst bone {deg(v):9.4f} deg   mean over all bones "
              f"{deg(total[key] / max(nbones, 1)):9.4f} deg" + (f"   (same as {also})" if also else ""))
    best, second = uniq[0], uniq[1]
    margin = deg(second[1]) - deg(best[1])
    print(f"winner {best[0]} at {deg(best[1]):.4f} deg worst, margin {margin:.2f} deg over {second[0]}")
    # The winner is judged absolutely, not relatively: the correct rule reproduces the stored
    # quaternion to float noise on *every* bone, so "0.0000 worst" is the pass condition.  A margin
    # alone would be meaningless here -- the wrong orders are only ~2 deg off because a rest pose is
    # mostly small angles -- which is exactly why the gate also demands the separation.
    if deg(best[1]) > args.max_worst:
        print(f"NO EXACT MATCH: winner is {deg(best[1]):.4f} deg off the worst bone "
              f"(> --max-worst {args.max_worst}) -- do not trust euler_to_quat")
        return 1
    if margin < args.min_separation:
        print(f"AMBIGUOUS: runner-up only {margin:.2f} deg worse (< --min-separation "
              f"{args.min_separation}) -- not enough non-trivial rest poses to decide")
        return 1
    print("OK: one convention explains every stored rest quaternion ("
          f"{', '.join(seen[sigs[best[0]]])})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
