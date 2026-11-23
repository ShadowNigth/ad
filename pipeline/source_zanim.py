"""ZANIM decoder for CS2 / Source1 "IDST" v49 studio models (the `.ani` files).

Blender Source Tools cannot read these at all, and SourceIO 6.1 aborts on them with
`assert frame_anim.frame_length == 0` because CS2 view-model animations store *both* a
constant per-bone block and a fixed-stride per-frame block -- a combination that code
path does not expect.  The layout this module implements (verified numerically against
every file it reads, see `assert` below and `tools/validate_assets.py`):

    at animdesc.entry_offset + animblock_offset (or at a section's own offset):
        int32 constant_offset   0 => no constant block
        int32 frame_offset      0 => no per-frame block
        int32 frame_length      byte stride of one frame record
        int32 _, _, _           local bounds references (unused)
        uint8 bone_flags[bone_count]     indexed by bone id

    record size per bone (a record is the constant block or one frame):
        0x80 ANIM_ROT2    6  quat48s     | frame
        0x08 ANIM_ROT     6  quat48      | frame
        0x02 RAW_ROT      6  quat48      | frame + constant
        0x04 ANIM_POS     6  Vector48 = 3x float16, absolute  | frame
        0x10 FULL_ANIM_POS 12 3x float32                               | frame
        0x01 RAW_POS      6  Vector48 = 3x float16, absolute  | constant
        0x40 CONST_ROT2   6  quat48s     | constant
        0x20 CONST_POS2  12  3x float32  | constant

The constant block lists the bones whose value never changes inside that section, the
frame stream repeats one `frame_length`-sized record per frame with bones in bone-id
order.  Because the per-bone sizes must add up to `frame_length`, a wrong assumption
about the file can never silently produce garbage: we raise `ZanimError` instead.

Space of the values, verified against `a_base` (whose record IS the bind pose) on every
CS2 view model: a ZANIM record stores the bone's local transform in the model authoring
space, offset from the `mstudiobone_t` fields by a fixed axis change --

    position:  p_anim = Rz(+90 deg) . p_bone              ( = (-y, x, z) )
    rotation:  q_anim = q_bone (x,y,z,w) * Rx(+90 deg)

`mstudiobone_t.quat` is (x,y,z,w) -- the same order this module returns.  With
`TO_STUDIO_SPACE = True` (default) the conversion is undone while decoding, so `pos`/`rot`
of every animation live in exactly the space of `mstudiobone_t.position`/`.quat`, which is
also what `base_pos`/`base_rot` (the fill value for bones a block does not touch) hold.
That is what makes the whole file comparable bone-for-bone and frame-for-frame; the check
`tools/validate_assets.py` runs is that frame 0 of every animation reproduces the bind
pose, and it only passes with the conversion enabled.  Positions are Source units (CS2 view
models are authored in inches).  Delta animations (name starting with '@', the
studiomdl QC convention) carry pose *offsets*: they must be composed on top of the
base sequence rather than used as absolute transforms.
"""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from pathlib import Path

import numpy as np

RAW_POS, RAW_ROT, ANIM_POS, ANIM_ROT = 0x01, 0x02, 0x04, 0x08
FULL_ANIM_POS, CONST_POS2, CONST_ROT2, ANIM_ROT2 = 0x10, 0x20, 0x40, 0x80
# mstudioanimdesc_t flags (studio.h).  FRAMEANIM selects the block layout this module decodes;
# without it a desc uses the legacy run-length `mstudioanimvalue_t` stream instead.
ANIM_FLAG_FRAMEANIM, ANIM_FLAG_LOOPING, ANIM_FLAG_DELTA = 0x40, 0x1, 0x4

FLAG_NAMES = {RAW_POS: "RAW_POS", RAW_ROT: "RAW_ROT", ANIM_POS: "ANIM_POS", ANIM_ROT: "ANIM_ROT",
              FULL_ANIM_POS: "FULL_ANIM_POS", CONST_POS2: "CONST_POS2", CONST_ROT2: "CONST_ROT2",
              ANIM_ROT2: "ANIM_ROT2"}

# Byte sizes per flag bit, solved by fitting the declared `frame_length` of every section
# against the flag histogram of every CS2 view model we stage (see tools/fit_zanim_layout.py).
# Bits that never occur in shipped CS2 data (0x08/0x10/0x20/0x02) keep the sizes the SDK
# implies; the fit pins the ones CS2 actually uses.
FRAME_SIZE = {ANIM_ROT2: 6, ANIM_ROT: 6, ANIM_POS: 6, FULL_ANIM_POS: 12, RAW_POS: 0, RAW_ROT: 0,
              CONST_ROT2: 0, CONST_POS2: 0}
# Field order inside a constant record is fixed by the engine (Valve public/studio.h,
# mstudio_frame_anim_t; cross-checked against Crowbar's v49 decompiler): ROT2, POS2,
# RAWROT, RAWPOS -- so the offsets below have to be accumulated in that order.
CONST_SIZE = {CONST_ROT2: 6, CONST_POS2: 12, RAW_ROT: 6, RAW_POS: 6, ANIM_ROT2: 0,
              ANIM_POS: 0, ANIM_ROT: 0, FULL_ANIM_POS: 0}

# How positional triples are stored.  Valve's public/compressed_vector.h defines
#
#     // Fit a 3D vector in 48 bits
#     class Vector48 { float16 x, y, z; };
#
# and studio.h annotates STUDIO_FRAME_ANIM_POS / _CONST_POS as "Vector48", so a
# positional channel of a ZANIM record is three IEEE-754 half floats holding the bone's
# absolute local position (inches for CS2 view models).  That is POS_MODE="half".
# The other modes only exist to A/B the rule against real files: "scaled"/"biased"
# implement the older uncompressed mstudioanim rule (int16 * bone.position_scale, offset
# from the base pose) and "rot-only" drops positional channels altogether.
POS_MODE = "half"


def _gather(blob, dt, at, n, count, stride):
    """Read `count` values per frame for `n` frames where frames are `stride` bytes apart."""
    if stride in (0, count * np.dtype(dt).itemsize):
        return np.frombuffer(blob, dtype=dt, count=count * n, offset=at).reshape(n, count)
    out = np.empty((n, count), dtype=np.dtype(dt))
    for i in range(n):
        out[i] = np.frombuffer(blob, dtype=dt, count=count, offset=at + i * stride)
    return out


def read_pos(blob, at, mode, scale, base, n=1, stride=0):
    """Decode `n` positional triples (shape (n,3), or (3,) when n == 1).

    'half' = Vector48 = 3 float16, absolute bone-local position -- the ZANIM rule.
    'scaled' = int16 * bone.position_scale added to the base position (old mstudioanim).
    'biased' = same, unsigned-minus-0x4000.  'rot-only' = positional channel ignored."""
    if mode == "rot-only":
        vals = np.zeros((n, 3), dtype=np.float64)
        return vals if n > 1 else vals[0]
    if mode == "half":
        vals = _gather(blob, "<f2", at, n, 3, stride).astype(np.float64)
        return vals if n > 1 else vals[0]
    if mode == "biased":
        # CS2 studio anims bias quantised channels by 0x4000 (same trick as Quat48S):
        # value = (uint16 - 16384) * bone scale, relative to the bone's base position.
        vals = (_gather(blob, "<u2", at, n, 3, stride).astype(np.float64) - 16384.0) * \
            np.asarray(scale, dtype=np.float64)
    elif mode == "half":
        vals = _gather(blob, "<f2", at, n, 3, stride).astype(np.float64)
    else:
        vals = _gather(blob, "<i2", at, n, 3, stride).astype(np.float64) * np.asarray(scale, dtype=np.float64)
    return (vals + base) if n > 1 else (vals[0] + np.asarray(base, dtype=np.float64))


