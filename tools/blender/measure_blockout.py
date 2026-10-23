"""Measures a TripoSG blockout (local guide only, never shipped) per body segment, so our own
rebuilt model can match its proportions: the mesh is scaled to 1 unit tall with its feet at 0,
then split into height bands and left/centre/right; each segment's bounding box is printed as
JSON (game coordinates: x right, y up, z toward the camera in the art). Bands and the centre
width come from the arguments.
Run: blender --background --factory-startup --python tools/blender/measure_blockout.py -- <blockout.glb> [out.json]
"""
import json
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = ARGS[0]
OUT = ARGS[1] if len(ARGS) > 1 else ""
BANDS = [("feet", 0.0, 0.07), ("shin", 0.07, 0.27), ("knee", 0.27, 0.33), ("thigh", 0.33, 0.47), ("pelvis", 0.47, 0.55),
         ("waist", 0.55, 0.65), ("chest", 0.65, 0.8), ("shoulders", 0.8, 0.92), ("top", 0.92, 1.01)]
CENTRE = 0.14

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
pts = []
for o in bpy.data.objects:
    if o.type == "MESH":
        pts += [o.matrix_world @ v.co for v in o.data.vertices]
# Blender is z-up; to game coords: x, y = z, z = -y.
g = [Vector((p.x, p.z, -p.y)) for p in pts]
lo = Vector((min(p.x for p in g), min(p.y for p in g), min(p.z for p in g)))
hi = Vector((max(p.x for p in g), max(p.y for p in g), max(p.z for p in g)))
k = 1.0 / max(1e-6, hi.y - lo.y)
cx, cz = (lo.x + hi.x) / 2, (lo.z + hi.z) / 2
g = [Vector(((p.x - cx) * k, (p.y - lo.y) * k, (p.z - cz) * k)) for p in g]
out = {"source": SRC, "verts": len(g), "size": [(hi.x - lo.x) * k, 1.0, (hi.z - lo.z) * k], "segments": {}}
for name, y0, y1 in BANDS:
    for side, test in (("l", lambda x: x < -CENTRE), ("c", lambda x: -CENTRE <= x <= CENTRE), ("r", lambda x: x > CENTRE)):
        s = [p for p in g if y0 <= p.y < y1 and test(p.x)]
        if len(s) < 20:
            continue
        mn = [round(min(p[i] for p in s), 3) for i in range(3)]
        mx = [round(max(p[i] for p in s), 3) for i in range(3)]
        out["segments"]["%s_%s" % (name, side)] = {"min": mn, "max": mx, "n": len(s)}
text = json.dumps(out, indent=1)
print("MEASURE", text)
if OUT:
    open(OUT, "w").write(text)
