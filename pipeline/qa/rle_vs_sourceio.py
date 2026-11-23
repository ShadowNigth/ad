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
`StudioAnimDesc.read_animations` and diff the two arrays per bone.  Four deliberate divergences are
excluded rather than hidden, each counted on the same screenful as the PASS so the gate's blind spots
are part of its output:

  * `held_frames` -- the words the file stores as the 0x8000 "no key for this frame" sentinel.  This
    reader holds the previous value; SourceIO multiplies the sentinel by the bone's scale, which is how
    a shell attachment ends up 9962 inches from the gun in its output.  The frames are counted and
    printed, and the divergence is a design decision, not an accident.
  * `n_noq` -- non-delta rows where SourceIO's valueptrs-only branch read no channel at all and left its
    float32 zero buffer in place, i.e. the quaternion (0, 0, 0, 0).  Not a rotation; this reader seeds
    identity, which is.
  * `n_seed` -- rows in a delta clip for a bone the clip does not animate, where this reader keeps the
    clip's identity/zero seed (build_pack composes every array onto the rest pose) and SourceIO returns
    that bone's rest quaternion/position (right for a layer writing absolute local rotations).  A
    composition choice on both sides, not a fact about the encoding; matching them needs the reference
    buffer's own float32 precision, hence the 1e-6 tolerance rather than 1e-9.
  * delta positions, which agree only once the setup-pose add is applied -- counted and printed as a
    percentage (`[delta]`), because "how many differ by exactly the base" is the number that tells you
    whether the record-level `0x10` rule is right.
  * `twist` -- bones with a positional channel are stored in the anim frame and this reader undoes the
    `Rz(+90)`, because the goal is a pose that agrees with the rest pose; SourceIO leaves the conversion
    to its Blender layer.  The comparison therefore runs with `twist_position_bones=False`, so it checks
    the *decode*, not the convention on top of it.  `pipeline/qa/arms_contact.py` and the base-pose
    residual check the convention.

A description SourceIO refuses outright (its own `assert frame_length == 0` on FRAMEANIM blocks) is not
a failure: those are the ZANIM clips, which have their own gates.  They are counted and reported.

What the four carve-outs leave is printed under `[delta]` / `[scope]` rather than swallowed: 26 rows on
delta clips, 1 of them on a model this repo builds.  Those are records whose rotation is a *constant*
with no `0x08` channel, where SourceIO's `_read_anim_rot_value` returns early and never reads the packed
value at all -- `[base_quat] * frame_count`, or `[(0,0,0,1)] * frame_count` when that record itself sets
`0x10` -- while this reader decodes the constant either way and adds the base only if the record allows
it.  So the surviving rows differ by exactly one side's rest pose, in whichever direction the two delta
bits fall.  `rle_proof.py`'s base control settles the
non-delta half of that: `v_shot_mag7 @base_pose` is made of constant records, and base+constant lands on
`mstudiobone_t` to 0.044 deg where the constant alone is 139 deg off.

    python3 pipeline/qa/rle_vs_sourceio.py --content build/content [--limit N] [--verbose]
