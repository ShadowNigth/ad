"""Visual QA harness for the ZANIM decode: pose a CS2 view model from decoded frames and render.

Numbers alone cannot settle every convention question -- a quantised 6-byte channel almost
always looks "smooth" under more than one reading -- so this renders the model once per
candidate rule.  A wrong rule is obvious by eye: the weapon leaves the hands, fingers bend
the wrong way, or the whole view model is twisted by a constant axis rotation.

Run inside headless Blender (bpy in a venv plus the stub libs, see headless_blender_stubs.py):

    LD_LIBRARY_PATH=/tmp/stubs /tmp/venv/bin/python pipeline/render_qa.py --anim @ak47_fire1

Options
    --mode half|scaled|biased|rot-only   how source_zanim decodes a Vector48 position channel
    --rest mdl|anim                      which pose is the armature's rest pose:
        mdl   mstudiobone_t.position/quat (what SourceIO imports by default)
        anim  frame 0 of the base animation, i.e. the space the animation is authored in
    --anim NAME                          animation to bake ('@ak47_fire1', 'a_bullets', ...)
    --frames 0,33,66,99                  percentages of the clip to sample
    --out /tmp/qa                          where to write the PNGs

The Blender pose relation (`pb.matrix = pb.matrix_parent_inverse @ pb.matrix_basis @
bone.matrix_local`) is solved once at run time and asserted, so the harness can never
silently keyframe the wrong thing; every local matrix we want is composed by walking the
Source bone hierarchy ourselves, which keeps this independent of how the importer laid out
its bones.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.argv[0] = "blender"              # SourceIO keys its bindings off the executable name
HERE = Path(__file__).resolve().parent
for _cand in (str(HERE.parent / "vendor"), "/tmp/bl-addons", os.environ.get("SIO_ADDONS", "")):
    if _cand and Path(_cand, "SourceIO").is_dir():
        sys.path.insert(0, _cand)
        break
sys.path.insert(0, str(HERE))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402


def enable_sourceio():
    import addon_utils
    addon_utils.enable("SourceIO", default_set=True)
    if not hasattr(bpy.ops.sourceio, "mdl"):
        raise RuntimeError("SourceIO registered no operators (make sure NO_BPY is unset)")


# ------------------------------------------------------------- blender matrix plumbing --
class PoseRule:
    """Which composition Blender evaluates for `pb.matrix`, measured rather than assumed.

    Blender 4.x folds the parent in:

        pb.matrix = par.matrix @ inv(par.bone.matrix_local) @ pb.bone.matrix_local @ pb.matrix_basis

    (`matrix_parent_inverse`, which used to sit right after `par.matrix`, is gone in 4.5.)  So
    baking a target armature-space matrix `M` needs

        basis = inv(L[b]) @ L[par] @ inv(M[par]) @ M[b]

    walking parents before children.  The tempting `inv(L[b]) @ M` is *only* right for root
    bones: keying a child of a moved bone with it rotates the child by the parent's motion
    twice, which is what tore the arms mesh into shards (177 deg on `Bip01_R_Finger02`) while
    the gun -- parented to nothing -- looked perfect.  We solve which rule this `bpy` uses by
    setting a random basis on a bone *and its parent* and comparing candidates numerically.
    """

    def __init__(self, arm):
        child = next((pb for pb in reversed(arm.pose.bones) if pb.parent), None)
        if child is None:
            raise RuntimeError("armature has no parented pose bone to calibrate against")
        parent = child.parent
        Lc = np.array(arm.data.bones[child.name].matrix_local)
        Lp = np.array(arm.data.bones[parent.name].matrix_local)
        rng = np.random.default_rng(7)

        def rand(scale):
            q = rng.normal(size=4)
            q /= np.linalg.norm(q)
            m = Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4()
            return Matrix(m) @ Matrix.Translation(Vector(rng.normal(scale=scale, size=3)))

        # A parent-relative rule is only visible if the parent is moved too, so randomise both
        # and keep the parent's basis pinned while every candidate is tested.
        Bpar, Bchild = rand(3.0), rand(2.0)
        parent.rotation_mode = child.rotation_mode = "QUATERNION"
        parent.matrix_basis = Matrix(Bpar)
        child.matrix_basis = Matrix(Bchild)
        bpy.context.view_layer.update()
        got, Mpar = np.array(child.matrix), np.array(parent.matrix)

        cands = {}
        # Which rule reproduces the observed pose?  Apply each and read Blender's own answer,
        # so the calibration cannot drift from the real evaluator.
        for name, basis in (("parent-relative", np.linalg.inv(Lc) @ Lp @ np.linalg.inv(Mpar) @ got),
                            ("naive", np.linalg.inv(Lc) @ got)):
            child.matrix_basis = Matrix(basis)
            bpy.context.view_layer.update()
            cands[name] = float(np.abs(np.array(child.matrix) - got).max())
        parent.matrix_basis.identity()
        child.matrix_basis.identity()
        bpy.context.view_layer.update()
        print("[qa] pose-rule candidates, max |pb.matrix - target|: "
              + ", ".join(f"{k}={v:.2e}" for k, v in cands.items()))
        hits = [k for k, v in cands.items() if v < 1e-3]
        if not hits:
            raise RuntimeError(f"could not calibrate the pose rule (candidates {cands})")
        self.rule = hits[0]
        self.parent_relative = self.rule == "parent-relative"
        self.arm = arm
        self.L = {pb.name: np.array(arm.data.bones[pb.name].matrix_local) for pb in arm.pose.bones}

    def order(self):
        """Pose-bone names, parents before children."""
        arm = self.arm
        out, seen = [], set()

        def visit(name):
            if name in seen:
                return
            seen.add(name)
            par = arm.data.bones[name].parent
            if par is not None:
                visit(par.name)
            out.append(name)

        for pb in arm.pose.bones:
            visit(pb.name)
        return out

    def basis_for(self, name, matrix_armature, parent_armature=None):
        """matrix_basis that puts pose bone `name` at `matrix_armature` (armature space)."""
        L = self.L[name]
        if self.parent_relative:
            par = self.arm.data.bones[name].parent
            if par is not None and parent_armature is not None:
                M = (np.linalg.inv(parent_armature) @ matrix_armature)
                return np.linalg.inv(L) @ self.L[par.name] @ M
        return np.linalg.inv(L) @ matrix_armature


# ------------------------------------------------------------------ animation matrices --
def hierarchy_matrices(pos, rot, parent_index):
    """(bone-local pos/rot) -> armature-space matrices, walking Source's parent chain.

    Returned as a list indexed by bone id; roots are placed in armature space.
    """
    out = [np.eye(4)] * len(parent_index)
    order = sorted(range(len(parent_index)), key=lambda i: _depth(i, parent_index))
    for bi in order:
        p = parent_index[bi]
        local = Matrix.Translation(Vector(pos[bi])) @ Quaternion(
            (rot[bi][3], rot[bi][0], rot[bi][1], rot[bi][2])).to_matrix().to_4x4()
        out[bi] = (out[p] if p is not None and 0 <= p < len(out) else np.eye(4)) @ local
    return out


def _depth(i, parent_index, cache={}):
    if i in cache:
        return cache[i]
    p = parent_index[i]
    d = 0 if p < 0 or p == i else _depth(p, parent_index, cache) + 1
    cache[i] = d
    return d


# ------------------------------------------------------------------------- scene setup --
def setup_scene(mesh):
    sc = bpy.context.scene
    # Workbench/EEVEE need a real GL context and abort in headless bpy, so this renders with
    # Cycles on the CPU: slow per frame but reliable, and 8 samples is plenty for a QA still.
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 8
    sc.cycles.max_bounces = 2
    try:
        sc.display.shading.light = "STUDIO"
        sc.display.shading.color_type = "MATERIAL"
    except AttributeError:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 720, 460
    sc.render.film_transparent = True
    cams = [o for o in sc.objects if o.type == "CAMERA"]
    cam = cams[0] if cams else bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    if cam.name not in [o.name for o in sc.collection.objects]:
        sc.collection.objects.link(cam)
    sc.camera = cam
    if mesh is not None:
        dg = bpy.context.evaluated_depsgraph_get()
        me = mesh.evaluated_get(dg)
        corners = [me.matrix_world @ Vector(c) for c in me.bound_box]
        ctr = sum(corners, Vector()) / 8.0
        span = max(max(c[i] for c in corners) - min(c[i] for c in corners) for i in range(3))
        dist = max(span * 1.6, 1e-3)
        from math import cos, pi, sin
        yaw, pitch = pi * 0.20, pi * 0.30
        cam.location = (ctr.x + dist * cos(pitch) * sin(yaw),
                        ctr.y - dist * cos(pitch) * cos(yaw),
                        ctr.z + dist * sin(pitch))
        cam.rotation_euler = (Vector(ctr) - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 60.0
        cam.data.clip_end = dist * 20 + 100
    for name, energy in (("K1", 3.0), ("K2", 1.4)):
        lamp = bpy.data.lights.new(name, "SUN")
        lamp.energy = energy
        ob = bpy.data.objects.new(name, lamp)
        sc.collection.objects.link(ob)
        ob.rotation_euler = (0.7, 0.3, 0.5) if name == "K1" else (-0.9, 0.2, 2.4)
    bpy.context.view_layer.update()
    return sc


# ------------------------------------------------------------------------------- main --
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mdl", default=str(Path("build/content/CS2GO.Pack.Director.s.Cut.-.Rifles/"
                                              "m_cs2_ak47/models/weapons/v_rif_ak47.mdl")))
    ap.add_argument("--anim", default="@ak47_fire1")
    ap.add_argument("--mode", default="half", choices=["half", "scaled", "biased", "rot-only"])
    ap.add_argument("--rest", default="mdl", choices=["mdl", "anim"])
    ap.add_argument("--base", default="a_base")
    ap.add_argument("--frames", default="0,33,66,99")
    ap.add_argument("--out", default="/tmp/qa")
    ap.add_argument("--tag", default="")
    ap.add_argument("--mesh-only", action="store_true", help="render the rest pose only")
    ap.add_argument("--scale", type=float, default=1.0,
                    help="import scale; 1.0 keeps the scene in Source units (inches) so the "
                         "decoded values need no rescaling")
    ap.add_argument("--max-pose-residual", type=float, default=0.5,
                    help="fail if the pose Blender evaluates after keying is off by more than "
                         "this many degrees at any sampled frame (0 disables)")
    ap.add_argument("--max-residual", type=float, default=0.5,
                    help="fail if frame 0 of the base animation does not reproduce the imported "
                         "rest pose within this many degrees (0 disables)")
    a = ap.parse_args()

    mdl_path = Path(a.mdl)
    if not mdl_path.is_absolute():
        mdl_path = HERE.parent / mdl_path
    if not mdl_path.is_file():
        raise SystemExit(f"no such .mdl: {mdl_path}")
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    # factory settings first: it reloads preferences and would otherwise unregister the
    # addon we are about to enable (bpy.ops.sourceio.mdl would then not exist).
    bpy.ops.wm.read_factory_settings(use_empty=True)
    enable_sourceio()
    bpy.ops.sourceio.mdl(filepath=str(mdl_path), directory=str(mdl_path.parent),
                         files=[{"name": mdl_path.name}], import_animations=False,
                         import_textures=True, compact_animations=False, scale=a.scale)
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    mesh = next((o for o in bpy.data.objects if o.type == "MESH" and len(o.vertex_groups) > 1), None)
    if arm is None or mesh is None:
        raise SystemExit("import produced no armature/skinned mesh")
    for o in list(bpy.data.objects):
        if o not in (arm, mesh) and o.type in {"MESH", "CAMERA", "LIGHT"}:
            bpy.data.objects.remove(o, do_unlink=True)
    arm.animation_data_clear()
    arm.data.transform(Matrix.Identity(4))
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()

    import source_zanim as Z
    Z.POS_MODE = a.mode
    anims = Z.load_model_animations(mdl_path)
    meta = anims.pop("_meta")
    if a.anim not in anims:
        print("[qa] available:", sorted(k for k in anims if not k.startswith("_")))
        raise SystemExit(2)
    frames = anims[a.anim]["frames"]
    names = meta["bone_names"]
    parents = meta["parent_index"]
    # SourceIO truncates bone names at 63 chars; keep a lookup that survives that.
    pose_names = [nm if nm in arm.pose.bones else nm[:63] if nm[:63] in arm.pose.bones else None
                  for nm in names]
    missing = sum(1 for x in pose_names if x is None)
    if missing:
        print(f"[qa] note: {missing} decoded bones are not in the imported armature")


    def local_matrices(row):
        return hierarchy_matrices(row["pos"] * a.scale, row["rot"], parents)

    if a.max_residual > 0 and a.base in anims:
        # The base animation's constant records ARE the bind pose, so decoding is only
        # correct if frame 0 reproduces the rest pose the importer built from
        # mstudiobone_t.  This single check catches quaternion order, the Vector48 axis
        # change, the parent chain and the record layout all at once.
        row0 = anims[a.base]["frames"][0]
        mats = local_matrices(row0)
        worst_a = worst_p = 0.0
        worst = None
        for bi, pn in enumerate(pose_names):
            if pn is None:
                continue
            rest = np.array(arm.data.bones[pn].matrix_local)
            mine = mats[bi]
            Rr, Rm = rest[:3, :3], mine[:3, :3]
            ang = np.degrees(np.arccos(np.clip((np.trace(Rr.T @ Rm) - 1.0) / 2.0, -1.0, 1.0)))
            dt = float(np.linalg.norm(rest[:3, 3] - mine[:3, 3]))
            if ang > worst_a:
                worst_a, worst = ang, pn
            worst_p = max(worst_p, dt)
        print(f"[qa] bind-pose residual: max rotation {worst_a:.3f} deg ({worst}), "
              f"max translation {worst_p:.5f}")
        if worst_a > a.max_residual:
            raise SystemExit(f"[qa] FAIL: frame 0 of {a.base} does not match the rest pose")

    rule = PoseRule(arm)
    print(f"[qa] pose relation: {'parent-relative' if rule.parent_relative else 'naive'}"
          "  (basis = inv(L[b]) @ L[par] @ inv(M[par]) @ M[b])")
    order = [nm for nm in rule.order() if nm in set(x for x in pose_names if x)]

    def pose_row(row, verify=True):
        """Key every bone, parents first, and assert Blender reproduced the target matrices."""
        mats = local_matrices(row)
        m_by_name = {pn: mats[bi] for bi, pn in enumerate(pose_names) if pn}
        done = {}
        for pn in order:
            M = m_by_name.get(pn)
            if M is None:
                continue
            par = arm.data.bones[pn].parent
            pb = arm.pose.bones[pn]
            pb.rotation_mode = "QUATERNION"
            pb.matrix_basis = Matrix(rule.basis_for(pn, M, done.get(par.name if par else None)))
            done[pn] = M
        bpy.context.view_layer.update()
        worst_a = worst_p = 0.0
        if verify:
            for pn, M in m_by_name.items():
                got = np.array(arm.pose.bones[pn].matrix)
                Ra, Rm = got[:3, :3], M[:3, :3]
                ang = np.degrees(np.arccos(np.clip((np.trace(Ra.T @ Rm) - 1.0) / 2.0, -1.0, 1.0)))
                worst_a = max(worst_a, ang)
                worst_p = max(worst_p, float(np.linalg.norm(got[:3, 3] - M[:3, 3])))
            if worst_a > a.max_pose_residual:
                raise SystemExit(f"[qa] FAIL: baked pose is off by {worst_a:.2f} deg "
                                 f"({worst_p:.3f} in) -- the bake rule does not match Blender's")
        return worst_a, worst_p

    if a.rest == "anim":
        # Freeze frame 0 of the base animation into the rest pose: the armature then lives
        # in the same space as the animation data, so skinning = pose @ rest^-1 is exactly
        # what the engine computes.
        rest_row = anims[a.base]["frames"][0] if a.base in anims else frames[0]
        pose_row(rest_row)
        frozen = {pn: np.array(arm.pose.bones[pn].matrix) for pn in pose_names if pn}
        bpy.ops.object.select_all(action="DESELECT")
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        for bn, m in frozen.items():
            arm.data.edit_bones[bn].matrix = Matrix(m)
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in arm.pose.bones:
            pb.matrix_basis.identity()
        bpy.context.view_layer.update()
        print(f"[qa] rest pose frozen from {a.base} ({len(frozen)} bones)")

    sc = setup_scene(mesh)
    tag = a.tag or f"{a.mode}_{a.rest}_{a.anim.strip('@')}"
    if a.mesh_only:
        sc.render.filepath = str(out / f"{tag}_rest.png")
        bpy.ops.render.render(write_still=True)
        print("[qa] rendered", sc.render.filepath)
        return
    n = frames.shape[0]
    picks = sorted({min(n - 1, max(0, int(round(float(p) / 100 * (n - 1)))))
                    for p in a.frames.split(",")})
    worst = (0.0, 0.0)
    for fi in picks:
        worst = pose_row(frames[fi])
        dest = out / f"{tag}_{fi:03d}.png"
        sc.render.filepath = str(dest)
        bpy.ops.render.render(write_still=True)
        print("[qa] rendered", dest)
    print(f"[qa] as-posed residual over {len(picks)} frame(s): max rotation {worst[0]:.3f} deg, "
          f"max translation {worst[1]:.5f}")
    print("[qa] DONE", tag)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except BaseException:
        import traceback
        traceback.print_exc()
        sys.stdout.flush()
        os._exit(1)
    sys.stdout.flush()
    # Blender's exit path is slow/noisy under the headless stub libs; the PNGs are already
    # written, so leave immediately.
    os._exit(0)
