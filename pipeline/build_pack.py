"""Build the deliverable: CS2 view models + archi's arms meshes, skinned to one armature,
with every animation baked to Blender actions, textures packed and sounds copied.

Why this exists instead of a plain addon import
----------------------------------------------
The `.smd` files shipped in archi contain a mesh and a reference skeleton but *no animation
frames* (0 in every `frames` section), and neither Blender Source Tools nor SourceIO can read
CS2's `.ani` (ZANIM) data, so animations come from `source_zanim.py` and are baked here.
The arms SMDs are skinned to the same bone names the weapon `.mdl` uses
(`v_weapon.Bip01_L_Forearm`, ...), so "merging the arms rig onto the models" is a matter of
binding the arm meshes to the weapon's armature -- no retargeting, no baked-in mismatch.

For each weapon `m_cs2_<name>` in the staged content tree this writes:

    <out>/<weapon>/<weapon>.blend          scene: weapon mesh + arms mesh + armature + actions
    <out>/<weapon>/<weapon>.glb           same, glTF (animations + textures embedded)
    <out>/<weapon>/animations/*.glb       one animation per file (for engines that want that)
    <out>/<weapon>/textures/*.png         every VTF the model uses, packed to PNG
    <out>/<weapon>/sounds/*.wav           the weapon's sounds, plus game_sounds_*.txt
    <out>/manifest.json                   the whole run; `<pack>/manifest.json` travels with a pack

Run inside headless bpy (see headless_blender_stubs.py):
    LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/build_pack.py --only ak47
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import time
import traceback
from pathlib import Path

sys.argv[0] = "blender"
HERE = Path(__file__).resolve().parent
for _cand in (str(HERE.parent / "vendor"), "/tmp/bl-addons", os.environ.get("SIO_ADDONS", "")):
    if _cand and Path(_cand, "SourceIO").is_dir():
        sys.path.insert(0, _cand)
        break
sys.path.insert(0, str(HERE))

import bpy  # noqa: E402
import mathutils  # noqa: E402
import numpy as np  # noqa: E402

import source_zanim as Z  # noqa: E402
import smd_import  # noqa: E402

ARMS_CANDIDATES = ("Ct Arms", "T Arms", "Anarchist Arms", "Balkan Arms")


def enable_sourceio():
    """Register the SourceIO operators. Must run *after* read_factory_settings, not before."""
    import addon_utils
    addon_utils.enable("SourceIO", default_set=True)
    if not hasattr(bpy.ops.sourceio, "mdl"):
        raise RuntimeError("SourceIO registered no import operators")


def clear_scene():
    """Empty bpy.data between weapons.

    `bpy.ops.wm.read_factory_settings(use_empty=True)` would do it, but it also unregisters the
    SourceIO operators in a headless session, so the datablocks are dropped by hand instead.
    """
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.armatures, bpy.data.actions,
                 bpy.data.materials, bpy.data.images, bpy.data.node_groups,
                 bpy.data.lights, bpy.data.cameras):
        for d in list(coll):
            try:
                coll.remove(d)
            except Exception:                            # noqa: BLE001 - user-deleted or linked
                pass
    bpy.data.orphans_purge(do_recursive=True)


# --------------------------------------------------------------------------------- utils --
def log(*a):
    print("[pack]", *a, flush=True)


def sha(p: Path):
    h = hashlib.sha1()
    h.update(p.read_bytes())
    return h.hexdigest()[:12]


def purge_junk():
    """Remove the objects Blender ships in a factory scene and SourceIO leftovers."""
    for o in list(bpy.data.objects):
        if o.name in {"Cube", "Camera", "Light"} or o.name.startswith("SIO_"):
            bpy.data.objects.remove(o, do_unlink=True)
    for coll in ("Cube", "Camera", "Light"):
        c = bpy.data.objects.get(coll)
        if c is not None:
            bpy.data.objects.remove(c, do_unlink=True)


def find_arms_sets(archi: Path, arms: str | None):
    """archi's first-person arm/glove folders: `Sport_gloves/<Rig>/<Side> Arms/`.

    Each holds one skin option as SMD sources:
      * `g0.smd`..`g4.smd`  -- the glove body (five morph/pose variants),
      * `<side>_*.smd`      -- the sleeve/forearm mesh (ct_1..3, t_arm, balkan_*, anarchist_*),
      * `L_0..4.bmp` / `R_0..4.bmp` / `sleeve.bmp` -- the textures those meshes name in their
        `triangles` material markers, which is why a texture lookup starts in the mesh's folder.
    Every SMD here is skinned to `v_weapon.Bip01_*` bones -- the same names a weapon .mdl rig
    carries -- so binding them onto the imported weapon armature *is* the merge; no retarget.
    """
    root = archi / "Sport_gloves"
    if not root.is_dir():
        return []
    found = [d for d in sorted(root.glob("*/*Arms*")) if d.is_dir() and any(d.glob("*.smd"))]
    if not found:                                        # some other layout: any SMD folder
        found = sorted({f.parent for f in root.rglob("*.smd")})
    if not found:
        return []
    def rel(d):
        return (d.parent.name + "/" + d.name).lower()

    if arms:
        q = arms.lower().strip("/")
        exact = [d for d in found if rel(d) == q or d.name.lower() == q]
        hits = exact or [d for d in found if q in rel(d) or q in d.name.lower()]
        if not hits:
            raise SystemExit("no arms set matching %r; have: %s"
                             % (arms, ", ".join(rel(d) for d in found)))
        if len(hits) > 1:
            # one arms set per pack: the arms folders are interchangeable skins, binding all
            # three rigs at once would just stack duplicate sleeves on the same bones.
            log(f"--arms {arms!r} matched {len(hits)} folders, using {rel(hits[0])} "
                f"(others: {', '.join(rel(d) for d in hits[1:])})")
        return hits[:1]
    ct = [d for d in found if d.name.lower().startswith("ct")]
    return [ct[0] if ct else found[0]]


def _topo_order(parents):
    """Bone indices sorted parent-before-child (Source stores them that way already)."""
    n = len(parents)
    order, placed = [], [False] * n
    for i in range(n):
        chain, j = [], i
        while 0 <= j < n and not placed[j]:
            chain.append(j)
            j = parents[j]
            if j in chain:                       # defensive: a cyclic parent list
                break
        for k in reversed(chain):
            if not placed[k]:
                placed[k] = True
                order.append(k)
    for i in range(n):
        if not placed[i]:
            placed[i] = True
            order.append(i)
    return order


def _set_interpolation(act, smoothing):
    """Write the interpolation onto an action.

    Blender 4.4 moved this off the FCurve (`fcurve.interpolation` no longer exists) onto each
    keyframe, so set both when the old attribute is still there and always per-keyframe.
    """
    for fc in act.fcurves:
        try:
            fc.interpolation = smoothing                 # <= 4.3
        except AttributeError:
            pass
        for kp in fc.keyframe_points:
            try:
                kp.interpolation = smoothing             # >= 4.4
            except AttributeError:
                pass
            if smoothing == "BEZIER":
                kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
            else:
                kp.handle_left_type = kp.handle_right_type = "AUTO"


def bake_actions(arm, anims, meta, scale, smoothing="BEZIER"):
    """Create one Blender action per decoded animation, keyed on the armature.

    Source gives each bone a *local* transform and the model-space matrix is the chain product

        M[i] = M[parent[i]] . Translation(pos[i] * scale) . Quaternion(rot[i])

    Blender's pose evaluation is parent relative too, but not at the same place:

        pb.matrix = pb.parent.matrix @ inv(parent.matrix_local) @ bone.matrix_local @ matrix_basis

    (measured on the imported rig to 1e-6).  `bone.matrix_local` is the absolute *rest* matrix,
    so the tempting shortcut `matrix_basis = matrix_local**-1 @ M` is only right for root bones;
    for anything below a rotated ancestor it leaves that bone's rest-to-pose delta in place,
    which is what tore archi's glove fingers into 20-inch shards while the gun -- keyed on the
    root -- kept looking correct.  Solving the relation above for the keyframed value:

        matrix_basis = inv(bone.matrix_local) @ parent.matrix_local @ inv(M[parent]) @ M[bone]

    with M[none] = identity, walked parent-before-child so M[parent] is this frame's pose.
    """
    names, parents = meta["bone_names"], meta["parent_index"]
    pose_names = [n if n in arm.pose.bones else (n[:63] if n[:63] in arm.pose.bones else None)
                  for n in names]
    live = [bi for bi, pn in enumerate(pose_names) if pn]
    if not live:
        raise RuntimeError("no decoded bone name matches the imported armature "
                           "(armature was built from a different model?)")
    L, Lpar = {}, {}
    for bi in live:
        nm = pose_names[bi]
        L[bi] = np.array(arm.data.bones[nm].matrix_local)
        p = parents[bi]
        pn = pose_names[p] if 0 <= p < len(parents) else None
        Lpar[bi] = np.array(arm.data.bones[pn].matrix_local) if pn and pn in arm.data.bones \
            else np.eye(4)
    L_inv = {bi: np.linalg.inv(v) for bi, v in L.items()}
    order = [bi for bi in _topo_order(parents) if pose_names[bi] is not None]
    for bi in live:
        arm.pose.bones[pose_names[bi]].rotation_mode = "QUATERNION"
    arm.animation_data_create()

    info = {}
    for name, v in anims.items():
        if "error" in v or not isinstance(v.get("frames"), np.ndarray):
            continue
        fr = v["frames"]
        n = int(fr.shape[0])
        act = bpy.data.actions.new(name=name.lstrip("@") or "anim")
        # An action whose only user is arm.animation_data.action is an orphan as soon as the
        # next one is assigned, and Blender frees orphans when saving a .blend -- so pin them.
        act.use_fake_user = True
        # 4.5 routes keyframe_insert through the object's active action (and its slot), so the
        # `action=` keyword is gone: assign the action first, then key.
        arm.animation_data.action = act
        M = {}
        for f in range(n):
            pos, rot = fr["pos"][f], fr["rot"][f]
            for bi in order:
                q = rot[bi]
                local = (mathutils.Matrix.Translation(mathutils.Vector(pos[bi] * scale))
                         @ mathutils.Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4())
                par = parents[bi]
                has_par = 0 <= par < len(parents) and par in M
                M[bi] = (M[par] @ local) if has_par else local
                want = Lpar[bi] @ ((np.linalg.inv(M[par]) if has_par else np.eye(4)) @ M[bi])
                basis = mathutils.Matrix(L_inv[bi] @ want)
                loc, quat, _sc = basis.decompose()
                pb = arm.pose.bones[pose_names[bi]]
                pb.location = (float(loc.x), float(loc.y), float(loc.z))
                pb.rotation_quaternion = (float(quat.w), float(quat.x), float(quat.y),
                                          float(quat.z))
                pb.keyframe_insert("location", frame=f + 1)
                pb.keyframe_insert("rotation_quaternion", frame=f + 1)
        _set_interpolation(act, smoothing)
        act.frame_range = (1, n)
        info[name] = {"frames": n, "fps": v["fps"], "looping": v["looping"],
                      "delta": v["delta"], "bones_keyed": len(order),
                      "fcurves": len(act.fcurves)}
    if info and arm.animation_data:
        arm.animation_data.action = bpy.data.actions.get(next(iter(info)))
    fps = max((v["fps"] for v in info.values()), default=30.0)
    bpy.context.scene.render.fps = int(round(fps))
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = max((d["frames"] for d in info.values()), default=1)
    return info


SIDE_TOKENS = ("Bip01_L_", "Bip01_R_")


def classify_arms_smd(path: Path):
    """(side, stem, index, smd) for one arms SMD, where side is 'L', 'R', 'both' or 'none'.

    archi keeps each glove option as a folder of SMD pieces and a `glove.txt` that lists them as
    repeated `$body` lines.  The two group names are not decoration: `weapon` holds the *hands*
    (five files, one per glove skin, each a complete hand mesh) and `studio` holds the *sleeve*,
    which is split into segments that tile along the arm (`ct_1` y 10.4-16.9, `ct_2` 6.6-11.1,
    `ct_3` 1.6-7.3 in model inches) -- taking one of each, as an LOD list would suggest, deletes
    the forearm and leaves a floating cuff.  Side comes from the bones the file actually weights.
    """
    import smd_import
    smd = smd_import.read_smd(path)
    names = {b for w in smd.vert_weights for b, _ in w}
    has_l = any(SIDE_TOKENS[0] in b for b in names)
    has_r = any(SIDE_TOKENS[1] in b for b in names)
    side = "both" if (has_l and has_r) else ("L" if has_l else ("R" if has_r else "none"))
    stem = re.sub(r"\d+$", "", path.stem)
    num = re.search(r"(\d+)$", path.stem)
    return side, stem, (int(num.group(1)) if num else 0), smd


def arms_body_groups(folder: Path):
    """`{smd stem: $body group}` read from the folder's `glove.txt` (case-insensitive).

    Empty when the file is missing, so callers must fall back on name heuristics.
    """
    groups = {}
    for txt in sorted(folder.glob("*.txt")):
        if txt.stem.lower() not in ("glove", "gloves", "model"):
            continue
        for line in txt.read_text(errors="replace").splitlines():
            m = re.match(r'\s*\$body\s+"([^"]*)"\s+"([^"]*)"', line)
            if m:
                groups[m.group(2)] = m.group(1)
    return groups


def _bbox(smd):
    lo = smd.vert_pos.min(0).astype(float)
    hi = smd.vert_pos.max(0).astype(float)
    return lo, hi


def _bbox_overlap(a, b):
    """Fraction of box `a`'s volume that box `b` covers."""
    va = np.prod(np.maximum(a[1] - a[0], 1e-6))
    inter = np.minimum(a[1], b[1]) - np.maximum(a[0], b[0])
    if (inter <= 0).any():
        return 0.0
    return float(np.prod(inter) / va)


