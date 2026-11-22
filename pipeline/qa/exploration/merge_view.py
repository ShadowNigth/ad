import sys, math
sys.argv[0] = "blender"
import bpy, mathutils, numpy as np
from mathutils import Vector
tag = sys.argv[1]; act = sys.argv[2] if len(sys.argv) > 2 else ""; fr = sys.argv[3] if len(sys.argv) > 3 else "1"
bpy.ops.wm.open_mainfile(filepath="/tmp/dist_test/m_cs2_ak47/v_rif_ak47.blend")
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
if act:
    arm.animation_data.action = bpy.data.actions[act]
    bpy.context.scene.frame_set(int(fr))
    print("[r] posed", act, "frame", bpy.context.scene.frame_current, flush=True)
else:
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
bpy.context.view_layer.update()
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 4
sc.render.resolution_x, sc.render.resolution_y = 900, 420
sc.world = sc.world or bpy.data.worlds.new("w"); sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.14, 0.14, 0.16, 1)
print("[r] object bounds (model space):", flush=True)
allv = []
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    a = np.array([o.matrix_world @ Vector(c) for c in o.bound_box])
    allv.append(a)
    print("[r]   %-24s min %s  max %s" % (o.name[:24], np.round(a.min(0), 1), np.round(a.max(0), 1)), flush=True)
V = np.concatenate(allv)
mid = mathutils.Vector(V.mean(0)); diag = float((V.max(0) - V.min(0)).max())
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera = cam
d = mathutils.Vector((-0.25, -1.0, 0.30)).normalized()
cam.location = mid + d * (diag * 1.3); cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
for i, (loc, en) in enumerate([((20, -60, 50), 4.0), ((-40, 30, 20), 1.5)]):
    L = bpy.data.objects.new(f"L{i}", bpy.data.lights.new(f"L{i}", "SUN")); L.data.energy = en
    L.rotation_euler = (mathutils.Vector(loc) * -1).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(L)
sc.render.filepath = f"/tmp/qa/merge_{tag}.png"
bpy.ops.render.render(write_still=True)
print("[r] wrote /tmp/qa/merge_%s.png (mid %s diag %.1f)" % (tag, np.round(V.mean(0), 1), diag), flush=True)
sys.stdout.flush(); import os; os._exit(0)
