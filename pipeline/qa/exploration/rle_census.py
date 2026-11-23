"""Legacy RLE animation census: record sizes, constant-channel candidates, base-pose agreement.

Not a gate. This is the probe that produced the numbers in
[`../../../docs/legacy-rle-anim.md`](../../../docs/legacy-rle-anim.md), kept because the negative
results are the whole value: four different record layouts walk every chain in the dump cleanly, and
only these measurements tell them apart.  Pure numpy, no Blender:

    /tmp/venv/bin/python pipeline/qa/exploration/rle_census.py [--content build/content] [--deep]

Three sections, printed in order:

1. **sizes** -- `flags -> Counter(nextoffset)` over every legacy chain.  This is what proves the
   header is 4 bytes, that a `Vector48` costs 6 and the constant rotation 8, and that the `0x10`
   delta bit carries no payload.  A layout that contradicts these numbers is wrong, however well it
   walks.
2. **the unit sphere** -- for every `0x20`/`0x21` record, which 3 of the first 4 words could be a
   Quaternion48 under which dequantisation.  `x^2+y^2+z^2` has to be 1 within quantisation for the
   right answer; the census shows no combination gets closer than a median of ~0.36, which is what
   "these bytes are not a quaternion" looks like.
3. **base pose** -- does frame 0 of a model's `base_pose` reproduce `mstudiobone_t`?  A *median* near
   zero here is meaningless (most bones carry no record and inherit the truth), so the number to read
   is the share of bones that DO carry a record, and the maximum.

`--deep` adds section 2's search over `.ani`-side blocks too (slower, and the `.mdl`-local chains are
where every layout conclusion so far came from).
"""
from __future__ import annotations

import argparse
import collections
import itertools
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(ROOT / "pipeline"))
for cand in (str(ROOT / "vendor"), "/tmp/bl-addons", ""):
    if cand and Path(cand, "SourceIO").is_dir():
        sys.path.insert(0, cand)
        break

import source_zanim as Z  # noqa: E402

# The candidate dequantisations for a 16-bit stored component -- every variant any Source quaternion
# has used, taken from studio.h's Quat48/Quat48S/QuatWithTwist comments.  The mask has to happen on
# the integers: `float64 & int` is a TypeError on numpy 1.x, and casting back would hide the bug.
def _i16(v):
    return np.where(v >= 32768, v - 65536, v).astype(np.float64)


SCALES = {
    "(v-16384)/23168": lambda v: (v.astype(np.float64) - 16384.0) / 23168.0,   # Quat48S stored part
    "(v-32768)/32768": lambda v: (v.astype(np.float64) - 32768.0) / 32768.0,    # Quat48.x
    "(v&0x7FFF)/16384-1": lambda v: (v & 0x7FFF).astype(np.float64) / 16384.0 - 1.0,
    "(v&0x7FFF)/16384": lambda v: (v & 0x7FFF).astype(np.float64) / 16384.0,
    "i16/16384": lambda v: _i16(v) / 16384.0,
    "i16/32768": lambda v: _i16(v) / 32768.0,
}


def models(content: Path):
    paths = set(content.glob("*/m_cs2_*/models/weapons/*.mdl"))
    paths |= set(content.glob("*/m_cs2_*/models/weapons/*/*.mdl"))
    return sorted(paths)


