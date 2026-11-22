# QA gates

Three scripts, three independent claims about a built pack. Each is a *gate*: it exits non-zero when
the thing it checks is wrong, so a build that "finished without errors" is not the same as a build
that passed. Run them from the repo root inside headless Blender -- see
[`../headless_blender_stubs.py`](../headless_blender_stubs.py) for the stub libs and the `LD_LIBRARY_PATH`
they need. `arms_bind.py` is pure numpy and needs no Blender at all.

```sh
LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/qa/pose_residual.py \
    --blend dist/m_cs2_ak47/v_rif_ak47.blend --anim ak47_reload --frame 37
LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/qa/arms_contact.py \
    --blend dist/m_cs2_ump45/v_smg_ump45.blend --min-in 3
```

None of them takes a weapon name. `pose_residual.py` finds the source `.mdl` in the manifest --
`<pack>/manifest.json`, which travels with a built pack, or the aggregate `<out>/manifest.json` --
and `arms_contact.py` samples the clips *this file* has (`--frames auto` picks its idle,
reload/fire and draw frames the same way `arm_fit` picks the frames to score), since the ak47's
`@ak47_reload` is the ump45's `a_reload` and a hardcoded name silently degrades a gate into a
report about the rest pose.

| script | claim it proves | fails when |
| --- | --- | --- |
| `pose_residual.py` | the baked action reproduces the `.mdl` bone chain in Blender's own evaluator | `pb.matrix` is off by > 0.5 deg / 0.05 in, or a bone without a position channel changed length |
| `arms_bind.py` | the re-bound arms mesh is not torn | the longest posed edge of a part grows past its rest edge (default mode `rigid`) |
| `arms_contact.py` | the arms are actually on the weapon | the arms never come within `--min-in` of the weapon at any sampled frame. Pass `--min-in 3` to make it a gate: the default `0` only prints, because "the closest vertex is touching" is also what a welded glove reports, and the interesting number is the *distribution* |

`python -m pipeline.arm_fit --blend ... [--write]` is not a gate but the fix the contact gate exists
to justify: it solves the one transform the arms SMDs do not carry (see its docstring).

## Why a gate per claim, and not a screenshot

Every convention in this pipeline -- the ZANIM bit packing, the per-bone space rule, Blender's pose
composition, the arms bind -- has exactly one right answer and a large set of answers that look
smooth, render without errors, and are wrong. Two of them (the pose bake, the arms bind) were wrong
in shipped builds and were caught only by numbers: a 178 deg bake error that left the gun looking
perfect because it only hit *child* bones, and a 47-inch tear in the sleeves that a rest-pose
screenshot cannot show. So these scripts compare against the `.mdl` itself rather than against
expectations, and are cheap enough to run on every build.

## Measured on `m_cs2_ak47` (2026-11-22, branch `arena/5c02a58f-ad`)

```
[residual] @ak47_reload frame 36: pb.matrix vs .mdl chain data, 69 bones
[residual] worst as-baked 0.032 deg / 0.0000 in   (the naive rule would give 177.55 deg)
[residual] parent-child lengths held (59 bones), 10 with a position channel exempt, 0 broken
[residual] PASS

[arms-bind] @ak47_reload frame 36 on Ct Arms, model inches        rest max   posed max
   g0.smd   skinned       0.955 -> 47.976 (9.5% of edges torn)
   g0.smd   rigid         0.955 ->  0.955 (0%)      <- shipped default
   g1.smd   skinned       0.586 -> 48.159
   g1.smd   rigid         0.586 ->  0.586
[arms-bind] rigid: no edge grew beyond rest (tolerance x1.02) -> PASS

[contact] v_rif_ak47.blend: weapon = 1 mesh(es) (21756 verts), arms = 4 mesh(es) (5922 verts)
[contact] frames from the file's own clips: :1,ak47_reload:37,ak47_fire1:12,lookat01:69,...
[contact] ak47_reload f37
    Ct_Arms_ct_1             min   2.71  p10   4.62  median   16.86  frac<6in  17.5% (upper sleeve: away, correct)
    Ct_Arms_ct_2             min   2.02  p10   3.51  median   15.60  frac<6in  31.6%
    Ct_Arms_ct_3             min   0.06  p10   1.23  median   14.92  frac<6in  49.8%
    Ct_Arms_g2               min   0.81  p10   3.62  median    7.35  frac<6in  41.3% (gloves: on the gun)
[contact] ak47_fire1 f12
    Ct_Arms_ct_3             min   0.25  p10   1.43  median   15.20  frac<6in  50.0%
    Ct_Arms_g2               min   0.82  p10   3.62  median    7.35  frac<6in  41.2%
[contact] closest arms-to-weapon distance over all samples: 0.04 in -> PASS

[arm_fit] offset [11.602 -11.211 -0.039] in: worst-frame gap 12.32 -> 2.54 in,
          unseen frames 11.72 -> 2.49 in; gap re-measured on the applied meshes: 2.28 in
```

Before `arm_fit` the gloves sat 6.16 in from the weapon in *every* clip (REST 7.46-20.47 in
depending on the file) -- the number that made the offset diagnosis possible, since a pose error
would not be constant across clips.  Those raw per-file gaps are what the fitted offset is closing:
the `min` columns above are post-fit.

## Two numbers that look like bugs and are not

**The glove line repeats across clips.** In the ak47 block above,
`Ct_Arms_g2` reports `min 0.81 p10 3.62 median 7.35` at the reload frame and `0.82 / 3.62 / 7.35` at
the firing frame, even though the mesh's world bounding box moves a dozen inches between them. The distances are *to the weapon*, and in a
viewmodel animation the weapon rides on the hand bones -- so a rigidly bound glove keeps exactly its
authored distance to the gun through those clips, by construction. It does change under
`lookat01` (0.05 / 1.85 / 5.06), the one clip that sways the weapon against the arm. A *sleeve*,
being skinned further up the chain, has no such invariance and its line differs every frame. Read
the sleeve lines to judge placement, and the glove line to judge whether the offset was applied.

**`--min-in` defaults to 0** so that a pack whose arms are merely far away still prints its
distribution instead of exiting 1 before you have seen it. The gate is opt-in on purpose.

## On other weapons

Measured the same way on the ump45 (70 bones, 4 weapon meshes against the ak47's 1): worst as-baked
`0.022 deg / 0.0000 in`, `0 broken` lengths, PASS, and its own grip fit solves its own offset
(`[11.05 -13.75 -2.58] in`) instead of inheriting the ak47's -- which only works because
`arm_fit.pick_frames` derives the scored frames from the file. Deriving them changed the ak47's own
result slightly: the rule excludes 1-frame clips as scorers (a static pose cannot over-determine
anything), so `ak47_idle f1` dropped out and `lookat01 f69` came in, moving the offset from
`[12.734 -10.0 -1.25]` (unseen 12.32 -> 3.83 in) to `[11.602 -11.211 -0.039]` (unseen
11.72 -> 2.49 in). Generalising the frame choice was the point; the unseen number *improving* is the
check that it was worth it.

The one weapon that does not fit is the knife. The kukri's scored frames improve
`25.57 -> 11.79 in`, which alone looks like partial success, but the frames it never saw get *worse*
(`20.23 -> 22.41 in`), because its blade rides `weapon_hand_r` while the sleeve follows the arm chain
and an attack swing separates the two by design. `build_pack` reads that as "not a conform", reverts
the shift and writes `arms_grip_fit.skipped` with both numbers -- so the knife packs carry the arms
exactly as authored and the manifest says why. A gate that only ever passes is not a gate, which is
also why `--min-in` and the holdout exist.
