# ad — CS2 viewmodel pack builder

Turns the compiled content of a CS2 weapon addon (`.mdl`/`.ani` v49 models, textures, sounds) into
per-weapon deliverables a Blender/GLTF viewer can load: a `.blend` with the full skeleton and every
clip baked as real keyframes, a `.glb` of the weapon, one skeleton-only `.glb` per animation, the
albedo/mask/normal textures, the weapon's sounds and a `game_sounds` script — plus a manifest that
records what was decided, not just what was produced.

The pack ships no animation importer that works, so the format is decoded here:
`pipeline/source_zanim.py` reads the v49 `ZANIM` animation payload (the 48-bit quantised
`Vector48`/`Quaternion48` channels, the block/frame-record layout, the `.ani` sidecar indirection and
the per-bone authoring-space rule) directly from the bytes. SourceIO is used only for the header,
bones and section tables — exactly the parts it gets right — and its own animation reader is stubbed
out during import, because it asserts on v49 frame-anim blocks.

## Layout

| path | what it is |
| --- | --- |
| `pipeline/source_zanim.py` | the ZANIM v49 decoder; `load_model_animations(mdl, ani=None)` is the entry point |
| `pipeline/smd_import.py` | ASCII SMD reader (both dialects this pack uses) plus the Blender mesh builder |
| `pipeline/arm_skin.py` | re-binding the pack's arm/glove SMDs, which ship one hard bone per vertex |
| `pipeline/arm_fit.py` | solves the constant arms-to-weapon offset the SMDs do not carry |
| `pipeline/build_pack.py` | the builder: one weapon directory in, one pack out |
| `pipeline/stage_content.py` | mirrors the 3.9 GB dump into per-addon Source content roots with hard links |
| `pipeline/validate_assets.py` | decodes every model and reports per-clip sanity (`build/decode_report.json`) |
| `pipeline/render_qa.py`, `pipeline/qa/` | rendering QA harness and the numeric gates — see [`pipeline/qa/README.md`](pipeline/qa/README.md) |
| `docs/reference-sources.md` | the third-party files the format was reverse engineered against, with hashes |
| `docs/legacy-rle-anim.md` | the pre-`ANIM_FLAG_FRAMEANIM` sequence format: the layout the files prove (including the bit-packed `Quat64` constant that every word-wise reading missed), what was measured and ruled out, and the two gates that back `RLE_TRUSTED` |

## Running it

Headless Blender needs `bpy` plus a few system stubs (see `pipeline/headless_blender_stubs.py`), and
SourceIO on the path (`SIO_ADDONS=/path/to/addons` or a `vendor/SourceIO` directory):

```sh
python3 pipeline/stage_content.py --archi /path/to/unpacked/addon --out build/content
LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/build_pack.py \
    --build build/content --archi /path/to/unpacked/addon --out dist --only ak47 --preview
LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/validate_assets.py
```

`--preview` renders the posed merge to PNGs, which is the only way to see the arms without opening
Blender; `--arms-bind` and `--arms-grip-fit` change the arms result's correctness, not just its looks, and
`--no-twist-fix` exists only to A/B the authoring-space rule in the decoder (turning it off is a
known 90° bug, never a shipping setting). Every knob is explained by `--help`.

## Status

All 45 weapon addons from the dump build end to end, and all 182 models in them decode: `182/182 models
fully decoded, 0 need the legacy RLE reader`. That is the result of naming the last unsupported format —
the pre-`ANIM_FLAG_FRAMEANIM` RLE sequence encoding, whose constant rotation turns out to be a 64-bit
*bit-packed* quaternion rather than any arrangement of 16- or 32-bit words, which is why every previous
attempt at it failed a unit-sphere test that a correct reading passes at 1e-7. The four shotgun packs that
used to fail with that named as the reason (`v_shot_{mag7,nova,sawedoff,xm1014}`) now build, and the 141
models that used to be reported as unsupported (`v_*` inspect clips, every `w_*` world model,
shell/ejection-port variants) decode. Each pack writes `dist/<pack>/manifest.json` (options, frame counts,
arms provenance, what the grip fit solved and why, if it refused); `dist/manifest.json` aggregates the run
and merges partial re-runs by pack directory. The format, what was measured and ruled out, and the two
whole-dump gates that back it are in [`docs/legacy-rle-anim.md`](docs/legacy-rle-anim.md).

Sweeping the gates over every built pack (45 of them, each on its own longest clip) gives `pose_residual`
0 failures at a worst residual of 0.061 deg / 0.0000 in and a median of 0.030 deg — with the four
legacy-only packs among the *best* in the batch at 0.005–0.020 deg — and `arms_contact` two packs where a
single rigid offset measurably does not reach (`v_mach_negev`, `v_eq_incendiarygrenade`), unchanged from
before the legacy decode existed. Per-model claims are checked by gates, not by eye: see
[`pipeline/qa/README.md`](pipeline/qa/README.md) for the measured residuals and what each script fails on.

The arms conform is solved per weapon and refused when it is not a conform: it has to improve the
frames it never saw, which the knife fails (its blade rides an attach bone the sleeve does not), so
those packs ship the arms as authored with `arms_grip_fit.skipped` in the manifest.

## Output shape, and what is out of scope

Two choices the pipeline had left open, settled here rather than per-pack:

* **One `.blend` and one `.glb` per weapon, with every clip as an action.** That is the deliverable,
  because the gates read it as a unit — `pose_residual` compares a baked action against the decoded
  frames, and `arms_contact` needs the weapon and the arms in one scene to measure them together. A pack
  is a weapon, so a file per weapon. `--per-anim` additionally writes one skeleton-only `.glb` per clip
  for handing a single animation to someone else; it is off by default because the base `.glb` already
  carries every animation, so the per-clip files duplicate data and, being skeleton-only, cannot be
  checked by the contact gate. Nothing in `dist/` should be read as "the animations are missing" because
  there is one file — `manifest.json` lists the clips and their frame counts.
* **`w_*` world models are not built.** Their animations now decode (they were the bulk of the
  legacy-RLE refusals), and `pipeline/validate_assets.py` reports them, but a pack is a viewmodel: a
  world model has no arms to fit, no attach-point grip to score, and its own set of `shell_*`,
  `_dropped` and `_mag` variants whose clips are rest poses or single-bone drops. Building them would
  produce files none of the gates can judge, so the pipeline refuses them by selection and the manifest
  of each pack names the model files it skipped and why. Exporting them is a matter of running the same
  decode with `--no-arms` over those files; it is deliberately not part of `dist/`.

Two things are known-limited by the source data rather than by this code: v49 exposes no frame rate,
so clip timing is resolved from `@`-stripped name pairs, and the arms meshes in
`Sport_gloves/<Rig>/<Side> Arms/*.smd` are decimated reference meshes with one hard bone per vertex,
which is why they are re-bound and re-positioned instead of imported verbatim.