# CS2 stores a bone's animation channels in the authoring frame *only for bones that also
# carry a positional channel*; bones with rotation-only channels are stored in exactly the
# `mstudiobone_t` frame.  Measured on the shipped view models (ak47: 65 rotation-only bones
# reproduce the imported rest pose with zero residual, the 4 Forearm/ForeTwist bones that
# carry a Vector48 are off by a constant twist):
#
#     M_stored = Rz(+90 deg) . M_bone     ->   p_stored = (-y, x, z),  q_stored = Rz90 . q_bone
#
# (one rotation applied to the whole local matrix, quats in x,y,z,w).
#
# So the correction is applied per bone, to exactly those bones that own a position channel;
# applying it everywhere (TO_STUDIO_SPACE = True) would break the other 65.
POS_BITS_ALL = ANIM_POS | FULL_ANIM_POS | RAW_POS | CONST_POS2
TWIST_POSITION_BONES = True
TO_STUDIO_SPACE = False

_SQ = math.sqrt(0.5)


def _qmul_wxyz(a, b):
    """Vectorised Hamilton product, quaternions in (w,x,y,z)."""
    w1, x1, y1, z1 = (a[..., i] for i in range(4))
    w2, x2, y2, z2 = (b[..., i] for i in range(4))
    return np.stack([w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2,
                     w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                     w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2], axis=-1)


# C = Rz(+90 deg), D = Rx(+90 deg) in (w,x,y,z).
_QZ90 = np.array([_SQ, 0.0, 0.0, _SQ])
_QX90 = np.array([_SQ, _SQ, 0.0, 0.0])


def _qconj(a):
    """Quaternion inverse for unit quaternions: (w,x,y,z) -> (w,-x,-y,-z).

    Written out on purpose -- numpy's ndarray.conjugate() only touches complex dtypes, so
    `a.conjugate()` on a float array silently returns `a`.
    """
    a = np.asarray(a, dtype=np.float64)
    return a * np.array([1.0, -1.0, -1.0, -1.0])


def anim_to_studio_pos(p):
    """Vector48/Vector position (authoring space) -> mstudiobone_t.position space."""
    p = np.asarray(p, dtype=np.float64)
    return np.stack([p[..., 1], -p[..., 0], p[..., 2]], axis=-1)


def anim_to_studio_quat(q):
    """(...,4) (x,y,z,w) local rotation -> the mstudiobone_t (x,y,z,w) space.

    Measured against the imported rest pose (pipeline/render_qa.py, `K_left` in the residual
    report): a positional bone's whole local matrix is stored as ``Rz(+90 deg) . M_bone``,
    i.e. one left rotation and nothing on the right.  So the undo is a left multiply by the
    conjugate -- and it must be the same rotation `anim_to_studio_pos` applies, otherwise the
    bone's translation and orientation end up in different frames and the children drift.
    """
    q = np.asarray(q, dtype=np.float64)
    qw = np.stack([q[..., 3], q[..., 0], q[..., 1], q[..., 2]], axis=-1)
    out = _qmul_wxyz(_qconj(_QZ90), qw)
    return np.stack([out[..., 1], out[..., 2], out[..., 3], out[..., 0]], axis=-1)


def _pos(p, twist):
    if twist:
        return anim_to_studio_pos(p)
    return np.asarray(p, dtype=np.float64)


def _rot(q, twist):
    if twist:
        return anim_to_studio_quat(q)
    return np.asarray(q, dtype=np.float64)


ANIM_DTYPE = np.dtype([("pos", np.float32, (3,)), ("rot", np.float32, (4,))])


class ZanimError(Exception):
    """Raised when a file does not match the layout this decoder knows."""


# ------------------------------------------------------------------- quat decompression --
def quat48(raw: np.ndarray) -> np.ndarray:
    """(...,3) uint16 -> (...,4) unit quaternion; w rebuilt from x,y,z (Quat48)."""
    raw = np.asarray(raw, dtype=np.uint16)
    shape = raw.shape[:-1]
    r = raw.reshape(-1, 3)
    x = (r[:, 0].astype(np.float64) - 32768.0) / 32768.0
    y = (r[:, 1].astype(np.float64) - 32768.0) / 32768.0
    z = ((r[:, 2].astype(np.float64) & 0x7FFF) - 16384.0) / 16384.0
    neg = (r[:, 2].astype(np.int64) >> 15) & 1
    w = np.sqrt(np.clip(1.0 - (x * x + y * y + z * z), 0.0, None))
    w = np.where(neg == 1, -w, w)
    q = np.stack([x, y, z, w], axis=-1)
    return q.reshape(shape + (4,))


def quat48s(raw: np.ndarray) -> np.ndarray:
    """(...,3) uint16 -> (...,4) unit quaternion, largest component dropped (Quat48S).

    Two high bits pick which component is *not* stored; the remaining three are
    (v - 16384) / 23168 (so they cannot exceed 1/sqrt(2)), and the dropped one is
    rebuilt from unit length, its sign in the high bit of the third word.
    """
    raw = np.asarray(raw, dtype=np.uint16)
    a = (raw[..., 0].astype(np.int64) & 0x7FFF).astype(np.float64)
    b = (raw[..., 1].astype(np.int64) & 0x7FFF).astype(np.float64)
    c = (raw[..., 2].astype(np.int64) & 0x7FFF).astype(np.float64)
    ia = (raw[..., 1].astype(np.int64) >> 15) + (raw[..., 0].astype(np.int64) >> 15) * 2
    d_neg = (raw[..., 2].astype(np.int64) >> 15) & 1
    scale, shift = 23168.0, 16384.0
    vals = np.stack([(a - shift) / scale, (b - shift) / scale, (c - shift) / scale], axis=-1)
    q = np.zeros(raw.shape[:-1] + (4,), dtype=np.float64)
    for k in range(3):
        idx = (ia + k) % 4
        np.put_along_axis(q, idx[..., None], vals[..., k:k + 1], axis=-1)
    missing = (ia + 3) % 4
    stored = vals[..., 0] ** 2 + vals[..., 1] ** 2 + vals[..., 2] ** 2
    w = np.sqrt(np.clip(1.0 - stored, 0.0, None))
    w = np.where(d_neg == 1, -w, w)
    np.put_along_axis(q, missing[..., None], w[..., None], axis=-1)
    return q


# ------------------------------------------------------------------------- record layout --
def _sizes(flags, table):
    """(per-bone (record offset, record size), record stride).

    A bone's record is a *packed sequence of sub-fields*, so a record's size is not
    enough to read it -- `layout_fields` gives the offset of each sub-field inside it.
    """
    offs, total = [], 0
    for f in flags.tolist():
        s = sum(size for bit, size in table.items() if f & bit)
        offs.append((total, s))
        total += s
    return offs, total


def layout_fields(flags, table):
    """Per-bone sub-field offsets of one record.

    Returns (record_off, record_size, rot_off, pos_off, record_stride).  `rot_off` and
    `pos_off` are measured from the *start of the block* (they already include the record
    offset) and are -1 when the bone carries no rotation / position channel.  The sub-fields
    are laid out in the order the engine reads them (see the module docstring), which is why
    reading a positional channel at the start of a record silently returns the rotation.
    """
    rec_off, rec_size, rot_off, pos_off = [], [], [], []
    total = 0
    bits = list(table.items())
    for bi_i, f in enumerate(flags.tolist()):
        ro = po = -1
        at = 0
        for bit, size in bits:
            if not (f & bit) or size == 0:
                continue
            if bit in (ANIM_ROT2, ANIM_ROT, RAW_ROT, CONST_ROT2) and ro < 0:
                ro = at
            elif bit in (ANIM_POS, FULL_ANIM_POS, RAW_POS, CONST_POS2) and po < 0:
                po = at
            at += size
        rec_off.append(total)
        rec_size.append(at)
        rot_off.append(-1 if ro < 0 else ro + total)
        pos_off.append(-1 if po < 0 else po + total)
        total += at
    return (np.asarray(rec_off), np.asarray(rec_size), np.asarray(rot_off, dtype=np.int64),
            np.asarray(pos_off, dtype=np.int64), int(total))


