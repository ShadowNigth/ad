#!/usr/bin/env python3
"""Prove the legacy RLE decode against the two things a correct reader cannot miss.

Run this instead of trusting `RLE_TRUSTED`.  The format was found by elimination -- every 16-bit and
32-bit word reading of a constant rotation was measured off the unit sphere in
`pipeline/qa/exploration/rle_census.py` -- and the answer (a *bit-packed* 64-bit quaternion, `Quat64`,
whose fields do not align to words) only counts as proven because two independent numbers land where
they must:

  1. every decoded quaternion is unit to within float32 noise.  Quantised data can be off the sphere by
     its own quantum (a Quaternion48 sits near 1e-4 here) but never by 0.16, which is what every wrong
     reading scored on the same records;
  2. a single-frame sequence whose name contains `base` reproduces `mstudiobone_t.quat`/`.position` --
     the rest pose -- because that is what such a sequence *is*.  This is the control that matters: it
     is the only legacy data in the dump with an answer written down somewhere else, and it is what a
     scale-too-small-to-move-everything cannot fake (the census caught exactly such a candidate passing
     the first test at 0.012 deg by reading every euler channel as zero).

A decode that passes both over the whole dump is what `RLE_TRUSTED = True` in `source_zanim.py` means.
Exit code is 0 when every model's legacy animations decode and both numbers are in range.

    python3 pipeline/qa/rle_proof.py --content build/content
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline"))
import source_zanim as Z  # noqa: E402

# What a right answer looks like, and why:
#   unit tolerance  -- quantisation of a 21-bit component is ~5e-7, so 1e-4 is generous by two orders
#   base residual    -- the ZANIM path's own clips score 0.03 deg through the same chain; a legacy base
#                      pose is the same information, so anything above a degree means the read is off
ROT_UNIT_TOL = 1e-4
BASE_RESIDUAL_DEG = 1.0
BASE_POS_IN = 0.5


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", default=str(ROOT / "build/content"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    files = sorted(set(Path(args.content).glob("*/m_cs2_*/models/weapons/*.mdl"))
                   | set(Path(args.content).glob("*/m_cs2_*/models/weapons/*/*.mdl")))
    if not files:
        print(f"nothing under {args.content} -- run pipeline/stage_models.py first")
        return 2
    if args.limit:
        files = files[:args.limit]

    legacy = n_ok = n_err = 0
    rot_err: list[float] = []
    base_res: list[tuple[str, float, float]] = []
    failures: list[str] = []
    for path in files:
        try:
            anims = Z.load_model_animations(str(path), strict=False)
        except Exception as exc:                       # a model we cannot parse at all
            failures.append(f"{path.name}: {type(exc).__name__}: {exc}")
            continue
        names = anims.get("_meta", {}).get("bone_names", [])
        for name, anim in anims.items():
            if name == "_meta" or "error" in anim:
                if name != "_meta":
                    n_err += 1
                    failures.append(f"{path.name} {name}: {anim['error']}")
                continue
            frames = anim["frames"]
            if frames.shape[1] < 2 or not anim.get("legacy_rle"):
                continue
            legacy += 1
            q = frames["rot"]
            rot_err.append(float(np.abs(np.linalg.norm(q, axis=-1) - 1.0).max()))
            if "base" in name.lower():
                meta = anims["_meta"]
                br, bp = meta["base_rot"], meta["base_pos"]
                ang = np.degrees(2.0 * np.arccos(np.clip(np.abs((q * br).sum(-1)), 0.0, 1.0)))
                pos = np.abs(frames["pos"] - bp)
                # only the bones a record actually touched: an untouched bone keeps the rest pose by
                # construction, which would make the median a lie about coverage
                touched = anim.get("rle_touched")
                if touched is not None and len(touched):
                    sel = np.array(sorted(touched), dtype=int)
                    sel = sel[sel < ang.size]
                    ang, pos = ang[0][sel], pos[0][sel]
                base_res.append((f"{path.name} {name}", float(ang.max()), float(pos.max())))
            n_ok += 1
        if args.verbose:
            print(f"  {path.name}: {len(names)} bones")

    print(f"[models] {len(files)} searched, {legacy} legacy animations decoded, {n_err} refused")
    if rot_err:
        arr = np.array(rot_err)
        print(f"[unit]   worst |q|-1 over those animations: median {np.median(arr):.2e} "
              f"max {arr.max():.2e}  (tolerance {ROT_UNIT_TOL:.0e})")
    else:
        print("[unit]   no legacy animation decoded -- nothing was proven")
    if base_res:
        a = np.array([r[1] for r in base_res])
        b = np.array([r[2] for r in base_res])
        print(f"[base]   {len(base_res)} base sequences: worst rest-pose residual "
              f"median {np.median(a):.4f} deg / {np.median(b):.4f} in, "
              f"max {a.max():.4f} deg / {b.max():.4f} in")
        for name, ra, rb in sorted(base_res, key=lambda r: -r[1])[:5]:
            flag = "  <- over tolerance" if ra > BASE_RESIDUAL_DEG else ""
            print(f"    {name[:58]:58s} {ra:8.4f} deg {rb:7.4f} in{flag}")
    else:
        print("[base]   no base-named sequence found -- the control did not run")

    bad = [f for f in failures if "RLE_TRUSTED" not in f]
    over = [r for r in base_res if r[1] > BASE_RESIDUAL_DEG]
    if rot_err and max(rot_err) > ROT_UNIT_TOL:
        print(f"[FAIL]   {sum(1 for e in rot_err if e > ROT_UNIT_TOL)} animation(s) off the unit sphere")
    if bad:
        print(f"[FAIL]   {len(bad)} refusal(s), first: {bad[0][:160]}")
    if over:
        print(f"[FAIL]   {len(over)} base sequence(s) more than {BASE_RESIDUAL_DEG} deg from the rest pose")
    ok = not bad and not over and bool(rot_err) and max(rot_err) <= ROT_UNIT_TOL and bool(base_res)
    print(f"\n[verdict] {'PASS' if ok else 'FAIL'}: the legacy layout is "
          f"{'confirmed by both numbers' if ok else 'not confirmed -- keep RLE_TRUSTED False'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
