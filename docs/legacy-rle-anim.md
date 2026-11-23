# The legacy RLE animation format (walked, verified, decoded)

141 of this dump's 182 models use the pre-frame-anim animation format: every `w_*` world model, every
`shell_*` / `_dropped` / `_mag` variant, and 9 `v_*` models (`v_shot_{mag7,nova,sawedoff,xm1014}`,
`v_rif_{aug,sg556}_scopelensmask`, `v_knife_{default_ct,default_t,kukri}_inspect`). They are decoded
now, by [`../pipeline/source_zanim.py`](../pipeline/source_zanim.py), and the last blocker was a
constant that is **not a set of 16-bit words**: flag `0x20` stores a `Quat64` — 21+21+21 bits of
component plus `w`'s sign bit, packed across two `uint32`, so no field is word-aligned.

End to end, on the same day: `182/182 models fully decoded` from `pipeline/validate_assets.py`, all 45
weapon packs build (the four `v_shot_*` packs that used to fail are among them), and `sweep_gates.py`
reports 0 failures over 45 packs with those four at the *top* of the batch — `v_shot_sawedoff` 0.000 deg,
`v_shot_nova` 0.005 deg, `v_shot_mag7` 0.008 deg as-baked residual, and their authored arms already within
0.04–1.76 in of the weapon.

## The layout, as measured

`mstudioanimdesc_t` is the header the ZANIM path reads too; SourceIO exposes it as `animblock_id`,
`animblock_offset`, `frame_count`, `section_frame_count`, `get_sections()`. On this dump:

| fact | evidence |
| --- | --- |
| record = `u8 bone, u8 flags, i16 nextoffset`, payload at `+4` | chains walk every animation of every model (135,396 records) |
| `0xFF` in the bone byte ends the chain; a chain that *starts* with it is an animation with no records | 99 `w_*_dropped` / `w_*_mag` blocks open with it; the engine leaves every bone on its `mstudiobone_t` values, which the reader reproduces and notes |
| bone order strictly increases, `nextoffset == 0` ends the chain | any other reading breaks the walk immediately |
| the **last** record's extent is the end of the block, not `off + 4` | `ammo_poses` (`0x1c`) and `@shoot2` (41 records) only walk with this rule |
| `0x20` = Quat64, **8 bytes**; `0x02` = Quaternion48, **6 bytes**; `0x01` = float16×3 position, **6 bytes**; so `0x20` → 4+8, `0x01` → 4+6, `0x21` → 4+8+6 | the record-size census (`pipeline/qa/exploration/rle_census.py` section 1), plus 90,999 (anim, bone) pairs agreeing to 1e-3 in with SourceIO's own reader |
| `mstudioanim_valueptr_t` is `short offset[3]` — **6 bytes**; each axis offset is relative to the *start of its own valueptr*, and `0` means "this axis does not move" | with 12 the run arrays land mid-record and `valid > total` fires everywhere; the 15-frame nova record's three channels sit exactly 32 bytes apart (2 header + 2·15) |
| a run is `{u8 valid, u8 total, int16[valid]}`; the run covers `total` frames and the frames past `valid` repeat the last stored value; `valid = 0, total > 0` is a hold; `valid = 0, total = 0` ends the stream | SourceIO's `_read_rle_compressed_data`; and `valid > total` or a run header past the payload is a layout failure, which the reader raises |
| a value of exactly `0x8000` means *"this frame carries no key for this bone"*, not a number | the one word in an otherwise smooth ramp, in **every** axis of the same frame: `v_shot_nova`'s shell bone at frame 10 of `@insert` reads `[..., 62, -34, -32768, 21, ...]`. Held at the previous frame, and counted (`held_frames`), never silently |
| per-record `0x10 ANIM_DELTA`: that record's channels are complete — do not add the bone base | `v_shot_nova`'s shell bone was 10.1 in off (`mstudiobone_t.position` at X/Z) in `@lookat01`, and the section seam read as a 179-in jump because the previous section had the base added and this one did not |
| rotation channels are **euler deltas in radians**, added to `mstudiobone_t`'s stored euler, which is *also* radians; position channels are int16 × `position_scale`, added to `mstudiobone_t.position` | 90,999 (anim, bone) pairs exactly equal to SourceIO's reader; and see the units note below |
| a constant record for a bone with a positional channel is in the **anim frame**: it needs the same `Rz(+90)` undo the ZANIM path applies, to the quaternion *and* the position | without it, `v_shot_mag7`'s `base_pose` forearms sit 90.000 deg and 14.77 in from the rest pose; with it, 0.044 deg and 0.006 in |
| inline section base = `entry + anim_offset + (animblock_offset - sections[0].anim_offset)`; a desc with no section table starts at `entry + animblock_offset` | the mag7's `base_pose` records decode from `entry + 1004`; reading `sec.anim_offset` raw produced `bone index 53 >= 52 bones` |