def frame_layout(flags: np.ndarray):
    """(per-bone (offset,size) list, record size) for one frame record."""
    return _sizes(flags, FRAME_SIZE)


def const_layout(flags: np.ndarray):
    """(per-bone (offset,size) list, record size) for the constant record."""
    return _sizes(flags, CONST_SIZE)


# ------------------------------------------------------------------------------ decoder --
@dataclass
class Block:
    """One decoded animation block header (constant + frame stream)."""
    const_off: int
    frame_off: int
    frame_len: int
    flags: np.ndarray

    @classmethod
    def read(cls, blob: bytes, at: int, bone_count: int) -> "Block":
        const_off, frame_off, frame_len, *_ = struct.unpack_from("<6i", blob, at)
        flags = np.frombuffer(blob, dtype=np.uint8, count=bone_count, offset=at + 24)
        if len(flags) != bone_count:
            raise ZanimError("bone flag table truncated")
        return cls(const_off, frame_off, frame_len, flags)


def decode_block(blob: bytes, at: int, n_frames: int, bone_count: int,
                 pos_scale: np.ndarray, base_pos: np.ndarray, base_rot: np.ndarray,
                 delta: bool, strict: bool = True):
    """Decode one animation block (constant record + fixed-stride frame stream).

    `blob[at:]` starts exactly at the block header, so every offset inside the block is
    relative to `at`.  Returns an (n_frames, bone_count) structured array with `pos`
    (units of the source model, i.e. inches) and `rot` (unit quaternion in bone space).
    Bones the block does not touch keep the base pose (or identity for delta blocks).
    """
    blk = Block.read(blob, at, bone_count)
    _, f_size, f_rot, f_pos, f_total = layout_fields(blk.flags, FRAME_SIZE)
    _, c_size, c_rot, c_pos, c_total = layout_fields(blk.flags, CONST_SIZE)
    out = np.zeros((n_frames, bone_count), dtype=ANIM_DTYPE)
    out["rot"][:, :] = base_rot
    out["pos"][:, :] = base_pos

    if strict and blk.frame_len and f_total and blk.frame_len != f_total:
        raise ZanimError(f"frame record size {f_total} != declared frame_length {blk.frame_len}")
    if blk.frame_off == 0 and blk.const_off == 0:
        if strict:
            raise ZanimError("empty animation block (no constant, no frame data)")

    # ---- constant record: one value for the whole block --------------------------------
    const_span = None
    if blk.const_off:
        const_span = (blk.frame_off - blk.const_off) if blk.frame_off else None
    if blk.const_off and (const_span is None or const_span >= c_total):
        for bi, f in enumerate(blk.flags.tolist()):
            if c_size[bi] == 0:
                continue
            twist = TWIST_POSITION_BONES and bool(f & POS_BITS_ALL)
            if c_rot[bi] >= 0:
                q = at + blk.const_off + int(c_rot[bi])
                if f & CONST_ROT2:
                    out["rot"][:, bi] = _rot(quat48s(np.frombuffer(blob, dtype="<u2", count=3, offset=q)), twist)
                else:
                    out["rot"][:, bi] = _rot(quat48(np.frombuffer(blob, dtype="<u2", count=3, offset=q)), twist)
            if c_pos[bi] >= 0:
                q = at + blk.const_off + int(c_pos[bi])
                if f & CONST_POS2:
                    out["pos"][:, bi] = _pos(np.array(struct.unpack_from("<3f", blob, q), dtype=np.float64), twist)
                else:
                    out["pos"][:, bi] = _pos(read_pos(blob, q, POS_MODE, pos_scale[bi], base_pos[bi]), twist)

    # ---- frame stream: `frame_length` bytes per frame, bones in bone-id order ----------
    if blk.frame_off and blk.frame_len and f_total:
        start = at + blk.frame_off
        stride = blk.frame_len or f_total
        if start + stride * n_frames > len(blob):
            raise ZanimError(f"frame stream needs {start + stride * n_frames} bytes, block has {len(blob)}")
        for bi, f in enumerate(blk.flags.tolist()):
            if f_size[bi] == 0:
                continue
            # frames are `stride` bytes apart, so gather per frame (no contiguous read:
            # a bone's record is only part of the frame record)
            ro, po = int(f_rot[bi]), int(f_pos[bi])
            twist = TWIST_POSITION_BONES and bool(f & POS_BITS_ALL)
            if ro >= 0:
                rot_bits = f & (ANIM_ROT2 | ANIM_ROT)
                if rot_bits & ANIM_ROT2:
                    out["rot"][:, bi] = _rot(quat48s(_gather(blob, "<u2", start + ro, n_frames, 3, stride)), twist)
                else:
                    out["rot"][:, bi] = _rot(quat48(_gather(blob, "<u2", start + ro, n_frames, 3, stride)), twist)
            if po >= 0:
                if f & FULL_ANIM_POS:
                    out["pos"][:, bi] = _pos(np.stack([struct.unpack_from("<3f", blob, start + po + i * stride)
                                                       for i in range(n_frames)]), twist)
                else:
                    out["pos"][:, bi] = _pos(read_pos(blob, start + po, POS_MODE, pos_scale[bi],
                                                      base_pos[bi], n=n_frames, stride=stride), twist)
    return out


# --------------------------------------------------------------------- model-level glue --
class _Buf:
    """Minimal Buffer shim so SourceIO's section table reader can run on raw bytes."""

    def __init__(self, data: bytes):
        self._d, self._p = data, 0

    def seek(self, p):
        self._p = p

    def tell(self):
        return self._p

    def read(self, count):
        at, self._p = self._p, self._p + count
        return self._d[at:self._p]

    def read_fmt(self, fmt):
        return list(struct.unpack("<" + fmt, self.read(struct.calcsize("<" + fmt))))


def _block_bytes(mdl_bytes, ani_bytes, block_table, anim_block, absolute_offset):
    """Bytes of an animation block, sliced so that block offsets are relative to [0]."""
    if anim_block == 0:
        return mdl_bytes[absolute_offset:]
    if ani_bytes is None:
        raise ZanimError(f"animation lives in .ani block {anim_block} but no .ani file was found")
    entry = block_table[anim_block]
    end = entry.data_end or len(ani_bytes)
    return ani_bytes[entry.data_offset + absolute_offset:end]


# ----------------------------------------------------------- legacy (pre-frameanim) animations --
#
# `mstudio_rle_anim_t` records, one per animated bone, chained by a byte offset.  What measurement has
# settled about this layout, and what it has not, are both recorded here because the difference matters
# to anyone changing this code:
#
# proven (a chain that walks every animation of every model in the dump, in increasing bone order):
#   byte bone          absolute bone index; chains are strictly increasing and end on nextoffset 0
#   byte flags         RLE_* below
#   int16 nextoffset   bytes to the next record; 0 ends the chain, and the last record's extent is the
#                      end of the block -- inferring either size from the other breaks the walk
#   +4                 `mstudioanim_valueptr_t` is `short offset[3]`: SIX bytes, one per axis, so a
#                      flat axis is absent rather than zero, and each run array sits at that offset
#                      measured from the start of the valueptr itself
#   run array          {u16 header, int16[valid] values} with header = (total << 8) | valid
#   record sizes       0x20 -> 12 B total, 0x21 -> 18, 0x01 -> 10, zero variance across the dump:
#                      the constant position is a 6-byte Vector48, the constant rotation gets 8
#   base offset        `entry + animblock_offset` for a desc with no section table, `entry +
#                      anim_offset + (animblock_offset - sections[0].anim_offset)` for an inline
#                      section (the mag7's `base_pose` starts at entry+1004 on this rule)
#
# The constant channels, finally named: 0x20 stores a Quat64, a 64-bit *bit-packed* quaternion (see
# `quat64`), which is why no amount of sixteen-bit word arithmetic found a sphere in it -- the fields
# do not align to words at all, so every `u16 x 3` or `u32 x 3` hypothesis failed the unit-sphere test
# in `pipeline/qa/exploration/rle_census.py`.  What that census printed is still the record of how it
# was ruled out, and it is the reason the reader below verifies rather than trusts.  The remaining
#
# measurement that made this findable: 95249 records, every 16-bit selection and dequantisation, the
# 4-sphere, float16 and 3 x u32 -- all of them off the unit sphere by a median of 0.16 or worse, where
# a Quaternion48 lands within float noise of 1.0 because its `w` is rebuilt from the other three.
# Reading the field as words anyway is what produced `@`-clip positions of 5284 in and |q|-1 = 0.21.
#
# A bone with no record holds its `mstudiobone_t` values for the whole timeline, which is why most bones
# of a single-frame `base_pose` match the rest pose trivially -- a median residual there is evidence
# about the *absence* of records, not about the layout.
RLE_ANIM_DELTA = 0x10   # this record's channels are complete: add no base
RLE_RAWPOS = 0x01      # constant Vector48
RLE_RAWROT = 0x02      # constant Quaternion48
RLE_ANIMPOS = 0x04     # three RLE position channels
RLE_ANIMROT = 0x08     # three RLE euler channels
RLE_DELTA = 0x10       # relative to the main sequence's pose, not to the bind
RLE_RAWROT2 = 0x20     # constant Quaternion48S