def choose_arms_meshes(folder: Path, all_meshes=False):
    """One complete arm (both hands *and* the whole sleeve) from an archi arms folder.

    Hands: the `$body "weapon"` files are skin variants of the same hand mesh, so exactly one is
    bound -- a both-hands file if there is one, else the largest left and largest right.
    Sleeve: the `$body "studio"` files are *segments*, so all of them are bound, except a file
    that another file largely covers while holding far fewer vertices (the shared `t_arm`
    bare-arm proxy), which would just Z-fight with the detailed segments.
    Returns (chosen, skipped) with a reason per skipped file.
    """
    info, groups = {}, arms_body_groups(folder)
    for f in sorted(folder.glob("*.smd")):
        try:
            side, stem, num, smd = classify_arms_smd(f)
        except Exception as e:                           # noqa: BLE001
            info[f] = ("error", str(e), None, None, None)
            continue
        if side == "none":
            info[f] = ("no weapon bones", None, stem, None, None)
            continue
        grp = groups.get(f.stem) or ("weapon" if stem.lower().startswith("g") else "studio")
        info[f] = (side, smd, stem, grp, _bbox(smd))
    usable = {f: v for f, v in info.items() if v[0] in ("L", "R", "both")}
    if all_meshes:
        return list(usable), {f: v[0] for f, v in info.items() if f not in usable}

    chosen, skipped = [], {}
    hands = {f: v for f, v in usable.items() if v[3] == "weapon"}
    sleeves = {f: v for f, v in usable.items() if v[3] == "studio"}
    if not sleeves and not hands:                        # no glove.txt: treat all as one pile
        hands, sleeves = dict(usable), {}

    both = sorted((f for f, v in hands.items() if v[0] == "both"),
                  key=lambda f: -len(hands[f][1].vert_pos))
    if both:
        keep = [both[0]]
        why = f"{both[0].stem} weights both hands, so the per-side files are its skin variants"
    else:
        keep = [max((f for f, v in hands.items() if v[0] == want),
                    key=lambda f: len(hands[f][1].vert_pos), default=None) for want in ("L", "R")]
        keep = [f for f in keep if f]
        why = "largest left + largest right"
    for f in hands:
        if f not in keep:
            skipped[f] = f"{hands[f][0]} skin/LOD variant of the hand mesh"
    chosen += keep
    if keep:
        log(f"  [arms] {folder.name}: hands -> {', '.join(k.name for k in keep)} ({why}), "
            f"{len(hands) - len(keep)} other hand file(s) not bound")

    sl_keep, sl_box = list(sleeves), {f: sleeves[f][4] for f in sleeves}
    for f in list(sl_keep):
        n = len(sleeves[f][1].vert_pos)
        for g in sleeves:
            if g == f:
                continue
            if len(sleeves[g][1].vert_pos) >= 4 * n and _bbox_overlap(sl_box[f], sl_box[g]) >= 0.5:
                sl_keep.remove(f)
                skipped[f] = (f"coarse proxy: {len(sleeves[g][1].vert_pos)} v in {g.name} covers "
                              f"the same region as its {n} v")
                break
    for f in sleeves:
        if f not in sl_keep and f not in skipped:
            skipped[f] = "sleeve segment"
    chosen += sorted(sl_keep, key=lambda f: f.name)
    if sl_keep:
        log(f"  [arms] {folder.name}: sleeve -> {', '.join(k.name for k in sorted(sl_keep, key=lambda f: f.name))} "
            f"({len(sl_keep)} segment(s) bound, {len(sleeves) - len(sl_keep)} proxy/skip)")
    return chosen, skipped

