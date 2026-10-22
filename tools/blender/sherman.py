"""HA Sherman, from the core book art (reference only, never shipped): heavy dark faceted armor
around a glowing red core, a huge faceted red reactor block riding high on the back with
glowing green vents, a round green-glowing port on the left shoulder, the long green ZF4 rail
slung over the right shoulder, heavy limbs with red joint caps and big hands, and a tattered
cloth at the waist. Modeled standing (the game's rig pose); the art shows it kneeling.
Run: blender --background --factory-startup --python tools/blender/sherman.py -- assets/mechs/mf_sherman.glb
Game coordinates (x right, y up, -z forward), about 1 unit tall; see mechlib.py."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Vector  # noqa: E402

import mechlib as L  # noqa: E402

L.reset()

DARK = L.mat("primary", (0.13, 0.1, 0.12), 0.45, 0.55)
DARK2 = L.mat("secondary", (0.09, 0.07, 0.09), 0.45, 0.55)
RED = L.mat("accent", (0.5, 0.06, 0.1), 0.35, 0.4)
CORE = L.mat("glow", (0.25, 0.01, 0.01), 0.0, 0.4, emit=(1.0, 0.06, 0.03))
GREEN = L.mat("glow2", (0.05, 0.3, 0.2), 0.0, 0.4, emit=(0.3, 1.0, 0.7))
RAIL = L.mat("rail", (0.1, 0.22, 0.2), 0.5, 0.45)
FRAME = L.mat("trim", (0.04, 0.035, 0.04), 0.7, 0.45)
CLOTH = L.mat("cloth", (0.1, 0.08, 0.09), 0.0, 0.9)

pelvis = L.joint("Pelvis", (0, 0.47, 0))
torso = L.joint("Torso", (0, 0.53, 0.0), pelvis)

# --- body: faceted dark armor around a glowing core ----------------------------------------------
L.box("pelvis_block", (0.24, 0.1, 0.18), (0, 0.46, 0.0), DARK2, pelvis, bevel_w=0.02)
L.box("core_glow", (0.13, 0.16, 0.06), (0, 0.6, -0.1), CORE, torso, bevel_w=0.02)
L.loft("abdomen", [dict(y=0.5, w=0.2, d=0.16, n=2.0), dict(y=0.62, w=0.24, d=0.18, n=2.0)], DARK2, torso, ring=8, sub=0)
L.loft("chest", [dict(y=0.6, w=0.28, d=0.22, n=1.6, z=0.0), dict(y=0.74, w=0.36, d=0.26, n=1.6, z=-0.01), dict(y=0.84, w=0.32, d=0.24, n=1.6, z=0.0)], DARK, torso, ring=8, sub=0)
for s in (1, -1):
    L.box("chest_plate_%d" % s, (0.12, 0.13, 0.04), (s * 0.08, 0.73, -0.13), DARK, torso, rot_deg=(-8, s * 12, 0), bevel_w=0.012)
L.box("core_slit", (0.1, 0.02, 0.01), (0, 0.66, -0.135), CORE, torso, bevel_w=0.004)
for i in range(4):
    L.tube("hose%d" % i, L.bezier((-0.12 + i * 0.03, 0.82, -0.08), (-0.14 + i * 0.03, 0.78, -0.14), (-0.1 + i * 0.03, 0.72, -0.14), (-0.08 + i * 0.03, 0.66, -0.12), 8), 0.008, FRAME, torso, sides=6)

# --- the reactor block: huge, faceted, red, high on the back ----------------------------------------
L.box("reactor", (0.4, 0.3, 0.3), (0.03, 0.92, 0.08), RED, torso, rot_deg=(-14, 8, -6), bevel_w=0.04)
L.box("reactor_top", (0.3, 0.06, 0.22), (0.03, 1.07, 0.06), RED, torso, rot_deg=(-14, 8, -6), bevel_w=0.025)
for i in range(3):
    L.box("reactor_vent%d" % i, (0.012, 0.08, 0.004), (0.12 + i * 0.03, 0.92, -0.075), GREEN, torso, rot_deg=(-14, 8, -6), bevel_w=0.0)
L.tube("reactor_handle", [(-0.1, 1.02, -0.02), (-0.1, 1.08, 0.0), (0.12, 1.08, 0.0), (0.12, 1.02, -0.02)], 0.01, FRAME, torso, sides=8)
L.torus("reactor_ring", 0.06, 0.018, (-0.14, 1.03, 0.1), GREEN, torso, normal_g=(-0.6, 0.6, 0.3))
head = L.joint("Head", (0.0, 0.86, -0.08), torso)
L.box("sensor_block", (0.1, 0.07, 0.06), (0.0, 0.85, -0.13), DARK2, head, bevel_w=0.015)
L.sphere("sensor_eye", 0.016, (0.02, 0.855, -0.165), GREEN, head)
L.joint("Eye", (0.02, 0.855, -0.17), head)

# --- shoulders: the green port on the left, heavy faceted pauldrons ------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    Sh = Vector((s * 0.22, 0.79, -0.01))
    pad = L.joint("Pad_" + side, tuple(Sh), torso)
    L.box("pauldron_" + side, (0.15, 0.13, 0.19), tuple(Sh + Vector((s * 0.03, 0.03, 0))), DARK, pad, rot_deg=(0, 0, -s * 10), bevel_w=0.03)
    if side == "l":
        L.cyl("port_housing", 0.06, 0.08, tuple(Sh + Vector((-0.02, 0.08, -0.08))), DARK2, pad, axis="z")
        L.torus("port_ring", 0.045, 0.012, tuple(Sh + Vector((-0.02, 0.08, -0.125))), GREEN, pad, normal_g=(0, 0, -1))
    L.cyl("red_cap_" + side, 0.022, 0.02, tuple(Sh + Vector((s * 0.11, 0.0, 0))), RED, pad, axis="x")
    L.slot("Slot_shoulder_" + side, tuple(Sh + Vector((s * 0.02, 0.12, 0.04))), (0, 0, -1), pad)
    L.slot("Slot_back_" + side, (s * 0.1, 0.95, 0.2), (0, 0, -1), torso)
# The ZF4 rail slung over the right shoulder.
L.box("rail", (0.06, 0.62, 0.07), (0.25, 0.86, 0.06), RAIL, torso, rot_deg=(0, 0, -28), bevel_w=0.01)
L.box("rail_rib", (0.065, 0.2, 0.02), (0.29, 0.94, 0.02), FRAME, torso, rot_deg=(0, 0, -28), bevel_w=0.004)
for i in range(3):
    L.box("rail_mark%d" % i, (0.004, 0.03, 0.006), (0.35 - i * 0.012, 1.02 - i * 0.02, 0.022), CORE, torso, rot_deg=(0, 0, -28), bevel_w=0.0)

# --- arms: heavy, faceted, red joint caps, big hands ---------------------------------------------------
ARMS = {"r": ((0.27, 0.75, -0.01), (0.33, 0.56, -0.04), (0.31, 0.38, -0.1)),
        "l": ((-0.27, 0.75, -0.01), (-0.33, 0.56, -0.03), (-0.32, 0.38, -0.08))}
for side, (Sh, El, Ha) in ARMS.items():
    s = 1 if side == "r" else -1
    Sh, El, Ha = Vector(Sh), Vector(El), Vector(Ha)
    sh = L.joint("Shoulder_" + side, tuple(Sh), torso)
    el = L.joint("Elbow_" + side, tuple(El), sh)
    ha = L.joint("Hand_" + side, tuple(Ha), el)
    L.tube("upper_" + side, [tuple(Sh), tuple(El)], 0.05, DARK2, sh, sides=8)
    L.cyl("elbow_" + side, 0.045, 0.11, tuple(El), DARK, el, axis="x")
    L.cyl("elbow_cap_" + side, 0.02, 0.02, tuple(El + Vector((s * 0.06, 0, 0))), RED, el, axis="x")
    L.tube("fore_" + side, [tuple(El), tuple(Ha + Vector((0, 0.03, 0)))], 0.058, DARK, el, sides=8)
    L.box("fore_plate_" + side, (0.035, 0.13, 0.1), tuple((El + Ha) / 2 + Vector((s * 0.05, 0, 0))), DARK2, el, bevel_w=0.01)
    L.box("hand_" + side, (0.09, 0.09, 0.1), tuple(Ha + Vector((0, -0.04, -0.01))), DARK2, ha, bevel_w=0.015)
    for k in range(4):
        L.box("finger%d_%s" % (k, side), (0.02, 0.06, 0.025), tuple(Ha + Vector(((k - 1.5) * 0.022, -0.1, -0.03))), RED if k == 0 else DARK, ha, bevel_w=0.005)
    L.slot("Slot_hand_" + side, tuple(Ha + Vector((0, -0.06, -0.02))), (0, 0, -1), ha)
    L.slot("Slot_forearm_" + side, tuple((El + Ha) / 2 + Vector((s * 0.06, 0, 0))), (0, 0, -1), el)

# --- legs: heavy, knee pads, boots, tattered waist cloth ------------------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    H = Vector((s * 0.1, 0.44, 0.0))
    K = Vector((s * 0.13, 0.26, -0.05))
    A = Vector((s * 0.13, 0.08, 0.0))
    hip = L.joint("Hip_" + side, tuple(H), pelvis)
    knee = L.joint("Knee_" + side, tuple(K), hip)
    ankle = L.joint("Ankle_" + side, tuple(A), knee)
    L.tube("thigh_" + side, [tuple(H), tuple(K)], 0.07, DARK, hip, sides=8)
    L.box("knee_pad_" + side, (0.11, 0.1, 0.06), tuple(K + Vector((0, 0.0, -0.06))), DARK2, knee, bevel_w=0.02)
    L.cyl("knee_cap_" + side, 0.02, 0.02, tuple(K + Vector((s * 0.07, 0, 0))), RED, knee, axis="x")
    L.tube("shin_" + side, [tuple(K), tuple(A + Vector((0, 0.03, 0)))], 0.06, DARK2, knee, sides=8)
    L.cyl("ankle_" + side, 0.05, 0.11, tuple(A), FRAME, ankle, axis="x")
    L.box("boot_" + side, (0.13, 0.09, 0.2), tuple(A + Vector((0, -0.03, -0.04))), DARK, ankle, bevel_w=0.025)
    L.box("cloth_" + side, (0.13, 0.22, 0.01), tuple(H + Vector((0, -0.08, -0.1))), CLOTH, hip, rot_deg=(8, 0, s * 4), bevel_w=0.0)
L.box("cloth_back", (0.26, 0.24, 0.01), (0, 0.38, 0.1), CLOTH, pelvis, rot_deg=(-8, 0, 0), bevel_w=0.0)

L.export(L.out_path("assets/mechs/mf_sherman.glb"))