## What the engine's own header says

The reference `studio.h` in this repository's notes is the **Source 1** header, so it is not authority on
v49's widths — but on the two things it does state, it agrees with the decode above:

```c
#define STUDIO_ANIM_RAWPOS    0x01 // Vector48
#define STUDIO_ANIM_RAWROT2   0x20 // Quaternion64
struct mstudioanimvalue_t { union { struct { byte valid, total; } num; }; short value; };
```

`0x20 // Quaternion64` is the bit-packed reading, and it is the only name in the file that explains an
8-byte constant whose components are not words — which is what the census could not square.  Where the
header and the files disagree, the files win: `0x01 // Vector48` is *not* what v49 stores (SourceIO reads
three float16s there, and that reading is what reproduces `mstudiobone_t.position` on the base-pose
control).  And `mstudioanimvalue_t` is the same struct this reader walks, once its `union` is read the way
the engine's own `pAnimvalue()`/`Next()` arithmetic reads it: the header bytes belong to the *first* entry
of a run and the rest of the run is bare `short value`s, which is why a 15-frame channel is 2 + 2·15 = 32
bytes and not 15 × 4.  Reading a header comment as a guarantee about a different engine version is how
3 × `u32` got tried in the first place.

## How it was proven, and why those two checks

`RLE_TRUSTED = True` is a claim about the *numbers*, not about the chain walking — four wrong layouts
walked cleanly. Two gates back it, and both run over the whole dump:

```
[models] 207 searched, 1586 legacy animations decoded, 0 refused
[unit]   worst |q|-1 over those animations: median 5.96e-08 max 1.19e-07  (tolerance 1e-04)
[base]   1 base sequences: worst rest-pose residual median 0.0441 deg / 0.0061 in
[verdict] PASS: the legacy layout is confirmed by both numbers
```

* [`../pipeline/qa/rle_proof.py`](../pipeline/qa/rle_proof.py) — every decoded quaternion is unit to
  float32 noise (median 5.96e-08, worst 1.19e-07; every word-wise candidate sat at **0.16 or worse**),
  and a single-frame `base*` sequence reproduces `mstudiobone_t` on the bones its records actually
  touch (0.044 deg / 0.006 in, the same band the ZANIM path scores on its own clips).
* [`../pipeline/qa/rle_vs_sourceio.py`](../pipeline/qa/rle_vs_sourceio.py) — reads the same bytes with
  SourceIO's own `StudioAnimDesc.read_animations` and diffs them per bone: **90,999 (animation, bone)
  pairs agree to 0.000000 in / 0.000000 rad**. Four things are excluded on purpose and *counted on the
  same screenful*, so a hole in the coverage never hides behind the `PASS`: the `0x8000` frames (1,841 —
  this reader holds, SourceIO multiplies the sentinel by the scale, which is how a shell attachment ends
  up 9962 in from the gun in *its* output); non-delta rows where SourceIO left an all-zero quaternion
  because its valueptrs-only branch read no channel (17,006 — see `q_alignment` under "Ruled out");
  delta rows where this reader seeds "no contribution" for a bone the clip does not animate and SourceIO
  seeds the bone's rest pose (782,677); and delta positions, which agree only after the setup-pose add
  (9,315 of them, 100 % exact).

The second gate is the one that found the last two bugs. Neither of the first gate's criteria can see
them: a wrong unit on an euler channel still produces perfect unit quaternions, a base added where it
should not be produces a smooth, plausible curve, and a base pose is made of constant records so it
never walks a channel. Anything that disagrees by the bone's own `mstudiobone_t` offset was the tell —
which is also why the comparison runs with `twist_position_bones=False`: it checks the *decode*, while
`arms_contact.py` and the residual gates check the convention layered on top.

## Delta, in two rules — and the first one was silently dropped in every delta clip

A delta clip is two separate questions, and reading them as one was the bug:

