# The legacy RLE animation format (walked, verified, and refused)

141 of this dump's 182 models use the pre-frame-anim animation format and report
`legacy RLE anim format` from [`../pipeline/source_zanim.py`](../pipeline/source_zanim.py): every
`w_*` world model, every `shell_*` / `_dropped` / `_mag` variant, and 9 `v_*` models
(`v_shot_{mag7,nova,sawedoff,xm1014}`, `v_rif_{aug,sg556}_scopelensmask`,
`v_knife_{default_ct,default_t,kukri}_inspect`). None of them carries a clip the viewmodel packs bake,
which is why this stays a deliberate gap rather than a bug — but the reader is now *implemented*, and
what follows is what it found. Read the "refused" section before changing anything here.

## What is settled about the layout

`mstudioanimdesc_t` is the same header the ZANIM path reads; SourceIO exposes it as `animblock_id`
(the `.ani` block, 0 for inline), `animblock_offset`, `frame_count`, `section_frame_count` and
`get_sections()`, which yields `mstudioanimsections_t { anim_offset, anim_block }`. Measured, on this
dump:

| fact | evidence |
| --- | --- |
| record header is `u8 bone, u8 flags, i16 nextoffset`, payload at `+4` | chains walk every animation of every model |
| chains are in strictly increasing bone order, `nextoffset == 0` ends them | any other reading breaks the walk immediately |
| the **last** record's extent is the end of the block, not `off + 4` | `ammo_poses` (flags `0x1c`) and `@shoot2` (41 records) only walk with this rule |
| `mstudioanim_valueptr_t` is `short offset[3]` — **6 bytes**, not 12 | with 12 the run arrays land mid-record and `valid > total` fires everywhere |
| a run is `{u16 header, int16[valid]}` with `header = (total << 8) \| valid` | `valid <= total`, `total != 0`, and in-bounds hold on every channel that the layout reaches |
| a `0x20` record is 12 bytes and a `0x21` is 18, with **no variance**; a bare `0x01` is 10 | 80021 and 15073 records, every one the same size (`nextoffset` census over the dump) |
| so: a `Vector48` constant position costs exactly 6 bytes, and the constant rotation 8 = 6 + a 2-byte tail | `0x01` -> 4+6, `0x20` -> 4+8, `0x21` -> 4+8+6, `0x30`/`0x31` (which add `0x10 DELTA`) cost the same 12/18 — the delta bit carries no payload. `pipeline/qa/exploration/rle_census.py` section 1 |
| animated chains cost `4 + 6` (`0x08` ANIMROT, sizes 16…many) and `4 + 6 + 6` (`0x0c`) | one `mstudioanim_valueptr_t` per flag, then runs |
| inline section base = `entry + anim_offset + (animblock_offset - sections[0].anim_offset)`; a desc with no section table starts at `entry + animblock_offset` | the mag7's `base_pose` records decode from `entry + 1004`; reading `sec.anim_offset` raw produced `bone index 53 >= 52 bones` |

Bone indices are absolute (`mstudiobone_t::boneid`), and a bone with no record holds its
`mstudiobone_t` values for the whole timeline — a flat channel is *absent*, which is why the valueptr
offsets are read per axis with 0 meaning "does not move".

## Why the decode is refused

`_rle_verify` (`source_zanim.py`) checks two things a correct decode cannot violate, and the legacy
path refuses (`RLE_TRUSTED = False`) until both hold *and* someone can name the encoding:

* a Quaternion48 rebuilds `w` from `x,y,z`, so `|q| - 1` must be float noise;
* a first-person weapon's bone never sits further from the origin than a few times the model's extent.

The single-frame `base_pose` / `ammo_poses` sequences of the mag7 pass both and are still refused. The
`@`-clips fail the first one, per file, with the bone and channel named:

```
bone 35 frame 0: |quaternion|-1 = 0.212 (const rot channel of a flags 0x20 record) at @lookat01_loop, section 0
```

That number is the whole problem: the layout walks, and the eight bytes the format reserves for a
constant rotation are not a quaternion.

## Ruled out, with the measurement

Everything below was tried against the dump, so it does not have to be re-tried:

1. **A 12-byte `mstudioanim_valueptr_t`.** Fails: `valid > total` on nearly every run.
2. **An 8-byte constant quaternion read as `Quaternion48S`, at payload offset 0** — i.e. the ZANIM
   path's own reader. It fixes the `0x1c`/`0x04` positions (they had reached 5284 in, where a delta
   clip stays within tens of inches) but leaves `|q| - 1` between 0.068 and 0.212 depending on the
   bone, which is what reading *anything* out of a non-quaternion looks like.
3. **constants-first vs valueptrs-first ordering.** The chain walk cannot tell them apart — both score
   clean at `const_size` 6 and 8 across 192 structure variants — so this is only decidable by the
   numbers, and they say neither ordering produces unit quaternions.
