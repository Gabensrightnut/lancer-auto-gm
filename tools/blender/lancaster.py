"""IPS-N Lancaster ("BESS"), from the core book art (reference only, never shipped): a tall
boxy olive cab at the front with a round hatch, a BESS name plate and lamps, a long hull with
brown cargo cabinets on the sides and a fuel tank on top at the back, a red pipe roll cage
over the cab, a rifle by the front-left, four splayed legs with armored upper plates (the
"116" sticker) and long corrugated hose shins ending in round pads.
Run: blender --background --factory-startup --python tools/blender/lancaster.py -- assets/mechs/mf_lancaster.glb
Game coordinates (x right, y up, -z forward), about 1 unit tall; see mechlib.py."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Vector  # noqa: E402

import mechlib as L  # noqa: E402

L.reset()

OLIVE = L.mat("primary", (0.13, 0.17, 0.08), 0.15, 0.7)
OLIVE2 = L.mat("secondary", (0.10, 0.13, 0.06), 0.15, 0.7)
BROWN = L.mat("cargo", (0.16, 0.09, 0.05), 0.1, 0.75)
RED = L.mat("accent", (0.55, 0.12, 0.07), 0.3, 0.5)
HOSE = L.mat("hose", (0.06, 0.055, 0.045), 0.05, 0.9)
FRAME = L.mat("trim", (0.035, 0.035, 0.035), 0.7, 0.45)
STEEL = L.mat("metal", (0.4, 0.4, 0.38), 0.85, 0.35)
WHITE = L.mat("stencil", (0.8, 0.78, 0.7), 0.0, 0.7)
GLOW = L.mat("glow", (0.3, 0.25, 0.05), 0.0, 0.4, emit=(1.0, 0.85, 0.3))

BODY_Y = 0.62       # hull underside
pelvis = L.joint("Pelvis", (0, BODY_Y, 0.05))
torso = L.joint("Torso", (0, BODY_Y + 0.1, 0.0), pelvis)

# --- hull ---------------------------------------------------------------------------------
L.box("cab", (0.44, 0.56, 0.36), (0, BODY_Y + 0.3, -0.2), OLIVE, torso, bevel_w=0.08)
L.box("cab_face", (0.38, 0.42, 0.03), (0, BODY_Y + 0.32, -0.385), OLIVE2, torso, bevel_w=0.02)
L.cyl("hatch", 0.055, 0.025, (-0.09, BODY_Y + 0.44, -0.4), STEEL, torso, axis="z")
L.cyl("hatch_rim", 0.07, 0.015, (-0.09, BODY_Y + 0.44, -0.396), FRAME, torso, axis="z")
L.box("name_plate", (0.13, 0.045, 0.012), (-0.04, BODY_Y + 0.33, -0.402), FRAME, torso, bevel_w=0.004)
L.box("name_text", (0.1, 0.022, 0.006), (-0.04, BODY_Y + 0.33, -0.409), WHITE, torso, bevel_w=0.0)
for i, (x, y) in enumerate(((0.13, 0.46), (0.13, 0.41), (-0.16, 0.22))):
    L.cyl("lamp%d" % i, 0.016, 0.012, (x, BODY_Y + y, -0.403), GLOW, torso, axis="z")
L.box("grille", (0.18, 0.06, 0.02), (0.02, BODY_Y + 0.17, -0.4), FRAME, torso, bevel_w=0.004)
for i in range(6):
    L.box("grille_bar%d" % i, (0.004, 0.05, 0.022), (-0.06 + i * 0.032, BODY_Y + 0.17, -0.402), STEEL, torso, bevel_w=0.0)
# Long rear hull, a little lower than the cab.
L.box("hull", (0.44, 0.36, 0.62), (0, BODY_Y + 0.19, 0.24), OLIVE, torso, bevel_w=0.05)
L.box("hull_top", (0.36, 0.05, 0.5), (0, BODY_Y + 0.385, 0.26), OLIVE2, torso, bevel_w=0.015)
L.box("belly", (0.34, 0.08, 0.7), (0, BODY_Y - 0.01, 0.1), FRAME, torso, bevel_w=0.02)
# Vents on the cab side.
for i in range(5):
    L.box("vent%d" % i, (0.012, 0.012, 0.12), (0.225, BODY_Y + 0.4 - i * 0.024, -0.2), FRAME, torso, bevel_w=0.0)

# Cargo cabinets on both sides (brown cases with red handles) and the fuel tank on top.
for s in (1, -1):
    for k in range(2):
        z = 0.08 + k * 0.2
        L.box("cabinet%d_%d" % (k, s), (0.06, 0.2, 0.17), (s * 0.245, BODY_Y + 0.22, z + 0.06), BROWN, torso, bevel_w=0.015)
        L.box("handle%d_%d" % (k, s), (0.012, 0.06, 0.012), (s * 0.28, BODY_Y + 0.23, z + 0.06), RED, torso, bevel_w=0.004)
L.cyl("tank", 0.075, 0.42, (0.06, BODY_Y + 0.46, 0.3), STEEL, torso, axis="z")
L.cyl("tank2", 0.06, 0.3, (-0.11, BODY_Y + 0.45, 0.32), BROWN, torso, axis="z")
for k in range(3):
    L.torus("tank_band%d" % k, 0.077, 0.008, (0.06, BODY_Y + 0.46, 0.14 + k * 0.15), FRAME, torso, normal_g=(0, 0, 1))
# Small clutter: canisters and a pouch.
L.cyl("can_a", 0.03, 0.08, (0.2, BODY_Y + 0.4, 0.46), RED, torso, axis="y")
L.box("pouch", (0.07, 0.06, 0.05), (-0.2, BODY_Y + 0.4, 0.42), BROWN, torso, bevel_w=0.012)

# --- roll cage: red pipes hugging the cab, with diagonal braces -------------------------------
CY = BODY_Y + 0.63
cage = [(-0.25, -0.42), (0.25, -0.42), (0.25, 0.0), (-0.25, 0.0)]
for i, (x, z) in enumerate(cage):
    L.tube("cage_post%d" % i, [(x, BODY_Y + 0.08, z), (x, CY, z)], 0.014, RED, torso, sides=10)
    nx, nz = cage[(i + 1) % 4]
    for k, y in enumerate((CY, BODY_Y + 0.36)):
        L.tube("cage_ring%d_%d" % (k, i), [(x, y, z), (nx, y, nz)], 0.013, RED, torso, sides=10)
    L.tube("cage_diag%d" % i, [(x, BODY_Y + 0.36, z), (nx, CY, nz)], 0.011, RED, torso, sides=10)
    L.sphere("cage_joint%d" % i, 0.022, (x, CY, z), RED, torso)
    L.sphere("cage_jointm%d" % i, 0.019, (x, BODY_Y + 0.36, z), RED, torso)
L.tube("cage_cross", [(-0.25, CY, -0.21), (0.25, CY, -0.21)], 0.012, RED, torso, sides=10)
# Pipes under the hull between the legs.
for k in range(3):
    L.tube("under_pipe%d" % k, [(-0.15 + k * 0.15, BODY_Y - 0.02, -0.25), (-0.15 + k * 0.15, BODY_Y - 0.06, 0.1), (-0.12 + k * 0.12, BODY_Y - 0.02, 0.45)], 0.014, RED if k == 1 else FRAME, torso, sides=8)
# Rail along the rear hull.
for s in (1, -1):
    L.tube("rail_%d" % s, [(s * 0.24, BODY_Y + 0.4, 0.05), (s * 0.24, BODY_Y + 0.4, 0.5)], 0.01, RED, torso, sides=8)
    for k in range(3):
        z = 0.1 + k * 0.18
        L.tube("rail_post%d_%d" % (k, s), [(s * 0.24, BODY_Y + 0.33, z), (s * 0.24, BODY_Y + 0.4, z)], 0.008, RED, torso, sides=8)

# --- legs: armored upper plates, corrugated hose shins, round pads ------------------------------
LEGS = {"fr": (1, -1), "fl": (-1, -1), "rr": (1, 1), "rl": (-1, 1)}
for side, (sx, sz) in LEGS.items():
    hip_p = Vector((sx * 0.2, BODY_Y + 0.14, -0.18 if sz < 0 else 0.42))
    knee_p = hip_p + Vector((sx * 0.2, -0.24, sz * 0.12))
    foot_p = Vector((knee_p.x + sx * 0.03, 0.03, knee_p.z + sz * 0.04))
    hip = L.joint("Hip_" + side, tuple(hip_p), pelvis)
    knee = L.joint("Knee_" + side, tuple(knee_p), hip)
    ankle = L.joint("Ankle_" + side, tuple(foot_p), knee)
    # Upper: a thick armored slab with a sticker, angled out and down.
    mid = (hip_p + knee_p) / 2
    ang = math.degrees(math.atan2(knee_p.x - hip_p.x, hip_p.y - knee_p.y))
    L.box("thigh_" + side, (0.12, 0.34, 0.2), tuple(mid + Vector((0, 0.02, 0))), OLIVE, hip, rot_deg=(0, 0, ang), bevel_w=0.025)
    L.box("thigh_plate_" + side, (0.022, 0.26, 0.15), tuple(mid + Vector((sx * 0.07, 0.03, 0))), OLIVE2, hip, rot_deg=(0, 0, ang), bevel_w=0.008)
    L.box("sticker_" + side, (0.006, 0.04, 0.035), tuple(mid + Vector((sx * 0.083, 0.08, -0.03))), WHITE, hip, rot_deg=(0, 0, ang), bevel_w=0.0)
    L.cyl("hip_joint_" + side, 0.05, 0.08, tuple(hip_p), FRAME, hip, axis="x")
    L.cyl("knee_joint_" + side, 0.05, 0.1, tuple(knee_p), FRAME, knee, axis="x")
    # Shin: a long corrugated hose that sags outward, ending in a pad.
    pts = L.bezier(tuple(knee_p), tuple(knee_p + Vector((sx * 0.14, -0.2, sz * 0.06))), tuple(foot_p + Vector((0, 0.18, 0))), tuple(foot_p + Vector((0, 0.04, 0))), 18)
    L.tube("shin_" + side, L.resample(pts, 0.008), 0.05, HOSE, knee, sides=14, ribs=0.12, rib_every=0.02)
    for k in range(2):
        L.torus("shin_band%d_%s" % (k, side), 0.05, 0.008, tuple(foot_p + Vector((0, 0.1 + k * 0.03, 0))), FRAME, knee, normal_g=(0, 1, 0))
    L.cyl("pad_" + side, 0.06, 0.04, tuple(foot_p + Vector((0, 0.02, 0))), FRAME, ankle, axis="y", top_r=0.05)

# --- the rifle by the front-left, sensors, weapon slots -----------------------------------------
L.box("rifle", (0.03, 0.035, 0.3), (-0.31, BODY_Y + 0.27, -0.42), FRAME, torso, bevel_w=0.006)
L.cyl("rifle_barrel", 0.008, 0.18, (-0.31, BODY_Y + 0.28, -0.63), STEEL, torso, axis="z")
head = L.joint("Head", (0, BODY_Y + 0.42, -0.3), torso)
L.joint("Eye", (0.16, BODY_Y + 0.35, -0.4), head)
L.slot("Slot_shoulder_r", (0.27, BODY_Y + 0.4, -0.25), (0, 0, -1), torso)
L.slot("Slot_shoulder_l", (-0.31, BODY_Y + 0.27, -0.42), (0, 0, -1), torso)
L.slot("Slot_back_r", (0.12, BODY_Y + 0.5, 0.3), (0, 0, -1), torso)
L.slot("Slot_back_l", (-0.12, BODY_Y + 0.5, 0.3), (0, 0, -1), torso)
L.slot("Slot_hand_r", (0.27, BODY_Y + 0.12, -0.4), (0, 0, -1), torso)
L.slot("Slot_hand_l", (-0.27, BODY_Y + 0.12, -0.4), (0, 0, -1), torso)

L.export(L.out_path("assets/mechs/mf_lancaster.glb"))
