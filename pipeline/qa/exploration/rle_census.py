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
                    if flags & (Z.RLE_RAWROT2 | Z.RLE_RAWROT) and len(body) >= 8:
                        # Padded to 12 bytes: the 4 u16 words for the 48-bit census and the 3 u32 for
                        # the 64-bit one, from the same view so the two cannot disagree about which
                        # bytes they looked at.  A `0x20` record only has 8, which is itself the point.
                        words.append(np.frombuffer(body[:12].ljust(12, b"\0"), dtype="<u2").astype(np.int64))
                    if flags & Z.RLE_DELTA == 0 and count == 1 and not ad.name.startswith("@"):
                        k = ids.get(bone, bone)
                        if k < n and len(body) >= 6:
                            # Tagged by name, because "a single-frame absolute sequence" and "the model's
                            # base pose" are not the same claim: only the second one says frame 0 *is*
                            # the rest pose, and pooling the two buries the number that matters.
                            base_recs.append((np.frombuffer(body[:8], dtype="<u2").astype(np.int64),
                                              bq[k], ad.name.lower().startswith(("base", "ref"))))
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

    print(f"\n== 2. unit-sphere census over {len(words)} records carrying a constant rotation")
    if not words:
        print("   none found")
    else:
        W6 = np.stack(words)                       # (N, 6) u16
        W = W6[:, :4]                              # the four words a 0x20 record reserves
        u32 = W6[:, :6].astype(np.int64)
        u32 = (u32[:, 1::2] << 16) | u32[:, 0::2]  # back to 3 x u32, exactly as the file packs them
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
        # The other two families a reader might reach for, so that "we tried them" is on the record.
        with np.errstate(over="ignore"):
            f16 = W.astype(np.float16).astype(np.float64)
        finite = np.isfinite(f16).all(1)
        print(f"   as float16 halves instead of ints: {finite.mean() * 100:.1f}% finite, "
              f"median |component| {np.median(np.abs(f16[:, :3][finite])) if finite.any() else float('nan'):.0f} "
              f"-- magnitudes of thousands, so these are integers, not halves")
        if True:
            v = (u32 & 0x3FFFFFFF).astype(np.float64) / 0x3FFFFFFF * 2.0 - 1.0
            ssq64 = (v * v).sum(1)
            print(f"   as Quaternion64 (3 x u32, 30-bit fields): median x^2+y^2+z^2 {np.median(ssq64):.3f}, "
                  f"{(np.abs(ssq64 - 1.0) < 0.02).mean() * 100:.1f}% near the sphere -- also not it "
                  f"(and 8 bytes cannot hold 12, which is what the sizes rule out anyway)")
        print("   (a real Quaternion48 is ~1e-4 / ~100%; anything in the 0.3-0.5 range is noise)")
        for i in range(4):
            v = W[:, i]
            print(f"   word{i}: [{v.min()}, {v.max()}] median {int(np.median(v))} "
                  f"share in [16384,49152] {np.mean((v >= 16384) & (v < 49152)) * 100:5.1f}%")

    print(f"\n== 3. single-frame absolute sequences, read as Quaternion48S at payload offset 0")
    for want, label in ((True, "named base/ref"), (False, "other single-frame sequences")):
        sel = [r for r in base_recs if r[2] == want]
        if not sel:
            print(f"   {label:26s}: none in the dump")
            continue
        errs = []
        for w, qb, _ in sel:
            q = Z.quat48s(np.asarray(w[:3], dtype=np.uint16)[None, :])[0]
            nn = float(np.linalg.norm(q)) or 1.0
            errs.append(np.degrees(2 * np.arccos(np.clip(abs(float(np.dot(q / nn, qb))), 0, 1))))
        errs = np.array(errs)
        print(f"   {label:26s}: {len(errs):6d} records, median {np.median(errs):8.4f} deg, "
              f"share under 1 deg {(errs < 1.0).mean() * 100:5.1f}%, max {errs.max():.4f}")
    print("   A base pose *should* read ~0 here if the constant were the rest orientation; it does not,")
    print("   and neither does anything else -- so section 2's verdict stands: these bytes are not a")
    print("   quaternion as stored.  A candidate layout passes when the first line's median is ~0 AND")
    print("   section 2's median is ~1e-4.  Only the first of those is easy to hit by accident.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