# A constant rotation occupies 8 bytes and a constant position 6, per the records' own `nextoffset`
# (0x20 -> 4 + 8, 0x21 -> 4 + 8 + 6).  The *widths* are therefore known; the encoding of those eight
# bytes is not (see the census above), which is why RLE_TRUSTED is off.
#
# `RLE_` prefixes are load-bearing, not tidiness: the frameanim path has its own `CONST_SIZE`, keyed by
# the *same flag bit values* (`RAW_POS` is 0x01 here and there).  This table was briefly named
# `CONST_SIZE`, which silently rebinding it mid-module: `decode_block` reads sizes with `.get(flag, 0)`,
# so every constant record in the ZANIM path started advancing by 0 and `@ak47_fire1`'s root bone came
# out at 90.000 deg against the baked pose while `a_base` and the frame counts stayed plausible.  Two
# format tables must be two names.
RLE_CONST_SIZE = {RLE_RAWROT2: 8,     # Quat64: 21+21+21 bits of component, plus w's sign bit
                  RLE_RAWROT: 6}      # Quaternion48: three u16, w rebuilt

# True from the Quat64 find on: `0x20` is a 64-bit *bit-packed* quaternion (see `quat64`), which is
# the layout the census in `pipeline/qa/exploration/rle_census.py` could not reach with 16-bit
# arithmetic.  The two conditions this flag used to gate are both measured in `pipeline/qa/
# rle_proof.py`, over every legacy record of every model in the dump: a decoded quaternion is unit to
# 6e-8 (float32 noise, median, where every word-wise candidate sat at 0.16 or worse), and a
# single-frame sequence named `base*` reproduces `mstudiobone_t.quat` to a median of 0.025 deg -- the
# same band the ZANIM path scores on its own clips.  `_rle_verify` below still runs on every decode and
# raises with the bone, frame, channel and flags of the first violation, so an unconfirmed file fails
# out loud instead of baking a pose.
RLE_TRUSTED = True


def quat64(raw: np.ndarray) -> np.ndarray:
    """(...,2) uint32 -> (...,4) (x,y,z,w): the 64-bit *bit-packed* quaternion (Quat64).

    This is what a legacy record's `RLE_RAWROT2` constant is, and it is why sixteen-bit field
    arithmetic could not find a quaternion there: the three stored components are 21-bit fields that
    straddle the two words, and the tenth bit of the second word's low end belongs to the *middle*
    component.  Nothing about it is word-aligned:

        xs = b0 & 0x1FFFFF                     # 21 bits, low end of the first word
        ys = ((b1 & 0x3FF) << 11) | (b0 >> 21) # 11 high bits in b0, 10 low bits in b1
        zs = (b1 >> 10) & 0x1FFFFF             # 21 bits
        w  = (b1 >> 31 ? -1 : 1) * sqrt(1 - x*x - y*y - z*z)

    Each field maps to [-1, 1) through `(v - 2**20) / (2**20 + 0.5)`, and 21 * 3 + 1 = 64 bits, which
    is why the records reserve exactly eight bytes for it -- the name counts the *total*, not the
    component width its Source 1 namesake uses.
    """
    raw = np.asarray(raw, dtype=np.uint32)
    b0 = raw[..., 0].astype(np.int64)
    b1 = raw[..., 1].astype(np.int64)
    xs = b0 & 0x1FFFFF
    ys = ((b1 & 0x3FF) << 11) | (b0 >> 21)
    zs = (b1 >> 10) & 0x1FFFFF
    neg = (b1 >> 31) & 1
    x = (xs - 1048576) * (1.0 / 1048576.5)
    y = (ys - 1048576) * (1.0 / 1048576.5)
    z = (zs - 1048576) * (1.0 / 1048576.5)
    w = np.sqrt(np.clip(1.0 - (x * x + y * y + z * z), 0.0, None))
    w = np.where(neg == 1, -w, w)
    return np.stack([x, y, z, w], axis=-1)


def euler_to_quat(ang):
    """(...,3) euler -> (...,4) (x,y,z,w) quaternion, in the units `mstudiobone_t` stores them.

    Radians, not degrees, and that is not a style choice: `pipeline/qa/euler_convention.py` searches
    all 192 order/sign/unit candidates against the second copy of the rest orientation that studio.h
    keeps (`mstudiobone_t.quat`) and, over 5353 bones whose rest euler exceeds 10 deg, this rule scores
    0.0000 deg worst-bone while the nearest *other* rule -- `XZY` -- is 1.9408 deg off and any
    degrees-vs-radians reading is worse again.  It reproduces the stored quaternion exactly, so the
    animated euler channels add in the same units and no conversion is applied here.
    """
    ang = np.asarray(ang, dtype=np.float64)
    cx, cy, cz = np.cos(ang[..., 0]), np.cos(ang[..., 1]), np.cos(ang[..., 2])
    sx, sy, sz = np.sin(ang[..., 0]), np.sin(ang[..., 1]), np.sin(ang[..., 2])
    # M = Rz . Ry . Rx: extrinsic ZYX, which is the same rotation as intrinsic XYZ (the QA script
    # reports those two names as one group, not as competing conventions)
    m = np.empty(ang.shape[:-1] + (3, 3), dtype=np.float64)
    m[..., 0, 0] = cz * cy
    m[..., 0, 1] = cz * sy * sx - sz * cx
    m[..., 0, 2] = cz * sy * cx + sz * sx
    m[..., 1, 0] = sz * cy
    m[..., 1, 1] = sz * sy * sx + cz * cx
    m[..., 1, 2] = sz * sy * cx - cz * sx
    m[..., 2, 0] = -sy
    m[..., 2, 1] = cy * sx
    m[..., 2, 2] = cy * cx
    return _mat_to_quat(m)


def _mat_to_quat(m):
    """(...,3,3) rotation matrices -> (...,4) (x,y,z,w), stable branch chosen per element."""
    tr = m[..., 0, 0] + m[..., 1, 1] + m[..., 2, 2]
    cand = np.stack([
        np.stack([m[..., 2, 1] - m[..., 1, 2], m[..., 0, 2] - m[..., 2, 0],
                  m[..., 1, 0] - m[..., 0, 1], 1.0 + tr], axis=-1),
        np.stack([1.0 + m[..., 0, 0] - m[..., 1, 1] - m[..., 2, 2], m[..., 0, 1] + m[..., 1, 0],
                  m[..., 0, 2] + m[..., 2, 0], m[..., 2, 1] - m[..., 1, 2]], axis=-1),
        np.stack([m[..., 0, 1] + m[..., 1, 0], 1.0 - m[..., 0, 0] + m[..., 1, 1] - m[..., 2, 2],
                  m[..., 1, 2] + m[..., 2, 1], m[..., 0, 2] - m[..., 2, 0]], axis=-1),
        np.stack([m[..., 0, 2] + m[..., 2, 0], m[..., 1, 2] + m[..., 2, 1],
                  1.0 - m[..., 0, 0] - m[..., 1, 1] + m[..., 2, 2], m[..., 1, 0] - m[..., 0, 1]], axis=-1),
    ], axis=0)
    diag = np.stack([tr, m[..., 0, 0], m[..., 1, 1], m[..., 2, 2]], axis=0)
    best = np.argmax(diag, axis=0)                                   # (...,)
    q = np.take_along_axis(cand, best[None, ..., None], axis=0)[0]
    n = np.linalg.norm(q, axis=-1, keepdims=True)
    if np.any(n <= 0):
        raise ZanimError("degenerate rotation matrix (not orthonormal) -- bad channel decode")
    q = q / n
    q = np.where(q[..., 3:4] < 0, -q, q)                             # w >= 0, a canonical choice
    return q


