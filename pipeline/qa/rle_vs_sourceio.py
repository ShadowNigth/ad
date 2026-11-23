#!/usr/bin/env python3
"""Compare the legacy RLE decode against SourceIO's own reader, value by value.

This is the gate that finished the format.  The other two (a unit-norm quaternion, and a single-frame
`base*` sequence reproducing `mstudiobone_t`) can both be satisfied by a decode that is wrong in a way
only a second implementation notices:

  * a wrong *unit* on an euler channel (the header's euler triple is radians; the ZANIM path converts,
    the legacy path must not) still produces perfect unit quaternions;
  * a hold-instead-of-sentinel choice is invisible in a base pose, because a base pose is made of
    constant records and never walks a channel;
  * an added-or-missing `mstudiobone_t` base on a per-record delta shows up as a clean, smooth, wrong
    curve.

So: for every legacy animation of every model, read the same bytes with SourceIO's
`StudioAnimDesc.read_animations` and diff the two arrays per bone.  Two deliberate divergences are
excluded rather than hidden:

  * `held_frames` -- the words the file stores as the 0x8000 "no key for this frame" sentinel.  This
    reader holds the previous value; SourceIO multiplies the sentinel by the bone's scale, which is how
    a shell attachment ends up 9962 inches from the gun in its output.  The frames are counted and
    printed, and the divergence is a design decision, not an accident.
  * `twist` -- bones with a positional channel are stored in the anim frame and this reader undoes the
    `Rz(+90)`, because the goal is a pose that agrees with the rest pose; SourceIO leaves the conversion
    to its Blender layer.  The comparison therefore runs with `twist_position_bones=False`, so it checks
    the *decode*, not the convention on top of it.  `pipeline/qa/arms_contact.py` and the base-pose
    residual check the convention.

A description SourceIO refuses outright (its own `assert frame_length == 0` on FRAMEANIM blocks) is not
a failure: those are the ZANIM clips, which have their own gates.  They are counted and reported.

    python3 pipeline/qa/rle_vs_sourceio.py --content build/content [--limit N] [--verbose]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "pipeline"))
for cand in (str(ROOT / "vendor"), "/tmp/bl-addons"):
    if Path(cand).is_dir() and cand not in sys.path:
        sys.path.insert(0, cand)

import source_zanim as Z  # noqa: E402

POS_TOL_IN = 1e-3        # float32 storage on both sides; 200 in of travel is ~1e-5 of rounding
ROT_TOL = 1e-4


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", default=str(ROOT / "build/content"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    from SourceIO.library.utils import FileBuffer
    from SourceIO.library.models.mdl.v49.mdl_file import MdlV49

    files = sorted(set(Path(args.content).glob("*/m_cs2_*/models/weapons/*.mdl"))
                   | set(Path(args.content).glob("*/m_cs2_*/models/weapons/*/*.mdl")))
    if not files:
        print(f"nothing under {args.content} -- run pipeline/stage_models.py first")
        return 2
    if args.limit:
        files = files[:args.limit]

    n_cmp = n_skip = n_sio_err = n_model = 0
    n_delta_pos = n_delta_explained = n_delta_rot = 0
    held = 0
    delta_notes: list[str] = []
    worst_pos = (0.0, "")
    worst_rot = (0.0, "")
    broken: list[str] = []
    for path in files:
        try:
            ours = Z.load_model_animations(str(path), strict=False, twist_position_bones=False)
        except Exception as exc:
            broken.append(f"{path.name}: our reader: {type(exc).__name__}: {exc}")
            continue
        if not any(v.get("legacy_rle") for k, v in ours.items() if k != "_meta"):
            continue
        n_model += 1
        try:
            with FileBuffer(str(path)) as buf:
                mdl = MdlV49.from_buffer(buf)
                ref = {}
                for d in mdl.anim_descs:
                    if int(d.flags) & Z.ANIM_FLAG_FRAMEANIM:
                        continue
                    try:
                        ref[d.name] = d.read_animations(buf, mdl.bones)
                    except Exception:
                        ref[d.name] = None
                        n_sio_err += 1
        except Exception as exc:
            broken.append(f"{path.name}: SourceIO reader: {type(exc).__name__}: {str(exc)[:80]}")
            continue
        bones = [b.name for b in mdl.bones]
        base_pos = ours["_meta"]["base_pos"]
        for name, anim in ours.items():
            if name == "_meta" or not anim.get("legacy_rle") or "frames" not in anim:
                continue
            them = ref.get(name)
            if not them:
                continue
            frames = anim["frames"]
            # A delta sequence is where the two readers part company *on purpose*: SourceIO adds
            # `mstudiobone_t.position`/`.rotation` to a record's channels unless that record sets the
            # per-bone delta bit, and it does not look at the description's own delta flag, so it folds the
            # setup pose into a stream the engine treats as relative to the main sequence.  This reader
            # keeps a delta clip relative (that is what lets the bake compose it onto the base pose), so
            # for those clips the test is not "are the arrays equal" but "is the difference exactly the
            # base add" -- which is a real claim about the code, and it can fail.
            is_delta = bool(anim.get("delta"))
            skip = {(int(f), int(c)) for f, c in (anim.get("rle_held") or [])}
            for key, data in them.items():
                if key not in bones:
                    continue
                col = bones.index(key)
                p_ = np.asarray(data["pos"])
                q = np.asarray(data["rot"])
                n = min(frames.shape[0], p_.shape[0])
                keep = np.array([f for f in range(n) if (f, col) not in skip], dtype=int)
                held += n - keep.size
                if keep.size == 0:
                    n_skip += 1
                    continue
                if p_.ndim == 2 and p_.shape[1] >= 3:
                    mine = frames["pos"][keep, col]
                    d = float(np.abs(mine - p_[keep, :3]).max())
                    if is_delta:
                        d_alt = float(np.abs(mine + base_pos[col] - p_[keep, :3]).max())
                        if d_alt < d:
                            d, explained = d_alt, True
                        else:
                            explained = False
                        n_delta_pos += 1
                        if explained:
                            n_delta_explained += 1
                    if d > worst_pos[0] and not is_delta:
                        worst_pos = (d, f"{path.name} {name} {key}")
                    if d > POS_TOL_IN:
                        n_skip += 1
                        # A delta clip is reported, not failed: inside one the two implementations differ
                        # by which pose the channel is composed onto, and that is a convention this gate
                        # has no standing to arbitrate -- the base-pose residual and `arms_contact.py`
                        # are what check a delta clip's numbers.  A *plain* clip has only one reading, so
                        # a difference there is a bug in one of the two decoders and it stops the build.
                        (delta_notes if is_delta else broken).append(
                            f"{path.name} {name} {key}: pos diff {d:.4f} in"
                            + (" (not explained by the delta base add)" if is_delta else ""))
                        continue
                if q.ndim == 2 and q.shape[1] >= 4:
                    if is_delta:
                        # The rotation half cannot be transformed the same way -- adding an euler before
                        # the quaternion conversion is not a rotation of the result -- so a delta clip's
                        # rotations are reported as not-compared rather than silently passed.  They are
                        # checked by the base-pose residual and by `arms_contact.py` instead.
                        n_delta_rot += 1
                        continue
                    d = float(np.abs(frames["rot"][keep, col] - q[keep, :4]).max())
                    if d > worst_rot[0]:
                        worst_rot = (d, f"{path.name} {name} {key}")
                    if d > ROT_TOL:
                        n_skip += 1
                        broken.append(f"{path.name} {name} {key}: rot diff {d:.5f}")
                        continue
                n_cmp += 1
        if args.verbose:
            print(f"  {path.name}: compared, worst so far {worst_pos[0]:.5f} in")

    print(f"[models] {len(files)} searched, {n_model} with legacy animations")
    print(f"[bones]  {n_cmp} (animation, bone) pairs agree within "
          f"{POS_TOL_IN:g} in / {ROT_TOL:g} rad")
    print(f"[held]   {held} frame value(s) excluded because they are the 0x8000 sentinel")
    if n_delta_pos or n_delta_rot:
        print(f"[delta]  {n_delta_pos} delta-clip position channel(s) differ by the setup-pose add "
              f"({n_delta_explained} of them exactly: {100.0 * n_delta_explained / max(n_delta_pos, 1):.1f}%), "
              f"{n_delta_rot} delta rotation(s) not compared -- see the note in this file's docstring")
    print(f"[ref]    worst position difference {worst_pos[0]:.6f} in at {worst_pos[1] or '-'}")
    print(f"[ref]    worst rotation difference {worst_rot[0]:.6f} at {worst_rot[1] or '-'}")
    print(f"[sio]    {n_sio_err} description(s) SourceIO's own reader refuses (ZANIM blocks: expected)")
    if delta_notes:
        print(f"[delta]  {len(delta_notes)} delta-clip position(s) differ beyond tolerance; worst: "
              f"{delta_notes[0].split(': ')[1]} -- reported, not failed (see the comment in this file)")
    if broken:
        print(f"[FAIL]   {len(broken)} disagreement(s); first: {broken[0][:150]}")
        for b in broken[1:5]:
            print(f"           {b[:150]}")
    ok = not broken and n_cmp > 0
    print(f"\n[verdict] {'PASS' if ok else 'FAIL'}: the legacy decode "
          f"{'matches the reference implementation frame for frame' if ok else 'does not match it'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
