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
| `docs/legacy-rle-anim.md` | the pre-`ANIM_FLAG_FRAMEANIM` sequence format: layout, run walk and verification plan — the recipe for the one part of the decoder not written |

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

45 weapon addons from the dump are staged and attempted; 41 build end to end and 4 (`v_shot_{mag7,
nova,sawedoff,xm1014}`, every sequence in the legacy RLE format) fail with that named as the reason
rather than producing a silent geometry-only pack. Each pack writes `dist/<pack>/manifest.json`
(options, frame counts, arms provenance, what the grip fit solved and why, if it refused);
`dist/manifest.json` aggregates the run and merges partial re-runs by pack directory. 41 of the pack's 182 models decode fully; the other 141 use the
pre-`ANIM_FLAG_FRAMEANIM` RLE sequence format and are reported as unsupported rather than failed
(`v_*` inspect clips, every `w_*` world model, shell/ejection-port variants) —
see [`docs/legacy-rle-anim.md`](docs/legacy-rle-anim.md) for that format. Per-model claims are checked
by gates, not by eye: see [`pipeline/qa/README.md`](pipeline/qa/README.md) for the measured residuals
and what each script fails on.

The arms conform is solved per weapon and refused when it is not a conform: it has to improve the
frames it never saw, which the knife fails (its blade rides an attach bone the sleeve does not), so
those packs ship the arms as authored with `arms_grip_fit.skipped` in the manifest.

Two things are known-limited by the source data rather than by this code: v49 exposes no frame rate,
so clip timing is resolved from `@`-stripped name pairs, and the arms meshes in
`Sport_gloves/<Rig>/<Side> Arms/*.smd` are decimated reference meshes with one hard bone per vertex,
which is why they are re-bound and re-positioned instead of imported verbatim.