def _import_smd_folder(folder: Path, arm, textures, all_meshes=False, bind="rigid"):
    """Bind the chosen SMDs in `folder` to the weapon armature; one record per mesh."""
    made = []
    chosen, skipped = choose_arms_meshes(folder, all_meshes=all_meshes)
    for name, why in sorted((f.name, w) for f, w in skipped.items()):
        log(f"  [arms] {folder.name}/{name}: {why}")
    for smd_path in chosen:
        try:
            smd = smd_import.read_smd(smd_path)
        except Exception as e:                           # noqa: BLE001 - report, keep going
            log(f"  [arms] {smd_path.name}: skipped ({e})")
            continue
        ob, keyed, slots = smd_import.to_blender_mesh(
            smd, arm, prefix=f"{folder.name.replace(' ', '_')}_",
            folders=[folder, folder.parent, folder.parent.parent], textures=textures,
            bind=bind)
        if ob is None:
            log(f"  [arms] {smd_path.name}: no bone names matched the weapon rig "
                f"({len(smd.nodes)} nodes) - skipped")
            continue
        me = ob.data
        made.append({"folder": folder.name, "source": smd_path.name, "mesh": me.name,
                     "object": ob.name, "vertices": len(me.vertices),
                     "triangles": len(me.polygons), "bones_bound": len(keyed),
                     "welded": list(smd.welded),
                     "bones": (keyed[:6] + ["..."]) if len(keyed) > 6 else keyed,
                     "bind": bind,
                     "components": int(ob.get("arms_components", 0)),
                     "component_bones": str(ob.get("arms_component_bones", "")),
                     "limb_anchors": str(ob.get("arms_limb_anchors", "")),
                     "unmapped_weights": int(ob.get("smd_unmapped_weights", 0)),
                     "materials": [m.name for m, _t in slots]})
    return made