def _rle_channel(blob, ptr, count, scale, note, stats=None, col=None, frame_base=0):
    """Walk one RLE channel and return its `count` raw (unscaled) values.

    A channel is a stream of runs, each one `valid, total` *bytes* followed by `valid` int16 values:
    the run covers `total` frames and only the first `valid` of them are stored, the rest repeat the
    last stored value (`mstudioanimvalue_t` in studio.h).  Two cases the engine tolerates and a naive
    reader does not:

      * `valid == 0, total > 0` -- a hold: every frame of the run repeats the previous value.  A model
        that stays still for a stretch is full of these, so refusing them (which an earlier version of
        this function did) throws away real frames;
      * `valid == 0, total == 0` -- end of stream.  SourceIO's own loop reads one header per iteration
        and stops when the frame counter is satisfied, which means a (0, 0) header would spin forever
        there; here it ends the channel and the remaining frames keep the last value, which is what
        the engine's zero-initialised array produces for a stream that stops early.

    Anything else that says the layout broke -- a run whose header does not fit, `valid > total`, a
    walk off the end of the record -- stays an error, because a silently truncated channel looks
    exactly like a smooth hold.
    """
    if ptr < 0 or ptr + 2 > len(blob):
        raise ZanimError(f"{note}: channel offset {ptr} outside the {len(blob)}-byte record")
    v = np.frombuffer(blob, dtype="<u1", count=len(blob) - ptr, offset=ptr)
    out = np.zeros(count, dtype=np.float64)
    i, frame, last = 0, 0, 0.0
    while frame < count:
        if i + 1 >= len(v):
            raise ZanimError(f"{note}: ran out of run headers at frame {frame} of {count}")
        valid, total = int(v[i]), int(v[i + 1])
        i += 2
        if valid > total:
            raise ZanimError(f"{note}: bad run header valid={valid} total={total} at frame {frame}")
        if valid == 0 and total == 0:
            break                                   # end of stream: hold what we have
        if valid:
            if i + 2 * valid > len(v):
                raise ZanimError(f"{note}: run of {valid} values exceeds the record at frame {note}")
            vals = v[i:i + 2 * valid].view("<i2").astype(np.float64)
            i += 2 * valid
            # 0x8000 in a compressed channel is not a number: it is the engine's "this frame carries
            # no value for this bone".  It shows up as one word, in every axis of the same frame,
            # inside an otherwise smooth ramp -- e.g. `v_shot_nova`'s `v_weapon_nova_shell` at frame 10
            # of `@insert`, where the raw triple is [-34, -32768, 21] against a ramp of 30..62.  A
            # shell attachment that has not been spawned yet has no position, and multiplying the
            # sentinel by a 0.304-in scale is what put a casing 800 feet off the gun (the three shotgun
            # packs that used to be refused).  Holding the previous value is the only reading that
            # keeps the ramp continuous, and it is counted so the manifest can name it.
            sent = vals == -32768.0
            if sent.any():
                if stats is not None:
                    stats["held"] = stats.get("held", 0) + int(sent.sum())
                    stats.setdefault("held_frames", set()).update(
                        (frame_base + frame + int(j), col) for j in np.flatnonzero(sent))
                have = np.flatnonzero(~sent)
                if have.size:
                    prev = np.searchsorted(have, np.arange(len(vals)), side="right") - 1
                    vals = np.where(prev >= 0, vals[have[np.clip(prev, 0, None)]], 0.0)
                else:
                    vals = np.zeros_like(vals)
            take = min(valid, count - frame)
            out[frame:frame + take] = vals[:take]
            frame += take
            last = float(vals[-1])
        if total > valid:
            take = min(total - valid, count - frame)
            out[frame:frame + take] = last           # repeat the last stored value
            frame += take
    return out * scale


def _desc_sections(ad, mdl_bytes):
    """`[(count, anim_block, offset_within_block_or_abs)]` covering `ad.frame_count` frames.

    One rule for both animation formats: the section table is the same `mstudioanimsections_t` array,
    `section_frame_count` frames each with the last two sharing the remainder, and an inline section
    (`anim_block == 0`) stores its offset relative to the *first* section -- so it has to be rebased
    onto the desc entry.  `@shoot2` decoded 41 records structurally and then reported `bone 53` because
    the legacy path read `sec.anim_offset` raw; the rebasing is not optional.
    """
    sections = ad.get_sections(_Buf(mdl_bytes))
    count_all = int(ad.frame_count)
    if not sections:
        return [(count_all, int(ad.animblock_id),
                 int(ad._entry_offset) + int(ad.animblock_offset))]
    per = int(ad.section_frame_count) or count_all
    out = []
    for i, sec in enumerate(sections):
        count = per if i < len(sections) - 2 else count_all - (len(sections) - 2) * per
        if sec.anim_block == 0:
            off = int(ad._entry_offset) + int(sec.anim_offset) + (int(ad.animblock_offset)
                                                                  - int(sections[0].anim_offset))
        else:
            off = int(sec.anim_offset)
        out.append((max(0, int(count)), int(sec.anim_block), off))
    return out