4. **`Quaternion48`/`Quaternion48S` in any of six dequantisations** — `(v-16384)/23168`,
   `(v-32768)/32768`, the two 15-bit-masked forms, `i16/16384`, `i16/32768` — for every choice of
   which 3 of the record's first 4 words are the components. Census section 2, all 80021 `0x20`
   records: the best row (words (0,2,3) as `i16/32768`) still has a median
   `|x²+y²+z² - 1|` of 0.3585. A correct one is ~1e-4, because `w` is *rebuilt* from the other three
   and cannot miss unless the three are not components.
5. **`Quaternion64` (3 × `u32`) — the only 8-byte quaternion there is**, which the sizes make the
   natural candidate. Over 90164 records, four index rules (largest-component index stored plain, +1,
   +2 mod 4, or always `w`) × two masks: median `x²+y²+z²` = 1.48, 4.4% near the sphere, 85 deg off
   the rest pose. So the payload is 6 + 2, not 12/4 — and the 2-byte tail is not padding, since its
   distribution matches the data words' (median 20969, 81% inside `[16384, 49152]`).
6. **a `Vector48` euler constant** (`raw * rotation_scale` in some axis order — the shape the `0x1c`
   record's twelve leading zero bytes suggest, and the only reading the sizes leave room for). Fitting
   `bone.rot[axis]` against `raw[axis'] * rotation_scale` over the 429 base-pose records that carry one
   gives slope 0 and correlation ±0.1 at every byte shift. Beware the inverse trap: dividing by a
   further 16384 makes the delta so small that it reproduces `base_pose` to 0.012° *for every shift and
   every axis selection* — a channel scaled to nothing passes any test, which is exactly why a
   candidate has to fail a control. (Those records also carry `0x10`, so their constant is a *delta* and
   the base-pose fit cannot confirm item 6 in either direction; the check that can is smoothness of
   `@`-clip bone motion, which no candidate has reached yet because the quaternions never come out
   unit.)

What remains untried, and is the obvious next step: the payload may not start with the rotation at all
— the census's per-word statistics show the *fourth* word in the quaternion band 81% of the time and
the first three only 40–45%, so a `short` count or index table ahead of the channels, with the
constants interleaved per frame, would explain both the 8-byte width and the noise. Any layout worth
trying has to be scored by criteria 4 and 5 jointly (unit sphere *and* `base_pose` ≈ `mstudiobone_t`),
not by whether the chain walks: four different layouts walk cleanly and all four are wrong.
`pipeline/qa/exploration/rle_census.py` prints all of it, and is the thing to re-run after a change.

## What is *not* in doubt

* **Euler composition.** The animated rotation channels are eulers, and `mstudiobone_t` stores each
  bone's rest orientation twice (`RadianEuler rot` and `Quaternion quat`), so the rule is measurable.
  [`../pipeline/qa/euler_convention.py`](../pipeline/qa/euler_convention.py) searches all 192
  order/sign/unit candidates, collapses the ones that are the same rotation written two ways, and
  requires the winner to be exact on every bone with a non-trivial rest pose: on the current dump that
  is 207 models, 5353 bones, winner `ZYXe+++rad` (= intrinsic `XYZ`) at **0.0000 deg worst bone**,
  runner-up `XZY` 1.9408 deg. So `euler_to_quat` takes the stored radians, and the animated channels
  add to `bone.rot` with no conversion.
* **Delta semantics.** A `@`-prefixed sequence, or one with `ANIM_FLAG_DELTA`/`RLE_DELTA`, seeds
  `rot = (0,0,0,1)` and `pos = 0` and does not add the bone base. `mstudioanimdesc_t` has no parent
  pointer, so the engine's parent-pose blend is not reproducible here; the record is flagged
  `"delta": True` for that reason.
* **Which models need this.** `pipeline/validate_assets.py`'s `decoder coverage` line reports
  `41/182 models fully decoded, 141 need the legacy RLE reader`, and the model list is the same one
  this file names.

## Reproducing the numbers

```bash
# sizes, the unit-sphere census and the base-pose residuals, over the whole dump (numpy only)
/tmp/venv/bin/python pipeline/qa/exploration/rle_census.py
# the euler convention search over the whole dump
/tmp/venv/bin/python pipeline/qa/euler_convention.py
# which anims of one model walk, which refuse, and with what message
/tmp/venv/bin/python -c "
import sys; sys.path.insert(0,'pipeline'); import source_zanim as Z
P='build/content/CS2GO.Pack.Director.s.Cut.-.Heavy.Weapons/m_cs2_mag7/models/weapons/v_shot_mag7.mdl'
for k,v in Z.load_model_animations(P, strict=False).items():
    if k!='_meta': print(f'{k:24s}', v.get('error') or 'ok')
"
```

`rle_census.py` prints the fourth word of each record sitting in the quaternion value band 81% of the
time while the first three sit there 40-45% -- the strongest hint left, and the reason item 5 is worth
another try with the *payload* shifted by two bytes.

To flip `RLE_TRUSTED` on, the first command has to print `ok` for every animation of every model named
at the top of this file — and the layout it then uses needs a paragraph here explaining which
criterion each alternative failed, the way items 1–6 above do.