def render_preview(pack: Path, name: str, arm, frames=(1,), samples=6, size=(900, 420),
                   anim="reload"):
    """One Cycles frame per requested index, written as `<pack>/preview.png`.

    Optional because it is the slow step of a pack (~15 s/frame on CPU) and it is the only way
    to see the arms merge without opening Blender: a mis-bound sleeve shows up immediately.
    Defaults to the reload clip because that is where the arms move most -- an idle frame hides
    a bad bind, a reload frame does not.
    """
    import mathutils

    acts = sorted((a for a in bpy.data.actions if a.frame_range[1] >= 1),
                  key=lambda a: (-a.frame_range[1], a.name))
    act = next((a for a in acts if anim and anim.lower() in a.name.lower()), None) \
        or (acts[0] if acts else None)
    if act is not None:
        arm.animation_data.action = act
        hi = int(round(act.frame_range[1]))
        frames = tuple(min(max(1, int(f)), hi) for f in frames)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.max_bounces = 2
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.image_settings.file_format = "PNG"
    # AgX (4.5's default) flattens the albedo to a muddy grey and a QA still has to be readable.
    try:
        sc.view_settings.view_transform = "Standard"
        sc.view_settings.look = "None"
    except (AttributeError, TypeError):
        pass
    if sc.world is None:
        sc.world = bpy.data.worlds.new("preview_world")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.13, 0.13, 0.15, 1)
        bg.inputs[1].default_value = 1.0
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        return None
    # Frame on the *posed* geometry: bound_box is the rest bound, and a viewmodel anim moves the
    # arms tens of units, so framing on rest lands the camera inside the sleeve.
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        if len(me.vertices):
            step = max(1, len(me.vertices) // 400)
            co = np.empty(len(me.vertices) * 3)
            me.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)[::step]
            pts.append(co @ np.array(ev.matrix_world)[:3, :3].T + np.array(ev.matrix_world)[:3, 3])
        ev.to_mesh_clear()
    if not pts:
        return None
    pts = np.concatenate(pts)
    lo, hi_b = pts.min(0), pts.max(0)
    # Bounding-box centre and radius, not the vertex mean: the gun carries 20x the vertices of
    # the arms, so a mean centres the shot on the rifle and pushes the sleeves out of frame.
    mid = mathutils.Vector((lo + hi_b) * 0.5)
    radius = float(np.linalg.norm((hi_b - lo) * 0.5)) or 1.0
    cam_data = bpy.data.cameras.new("preview_cam")
    cam_data.lens = 42.0
    # Fit the bounding sphere in the *smaller* viewport axis, with margin.
    import math as _m
    sensor = cam_data.sensor_width * min(1.0, size[1] / size[0])
    dist = radius / _m.sin(_m.atan(sensor / 2.0 / cam_data.lens)) * 1.15
    cam = bpy.data.objects.new("preview_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    dirv = mathutils.Vector((-0.30, -1.0, 0.34)).normalized()
    cam.location = mid + dirv * dist
    cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.clip_end = dist * 10.0 + 100.0
    for i, (lp, en) in enumerate((((0.35, -0.8, 0.5), 4.0), ((-0.6, 0.5, 0.35), 1.4))):
        lamp = bpy.data.objects.new(f"preview_l{i}", bpy.data.lights.new(f"preview_l{i}", "SUN"))
        lamp.data.energy = en
        lamp.rotation_euler = mathutils.Vector(lp).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(lamp)
    written = []
    for f in frames:
        sc.frame_set(int(f))
        bpy.context.view_layer.update()
        out = pack / ("preview.png" if len(frames) == 1 else f"preview_{int(f):03d}.png")
        sc.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        written.append(out.name)
    log(f"  preview: {', '.join(written)}"
        + (f" (action {act.name} frame {sc.frame_current})" if act else ""))
    return written


def fit_arms_grip(arm, arm_objects, log, clearance=0.5):
    """Translate the arms assembly onto the weapon -- see pipeline/arm_fit.py for why."""
    try:
        import arm_fit
    except ImportError as e:                             # noqa: BLE001
        log(f"  [warn] arms grip fit unavailable: {e}")
        return {"error": str(e)}
    objs = [bpy.data.objects[m["object"]] for m in arm_objects if m.get("object") in bpy.data.objects]
    if not objs:
        return None
    before = (arm.animation_data.action.name if arm.animation_data.action else "",
              bpy.context.scene.frame_current)
    try:
        off, (gap0, gap1), hold, _meshes, guns, used = arm_fit.fit(
            meshes=objs, verbose=False, clearance=clearance)
        arm_fit.shift_meshes(objs, off)
        # Re-measured on the applied meshes: the fit scores a world-space shift, the mesh carries a
        # bone-relative one, and the deliverable has to be judged on what is actually in the file.
        # same meshes, same frame-picking rule, offset now inside the mesh data
        applied = arm_fit.measure_gap(objs, guns, None)
        # Two ways this offset is a fiction: applying it does not help the frames it was fitted to,
        # or it *hurts* the frames it never saw.  The second is what a knife reports -- the blade
        # rides `weapon_hand_r` while the sleeve follows the arm chain, so an attack swing moves the
        # weapon against the hand and no constant translation can hold; the fit that nails
        # `light_hit1` pushes `lookat01` 2 in further away.  Refuse both and leave the arms authored.
        worse_holdout = bool(hold) and hold[1] > hold[0]
        if applied > gap0 or worse_holdout:
            arm_fit.shift_meshes(objs, -off)
            why = (f"applying it worsens the gap it was fitted to ({gap0:.2f} -> {applied:.2f} in)"
                   if applied > gap0 else
                   f"it worsens the frames it never saw ({hold[0]:.2f} -> {hold[1]:.2f} in)")
            log(f"  arms grip fit: skipped -- {why}; leaving the arms as authored")
            # Not a failure of the fit -- for a weapon whose hands and blade part company between
            # clips (the knife: `light_hit1` needs 22.8 in of shift and `lookat01` needs -4) no
            # single translation reaches, so leaving the arms as authored beats welding them to
            # whatever clip was scored.  The holdout numbers say that out loud.
            return {"offset": [round(float(x), 4) for x in off],
                    "skipped": "no single translation reaches across this model's clips",
                    "gap_before": round(float(gap0), 3),
                    "gap_after_would_be": round(float(gap1), 3),
                    "applied_would_worsen_to": round(float(applied), 3),
                    "holdout_would_worsen_to": [round(float(x), 3) for x in hold] if hold else None,
                    "scored_frames": used}
        rec = {"offset": [round(float(x), 4) for x in off],
               "gap_before": round(float(gap0), 3), "gap_after": round(float(gap1), 3),
               "gap_applied": round(float(applied), 3),
               "weapon_meshes": [g.name for g in guns], "scored_frames": used,
               "score_frames_note": "picked from this model's own clips by arm_fit.pick_frames"}
        if hold:
            rec["gap_unscored_before"], rec["gap_unscored_after"] = (round(float(hold[0]), 3),
                                                                     round(float(hold[1]), 3))
        log(f"  arms grip fit: offset [{off[0]:.2f} {off[1]:.2f} {off[2]:.2f}] in -> worst-frame "
            f"gap {gap0:.2f} -> {gap1:.2f} in"
            + (f", unseen frames {hold[0]:.2f} -> {hold[1]:.2f}" if hold else ""))
        return rec
    except Exception as e:                               # noqa: BLE001
        log(f"  [warn] arms grip fit failed: {type(e).__name__}: {e}")
        return {"error": f"{type(e).__name__}: {e}"}
    finally:
        act = bpy.data.actions.get(before[0]) if before[0] else None
        arm.animation_data.action = act
        bpy.context.scene.frame_set(before[1])
        bpy.context.view_layer.update()


def save_textures(pack: Path, max_size=2048):
    """Write every image packed into the blend out as PNG under `models/weapons/textures`."""
    tex_dir = pack / "models/weapons/textures"
    tex_dir.mkdir(parents=True, exist_ok=True)
    used = set()
    for mat in bpy.data.materials:
        if mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    used.add(node.image.name)
    written = []
    for img in bpy.data.images:
        if img.name not in used:
            continue            # SourceIO leaves placeholder/cubemap images around (SIOe_*,
        if img.name in {"Render Result", "Viewer Image"} or img.size[0] < 2:
            continue            # missing_*) -- only write what a material actually samples
        try:
            if max(img.size) > max_size:                 # 4K/8K packed maps bloat the pack
                img.scale(max_size, max_size)
            name = re.sub(r"[^A-Za-z0-9_.-]", "_", Path(img.name).stem)
            f = tex_dir / (name if f"{name}".lower().endswith(".png") else f"{name}.png")
            img.filepath_raw = str(f)
            img.file_format = "PNG"
            img.save()
            written.append(f.relative_to(pack).as_posix())
        except Exception as e:                           # noqa: BLE001
            log(f"  [warn] texture {img.name}: {e}")
    return written


def copy_sound_assets(weapon_dir: Path, pack: Path):
    """Copy the weapon's sound scripts and .wav files, keeping their game-relative paths.

    The scripts use `~)weapons/ak47/ak47_01.wav`, i.e. `sound/` is a content root, so the files
    are copied under the same relative path (`sound/weapons/ak47/ak47_01.wav`) and the pack can
    be dropped into an addon folder as-is.
    """
    out = []
    snd = weapon_dir / "sound"
    if snd.is_dir():
        for w in sorted(p for p in snd.rglob("*") if p.is_file()
                        and p.suffix.lower() in {".wav", ".mp3", ".ogg"}):
            tgt = pack / "sound" / w.relative_to(snd)
            tgt.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(w, tgt)
            out.append(tgt.relative_to(pack).as_posix())
    scripts = weapon_dir / "scripts"
    if scripts.is_dir():
        for t in sorted(scripts.glob("game_sounds*.txt")):
            tgt = pack / "scripts" / t.name
            tgt.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(t, tgt)
            out.append(tgt.relative_to(pack).as_posix())
    return out


def build_one(weapon_dir: Path, mdl: Path, arms_dirs, out_dir: Path, opts):
    name = mdl.stem
    log(f"[{name}] {mdl.relative_to(weapon_dir)}")
    rec = {"weapon": name, "model": str(mdl.relative_to(weapon_dir.parent.parent)),
           "mdl_abs": str(mdl.resolve()),
           "arms": [str(d) for d in arms_dirs]}

    clear_scene()
    # `files`/`directory` are not decorative: SourceIO iterates its file-collection operator
    # property, so passing only `filepath` silently imports nothing at all.
    with Z.sourceio_anim_parse_disabled():
        # SourceIO parses animation payloads even with import_animations=False, and asserts on every
        # v49 frame-anim block -- a traceback per model, which buries real failures in the log.
        bpy.ops.sourceio.mdl(filepath=str(mdl), directory=str(mdl.parent),
                             files=[{"name": mdl.name}], import_animations=False,
                             import_textures=not opts.no_textures, import_physics=False,
                             compact_animations=False, scale=opts.scale)
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        raise RuntimeError("importer produced no armature (objects: %s)"
                           % ", ".join(f"{o.name}:{o.type}" for o in bpy.data.objects[:12]))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    log(f"  armature {arm.name}: {len(arm.data.bones)} bones | meshes: "
        f"{', '.join(f'{m.name}({len(m.data.polygons)})' for m in meshes[:6])}")

    # `strict=False` keeps a model with a few legacy-RLE anims buildable instead of raising:
    # those anims come back as {"error": ...} and are reported in the manifest.
    all_anim = Z.load_model_animations(mdl, strict=False,
                                       twist_position_bones=not opts.no_twist_fix)
    meta = all_anim.pop("_meta")
    anims = all_anim
    good = {k: v for k, v in anims.items() if "frames" in v}
    log(f"  decoded {len(good)}/{len(anims)} animations")
    if not good:
        raise RuntimeError("no animation decoded: "
                           + "; ".join(f"{k}={v.get('error')}" for k, v in list(anims.items())[:3]))
    baked = bake_actions(arm, good, meta, opts.scale, smoothing=opts.smoothing)
    log(f"  baked {len(baked)} actions onto {arm.name}")

    arm_objects = []
    textures = {}
    for d in arms_dirs:
        arm_objects += _import_smd_folder(d, arm, textures, all_meshes=opts.all_arms,
                                          bind=opts.arms_bind)
    rec["arms_meshes"] = arm_objects
    rec["arms_note"] = (
        "The archi arms are loose SMD reference meshes with one hard bone per vertex, so they are "
        "re-bound here (see --arms-bind); they cannot bend at the elbow because each sleeve segment "
        "weights a single bone. The shipped weapon .mdl carries no arms mesh, and no compiled "
        "v_arms model exists in the pack, so the game's real skin weights are not available.")
    rec["arms_vertices"] = sum(m["vertices"] for m in arm_objects)
    rec["arms_triangles"] = sum(m["triangles"] for m in arm_objects)
    log(f"  arms: {len(arm_objects)} meshes, {rec['arms_vertices']} verts, "
        f"{rec['arms_triangles']} tris")

    if opts.arms_grip_fit and arm_objects:
        rec["arms_grip_fit"] = fit_arms_grip(arm, arm_objects, log,
                                            clearance=opts.arms_grip_clearance)

    pack = out_dir
    (pack / "models/weapons/animations").mkdir(parents=True, exist_ok=True)
    nf = max((d["frames"] for d in baked.values()), default=1)
    spec = opts.preview_frame            # needs the baked frame counts, so resolve it here
    if spec == "mid":
        frames = (max(1, nf // 2),)
    elif spec == "both":
        frames = (1, max(1, nf // 2), nf)
    else:
        frames = tuple(int(x) for x in str(spec).split(","))
    if not opts.no_textures:
        rec["textures"] = save_textures(pack, max_size=opts.texture_size)
        log(f"  textures: {len(rec['textures'])} files")
    rec["sounds"] = copy_sound_assets(weapon_dir, pack)
    if rec["sounds"]:
        log(f"  sounds: {len(rec['sounds'])} files")

    gltf = {"scale": opts.scale, "gltf_up_axis": "Y", "rest_transform": "imported",
            "pose_relation": "pb.matrix = bone.matrix_local @ matrix_basis",
            "bake": "bone-local M[parent] @ T(pos) @ R(rot) -> matrix_local^-1 @ M, per key",
            "bone_count": len(meta["bone_names"]), "animations": baked}
    try:
        f = pack / "models/weapons" / f"{name}.glb"
        # Blender 4.5's exporter turned `export_materials` into an enum and added
        # `export_animation_mode`; ACTIONS writes every action as its own glTF animation.
        bpy.ops.export_scene.gltf(filepath=str(f), export_format="GLB", export_yup=True,
                                  export_animations=True, export_skins=True,
                                  export_materials="EXPORT", export_animation_mode="ACTIONS",
                                  export_apply=False)
        gltf["base"] = {"path": f.relative_to(pack).as_posix(), "bytes": f.stat().st_size,
                        "sha256_8": sha(f)[:8]}
        log(f"  glb {f.stat().st_size/1e6:.1f} MB")
    except Exception as e:                               # noqa: BLE001
        gltf["error"] = f"base export failed: {e}"
        log(f"  [warn] base glb export failed: {e}")

    if opts.per_anim:
        # Animation-only files: select just the armature so the geometry is not re-embedded
        # eleven times (25 MB per weapon otherwise).  Each drops onto any rig with these bones.
        adir = pack / "models/weapons/animations"
        current = arm.animation_data.action
        for o in bpy.context.selected_objects:
            o.select_set(False)
        arm.select_set(True)
        for act in sorted(bpy.data.actions, key=lambda a: a.name):
            try:
                arm.animation_data.action = act
                f = adir / f"{name}_{act.name.replace('.', '_')}.glb"
                bpy.ops.export_scene.gltf(filepath=str(f), export_format="GLB", export_yup=True,
                                          export_animations=True, export_skins=True,
                                          export_materials="EXPORT",
                                          export_animation_mode="ACTIVE_ACTIONS",
                                          export_nla_strips_merged_animation_name=act.name,
                                          export_apply=False, use_selection=True)
                gltf.setdefault("per_animation", {})[act.name] = {
                    "path": f.relative_to(pack).as_posix(), "bytes": f.stat().st_size,
                    "frames": baked.get(act.name, {}).get("frames")}
            except Exception as e:                       # noqa: BLE001
                gltf["per_animation_error"] = f"{act.name}: {e}"
                log(f"  [warn] per-anim export failed on {act.name}: {e}")
                break
        arm.animation_data.action = current or arm.animation_data.action
        for o in bpy.context.selected_objects:
            o.select_set(False)
    rec["gltf"] = gltf

    if opts.preview:
        try:
            rec["preview"] = render_preview(pack, name, arm, frames=frames,
                                           samples=opts.preview_samples,
                                           anim=opts.preview_anim)
        except Exception as e:                           # noqa: BLE001 - cosmetic, never fatal
            rec["preview_error"] = f"{type(e).__name__}: {e}"
            log(f"  [warn] preview render failed: {rec['preview_error']}")

    if not opts.no_blend:
        blend = pack / f"{name}.blend"
        bpy.ops.wm.save_as_mainfile(filepath=str(blend))
        backup = blend.with_suffix(".blend1")
        if backup.exists():
            backup.unlink()
        rec["blend"] = blend.name
        log(f"  saved {blend.name}")
    rec["animations"] = {
        k: ({"frames": int(v["frames"].shape[0]), "fps": v["fps"], "looping": v["looping"],
             "delta": v["delta"], "frame_count": v.get("frame_count")}
            if "frames" in v else {"error": v["error"]})
        for k, v in anims.items()
    }
    rec["animation_count"] = len(rec["animations"])
    rec["frames_total"] = sum(v.get("frames", 0) for v in rec["animations"].values())
    rec["bones"] = {"count": len(meta["bone_names"]), "names": list(meta["bone_names"])}
    rec["problems"] = []
    if rec["gltf"].get("error"):
        rec["problems"].append(rec["gltf"]["error"])
    if not rec["arms_meshes"]:
        rec["problems"].append("no arms mesh bound (SMD bone names did not match the rig)")
    rec["ok"] = not rec["problems"]
    # One manifest per pack, beside the .blend.  The aggregate at `<out>/manifest.json` describes a
    # build run; a pack gets copied into a project on its own and has to say what it is, which
    # textures were dropped, what the arms bind did, and where its .mdl came from.  The QA gates read
    # it to find the source model, so a built pack is checkable without the content root.
    (pack / "manifest.json").write_text(json.dumps(
        {"weapon": rec["weapon"], "options": _options_dict(opts), "build": rec},
        indent=1, default=str))
    return rec


def _options_dict(opts):
    """The knob values that change the output, for the per-pack and aggregate manifests."""
    return {"scale": opts.scale, "smoothing": opts.smoothing, "only": opts.only,
            "twist_position_bones": not opts.no_twist_fix,
            "arms_bind": opts.arms_bind, "arms_grip_fit": opts.arms_grip_fit,
            "arms_grip_clearance": opts.arms_grip_clearance, "all_arms": opts.all_arms,
            "textures": not opts.no_textures, "texture_size": opts.texture_size,
            "per_animation_glb": opts.per_anim}


def main():
    ap = argparse.ArgumentParser(description="Build one deliverable pack per weapon.")
    ap.add_argument("--build", default="build/content", help="staged content root")
    ap.add_argument("--archi", default="/tmp/archi", help="archi checkout (source of the arms SMDs)")
    ap.add_argument("--out", default="dist", help="output root; one folder per weapon")
    ap.add_argument("--only", default="", help="substring filter on the weapon folder name")
    ap.add_argument("--limit", type=int, default=0, help="build at most N weapons")
    ap.add_argument("--arms", default="Ct Arms",
                    help="arms folder to bind: 'Ct Arms', 'Knife Rig/Ct Arms', 'balkan', ...")
    ap.add_argument("--arms-bind", choices=["rigid", "side", "smooth", "skinned"],
                    default="rigid",
                    help="how the arms SMDs are weighted. They ship ONE hard bone per vertex and "
                         "the bones they name disagree under the weapon's animation (ForeTwist "
                         "vs Forearm diverge by 72 deg at reload frame 36), so a per-vertex split "
                         "drags the mesh into spikes. 'rigid' (default) binds each connected part "
                         "to its dominant bone: longest edge stays at its authored 2.1 in instead "
                         "of 47.7. 'side' collapses a whole arm onto one limb bone, 'smooth' "
                         "diffuses the authored weights over the edge graph (13.3 in), "
                         "'skinned' uses the file verbatim (tears, but no invented weights).")
    ap.add_argument("--arms-grip-fit", dest="arms_grip_fit", action="store_true", default=True,
                    help="translate the arms assembly so the hands sit on the weapon (default); "
                         "the loose SMDs carry no reference-frame transform, so without this the "
                         "gloves stay ~6 in from the grip in every frame")
    ap.add_argument("--arms-grip-clearance", type=float, default=0.5,
                    help="how close --arms-grip-fit pulls the arms to the weapon, in model inches; "
                         "closer than this earns nothing, so the sleeves do not end up inside the "
                         "rifle")
    ap.add_argument("--no-arms-grip-fit", dest="arms_grip_fit", action="store_false",
                    help="keep the arms exactly where the SMD puts them")
    ap.add_argument("--all-arms", action="store_true",
                    help="bind every SMD in the folder instead of one hand per side "
                         "(archi ships the variants/LODs side by side, so this stacks duplicates)")
    ap.add_argument("--no-arms", dest="arms", action="store_const", const=None,
                    help="weapon only, do not bind any arms mesh")
    ap.add_argument("--scale", type=float, default=1.0,
                    help="import scale; 1.0 keeps Source units (inches) so decoded values need "
                         "no rescale and the bind-pose residual can be measured directly")
    ap.add_argument("--smoothing", default="BEZIER", choices=["BEZIER", "LINEAR", "CONSTANT"],
                    help="keyframe interpolation written into every baked action")
    ap.add_argument("--no-twist-fix", dest="no_twist_fix", action="store_true",
                    help="skip the Rz(-90) authoring-frame correction on bones that carry a "
                         "position channel (reproduces the raw decoded numbers)")
    ap.add_argument("--per-anim", dest="per_anim", action="store_true", default=False,
                    help="also write one skeleton-only .glb per animation (the base .glb "
                         "already carries every animation, so this is only for handing a "
                         "single clip to someone)")
    ap.add_argument("--no-per-anim", dest="per_anim", action="store_false",
                    help="explicitly skip --per-anim (the default)")
    ap.add_argument("--no-textures", action="store_true", help="skip PNG texture export")
    ap.add_argument("--texture-size", type=int, default=2048, help="downscale textures to this")
    ap.add_argument("--no-blend", action="store_true", help="skip saving the .blend")
    ap.add_argument("--preview", action="store_true",
                    help="render preview.png from the posed merge (slow: ~15 s/frame on CPU, "
                         "but it is how you tell a bad arm bind from a good one)")
    ap.add_argument("--preview-frame", dest="preview_frame", default="mid",
                    help="frame index, 'mid', or a comma list (default: mid of the longest anim)")
    ap.add_argument("--preview-samples", type=int, default=6)
    ap.add_argument("--preview-anim", default="reload",
                    help="which baked action to preview (substring match; empty = longest clip)")
    ap.add_argument("-v", "--verbose", action="store_true")

    opts = ap.parse_args()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    if opts.arms and not Path(opts.archi).is_dir():
        log(f"[warn] arms source {opts.archi} missing; run pipeline/stage_content.py first")
    enable_sourceio()

    build = Path(opts.build)
    if not build.is_absolute():
        build = HERE.parent / build
    out = Path(opts.out)
    if not out.is_absolute():
        out = HERE.parent / out
    archi = Path(opts.archi)
    if not archi.is_dir():
        archi = None

    weapon_dirs = sorted(p for p in build.glob("*/m_cs2_*") if p.is_dir())
    if opts.only:
        weapon_dirs = [d for d in weapon_dirs if opts.only in d.name]
    if opts.limit:
        weapon_dirs = weapon_dirs[:opts.limit]
    if not weapon_dirs:
        raise SystemExit(f"no weapon folders staged under {build} (run stage_content.py)")

    arms_dirs = find_arms_sets(archi, opts.arms) if archi else []
    log(f"{len(weapon_dirs)} weapon(s); arms source: "
        + (", ".join(str(d.relative_to(archi)) for d in arms_dirs) if arms_dirs else "none")
        + (f" ({sum(len(list(d.glob('*.smd'))) for d in arms_dirs)} smd)" if arms_dirs else ""))

    manifest = {"built": [], "src": str(build), "run_options": _options_dict(opts),
                "arms": [str(d.relative_to(archi)) for d in arms_dirs] if archi else [],
                "note": "each pack also writes <pack>/manifest.json, which travels with the pack"}
    t_start = time.time()
    for d in weapon_dirs:
        cand = sorted((d / "models" / "weapons").glob("v_*.mdl")) or sorted(d.rglob("v_*.mdl"))
        if not cand:
            log(f"  {d.name}: no v_*.mdl, skipped")
            continue
        od = out / d.name
        od.mkdir(parents=True, exist_ok=True)
        clear_scene()
        t0 = time.time()
        try:
            rec = build_one(d, cand[0], arms_dirs, od, opts)
        except Exception as e:                           # noqa: BLE001 - one bad model, keep going
            log(f"  [FAIL] {d.name}: {type(e).__name__}: {e}")
            if opts.verbose:
                traceback.print_exc()
            manifest["built"].append({"weapon": cand[0].stem, "ok": False,
                                      "error": f"{type(e).__name__}: {e}"})
            continue
        rec["seconds"] = round(time.time() - t0, 1)
        status = "ok  " if rec["ok"] else "WARN"
        log(f"  [{status}] {d.name}: {rec['animation_count']} anims / {rec['frames_total']} frames, "
            f"{rec['arms_triangles']} arm tris, {len(rec.get('textures', []))} textures, "
            f"{len(rec.get('sounds', []))} sound files, {rec['seconds']}s"
            + (f"  ! {'; '.join(rec['problems'][:2])}" if rec["problems"] else ""))
        manifest["built"].append(rec)
    manifest["seconds"] = round(time.time() - t_start, 1)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, default=str))
    log(f"manifest -> {out / 'manifest.json'}")
    bad = [r["weapon"] for r in manifest["built"] if not r.get("ok")]
    if bad:
        log("FAILED:", ", ".join(bad))
    sys.stdout.flush()
    # Blender's exit path hangs/noisily under the headless stub libs; everything is on disk.
    os._exit(1 if bad else 0)


if __name__ == "__main__":
    raise SystemExit(main())