1. **What a record's numbers are relative to** is decided by the *record's* `0x10` bit alone. A
   `@`-prefixed or `ANIM_FLAG_DELTA` description must **not** turn the bone base off for records that did
   not set `0x10`. The reader used to zero `eul_base`/`pos_base` for the whole description, which dropped
   the `mstudiobone_t` offset from 610 (bone, clip) positions — `v_zeus` `pelvis` by 42.8 in — and every
   rotation in every delta clip, including all four shotgun `@lookat01` inspect poses. `RLE_DELTA_USES_RECORD_BIT`
   reproduces the old rule; nothing normalises it. Nothing inside one model could see the error: the
   channels stay smooth, only the composition is wrong.
2. **What a bone the clip does not animate does instead** is a composition choice, not a decoding fact.
   This reader seeds identity/zero — "this clip contributes nothing", which is what the bake needs,
   because `build_pack` composes every array onto the rest pose. SourceIO seeds the bone's rest
   quaternion and position, which is what a layer that writes absolute local rotations needs. Both are
   right in their own model, so the gate counts the rows (782,677) and compares everything else — which
   still checks `0x10`, the run walk, both scales and `quat64()` *inside* delta clips.

Only `v_shot_sawedoff` and `v_shot_xm1014` ship a delta `@lookat01` as their sole animation, so that is
where rule 1 shows up in the output: sawedoff's weapon residual went 9.43 in → 2.52 in (its `arm_fit`
now solves instead of refusing) and its hand gap 0.26 in → 5.05 in. Correct numbers, looser pose — the
game's own inspect does hold that gun out at arm's length.

## Ruled out, with the measurement — all of it word-wise

Nothing below has to be re-tried. Each item reads the constant as 16- or 32-bit *words*, which is the
one thing the field is not; the components straddle the word boundary, so they cannot land:

1. **A 12-byte `mstudioanim_valueptr_t`.** `valid > total` on nearly every run.
2. **Quaternion48S at payload offset 0** (the ZANIM reader). Fixes the `0x1c`/`0x04` positions (which had
   reached 5284 in) but leaves `|q| - 1` between 0.068 and 0.212.
3. **constants-first vs valueptrs-first ordering.** The chain walk cannot tell them apart — both score
   clean at `const_size` 6 and 8 over 192 structure variants — so only the numbers decide.
4. **`Quaternion48`/`Quaternion48S` in all six dequantisations** (`(v-16384)/23168`, `(v-32768)/32768`,
   both 15-bit-masked forms, `i16/16384`, `i16/32768`) for every choice of which 3 of the first 4 words
   are the components, over all 95,249 records that carry a constant rotation: best row (words (1,2,3),
   `i16/32768`) median `|x²+y²+z²-1|` = **0.3750**. A correct reading is ~1e-4 and ~100%, because `w` is
   *rebuilt* from the other three and cannot miss. Section 3 asks the same question of the bytes with a
   known answer and gets **139.5 deg** off `mstudiobone_t.quat` at the median.
5. **`Quaternion64` as 3 × `u32`** — the Source 1 namesake, and the wrong guess: median `x²+y²+z²` =
   1.711, 2.8% near the sphere; as float16 halves the components are ~24976 (integers). Its 8-byte width
   is *total* bits (21·3 + 1), not 3 components of 32.
6. **A `Vector48` euler constant.** Fitting `bone.rot[axis]` against `raw[axis'] * rotation_scale` over
   the 429 base-pose records gives slope 0 and correlation ±0.1 at every byte shift. Beware the inverse
   trap that made an earlier attempt think it had passed: divide by a further 16384 and the delta is so
   small it reproduces `base_pose` to 0.012° *for every shift and every axis selection*. A candidate has
   to fail a control, not only reproduce the answer.
7. **`0x40 CONST_ROT2` / `0x80 CONST_POS2` per-frame `m_const` tables.** Zero records in 135,396 carry
   either bit, so the format needs no `m_const` reader; the flags are still refused by name if a file
   ever uses them.

The census in `pipeline/qa/exploration/rle_census.py` prints items 4 and 5 and is the thing to re-run if
any of this is ever in doubt again.

There is no field to read this from. `mstudiobone_t` in Source 1 carries `qAlignment`, which would state
the authoring-frame rotation per bone and make the whole question empirical; v49's bone record does not
populate it — measured across 925 bones of 25 models, every `q_alignment` SourceIO returns is
`(0, 0, 0, 0)`, i.e. the default its reader writes when the field is absent. So the rule has to be
*derived* (from the rest pose and the contact gates), and it has to be re-derived if a future dump starts
populating that field, at which point the constant `Rz(+90)` becomes the bug.

## Two lessons this path left behind

