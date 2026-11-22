"""Minimal SMD (Valve StudioModelData, version 1, ASCII) reader + Blender mesh builder.

archi ships the first-person arms/glove meshes only as `.smd`.  SourceIO only *exports* SMD and
Blender Source Tools needs a real windowed Blender, so this module reads the format directly.
Two dialects show up in the archive and both are handled:

  * classic: `triangles` holds index records (`<smooth> i0 i1 i2`) and a later `vertices`
    section holds `bone x y z nx ny nz u v [w0 b0 w1 b1 w2 b2]`;
  * inline:  `triangles` holds the vertices themselves -- a bare material line then three
    records of `bone x y z nx ny nz u v`, no index list, no shared vertices (what the glove
    and arm meshes in `Sport_gloves/` use).

Sections this pipeline does not need (`$cdmaterials`-style collision, eyes, flexes, IK,
animation) are skipped by name, everything else is parsed positionally.
Meshes are skinned by bone *name*, so they bind onto whatever armature carries those bones:
that is what lets archi's arms ride on each weapon's own `v_weapon.Bip01_*` skeleton.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

NUMBER = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")
SECTION = re.compile(r"^(nodes|skeleton|triangles|vertices|collision|clip|hitboxes|physics|"
                     r"eyebags|eyes|flexes|flexdata|iqe|anim|animation|boneframe|baseframe|"
                     r"sequence|ik|lol|jiggle|cloth|ballsocket|link|constraint|deltanodes|"
                     r"deltatransform|split)\b", re.I)
SKIP_SECTIONS = {"collision", "clip", "hitboxes", "physics", "eyebags", "eyes", "flexes",
                 "flexdata", "iqe", "anim", "animation", "boneframe", "baseframe", "sequence",
                 "ik", "lol", "jiggle", "cloth", "ballsocket", "link", "constraint",
                 "deltanodes", "deltatransform", "split"}


@dataclass
class Smd:
    path: str = ""
    version: int = 1
    nodes: list = field(default_factory=list)        # [(name, parent_index)]
    bone_pos: dict = field(default_factory=dict)     # reference-pose translation per bone
    materials: list = field(default_factory=list)    # material names, in order of appearance
    tri_idx: np.ndarray = None                       # (n, 3) vertex ids
    tri_mat: np.ndarray = None                       # (n,)  material slot per triangle
    vert_pos: np.ndarray = None                      # (v, 3)
    vert_nrm: np.ndarray = None                      # (v, 3)
    vert_uv: np.ndarray = None                       # (v, 2)
    vert_weights: list = field(default_factory=list)  # per vertex: [(bone_name, weight)]
    frames: int = 0
    welded: tuple = (0, 0)          # vertex count before -> after weld_unshared()

    @property
    def tri_count(self):
        return 0 if self.tri_idx is None else len(self.tri_idx)

    def weld_unshared(self):
        """Merge duplicated corner vertices, cutting the mesh down to its real size.

        The inline dialect stores every triangle corner separately, so a closed glove has three
        records for each shared corner.  Merging only records that agree in position *and*
        normal *and* uv *and* bone cannot change the render -- it just lets one set of skinning
        weights land on one vertex instead of three, which is also what keeps the glTF small
        enough to ship (g0.smd: 6000 -> 1153 vertices).
        """
        if self.tri_idx is None or len(self.tri_idx) * 3 != len(self.vert_pos):
            return                                     # already indexed, or not one-to-one
        if any(len(w) != 1 for w in self.vert_weights):
            return                                     # multi-bone vertices: leave it alone
        ids = {n: i for i, (n, _p) in enumerate(self.nodes)}
        bone = np.array([[ids.get(w[0][0], -1)] if w else [-1] for w in self.vert_weights],
                        dtype=np.float32)
        key = np.round(np.hstack([self.vert_pos, self.vert_nrm, self.vert_uv, bone]), 6)
        _uniq, inv = np.unique(key, axis=0, return_inverse=True)
        inv = inv.reshape(-1).astype(np.int64)
        n_uniq = int(inv.max()) + 1
        if n_uniq == len(key):
            return
        order = np.argsort(inv, kind="stable")        # keep the first occurrence of each id
        grouped = inv[order]
        first = order[np.concatenate(([True], grouped[1:] != grouped[:-1]))]
        before = len(self.vert_pos)
        self.vert_pos = self.vert_pos[first]
        self.vert_nrm = self.vert_nrm[first]
        self.vert_uv = self.vert_uv[first]
        self.vert_weights = [self.vert_weights[i] for i in first]
        self.tri_idx = inv.reshape(-1, 3)
        self.welded = (before, len(self.vert_pos))

def _nums(line: str):
    return [float(m.group()) for m in NUMBER.finditer(line)]


def read_smd(path) -> Smd:
    path = Path(path)
    smd = Smd(path=str(path))
    lines = path.read_text(errors="replace").splitlines()
    section, i = None, 0
    tri_mat_rows, tri_idx_rows, tri_inline = [], [], []
    vert_rows = []
    cur_mat = -1
    while i < len(lines):
        raw = lines[i]
        line = raw.strip()
        i += 1
        if not line or line.startswith("//"):
            continue
        low = line.lower()
        if low == "end":
            section = None
            continue
        if section is None:
            m = SECTION.match(line)
            if m:
                head = m.group(1).lower()
                if head in SKIP_SECTIONS:
                    depth = 1
                    while i < len(lines):
                        l2 = lines[i].strip().lower()
                        i += 1
                        if l2 == "end":
                            depth -= 1
                            if depth == 0:
                                break
                        elif l2 in SKIP_SECTIONS or l2 in ("triangles", "nodes", "skeleton",
                                                           "vertices"):
                            depth += 1
                    continue
                section = head
                continue
            if low.startswith("version"):
                v = _nums(line)
                smd.version = int(v[0]) if v else 1
                continue
            continue                                # property lines ($flags etc.)
        if section == "nodes":
            m = re.match(r'\s*(\d+)\s+"([^"]*)"\s+(-?\d+)', line)
            if m:
                smd.nodes.append((m.group(2), int(m.group(3))))
            continue
        if section == "skeleton":
            if low.startswith("time"):
                smd.frames += 1
                continue
            v = _nums(line)
            if len(v) >= 10 and smd.frames <= 1:     # reference pose only
                idx = int(v[0])
                if 0 <= idx < len(smd.nodes):
                    smd.bone_pos.setdefault(smd.nodes[idx][0], tuple(v[1:4]))
            continue
        if section == "triangles":
            v = _nums(line)
            if len(v) >= 9:                          # inline vertex record
                tri_inline.append((cur_mat, v))
            elif len(v) >= 4:                        # index record: smooth + 3 ids
                tri_idx_rows.append([int(x) for x in v[1:4]])
                tri_mat_rows.append(cur_mat)
            else:                                    # material marker
                name = line.strip('"').strip()
                if name:
                    if name not in smd.materials:
                        smd.materials.append(name)
                    cur_mat = smd.materials.index(name)
            continue
        if section == "vertices":
            v = _nums(line)
            if len(v) >= 9:
                vert_rows.append(v)
            continue
    if tri_inline:
        n = len(tri_inline) // 3
        smd.tri_idx = np.arange(3 * n, dtype=np.int64).reshape(n, 3)
        smd.tri_mat = np.array([r[0] for r in tri_inline[:3 * n:3]], dtype=np.int64)
        vals = np.array([r[1] for r in tri_inline[:3 * n]], dtype=np.float32)
        smd.vert_pos = vals[:, 1:4].copy()
        smd.vert_nrm = vals[:, 4:7].copy()
        smd.vert_uv = vals[:, 7:9].copy()
        names = [nm for nm, _ in smd.nodes]
        smd.vert_weights = [([(names[int(b)], 1.0)] if 0 <= int(b) < len(names) else [])
                            for b in vals[:, 0]]
    elif vert_rows and tri_idx_rows:
        smd.tri_idx = np.array(tri_idx_rows, dtype=np.int64)
        smd.tri_mat = np.array(tri_mat_rows, dtype=np.int64)
        arr = np.array(vert_rows, dtype=np.float32)
        smd.vert_pos = arr[:, 1:4].copy()
        smd.vert_nrm = arr[:, 4:7].copy()
        smd.vert_uv = arr[:, 7:9].copy()
        names = [nm for nm, _ in smd.nodes]
        ws = []
        for row in arr:
            out, k = [], 9
            while k + 1 < len(row):
                bi, w = int(row[k]), float(row[k + 1])
                k += 2
                if w > 0 and 0 <= bi < len(names):
                    out.append((names[bi], w))
            ws.append(out)
        smd.vert_weights = ws
    if tri_inline:
        smd.weld_unshared()
    if smd.tri_idx is None:
        raise ValueError(f"{path.name}: no usable triangles/vertices section "
                         f"(nodes={len(smd.nodes)}, inline={len(tri_inline)}, "
                         f"verts={len(vert_rows)})")
    return smd


# ------------------------------------------------------------------------------- blender --
BONE_ALIASES = {                                        # arms SMD <-> weapon .mdl naming drift
    "Bip01_L_Forearm": "v_weapon.Bip01_L_Forearm",
    "Bip01_R_Forearm": "v_weapon.Bip01_R_Forearm",
}


def resolve_bone(name: str, bones) -> str | None:
    """Map an SMD node name onto an armature bone, or None when there is no match."""
    if name in bones:
        return name
    for a, b in BONE_ALIASES.items():
        if name.endswith(a) and b in bones:
            return b
    for cand in (f"v_weapon.{name}", name.split(".")[-1],
                 name.replace("v_weapon.", "")):
        if cand in bones:
            return cand
    return None


def find_texture(name: str, folders) -> Path | None:
    """Locate a material name (`R_0.bmp`) among the SMD's own folder and its parents."""
    if not name:
        return None
    stem = Path(name).stem.lower()
    exts = (".bmp", ".tga", ".png", ".jpg", ".jpeg", ".vtf")
    for folder in folders:
        folder = Path(folder)
        for _ in range(4):                             # search the folder and 3 parents up
            if not folder.is_dir():
                break
            for cand in (folder / name, *(folder / f"{stem}{e}" for e in exts)):
                if cand.is_file():
                    return cand
            for cand in sorted(folder.glob(f"{stem}.*")):
                if cand.suffix.lower() in exts:
                    return cand
            for sub in sorted(p for p in folder.iterdir() if p.is_dir()):
                for cand in sorted(sub.glob(f"{stem}.*")):
                    if cand.suffix.lower() in exts:
                        return cand
            folder = folder.parent
    return None