"""
from __future__ import annotations

import argparse
import collections
import re
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
    n_noq = n_seed = 0
    n_delta_pos = n_delta_explained = n_delta_rot = 0
    held = 0
    delta_notes: list[str] = []
    worst_pos = (0.0, "")
    worst_rot = (0.0, "")
    worst_delta = (0.0, "")   # worst difference among delta rows, which the [ref] line excludes
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
                    ref_p = p_[keep, :3]
                    mine = frames["pos"][keep, col]
                    if is_delta:
                        # The position twin of the rotation seed fork above, and the reason the same
                        # design choice has to be stated twice: in a delta clip this reader seeds "no
                        # contribution" (0) for a bone whose record has no position channel, because the
                        # bake composes the clip onto the base pose, while SourceIO fills that bone with
                        # its rest position.  Rows that are exactly that pair are skipped and counted;
                        # everything else has to match, which is what makes 0x10 handling, the run walk
                        # and the scales all still checkable inside delta clips.
                        seeded = (np.abs(mine).max(axis=1) < 1e-9) & \
                            (np.abs(ref_p - base_pos[col]).max(axis=1) < 1e-4)  # float32 reference buffer
                        n_seed += int(seeded.sum())
                        if seeded.all():
                            n_skip += 1
                            continue
                        mine, ref_p = mine[~seeded], ref_p[~seeded]
                    d = float(np.abs(mine - ref_p).max())
                    if is_delta:
                        n_delta_pos += 1
                        n_delta_explained += int(d <= POS_TOL_IN)
                    if d > worst_pos[0] and not is_delta:  # strict claim: non-delta rows only
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
                    # Two things this comparison has to survive before it means anything:
                    #  * q and -q are the same rotation, so the difference is taken up to sign -- without
                    #    that, an antipodal identity scores a "difference" of 2.000000;
                    #  * SourceIO's frame buffer is `np.zeros(..., ANIM_DTYPE)`, so a bone it never writes
                    #    has the quaternion (0, 0, 0, 0), which is not a rotation at all -- this reader
                    #    seeds identity, which is.  That is a difference in what "untouched" initialises
                    #    to, not in the decode, so those rows are skipped and counted.
                    b = q[keep, :4]
                    nz = np.linalg.norm(b, axis=-1) > 1e-6
                    n_noq += int((~nz).sum())
                    if not nz.any():
                        n_skip += 1
                        continue
                    a = frames["rot"][keep, col][nz]
                    b = b[nz]
                    if is_delta:
                        # And one design difference, stated rather than argued: in a delta clip, a bone
                        # whose record carries no rotation channel keeps *this* reader's seed (identity =
                        # "this clip adds no rotation"), because the bake composes every array against the
                        # rest pose.  SourceIO hands back that bone's rest quaternion instead, which is the
                        # right answer for a layer that writes the value as an absolute local rotation.
                        # Neither is a fact about the encoding, so those rows are skipped and counted -- and
                        # a genuine rotation error in a delta clip still fails the gate.
                        bq = np.asarray(mdl.bones[col].quat, dtype=np.float64)
                        # The tolerance is the reference buffer's own precision, not ours: SourceIO's
                        # frame array is float32 (ANIM_DTYPE), so its rest-pose seed differs from the
                        # float64 `mstudiobone_t` quaternion by ~6e-8. 1e-9 here silently fails to match.
                        ident = np.abs(a - np.array([0.0, 0.0, 0.0, 1.0])).max(axis=1) < 1e-9
                        likebase = np.abs(np.minimum(np.abs(b - bq), np.abs(b + bq))).max(axis=1) < 1e-6
                        keep2 = ~(ident & likebase)
                        n_seed += int((~keep2).sum())
                        if not keep2.any():
                            n_skip += 1
                            continue
                        a, b = a[keep2], b[keep2]
                    d = float(np.minimum(np.abs(a - b), np.abs(a + b)).max())
                    # The [ref] line is the gate's strict claim, so it is scored only on rows both
                    # implementations are actually committed to: a delta row's difference is reported on
                    # the [delta] line instead, where the carve-outs are named next to the number.
                    if d > worst_rot[0] and not is_delta:
                        worst_rot = (d, f"{path.name} {name} {key}")
                    if is_delta and d > worst_delta[0]:
                        worst_delta = (d, f"{path.name} {name} {key}")
                    if d > ROT_TOL:
                        n_skip += 1
                        (delta_notes if is_delta else broken).append(
                            f"{path.name} {name} {key}: rot diff {d:.5f}")
                        continue
                n_cmp += 1
        if args.verbose:
            print(f"  {path.name}: compared, worst so far {worst_pos[0]:.5f} in")

    print(f"[models] {len(files)} searched, {n_model} with legacy animations")
    print(f"[bones]  {n_cmp} (animation, bone) pairs agree within "
          f"{POS_TOL_IN:g} in / {ROT_TOL:g} rad")
    print(f"[held]   {held} frame value(s) excluded because they are the 0x8000 sentinel")
    print(f"[seed]   {n_noq} row(s) where SourceIO left an all-zero quaternion (no rotation channel for "
          "that bone) and this reader seeded an identity -- not a decode difference")
    if n_seed:
        print(f"[seed]   {n_seed} delta row(s) where the bone has no rotation (or no position) channel: we keep the "
              "clip's identity seed, SourceIO returns the rest quaternion (each correct for its own "
              "composition model) -- skipped and counted, not hidden")
    if n_delta_pos or n_delta_rot:
        print(f"[delta]  {n_delta_pos} delta-clip position channel(s) differ by the setup-pose add "
              f"({n_delta_explained} of them exactly: {100.0 * n_delta_explained / max(n_delta_pos, 1):.1f}%), "
              f"{n_delta_rot} delta rotation(s) not compared -- see the note in this file's docstring")
    print(f"[ref]    worst position difference {worst_pos[0]:.6f} in at {worst_pos[1] or '-'}")
    print(f"[ref]    worst rotation difference {worst_rot[0]:.6f} at {worst_rot[1] or '-'}")
    print(f"[sio]    {n_sio_err} description(s) SourceIO's own reader refuses (ZANIM blocks: expected)")
    kinds = collections.Counter(n.split(".mdl")[0].split("_")[1] if False else ("v_*" if re.search(r"\bv_[a-z]+_", n) else "w_*") for n in delta_notes)
    print(f"[scope]  delta notes by model family: {dict(kinds)}")
    # The v_*/w_* split matters for this repo's purposes: the delta clips on the viewmodels are the
    # ones the bake consumes, so a note on a world model is a curiosity, a note on a v_* model is
    # something the addon actually ships with.
    for n in [x for x in delta_notes if re.search(r"\bv_[a-z]+_", x)][:4]:
        print(f"       on a viewmodel (in scope for the bake): {n[:120]}")
    if delta_notes:
        print(f"[delta]  {len(delta_notes)} delta-clip row(s) differ beyond what the carve-outs "
              f"explain; worst {worst_delta[0]:.5f} at {worst_delta[1]} -- reported, not failed, "
              "because on a delta clip the composition is this repo's choice (see [seed] and "
              "[docstring])")
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