def walk(blob, n):
    """Yield `(bone, flags, payload)` for a record chain, or stop at the first impossibility."""
    off, prev = 0, -1
    while off + 4 <= len(blob):
        bone, flags = int(blob[off]), int(blob[off + 1])
        nxt = int(np.frombuffer(blob[off + 2:off + 4], dtype="<i2")[0])
        if bone > n or nxt < 4 or bone <= prev:
            return
        yield bone, flags, blob[off + 4:off + nxt]
        prev = bone
        if nxt == 0:
            return
        off += nxt


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", default=str(ROOT / "build/content"))
    ap.add_argument("--deep", action="store_true", help="include .ani-side blocks in section 2")
    args = ap.parse_args()

    files = models(Path(args.content))
    if not files:
        print(f"nothing under {args.content} -- run pipeline/stage_models.py first")
        return 2

    sizes = collections.defaultdict(collections.Counter)
    words, base_recs = [], []
    nmodel = 0
    for P in files:
        mb = P.read_bytes()
        try:
            saved = Z._stub_sourceio_anim_parse()
            from SourceIO.library.utils import FileBuffer
            from SourceIO.library.models.mdl.v49.mdl_file import MdlV49
            with FileBuffer(str(P)) as buf:
                m = MdlV49.from_buffer(buf)
            Z._restore_sourceio_anim_parse(saved)
        except Exception:
            continue
        n = len(m.bones)
        ids = {b.bone_id: i for i, b in enumerate(m.bones)}
        bq = np.array([b.quat for b in m.bones], dtype=np.float64)
        ab, bt = None, None
        if args.deep:
            sidecar = P.with_suffix(".ani")
            if sidecar.exists():
                ab = sidecar.read_bytes()
                from SourceIO.library.models.mdl.structs.ani_file import read_anim_block_table
                try:
                    bt = read_anim_block_table(Z._Buf(mb), getattr(m.header, "anim_block_offset", 0),
                                               getattr(m.header, "anim_block_count", 0))
                except Exception:
                    bt = None
        seen = 0
        for ad in m.anim_descs:
            if int(ad.flags) & Z.ANIM_FLAG_FRAMEANIM:
                continue
            for (count, blk, off) in Z._desc_sections(ad, mb):
                if blk != 0 and not args.deep:
                    continue
                try:
                    blob = Z._block_bytes(mb, ab, bt, blk, off)
                except Exception:
                    continue
                for bone, flags, body in walk(blob, n):
                    seen += 1
                    sizes[flags][len(body) + 4] += 1
                    if flags in (Z.RLE_RAWROT2, Z.RLE_RAWROT) and len(body) >= 8:
                        words.append(np.frombuffer(body[:8], dtype="<u2").astype(np.int64))
                    if flags & Z.RLE_DELTA == 0 and count == 1 and not ad.name.startswith("@"):
                        k = ids.get(bone, bone)
                        if k < n and len(body) >= 6:
                            base_recs.append((np.frombuffer(body[:8], dtype="<u2").astype(np.int64),
                                              bq[k]))
        nmodel += 1 if seen else 0

    print(f"{len(files)} model(s) read, {nmodel} with walkable legacy chains\n")
    print("== 1. record sizes (payload + 4-byte header), by flags bit")
    for flags in sorted(sizes):
        c = sizes[flags]
        tot = sum(c.values())
        names = "+".join(n for n, bit in (("RAWPOS", 1), ("RAWROT", 2), ("ANIMPOS", 4), ("ANIMROT", 8),
                                          ("DELTA", 0x10), ("RAWROT2", 0x20)) if flags & bit) or "-"
        common = ", ".join(f"{sz}B x{cnt}" for sz, cnt in sorted(c.items())[:5])
        spread = "" if len(c) == 1 else f"  ({len(c)} distinct sizes: RLE runs)"
        print(f"   0x{flags:02x} {names:32s} {tot:7d} records: {common}{spread}")
    fixed = {f: c for f, c in sizes.items() if len(c) == 1}
    for f, c in sorted(fixed.items()):
        print(f"   0x{f:02x} has exactly one size: {next(iter(c))} bytes")

    print(f"\n== 2. unit-sphere census over {len(words)} constant-rotation records")
    if not words:
        print("   none found")
    else:
        W = np.stack(words)
        worst = []
        for sel in itertools.combinations(range(4), 3):
            for tname, fn in SCALES.items():
                v = fn(W[:, list(sel)])
                ssq = (v * v).sum(1)
                worst.append((float(np.median(np.abs(ssq - 1.0))), float((ssq <= 1.001).mean()), sel, tname))
        worst.sort()
        for med, share, sel, tname in worst[:6]:
            print(f"   words{sel} {tname:18s} median |x^2+y^2+z^2 - 1| {med:7.4f}   "
                  f"share on/inside the sphere {share*100:5.1f}%")
        print("   (a real Quaternion48 is ~1e-4 / ~100%; anything in the 0.3-0.5 range is noise)")
        for i in range(4):
            v = W[:, i]
            print(f"   word{i}: [{v.min()}, {v.max()}] median {int(np.median(v))} "
                  f"share in [16384,49152] {np.mean((v >= 16384) & (v < 49152)) * 100:5.1f}%")

    print(f"\n== 3. base pose: {len(base_recs)} records in single-frame absolute sequences")
    if not base_recs:
        print("   none found -- the dump has no absolute one-frame sequence with a constant record,")
        print("   so `base_pose` cannot decide anything and section 2 is the only numeric anchor")
    else:
        errs = []
        for w, qb in base_recs:
            q = Z.quat48s(w[:3].astype(np.uint16)[None, :])[0]
            nn = float(np.linalg.norm(q)) or 1.0
            errs.append(np.degrees(2 * np.arccos(np.clip(abs(float(np.dot(q / nn, qb))), 0, 1))))
        errs = np.array(errs)
        print(f"   read as Quaternion48S at +0: median {np.median(errs):.4f} deg, "
              f"max {errs.max():.4f} deg over {len(errs)} bones with records")
        print("   read this number with section 2 in hand: a small median with a huge max means most")
        print("   of these bones are not actually animated and the residual is inherited, not decoded.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