def to_blender_mesh(smd: Smd, armature, prefix="", folders=(), textures=None, link=True,
                    bind="rigid"):
    """Build one skinned object from the SMD, parented to `armature`.

    Returns (object, bound_bone_names, material_slots), or (None, [], []) when no vertex of the
    SMD maps onto the rig.  The vertex groups are created on the *object*, not the mesh: this
    Blender (4.5 LTS) has no `Mesh.vertex_groups` any more, and it is also where SourceIO puts
    the weights it imports from a .mdl, which is what lets both sets of meshes share one rig.
    """
    import bpy

    bones = set(armature.data.bones.keys())
    stem = Path(smd.path).stem
    me = bpy.data.meshes.new(f"{prefix}{stem}")
    faces = [tuple(int(x) for x in row) for row in smd.tri_idx]
    me.from_pydata([tuple(v) for v in smd.vert_pos], [], faces)
    me.validate()
    me.update()
    if len(me.vertices) != len(smd.vert_pos):
        bpy.data.meshes.remove(me)
        raise ValueError(f"{stem}: vertex count changed while building ({len(me.vertices)} "
                         f"!= {len(smd.vert_pos)}) - out-of-range or degenerate faces")
    ob = bpy.data.objects.new(f"{prefix}{stem}", me)
    if link:
        bpy.context.collection.objects.link(ob)

    depth = {}
    if armature is not None:
        for b in armature.data.bones:
            d, p = 0, b.parent
            while p is not None:
                d += 1
                p = p.parent
            depth[b.name] = d

    groups, missing = {}, 0
    rows_of = None
    if bind == "skinned":                              # the file's weights, verbatim
        rows_of = None
    elif bind in ("side", "rigid", "smooth"):
        import arm_skin
        nv = len(smd.vert_pos)
        if bind == "side":
            rows_of, anchor = arm_skin.limb_rows(smd.vert_weights)
            ob["arms_limb_anchors"] = ", ".join(f"{k}={v}" for k, v in sorted(anchor.items()))
        elif bind == "rigid":
            comp = arm_skin.components(nv, smd.tri_idx)
            dom = arm_skin.bone_matrix(smd.vert_weights, comp, depth)
            rows_of = [[(b, 1.0)] if b else [] for b in dom]
            ob["arms_components"] = len({i for i in comp})
            ob["arms_component_bones"] = ", ".join(sorted({x.split(".")[-1] for x in dom if x}))
        else:
            nbr = arm_skin.adjacency(nv, smd.tri_idx)
            W, bones = arm_skin.smooth_weights(smd.vert_weights, nbr)
            rows_of = [[(b, float(W[vi, i])) for i, b in enumerate(bones) if W[vi, i] > 0]
                       for vi in range(nv)]
            ob["arms_smooth_bones"] = len(bones)
    else:
        raise ValueError(f"unknown arms bind mode {bind!r} "
                         "(expected skinned, side, rigid or smooth)")
    for vi, ws in enumerate(smd.vert_weights):
        rows = ws if rows_of is None else rows_of[vi]
        for bone, w in rows:
            target = resolve_bone(bone, bones)
            if target is None:
                missing += 1
                continue
            vg = groups.get(target) or ob.vertex_groups.new(name=target)
            groups[target] = vg
            vg.add([vi], w, "REPLACE")
    if not groups:
        bpy.data.objects.remove(ob, do_unlink=link)
        bpy.data.meshes.remove(me)
        return None, [], []

    if smd.vert_nrm is not None and len(smd.vert_nrm) == len(me.vertices):
        ln = np.zeros((len(me.loops), 3), dtype=np.float64)
        for poly in me.polygons:
            for li in poly.loop_indices:
                ln[li] = smd.vert_nrm[me.loops[li].vertex_index]
        me.normals_split_custom_set([tuple(v) for v in ln])
    if smd.vert_uv is not None and len(smd.vert_uv) == len(me.vertices):
        uv = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li in poly.loop_indices:
                uv.data[li].uv = smd.vert_uv[me.loops[li].vertex_index]
    for poly in me.polygons:
        poly.use_smooth = True

    slots = []
    names = smd.materials or [""]
    for k, mname in enumerate(names):
        mat = (textures or {}).get(mname)
        if mat is None:
            mat = bpy.data.materials.new(f"{prefix}{stem}_{k}")
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            tex = find_texture(mname, folders) if folders else None
            if bsdf is not None and tex is not None:
                img = bpy.data.images.load(str(tex), check_existing=True)
                node = mat.node_tree.nodes.new("ShaderNodeTexImage")
                node.image = img
                node.location = (-420, 240)
                mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            elif bsdf is not None:
                bsdf.inputs["Base Color"].default_value = (0.35, 0.30, 0.26, 1)
                bsdf.inputs["Roughness"].default_value = 0.7
        me.materials.append(mat)
        slots.append((mat, mname))
    if smd.tri_mat is not None and len(names) > 1:
        for poly, mi in zip(me.polygons, smd.tri_mat):
            poly.material_index = int(mi) % len(names)

    ob.parent = armature
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = armature
    ob["smd_source"] = str(smd.path)
    ob["smd_unmapped_weights"] = missing
    return ob, sorted(groups), slots