* **A heuristic gate can refuse correct data.** The reader used to *refuse* any position further than
  4× the model's rest extent, on the theory that no viewmodel bone belongs that far out. That is true of
  hands and false of **attachments that despawn and respawn**: `v_shot_nova`'s `v_weapon_nova_shell`
  rides a smooth arc 187 in from the gun in `@lookat01`, and SourceIO's own reader produces the same
  numbers. The reach and step checks are now *notes* in the manifest; the refusals are the invariants
  that are actually format-independent (unit quaternion, and a run header that does not fit).
* **Two flag tables share bit values.** `AnimBoneFlags` (legacy: `0x10 ANIM_DELTA`, `0x20 ANIM_RAW_ROT2`)
  and `AniBoneFlags` (frameanim: `0x10 FULL_ANIM_POS`, `0x20 CONST_POS2`) collide at three of eight
  values. Assuming one table is what made the census above score `0x20` records against a Quaternion48S
  rule that never applied to them. The legacy constants are `RLE_`-prefixed on purpose: an earlier
  version of this reader declared `CONST_SIZE` at module scope, shadowed the frameanim table of the same
  name, and the ZANIM path (which looks sizes up with `.get(flag, 0)`) began skipping its constant
  fields — frame counts, bone counts and `a_base` all stayed plausible, and the 41-pack
  `pipeline/qa/sweep_gates.py` sweep is what caught it at 90.000 deg on the ak47 root bone.

## What is not in doubt

* **Euler composition.** `mstudiobone_t` stores each bone's rest orientation twice (`RadianEuler rot`
  and `Quaternion quat`), so the rule is measurable:
  [`../pipeline/qa/euler_convention.py`](../pipeline/qa/euler_convention.py) searches all 192
  order/sign/unit candidates over 207 models / 5353 non-trivial rest bones and requires the winner to be
  exact on every one of them — `ZYXe+++rad` (= intrinsic `XYZ`) at **0.0000 deg worst**, runner-up
  `XZY` 1.9408 deg. `euler_to_quat` therefore takes the stored radians and the animated channels add to
  `bone.rot` with no conversion.
* **Delta semantics — two separate rules, and they were conflated here.** (i) *What a record's numbers
  are relative to* is decided by the **record's** `0x10` bit: without it the channel adds the bone's
  `mstudiobone_t` base, with it the channel is complete. A `@`-prefixed or `ANIM_FLAG_DELTA` description
  does *not* turn that off for records that did not set it — the reader used to zero the base for the
  whole description, which is 610 (bone, clip) positions and every delta rotation in the dump being
  wrong in a way no in-model check can see (they stay smooth). `RLE_DELTA_USES_RECORD_BIT` is the switch.
  (ii) *What a bone with no channel in this clip does* is a composition choice, not a decoding fact: this
  reader seeds identity/zero ("this clip adds nothing"), because `build_pack` composes every array against
  the rest pose, while SourceIO fills in the bone's rest quaternion/position, which is right for a layer
  writing absolute local rotations. `rle_vs_sourceio.py` skips and counts those rows (782,677 of them)
  rather than pretending either side is wrong. `mstudioanimdesc_t` has no parent pointer, so the engine's
  parent-pose blend is not reproducible here; the record is flagged `"delta": True` for that reason.
* **Which models needed this.** `pipeline/validate_assets.py`'s `decoder coverage` line is the count,
  and `build/decode_report.json` carries the per-model reasons.

## Reproducing the numbers

```bash
/tmp/venv/bin/python pipeline/qa/rle_proof.py             # the two pass conditions, whole dump
/tmp/venv/bin/python pipeline/qa/rle_vs_sourceio.py       # frame-for-frame against SourceIO's reader
/tmp/venv/bin/python pipeline/qa/exploration/rle_census.py # sizes, the unit-sphere census, base residuals
/tmp/venv/bin/python pipeline/qa/euler_convention.py      # the euler search
# which anims of one model decode, which refuse, and with what message
/tmp/venv/bin/python -c "
import sys; sys.path.insert(0,'pipeline'); import source_zanim as Z
P='build/content/CS2GO.Pack.Director.s.Cut.-.Heavy.Weapons/m_cs2_mag7/models/weapons/v_shot_mag7.mdl'
for k,v in Z.load_model_animations(P, strict=False).items():
    if k!='_meta': print(f'{k:24s}', v.get('error') or 'ok')
"
```

`RLE_TRUSTED` is the documented off-switch: set it to `False` and every legacy description refuses with a
message that names the flag and the document, instead of emitting poses nobody has checked.
