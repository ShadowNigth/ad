# Exploration probes

Not supported tools. These are the probes that settled the open questions during the reverse
engineering, kept because they are the only executable record of the *negative* results -- the
conventions that look right and are not. Each one hardcodes `/tmp` paths from the session that wrote
it, so adjust those before running; run them the same way as the gates next door (headless Blender
where they import `bpy`).

| probe | question | verdict |
| --- | --- | --- |
| `basis_probe.py` | how does Blender 4.5 compose a pose bone matrix? | measured to 1e-6: `pb.matrix = par.matrix @ inv(par.bone.matrix_local) @ bone.matrix_local @ matrix_basis`. This is what `bake_actions` now inverts. Both tempting rules -- `inv(matrix_local) @ M` and `par.matrix @ basis` -- are off by ~1.8 in the same units, and only the four-term form is right. |
| `delta_rule.py` | do CS2 delta (`@`) animations need the `mstudiobone_t` base pose composed back in? | **No.** 2 position rules x 4 rotation rules x 4 clips: pass-through wins (`@ak47_fire1` residual 16.19 deg / 2.04 in) and every composition inflates drift to 159-180 deg. `decode_block`'s seed-then-replace is correct as is. Do not "fix" this again. |
| `smd_euler.py` | which Euler order do the arms SMD `skeleton` blocks use? | **Undecidable this way.** The "child head lies along the parent's +X" test returns 0.00 deg for all six orders, because a Bip01 bone's +X is its own axis regardless. Not a usable convention probe. Local positions match the `.mdl` to 1e-6; local rotations stay 56-63 deg apart for every order. |
| `smd_rig_match.py` | does an arms SMD's skeleton match some other model's rig up to one global transform? | **No global fit exists** -- best residual >= 15.7 in / 79 deg for every candidate `.mdl` and every order. Which is why the arms offset is *solved* ([`../../arm_fit.py`](../../arm_fit.py)) instead of read from a file. |
| `rest_cmp.py` | is the imported arms rest the same as the SMD bind pose? | yes, to 1e-6 -- the importer is faithful, so any arms misplacement is in the source data or the bind, never in the import. |
| `merge_view.py` | render the merged weapon+arms from a built `.blend` at an arbitrary action/frame | the original eyeball check; superseded by `build_pack.py --preview`, which frames on the posed evaluated mesh instead of the rest bound. |

Two more probes were folded into gates rather than kept here: the arms tear measurement became
[`../arms_bind.py`](../arms_bind.py) and the arms-to-weapon distance became
[`../arms_contact.py`](../arms_contact.py).
