"""Compare the arms SMD skeleton (bind pose) against the weapon .mdl rest pose, per bone."""
import sys, math
sys.argv[0] = "blender"
sys.path.insert(0, "/home/user/ad/pipeline"); sys.path.insert(0, "/tmp/bl-addons")
import numpy as np, bpy, addon_utils, mathutils
from pathlib import Path
bpy.ops.wm.read_factory_settings(use_empty=True)
addon_utils.enable("SourceIO", default_set=True)
MDL = Path("/home/user/ad/build/content/CS2GO.Pack.Director.s.Cut.-.Rifles/m_cs2_ak47/models/weapons/v_rif_ak47.mdl")
SMD = Path("/tmp/archi/Sport_gloves/Knife Rig/Ct Arms/g0.smd")
bpy.ops.sourceio.mdl(filepath=str(MDL), directory=str(MDL.parent), files=[{"name": MDL.name}],
                     import_animations=False, import_textures=False, compact_animations=False, scale=1.0)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
bl = {b.name: np.array(b.matrix_local) for b in arm.data.bones}

# --- full SMD skeleton (pos + euler radians), accumulated through the parent chain
import smd_import
txt = SMD.read_text(errors="replace").splitlines()
nodes, parents, pose = [], [], {}
sec, i = None, 0
while i < len(txt):
    ln = txt[i].strip(); i += 1
    if not ln: continue
    low = ln.lower()
    if low == "end": sec = None; continue
    if low in ("nodes","skeleton","triangles","vertices"): sec = low; continue
    if sec == "nodes":
        import re
        m = re.match(r'(\d+)\s+"([^"]*)"\s+(-?\d+)', ln)
        if m: nodes.append(m.group(2)); parents.append(int(m.group(3)))
    elif sec == "skeleton":
        if low.startswith("time"): continue
        parts = ln.split()
        v = [float(x) for x in parts[1:]] if parts and parts[0].isdigit() else None
        if v is not None and len(v) >= 6:
            idx = int(ln.split()[0]); pose[idx] = (np.array(v[0:3]), np.array(v[3:6]))
print(f"[cmp] smd nodes {len(nodes)} skeleton rows {len(pose)}")

def mat(loc, euler):
    L = mathutils.Matrix.Translation(mathutils.Vector(loc))
    R = mathutils.Euler((float(euler[0]), float(euler[1]), float(euler[2])), "XYZ").to_matrix().to_4x4()
    return L @ R

def accum_smd():
    M = {}
    for k in range(len(nodes)):
        loc, eul = pose.get(k, (np.zeros(3), np.zeros(3)))
        L = mat(loc, eul)
        p = parents[k]
        M[k] = (mathutils.Matrix(M[p]) @ L) if (0 <= p < k and p in M) else L
    return {k: np.array(v) for k, v in M.items()}
Msmd = accum_smd()

# mdl side
sys.path.insert(0, "/home/user/ad/pipeline")
import os; os.environ["NO_BPY"]="1"
all_anim = None
import source_zanim as Z
all_anim = Z.load_model_animations(MDL, strict=False)
meta = all_anim["_meta"]
names, par = meta["bone_names"], meta["parent_index"]
bp, br = meta["base_pos"], meta["base_rot"]
Mmdl = {}
for k in range(len(names)):
    q = br[k]
    R = mathutils.Quaternion((float(q[3]), float(q[0]), float(q[1]), float(q[2]))).to_matrix().to_4x4()
    L = mathutils.Matrix.Translation(mathutils.Vector(bp[k])).to_4x4()
    Mmdl[k] = (Mmdl[par[k]] @ L @ R) if 0 <= par[k] < k and par[k] in Mmdl else L @ R
mdl_M = {names[k]: np.array(Mmdl[k]) for k in range(len(names))}

def ang(A, B):
    Ra, Rb = A[:3,:3], B[:3,:3]
    c = np.clip((np.trace(Ra @ Rb.T)-1)/2, -1, 1)
    return math.degrees(math.acos(c)), np.linalg.norm(A[:3,3]-B[:3,3])

print("[cmp] per-bone: |SMD_bind vs mdl_rest| and |SMD_bind vs blender_rest|")
rows=[]
for k, n in enumerate(nodes):
    if n not in mdl_M or n not in bl: 
        rows.append((n, None)); continue
    a = np.array(Msmd[k]); 
    d1 = ang(a, mdl_M[n]); d2 = ang(a, np.array(bl[n]))
    rows.append((n, d1, d2))
for r in rows:
    if r[1] is None: print("   %-40s (not in mdl)" % r[0]); continue
    print("   %-40s mdl: %7.2f deg / %7.3f   blender: %7.2f deg / %7.3f" % (r[0], r[1][0], r[1][1], r[2][0], r[2][1]))
sys.stdout.flush(); import os as _os; _os._exit(0)
