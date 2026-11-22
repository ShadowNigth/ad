"""Determine Blender's pose composition rule using the real imported rig (no ops, no edits)."""
import sys, math, numpy as np
sys.argv[0] = "blender"
import bpy, mathutils
bpy.ops.wm.open_mainfile(filepath="/tmp/dist_test/m_cs2_ak47/v_rif_ak47.blend")
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
arm.animation_data.action = None
pb = arm.pose.bones
for b in pb:
    b.matrix_basis.identity()
bpy.context.view_layer.update()

def pick(name):
    return pb[name], arm.data.bones[name]

root = "v_weapon"
# find a bone with a parent, and a grandparent chain to test propagation
child = next(n for n in pb.keys() if pb[n].parent and pb[n].parent.parent)
gp = pb[child].parent.parent.name
par = pb[child].parent.name
print("[p] chain:", gp, "->", par, "->", child, flush=True)

L = {n: np.array(arm.data.bones[n].matrix_local) for n in (gp, par, child)}
I = np.eye(4)
Dpar = mathutils.Matrix.Rotation(math.radians(53), 4, "Y") @ mathutils.Matrix.Translation((2.0, -1.0, 0.5))
Dch = mathutils.Matrix.Rotation(math.radians(-31), 4, "X") @ mathutils.Matrix.Translation((0.4, 0.9, -0.2))

def snap():
    bpy.context.view_layer.update()
    return {n: np.array(pb[n].matrix) for n in (gp, par, child)}, {n: np.array(pb[n].matrix_basis) for n in (gp, par, child)}

def d(a, b): return float(np.abs(a - b).max())

# case A: only the parent bone gets a basis
pb[par].matrix_basis = Dpar
M, B = snap()
print("[p] A (only parent basis):", flush=True)
print("     par.matrix == basis                       :", d(M[par], np.array(Dpar)))
print("     par.matrix == L[par] @ basis              :", d(M[par], L[par] @ np.array(Dpar)))
print("     par.matrix == basis @ L[par]              :", d(M[par], np.array(Dpar) @ L[par]))
print("     child.matrix (basis I) == par.matrix      :", d(M[child], M[par]))
print("     child.matrix (basis I) == par.matrix @ inv(L[par]) @ L[child] :",
      d(M[child], M[par] @ np.linalg.inv(L[par]) @ L[child]))
print("     child.matrix (basis I) == L[child]        :", d(M[child], L[child]))

# case B: both bones keyed
pb[child].matrix_basis = Dch
M, B = snap()
print("[p] B (parent + child basis):", flush=True)
print("     child.matrix == par.matrix @ basis        :", d(M[child], M[par] @ np.array(Dch)))
print("     child.matrix == par.matrix @ inv(L[par]) @ L[child] @ basis :",
      d(M[child], M[par] @ np.linalg.inv(L[par]) @ L[child] @ np.array(Dch)))
print("     child.matrix == L[child] @ basis           :", d(M[child], L[child] @ np.array(Dch)))
print("     child.matrix == par.matrix @ inv(L[par]) @ basis :",
      d(M[child], M[par] @ np.linalg.inv(L[par]) @ np.array(Dch)))
sys.stdout.flush()
import os; os._exit(0)