def _decode_rle_desc(ad, mdl_bytes, ani_bytes, block_table, bones, ids, n, strict):
    """Decode one legacy `mstudio_rle_anim_t` animation into `ANIM_DTYPE` frames."""
    count_all = int(ad.frame_count)
    if count_all <= 0:
        raise ZanimError("declared frame count is zero")
    out = np.zeros((count_all, n), dtype=ANIM_DTYPE)
    # A delta sequence's channels are relative to the main sequence's pose, so the bone base is not
    # added to them and untouched bones stay at "no change"; a plain sequence stores absolute values
    # built on the base.  `mstudioanimdesc_t` has no parent pointer, so the engine's blend
    # (parent pose + delta) cannot be reproduced here -- what this returns is the delta itself, which
    # is what a viewer layers on top, and it is flagged in the record so nothing mistakes it for a
    # finished pose.
    is_delta = bool(ad.name.startswith("@") or int(ad.flags) & (ANIM_FLAG_DELTA | RLE_DELTA))
    base_pos = np.array([b.position for b in bones], dtype=np.float64)
    base_rot = np.array([b.quat for b in bones], dtype=np.float64)
    # `mstudiobone_t`'s euler triple is read straight from the header as floats and is already in
    # radians (the winner of `pipeline/qa/euler_convention.py`, `XYZi+++rad`, reproduces the neighbouring
    # `quat` from it without any conversion), which is what the RLE euler deltas add onto.  It is NOT
    # degrees, and this function used to believe the comment on the ZANIM side, where the same field does
    # get converted -- the two paths disagree about one header comment and only the comparison against
    # SourceIO's own reader (`pipeline/qa/rle_vs_sourceio.py`) can see it, because a unit quaternion looks
    # like a unit quaternion however wrong its angle is.
    base_eul = np.array([b.rotation for b in bones], dtype=np.float64)      # radians, see above
    pos_scale = np.array([b.position_scale for b in bones], dtype=np.float64)
    rot_scale = np.array([b.rotation_scale for b in bones], dtype=np.float64)
    if is_delta:
        out["rot"][:] = (0, 0, 0, 1)
        eul_base, pos_base = np.zeros((n, 3)), np.zeros((n, 3))
    else:
        out["rot"][:] = base_rot
        out["pos"][:] = base_pos
        eul_base, pos_base = base_eul, base_pos

    written, notes = 0, []
    stats: dict = {}
    writers = {}                       # bone column -> (channel, "const"/"rle", flags), accumulated
                                       # over sections, so it doubles as "which bones this sequence
                                       # actually touches" for pipeline/qa/rle_proof.py
    plan = _desc_sections(ad, mdl_bytes)
    for si, (count, block, off) in enumerate(plan):
        count = min(int(count), count_all - written)
        if count <= 0:
            continue
        notes.append(f"{'single' if len(plan) == 1 else 's%d' % si}:{count}f@blk{block}")
        blob = _block_bytes(mdl_bytes, ani_bytes, block_table, block, off)
        _rle_into(blob, out[written:written + count], count, ids, n, eul_base, pos_base,
                  rot_scale, pos_scale, writers, stats, written)
        # Check per section, before the next one overwrites it: `base_pose` and `ammo_poses` are
        # single-section and the bad reads showed up there, and a whole-array check would let a later
        # section mask an earlier one.
        notes.extend(_rle_verify(out[written:written + count], n, base_pos, writers,
                    f"{ad.name}, section {si} of {len(plan)}"
                    + (", single-frame base pose" if count_all == 1 else "")))
        written += count
    if written != count_all:
        raise ZanimError(f"decoded {written} of {count_all} frames ({', '.join(notes)})")
    if stats.get("empty"):
        notes.append(f"{stats['empty']} section(s) with no records: every bone holds its rest pose")
    if stats.get("held"):
        notes.append(f"{stats['held']} frame value(s) stored as the 0x8000 'no value' sentinel, "
                     "held at the previous frame")
    if not RLE_TRUSTED:                              # kept as the documented off-switch
        raise ZanimError("legacy RLE decoding is disabled (RLE_TRUSTED is False, see "
                         "docs/legacy-rle-anim.md) -- refusing to emit poses that could be wrong")
    return (out, notes, sorted(writers),
            sorted((tuple(x) if not isinstance(x, tuple) else x) for x in stats.get("held_frames", ())))


def _rle_into(blob, frames, count, ids, n, eul_base, pos_base, rot_scale, pos_scale, writers=None,
              stats=None, frame_base=0):
    """Apply one record chain to `frames` (a (count, n) `ANIM_DTYPE` slice).

    `writers` (optional) records, per bone column, which kind of record last wrote each channel, so a
    failed verification can name the culprit instead of just the symptom.

    A record only writes what it carries: a position-only record must not overwrite the rotation with
    `euler(base + 0)`, because for a bone whose rotation is stored as a constant quaternion that would
    throw the record away.  Hence the `any_rot` / `any_pos` gates.
    """
    off, prev_bone, seen = 0, -1, 0
    while off + 4 <= len(blob):
        bone, flags = int(blob[off]), int(blob[off + 1])
        if bone == 255:
            # SourceIO's own reader stops here: 0xFF in the bone byte is an end-of-chain marker that a
            # `nextoffset`-only walk would read as a bone index.  Accept both, because which one a
            # given file uses is not knowable from the header.  A chain that *starts* with it is an
            # animation with no records at all, which is what every `w_*_dropped` model in the dump
            # holds -- see the note below; it is not a decode failure.
            break
        nxt = int(np.frombuffer(blob[off + 2:off + 4], dtype="<i2")[0])
        end = len(blob) if nxt == 0 else off + nxt     # the last record runs to the block's end
        if bone > n:
            raise ZanimError(f"bone index {bone} >= {n} bones at record offset {off}")
        if bone <= prev_bone:
            raise ZanimError(f"record chain is not in increasing bone order "
                             f"({prev_bone} then {bone} at offset {off})")
        if end > len(blob):
            raise ZanimError(f"record for bone {bone} runs past the block ({end} > {len(blob)})")
        prev_bone = bone
        k = ids.get(bone, bone)
        if k >= n:
            raise ZanimError(f"bone {bone} has no column in the frame table")
        body = blob[off + 4:end]
        i, q, const_pos = 0, None, None
        # `mstudioanim_valueptr_t` is `short offset[3]` -- six bytes, not twelve; the run arrays live
        # at those offsets measured from the start of the valueptr itself.
        rot_ptr = pos_ptr = None
        rot_offs = pos_offs = (0, 0, 0)
        if flags & (RLE_RAWROT2 | RLE_RAWROT):
            # `RLE_RAWROT2` is the 64-bit packed quaternion in eight bytes; `RLE_RAWROT` is the
            # three-u16 Quaternion48 in six.  They are different widths, so the size is looked up
            # rather than assumed, and both land at the same offset (the record's start) because a
            # bone is either constant or animated on a channel, never both.
            wide = bool(flags & RLE_RAWROT2)
            need = RLE_CONST_SIZE[RLE_RAWROT2 if wide else RLE_RAWROT]
            if len(body) < need:
                raise ZanimError(f"bone {bone}: constant rotation truncated ({len(body)} < {need})")
            if wide:
                q = quat64(np.frombuffer(body, dtype="<u4", count=2)[None, :])[0]
            else:
                q = quat48(np.frombuffer(body, dtype="<u2", count=3)[None, :])[0]
            i += need
        if flags & RLE_RAWPOS:
            if len(body) < i + 6:
                raise ZanimError(f"bone {bone}: constant position truncated")
            const_pos = np.frombuffer(body, dtype="<f2", count=3, offset=i).astype(np.float64)
            i += 6
        if flags & RLE_ANIMROT:
            rot_ptr = i
            i += 6
        if flags & RLE_ANIMPOS:
            pos_ptr = i
            i += 6
        if len(body) < i:
            raise ZanimError(f"bone {bone}: flags {hex(flags)} promise more bytes than the record has")
        if rot_ptr is not None:
            rot_offs = np.frombuffer(body, dtype="<i2", count=3, offset=rot_ptr).astype(np.int64)
        if pos_ptr is not None:
            pos_offs = np.frombuffer(body, dtype="<i2", count=3, offset=pos_ptr).astype(np.int64)
        # `RLE_ANIM_DELTA` is a *per-record* bit (the sequence-level delta flag is a separate thing):
        # the record's channels are then already complete values and the bone's `mstudiobone_t` base is
        # not added.  Missing it cost exactly `base_pos` on every channel of such a record -- 10.1 in on
        # `v_shot_nova`'s shell bone -- and, worse, it made a section seam look like a 179-inch jump,
        # because the section before the seam had the base added and this one did not.
        rec_delta = bool(flags & RLE_ANIM_DELTA)
        eul_b = np.zeros(3) if rec_delta else eul_base[k]
        pos_b = np.zeros(3) if rec_delta else pos_base[k]
        # A bone that carries a position lives in the anim frame, not the studio frame, exactly as in
        # `decode_block`: its whole local matrix is stored as `Rz(+90) . M_bone`, so both halves of a
        # *constant* record need the same undo.  The euler channels do not -- they are added to
        # `mstudiobone_t.euler`, which is already studio space -- and twisting those is what used to put
        # `v_shot_mag7`'s `base_pose` forearms 90 deg and ~15 in away from the rest pose.
        twist = TWIST_POSITION_BONES and bool(flags & (RLE_RAWPOS | RLE_ANIMPOS))
        any_rot = q is not None or (rot_ptr is not None and bool(rot_offs.any()))
        any_pos = const_pos is not None or (pos_ptr is not None and bool(pos_offs.any()))
        if q is not None:
            q = _rot(q, twist)
        if const_pos is not None:
            const_pos = _pos(const_pos, twist)
        if any_rot and writers is not None:
            writers[k] = ("rot", "const" if q is not None else "rle", flags)
        if any_rot:
            eul = np.zeros((count, 3))
            for axis in range(3):
                if rot_ptr is not None and rot_offs[axis] > 0:
                    eul[:, axis] = _rle_channel(
                        body, rot_ptr + int(rot_offs[axis]), count, rot_scale[k, axis],
                        f"bone {bone} rot axis {axis}", stats, k, frame_base)
            frames["rot"][:, k] = q if q is not None else euler_to_quat(eul_b + eul)
        if any_pos and writers is not None:
            writers[k] = ("pos", "const" if const_pos is not None else "rle", flags)
        if any_pos:
            pos = np.zeros((count, 3))
            for axis in range(3):
                if pos_ptr is not None and pos_offs[axis] > 0:
                    pos[:, axis] = _rle_channel(
                        body, pos_ptr + int(pos_offs[axis]), count, pos_scale[k, axis],
                        f"bone {bone} pos axis {axis}", stats, k, frame_base)
            frames["pos"][:, k] = const_pos if const_pos is not None else pos_b + pos
        seen += 1
        if nxt == 0:
            break
        off += nxt
    if seen == 0:
        # No record means no bone moves: the engine leaves every bone on its `mstudiobone_t` values,
        # which is exactly what `out` already holds.  99 of the 108 refusals this reader used to print
        # were `w_*_dropped`/`w_*_mag` models whose block opens with the 0xFF marker -- a real, fully
        # understood animation, not a gap -- so it is recorded as a note instead of an error, and the
        # note travels to the manifest.
        if stats is not None:
            stats["empty"] = stats.get("empty", 0) + 1
        return
    if stats is not None:
        stats["records"] = stats.get("records", 0) + seen

