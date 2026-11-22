# The legacy RLE animation format (not implemented, recipe preserved)

141 of this dump's 182 models report `legacy RLE anim format (no ANIM_FLAG_FRAMEANIM)` from
[`../pipeline/source_zanim.py`](../pipeline/source_zanim.py). They are every `w_*` world model, every
`shell_*` / `_dropped` / `_mag` variant, and 9 `v_*` inspect models (`v_shot_{mag7,nova,sawedoff,
xm1014}`, `v_rif_{aug,sg556}_scopelensmask`, `v_knife_{default_ct,default_t,kukri}_inspect`). None of
them carries a clip the viewmodel packs bake, which is why this reader is the one deliberate gap in
the decoder rather than a bug.

What is known about the format, so that implementing it is transcription and not archaeology:

## Where the bytes are

`mstudioanimdesc_t` (quoted from `studio.h`, see [`reference-sources.md`](reference-sources.md)) is the
same header the ZANIM path reads, and it holds two things the frame-anim path ignores:

```c
int   animblock;    // 0 => the data is inline in the .mdl, else .ani block index
int   animindex;    // offset of the first mstudio_rle_anim_t, relative to the animdesc start
int   numframes;
short zeroframespan, zeroframescount;   // bones with no data at all in a span hold their bind value
int   sectionindex; int sectionframes;  // mstudioanimsections_t { int animoffset; int framecount; }
```

so the entry point is `animdesc + animindex` (inline) or
`block_table[animblock].data_offset + animindex` (`.ani` sidecar) — the identical rule the ZANIM path
uses, already implemented in `source_zanim._anim_bytes`.

## Per-bone records

Unlike ZANIM there is no frame table: the data is a **linked list of per-bone channels**, RLE runs
shared by the whole timeline.

```c
struct mstudio_rle_anim_t {            // 4-byte header, then channel data
    byte bone;                         // bone index
    byte flags;                        // STUDIO_ANIM_* below
    short nextoffset;                  // to the next bone's record, 0 to stop
};
#define STUDIO_ANIM_RAWPOS   0x01      // Vector48 at pData (constant position)
#define STUDIO_ANIM_RAWROT   0x02      // Quaternion48 at pData (constant rotation)
#define STUDIO_ANIM_ANIMPOS  0x04      // mstudioanim_valueptr_t following
#define STUDIO_ANIM_ANIMROT  0x08      // mstudioanim_valueptr_t at pData, pos's after it
#define STUDIO_ANIM_DELTA    0x10
#define STUDIO_ANIM_RAWROT2  0x20      // Quaternion64 at pData
```

`pData() = record + 4`; the constant quaternion (if `RAWROT`) is 8 bytes there and a constant
`Vector48` position (if `RAWPOS`) follows it, exactly as in the ZANIM constant block — those two
readers are reusable (`read_quat48`, `read_vec48`). The animated channels are
`mstudioanim_valueptr_t { short offset[3]; }`, offsets relative to the valueptr itself, 0 meaning
"this axis does not move":

```c
union mstudioanimvalue_t { struct { byte valid; byte total; } num; short value; };
```

a run is that header word followed by `valid` value words. Walk it with the engine's `ExtractAnimValue`
(`k` is the 0-based frame):

```python
idx = 0
while values[idx].num.total <= k:
    k -= values[idx].num.total
    idx += values[idx].num.valid + 1
raw = values[idx + (k + 1 if values[idx].num.valid > k else values[idx].num.valid)].value
```

## From channels to a bone transform

`mstudiobone_t` supplies both the scale and the base, and SourceIO exposes all four fields:

```c
Vector pos; Quaternion quat; RadianEuler rot; Vector posscale; Vector rotscale;
matrix3x4_t poseToBone; Quaternion qAlignment;
```

Rotation channels are **euler radians, not quaternions** — `value * bone.rotscale[axis] + bone.rot[axis]`
— and position channels `value * bone.posscale[axis] + bone.pos[axis]`. The engine then composes
`Matrix3FromAngles(rot_total)` and pre-multiplies the bone's `poseToBone`, which is the same axis
alignment the SMD importer applies through `q_alignment`.

## What to check it against

Do not trust a smooth result; the format is small enough to prove:

1. Frame 0 of a model's `base_pose` / `@idle` should reproduce `mstudiobone_t` for the bones the
   record does not touch — the residual test `pipeline/validate_assets.py` already runs on the ZANIM
   path (`a_base` vs `base_rot`, currently 0.03–0.08°). Expect the same magnitude, and expect the
   author's base pose to differ on one or two bones, not on the chain.
2. Every euler order matters here and none of them is documented in the file: `AngleQuaternion` is
   pitch-yaw-roll in radians while `Matrix3FromAngles` is not the same function. Identify the order by
   A/B against `poseToBone`-composed `mstudiobone_t` values across many models — the mistake to avoid
   is accepting whichever order happens to work on a symmetric rest pose (a SMD probe in
   `pipeline/qa/exploration/smd_euler.py` found all six orders gave 0.00° on the data it had).
3. `runlen == framecount` on every run, and the last run's `total >= remaining frames`, or the record
   walk has slipped a byte — the same "declared length equals consumed bytes" discipline that made the
   ZANIM block layout provable.
