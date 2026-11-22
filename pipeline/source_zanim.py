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
            # Pre-frameanim format: per-bone `mstudioanimvalue_t` runs ({byte valid, byte total}
            # then `total` shorts, value = short * scale + base, walked by subtracting `total`
            # from the frame index) inside mstudioanim_t's 6 channel offsets.  Crowbar's
            # ExtractAnimValue is the reference walk.  Saying so here beats the nonsense the
            # block reader would otherwise report, since those bytes are not a frame stride.
            out_all[ad.name] = {"error": "legacy RLE anim format (no ANIM_FLAG_FRAMEANIM); "
                                         "needs mstudioanimvalue_t decoding",
                                "flags": flags, "frames": 0, "fps": float(ad.fps),
                                "frame_count": int(ad.frame_count)}
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
