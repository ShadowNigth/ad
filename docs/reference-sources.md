# Reference sources for the decoder

`pipeline/source_zanim.py` was written against two third-party reads of the same binary format, not
against a specification. Neither is committed here; `/tmp` does not survive the sandbox, so each is
recorded by content hash plus the path it came from, and every conclusion is written into the
decoder's own docstring and re-checked against the `.mdl` files.

Re-fetch:

```sh
git clone --depth 1 https://github.com/ValveSoftware/cstrike15_src /tmp/src        # Source SDK (CGoSS)
git clone --depth 1 https://github.com/ZeqMacaw/Crowbar /tmp/crowbar              # MIT
# studio.h          -> /tmp/src/game/shared/studio.h
# compressed_vector.h -> /tmp/src/public/vstdlib/compressed_vector.h
# SourceMdlFile49.vb / SourceAniFile49.vb / SourceSmdFile49.vb
#                   -> /tmp/crowbar/Crowbar/data/mdl/v49/  (and data/smd/v49/)
```

| file | sha256 | what it settled |
| --- | --- | --- |
| `game/shared/studio.h` (Valve, `cstrike15_src`) | `27439f601a2a35ca9579157a64935fa21d79e76162acbb772ff912828479e348` | `mstudiobone_t`, `mstudioanimdesc_t` and `mstudioanimblock_t` field order and sizes; the `ANIM_*` flag bits (0x01 RAW_POS … 0x80 ANIM_ROT2); `ANIM_FLAG_FRAMEANIM`; the 30/45/48-bit `Vector48`/`Quaternion48` layouts shared with `public/vstdlib/compressed_vector.h` |
| `SourceMdlFile49.vb` (Crowbar) | `1d4094c495e36ab64b6ecdf7eebfe83750814052c593070a1f2469a251441080` | the v49 section order; `localAnimIndex` and `anim_block` indirection; that an animation's constant records *seed and then replace* the `mstudiobone_t` base values; the frame-anim record size check that `validate_assets.py` asserts |
| `SourceAniFile49.vb` (Crowbar) | `c73e598e4a57d127800d63dba64755fa6a8ae3e6f8d17ce026b807027d96bfd4` | the `.ani` sidecar's per-frame record: one flag byte per bone, then the flag-sized payloads in bone order; and the `valid`/`delta` walk over `mstudioanimvalue_t` for legacy RLE clips |
| `SourceSmdFile49.vb` (Crowbar) | `2012f2a31e304ebda5fc0a12b3020693798e80048e0e4d2caeb913b992b47f54` | the SMD dialect the archi arms files use (`$body`-style property lines, `nodes`/`skeleton`/`triangles` with inline vertex records, one bone per vertex line), which is what `pipeline/smd_import.py` parses and why it needs `weld_unshared()` |

Where sources disagreed or said nothing, the `.mdl` files themselves arbitrated, and two conventions
could only be pinned down by measurement (both documented in `source_zanim.py`):

* the per-bone space rule -- bones that carry a position channel are authored in a frame rotated 90°
  about Z relative to `mstudiobone_t` (`anim_to_studio_pos` / `anim_to_studio_quat`), rotation-only
  bones are not; `TWIST_POSITION_BONES` is load-bearing: worst angular residual against the bone
  chain is 0.12° with it, 90.00° without;
* the `Quaternion48` short-axis reconstruction, including the sign of the recovered component.

The measured evidence for both lives in [`../pipeline/qa`](../pipeline/qa/README.md), and
`pipeline/qa/exploration/` keeps the probes that produced it -- including the ones that came back
negative, which is most of them.
