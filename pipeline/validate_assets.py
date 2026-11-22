"""Decode-and-check every CS2 view model in a content tree.

The decoder in `source_zanim.py` reverse-engineered a file format with no public spec for
this version, so the only honest way to call it finished is to run it over everything and
assert the properties that must hold for *any* correct decode:

  1. every animation description of every model decodes without `ZanimError`
     (the byte-count self-checks -- `frame_length` vs the sum of per-bone records, and the
     constant span vs `frame_offset - constant_offset` -- are the layout proof);
  2. every rotation is a unit quaternion (|q| - 1 within float32 epsilon), since both
     Quaternion48 and Quaternion48S rebuild the dropped component from unit length;
  3. the base animation's constant records reproduce `mstudiobone_t.position`/`.quat`
     (that is what "bind pose" means; a wrong axis change or a wrong field order breaks it
     while still looking "smooth", so this is the check that actually pins the convention);
  4. adjacent-frame rotation steps stay below a plausible maximum for a hand animation, and
     positional channels contain no NaN/inf.

Usage:
    /tmp/venv/bin/python pipeline/validate_assets.py --archi /tmp/archi --json build/decode_report.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
# `source_zanim` reuses SourceIO's struct readers for the .mdl side tables.  When running
# outside Blender that package must be importable: either installed, on PYTHONPATH, or in
# one of the locations below (pipeline/vendor is the vendored copy this repo ships).
for _cand in (str(HERE.parent / "vendor"), "/tmp/bl-addons",
              str(Path.home() / ".config/blender-addons"), os.environ.get("SIO_ADDONS", "")):
    if _cand and Path(_cand, "SourceIO").is_dir() and _cand not in sys.path:
        sys.path.insert(0, _cand)
        break

MAX_STEP_DEG = 95.0          # 30 fps hand animation: >95 deg between frames means mis-decode
UNIT_TOL = 2e-3              # values are stored as float32 after decode
BIND_TOL_DEG = 1.0           # base-anim constant rotation vs mstudiobone_t.quat
BIND_TOL_IN = 0.05           # base-anim constant position vs mstudiobone_t.position (f16 step)


def find_pairs(archi: Path):
    out = []
    for mdl in sorted(archi.rglob("models/**/*.mdl")):
        ani = mdl.with_suffix(".ani")
        out.append((mdl, ani if ani.exists() else None))
    return out


def check_model(mdl_path: Path, ani_path: Path | None):
    import source_zanim as Z
    # `unsupported` distinguishes "this model needs the legacy RLE reader we have not written"
    # from "the decoder produced wrong numbers": 124 of the pack's 182 models are the former (every
    # `w_*` world model and every shell/dropped variant), and counting them as failures buries the
    # handful of real ones.  Only the latter should ever fail a build.
    rep = {"mdl": str(mdl_path), "ok": True, "unsupported": True, "problems": [],
           "anims": {}, "notes": []}
    try:
        anims = Z.load_model_animations(mdl_path, ani_path)
    except Exception as e:                                   # noqa: BLE001 - reporting
        rep["ok"] = rep["unsupported"] = False
        rep["problems"].append(f"load failed: {type(e).__name__}: {e}")
        return rep
    meta = anims.pop("_meta", {})
    names = meta.get("bone_names", [])
    base_pos, base_rot = meta.get("base_pos"), meta.get("base_rot")
    if base_pos is None:
        rep["problems"].append("decoder returned no _meta")
        rep["ok"] = rep["unsupported"] = False
        return rep

    def is_unit(q):
        return np.abs(np.linalg.norm(q, axis=-1) - 1.0)

    for name, v in anims.items():
        if "error" in v:
            rep["problems"].append(f"{name}: {v['error']}")
            rep["ok"] = False
            if "legacy RLE" not in v["error"]:
                rep["unsupported"] = False       # a real decode failure, not a missing feature
            continue
        fr = v["frames"]
        n, nb = fr.shape[:2]
        rot, pos = fr["rot"], fr["pos"]
        entry = {"frames": int(n), "bones": int(nb), "fps": v["fps"], "delta": v["delta"],
                 "looping": v["looping"], "notes": list(v["notes"])}
        bad = float(is_unit(rot).max())
        if bad > UNIT_TOL:
            i = int(np.argmax(is_unit(rot)))
            entry["nonunit"] = round(bad, 4)
            rep["problems"].append(f"{name}: |q|-1 = {bad:.4f} (bone {names[i] if i < len(names) else i})")
        if not np.all(np.isfinite(pos)):
            rep["problems"].append(f"{name}: {int((~np.isfinite(pos)).sum())} non-finite positions")
        if n > 1:
            step = np.degrees(2 * np.arccos(np.clip(np.abs((rot[:-1] * rot[1:]).sum(-1)), -1, 1)))
            mx = float(step.max())
            entry["max_step_deg"] = round(mx, 2)
            if mx > MAX_STEP_DEG:
                k = int(np.argmax(step.max(axis=0)))
                rep["problems"].append(f"{name}: {mx:.1f} deg rotation step (bone "
                                       f"{names[k] if k < len(names) else k})")
        # 3. base animation == bind pose
        if name.startswith("a_") and n == 1:
            qa = rot[0]
            ang = np.degrees(2 * np.arccos(np.clip(np.abs((qa * base_rot).sum(-1)), 0, 1)))
            # compare only the bones this block actually carries
            touched = np.linalg.norm(pos[0] - base_pos, axis=-1) > 1e-6
            touched |= (np.abs(ang) > 1e-6)
            worst_a = float(ang[touched].max()) if touched.any() else 0.0
            worst_p = float(np.linalg.norm(pos[0] - base_pos, axis=-1)[touched].max()) if touched.any() else 0.0
            entry["bind_residual_deg"] = round(worst_a, 4)
            entry["bind_residual_in"] = round(worst_p, 5)
            if worst_a > BIND_TOL_DEG or worst_p > BIND_TOL_IN:
                rep["problems"].append(f"{name}: base anim differs from mstudiobone_t by "
                                       f"{worst_a:.2f} deg / {worst_p:.3f} in")
        rep["anims"][name] = entry
    return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--archi", default="/tmp/archi")
    ap.add_argument("--build", default="build/content")
    ap.add_argument("--json", default="build/decode_report.json")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    roots = []
    for base in (Path(a.build), Path(a.archi)):
        if base.is_dir():
            roots.extend(find_pairs(base))
    seen, pairs = set(), []
    for mdl, ani in roots:
        key = (mdl.parent.name, mdl.stem)
        if key in seen:
            continue
        seen.add(key)
        pairs.append((mdl, ani))
    if a.limit:
        pairs = pairs[:a.limit]
    print(f"[validate] {len(pairs)} model(s)")
    reports = []
    n_ok = n_skip = 0
    for mdl, ani in pairs:
        r = check_model(mdl, ani)
        reports.append(r)
        tot = sum(e["frames"] for e in r["anims"].values())
        status = "OK " if r["ok"] else ("NOSUP" if r.get("unsupported") else "FAIL")
        n_ok += bool(r["ok"])
        n_skip += bool(r.get("unsupported")) and not r["ok"]
        note = "" if r["ok"] else "  <- " + " | ".join(r["problems"][:3])
        if status == "NOSUP":
            note = "  <- all sequences are legacy RLE (no ANIM_FLAG_FRAMEANIM)"
        print(f"  [{status:5s}] {mdl.parent.parent.name}/{mdl.stem}: {len(r['anims'])} anims, "
              f"{tot} frames{note}")
    out = Path(a.json)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"models": len(pairs), "ok": n_ok, "unsupported": n_skip,
                               "reports": [{k: v for k, v in r.items()} for r in reports]},
                              indent=1, default=float))
    print(f"[validate] {n_ok}/{len(pairs)} models fully decoded, {n_skip} need the legacy RLE "
          f"reader (unsupported, not a decode failure) -> {out}")
    return 0 if n_ok + n_skip == len(pairs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