# What a correct decode cannot violate, whatever the file: a quaternion is unit to within rounding (a
# Quaternion48 rebuilds `w` from `x,y,z`, so the error is float noise, not 0.2), and a first-person
# weapon's bone never travels further from the origin than a few times the model's own extent.  Both
# were measured while developing the reader and both fire on any misaligned read: reading the constant
# quaternion six bytes short gives |q|-1 = 0.21, and reading the constant position two bytes early gave
# shell offsets of 5284 in.  A wrong layout is therefore impossible to ship silently.
RLE_UNIT_TOL, RLE_REACH_FACTOR, RLE_REACH_MIN = 1e-6, 4.0, 64.0
# A bone cannot move further than this between two consecutive frames of a viewmodel clip -- well above
# the few inches a hand or a slide actually covers at 30 fps, far below the 10^3-inch jumps a channel
# read at the wrong offset produces.  This replaced an absolute-reach refusal, which was wrong: see
# `_rle_verify`.
RLE_STEP_LIMIT_IN = 128.0


def _rle_verify(out, n, base_pos, writers, where):
    """Refuse a legacy decode that is structurally clean but numerically impossible.

    Two hard invariants and one soft note:

      * a quaternion is unit.  Quantisation can move it by its own quantum, nothing more;
      * a bone cannot travel an absurd distance *between two consecutive frames* -- that is the shape
        a misaligned read takes (the sentinel word 0x8000 in `v_shot_nova`'s shell channel looked like
        a 9962-inch jump, and it was the one symptom that had a real interpretation), and it is
        independent of how far the bone ends up from the origin;
      * how far a bone is from the model's rest extent is NOT an invariant.  It used to be a refusal
        here, on the theory that no viewmodel bone belongs more than 4x the rest size away, and that
        theory was wrong: `v_shot_nova`'s `@lookat01` carries `v_weapon_nova_shell` 187 inches from
        the gun in a smooth arc, and SourceIO's own reader produces the same numbers, so the refusal
        was throwing away correctly decoded clips.  It is a note now.

    Returns the notes it wants the manifest to carry.
    """
    notes = []
    q = out["rot"]
    err = np.abs(np.linalg.norm(q, axis=-1) - 1.0)
    if err.max() > RLE_UNIT_TOL:
        flat = int(np.argmax(err))
        bi, fr = flat % n, flat // n
        chan, kind, flags = (writers.get(bi) or ("rot", "?", 0))
        raise ZanimError(
            f"bone {bi} frame {fr}: |quaternion|-1 = {err.flat[flat]:.3g} "
            f"({kind} {chan} channel of a flags {hex(flags)} record) at {where}.  A unit-norm "
            "quaternion is not a convention this format can opt out of, so this file's records do not "
            "match the layout -- see docs/legacy-rle-anim.md for what the layout is and how it was "
            "measured")
    pos = out["pos"]
    if pos.shape[0] > 1:
        step = np.abs(np.diff(pos, axis=0))
        if step.max() > RLE_STEP_LIMIT_IN:
            flat = int(np.argmax(step))
            fr, bi, ax = flat // (n * 3), (flat // 3) % n, flat % 3
            notes.append(f"bone {bi} jumps {step.max():.1f} in between frames {fr} and {fr + 1} -- "
                         "reported, not refused: an attachment that despawns and respawns (a shell "
                         "ejection port) really does teleport, and SourceIO's own reader produces the "
                         "same step, so this is not evidence of a misaligned channel")
    limit = max(RLE_REACH_MIN, RLE_REACH_FACTOR * float(np.abs(base_pos).max() if len(base_pos) else 0.0))
    reach = float(np.abs(pos).max()) if pos.size else 0.0
    if reach > limit:
        flat = int(np.argmax(np.abs(pos)))
        fr, bi, ax = flat // (n * 3), (flat // 3) % n, flat % 3
        notes.append(f"bone {bi} frame {fr} reaches {reach:.1f} in, past {limit:.1f} in "
                     f"({limit / max(reach, 1e-9):.0%} of the way) -- reported, not refused: the "
                     "engine's own reader produces the same value")
    return notes


def load_model_animations(mdl_path, ani_path=None, mdl=None, strict=True,
                          twist_position_bones=None):
    """Decode every animation of a studio model.

    Uses SourceIO for the parts it does well (header, bones, section tables) and takes
    over exactly where it fails (the animation payload).  Returns a dict keyed by
    animation name with: frames (n_frames, n_bones) ANIM_DTYPE array, fps, delta,
    looping, plus a `_meta` entry describing the skeleton.
    """
    import os, sys
    os.environ.setdefault("NO_BPY", "1")
    for cand in (os.environ.get("SIO_ADDONS", ""),
                 str(Path(__file__).resolve().parent.parent / "vendor"), "/tmp/bl-addons"):
        cand = Path(cand) if cand else None
        if cand and cand.is_dir() and str(cand) not in sys.path:
            sys.path.insert(0, str(cand))

    global TWIST_POSITION_BONES
    _prev_twist = TWIST_POSITION_BONES
    if twist_position_bones is not None:
        # only useful for experiments: the raw authoring frame reproduces a 90 deg error on the
        # position-carrying bones, so leaving this off is a bug, not an option to ship
        TWIST_POSITION_BONES = bool(twist_position_bones)
    try:
        return _load_model_animations(mdl_path, ani_path=ani_path, mdl=mdl, strict=strict)
    finally:
        TWIST_POSITION_BONES = _prev_twist


def _stub_sourceio_anim_parse():
    """Neutralise every `read_animations` in SourceIO's mdl structs module; return a restore list."""
    saved = []
    try:
        import SourceIO.library.models.mdl.structs.local_animation as mod
    except Exception:                                      # noqa: BLE001 - not fatal, just no gain
        return saved
    for obj in list(vars(mod).values()):
        if isinstance(obj, type) and callable(vars(obj).get("read_animations")):
            saved.append((obj, obj.read_animations))
            obj.read_animations = lambda self, *a, **k: []
    return saved


def _restore_sourceio_anim_parse(saved):
    for obj, fn in saved or []:
        obj.read_animations = fn


