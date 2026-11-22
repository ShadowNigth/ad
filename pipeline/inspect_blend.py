"""Dump the structure of a .blend: collections, objects, armature bones, actions, drivers."""
import sys, bpy

path = sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=path)
d = bpy.data
print("== FILE:", path)
print("scene:", [s.name for s in d.scenes])
for sc in d.scenes:
    print(f"-- scene '{sc.name}' frame {sc.frame_start}..{sc.frame_end} fps {sc.render.fps}")
print("== collections ==")
def walk(col, depth=0):
    print("  " * depth + f"[{col.name}] objs={len(col.objects)}")
    for ch in col.children:
        walk(ch, depth + 1)
for sc in d.scenes:
    walk(sc.collection)
print("== objects ==")
for o in d.objects:
    par = o.parent.name if o.parent else None
    print(f"  {o.name:34s} type={o.type:12s} mesh_verts={len(o.data.vertices) if o.type=='MESH' else '-':>7} "
          f"parent={par} vgroups={len(o.vertex_groups) if hasattr(o,'vertex_groups') else 0}")
print("== armatures ==")
for a in d.armatures:
    print(f"  armature '{a.name}': bones={len(a.bones)} layers={a.layers if hasattr(a,'layers') else ''}")
    for b in a.bones:
        p = b.parent.name if b.parent else "-"
        print(f"     {b.name:34s} parent={p:28s} children={len(b.children)} use_deform={b.use_deform}")
print("== actions ==")
def action_channels(ac):
    out = []
    for lay in ac.layers:
        for strip in getattr(lay, "strips", []):
            for cb in getattr(strip, "channelbags", []):
                out += list(cb.fcurves)
    return out
for ac in d.actions:
    chs = action_channels(ac)
    print(f"  action '{ac.name}': fcurves={len(chs)} frame {tuple(ac.frame_range)}")
    seen = set()
    for c in chs[:400]:
        key = (c.data_path, c.array_index)
        if key in seen: continue
        seen.add(key)
        print("     ", c.data_path, "|", c.array_index, "| keys:", len(c.keyframe_points))
print("== meshes/materials/images ==")
print("  meshes:", len(d.meshes), "materials:", [m.name for m in d.materials][:30])
print("  images:", [(im.name, im.size[0], im.size[1], im.packed_file is not None) for im in d.images][:40])
print("== node groups ==")
for ng in d.node_groups:
    print("  ng:", ng.name, len(ng.interface.items_tree) if hasattr(ng,'interface') else '')
print("== pose bones: controls, constraints, custom props ==")
for a in d.armatures:
    ob = bpy.data.objects.get("Rig") or next((o for o in d.objects if o.type=="ARMATURE"), None)
    if not ob: continue
    for pb in ob.pose.bones:
        cs = [f"{c.type}<-{c.subtarget or (c.object.name if c.object else '')}" for c in pb.constraints]
        props = [k for k in pb.keys() if not k.startswith("_")]
        if cs or props:
            print(f"  {pb.name:26s} mode={pb.bone_collection or ''} constraints={cs} props={props}")
print("== constraints summary ==")
for o in d.objects:
    cs = [c.type for c in o.constraints] if hasattr(o, "constraints") else []
    if cs: print(f"  {o.name}: {cs}")
print("== armature modifiers bone props ==")
for o in d.objects:
    for m in getattr(o, "modifiers", []):
        if m.type == "ARMATURE":
            print(f"  {o.name} armature modifier -> {m.object.name if m.object else None}")