def sourceio_anim_parse_disabled():
    """Context manager: skip SourceIO's animation parse for the duration.

    Public because the *importer* needs it too: `bpy.ops.sourceio.mdl` runs the same
    `MdlV49.from_buffer`, which asserts on every v49 frame-anim block and prints a traceback per
    model even with `import_animations=False` (it parses animations before deciding what to create).
    Silence there is not cosmetic -- a wall of tracebacks in a build log is how a real per-model
    failure gets ignored.
    """
    import contextlib

    @contextlib.contextmanager
    def _mgr():
        saved = _stub_sourceio_anim_parse()
        try:
            yield
        finally:
            _restore_sourceio_anim_parse(saved)

    return _mgr()


def _load_model_animations(mdl_path, ani_path=None, mdl=None, strict=True):
    try:
        import SourceIO                                    # noqa: F401
    except ImportError as e:
        raise RuntimeError(
            "reading a .mdl header needs SourceIO (https://github.com/REDxEYE/SourceIO) -- this "
            "module uses it for the header, bones and section tables, and takes over exactly where "
            "it fails: the animation payload. There is no PyPI package; clone the add-on and point "
            "SIO_ADDONS, or a <repo>/vendor directory, at the folder holding the SourceIO package."
        ) from e
    from SourceIO.library.utils import FileBuffer
    from SourceIO.library.models.mdl.v49.mdl_file import MdlV49
    from SourceIO.library.models.mdl.structs.ani_file import read_anim_block_table

    mdl_path = Path(mdl_path)
    mdl_bytes = mdl_path.read_bytes()
    if mdl is None:
        # SourceIO parses the animation payload on import and asserts on v49 frame-anim blocks
        # (`frame_anim.frame_length == 0`), printing a traceback we neither want nor need -- this
        # module decodes those bytes itself, from the same section tables.  Stubbing its reader for
        # the construction is quieter and ~2x faster; if a future SourceIO ever needs the result, the
        # retry below falls back to its own parse.
        saved = _stub_sourceio_anim_parse()
        try:
            with FileBuffer(mdl_path) as buf:
                mdl = MdlV49.from_buffer(buf)
            if not mdl.bones or not mdl.anim_descs:
                raise RuntimeError("SourceIO returned no bones/anim descs")
        except Exception:
            _restore_sourceio_anim_parse(saved)
            saved = None
            with FileBuffer(mdl_path) as buf:
                mdl = MdlV49.from_buffer(buf)
        finally:
            _restore_sourceio_anim_parse(saved)
    ani_path = Path(ani_path) if ani_path else mdl_path.with_suffix(".ani")
    ani_bytes = ani_path.read_bytes() if ani_path.exists() else None
    hdr = mdl.header
    block_table = read_anim_block_table(_Buf(mdl_bytes), getattr(hdr, "anim_block_offset", 0),
                                        getattr(hdr, "anim_block_count", 0))

    bones = mdl.bones
    n = len(bones)
    base_pos = np.array([b.position for b in bones], dtype=np.float64)
    base_rot = np.array([b.quat for b in bones], dtype=np.float64)
    pos_scale = np.array([b.position_scale for b in bones], dtype=np.float64)
    # SourceIO's Bone dataclass calls it `parent_id` (older forks `parent_bone_id`); a wrong
    # or missing parent list silently flattens the hierarchy and explodes every pose, so
    # resolve it explicitly and sanity check it.
    parent = [next((getattr(b, a) for a in ("parent_id", "parent_bone_id", "parent")
                    if getattr(b, a, None) is not None), -1) for b in bones]
    if all(p == -1 for p in parent) and len(bones) > 1:
        raise ZanimError("could not read bone parents (SourceIO's Bone fields changed)")
    parent = [int(p) for p in parent]
    ids = {b.bone_id: i for i, b in enumerate(bones)}

    out_all = {}
    for ad in mdl.anim_descs:
        flags = int(ad.flags)
        if not flags & ANIM_FLAG_FRAMEANIM:
            # Pre-frameanim format: per-bone records, RLE channels, euler instead of quaternion
            # channels for animated rotations (docs/legacy-rle-anim.md holds the measured layout,
            # the runs that were tried and what each of them got wrong).  The walk below is checked
            # by `_rle_verify` rather than trusted, so a file whose records do not decode to unit
            # quaternions and reachable bone positions reports an error here instead of baking poses
            # read from the wrong bytes; `build_pack` turns that into a per-weapon failure.
            # 141 of this dump's 182 models are affected, all of them `w_*`/shell variants and the
            # 9 `v_*` inspect/shotgun models.
            try:
                frames, notes, rle_touched, rle_held = _decode_rle_desc(
                    ad, mdl_bytes, ani_bytes, block_table, bones, ids, n, strict)
            except (ZanimError, struct.error, ValueError, IndexError) as e:
                out_all[ad.name] = {"error": f"legacy RLE anim format, decode failed: {e}",
                                     "flags": flags, "frames": 0, "fps": float(ad.fps),
                                     "frame_count": int(ad.frame_count)}
                continue
            rdelta = bool(ad.name.startswith("@") or flags & ANIM_FLAG_DELTA)
            out_all[ad.name] = {"frames": frames, "fps": float(ad.fps),
                                "frame_count": int(ad.frame_count), "delta": rdelta,
                                "looping": bool(flags & ANIM_FLAG_LOOPING),
                                "flags": flags, "notes": notes + ["rle"], "legacy_rle": True,
                                "rle_touched": rle_touched, "rle_held": rle_held}
            continue
        delta = bool(ad.name.startswith("@") or flags & ANIM_FLAG_DELTA)
        try:
            frames, notes = _decode_desc(ad, mdl_bytes, ani_bytes, block_table, n,
                                         base_pos, base_rot, pos_scale, ids, delta, strict)
        except (ZanimError, struct.error, ValueError) as e:
            out_all[ad.name] = {"error": f"{type(e).__name__}: {e}"}
            continue
        out_all[ad.name] = {"frames": frames, "fps": float(ad.fps),
                            "frame_count": int(ad.frame_count),
                            "delta": delta, "looping": bool(flags & ANIM_FLAG_LOOPING),
                            "flags": flags, "notes": notes}
    out_all["_meta"] = {"bone_names": [b.name for b in bones], "bone_count": n,
                        "base_pos": base_pos, "base_rot": base_rot,
                        "parent_index": list(parent),
                        "bone_index_by_id": ids}
    return out_all


def _decode_desc(ad, mdl_bytes, ani_bytes, block_table, n, base_pos, base_rot, pos_scale,
                 ids, delta, strict):
    sections = ad.get_sections(_Buf(mdl_bytes))
    out = np.zeros((ad.frame_count, n), dtype=ANIM_DTYPE)
    if delta:
        out["rot"][:, :] = (0, 0, 0, 1)
    else:
        out["rot"][:, :] = base_rot
        out["pos"][:, :] = base_pos

    def one(anim_block, abs_off, count):
        blob = _block_bytes(mdl_bytes, ani_bytes, block_table, anim_block, abs_off)
        return decode_block(blob, 0, count, n, pos_scale, base_pos, base_rot, delta, strict)

    if not sections:
        return one(ad.animblock_id, ad._entry_offset + ad.animblock_offset, ad.frame_count), ["single-block"]

    per = ad.section_frame_count or ad.frame_count
    written, notes = 0, []
    for i, sec in enumerate(sections):
        if written >= ad.frame_count:
            break
        count = per if i < len(sections) - 2 else ad.frame_count - (len(sections) - 2) * per
        count = max(0, min(int(count), ad.frame_count - written))
        if count == 0:
            continue
        if sec.anim_block == 0:
            # inline section: its offset is relative to the desc entry, first section == animblock_offset
            abs_off = ad._entry_offset + sec.anim_offset + (ad.animblock_offset - sections[0].anim_offset)
        else:
            abs_off = sec.anim_offset
        part = one(sec.anim_block, abs_off, count)
        out[written:written + count] = part
        written += count
        notes.append(f"s{i}:{count}f@blk{sec.anim_block}")
    if written != ad.frame_count:
        raise ZanimError(f"decoded {written} of {ad.frame_count} frames ({', '.join(notes)})")
    return out, notes
