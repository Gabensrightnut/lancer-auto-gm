"""HORUS Goblin, from the core book art (reference only, never shipped): a hunched, organic
teal frame. A low head with a red visor and a crest of red-tipped spikes and two long antenna
rods, bulbous shoulder pads bristling with spikes, a layered chest over an exposed inner
frame with red cabling, a hanging pelvis plate, long arms with spindly clawed hands, and
crouched digitigrade legs (knees forward, shins sweeping back) with splayed clawed feet.
Run: blender --background --factory-startup --python tools/blender/goblin.py -- assets/mechs/mf_goblin.glb
Game coordinates (x right, y up, -z forward), about 1 unit tall; see mechlib.py."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Vector  # noqa: E402

import mechlib as L  # noqa: E402

L.reset()

TEAL = L.mat("primary", (0.11, 0.3, 0.32), 0.25, 0.5)
TEAL2 = L.mat("secondary", (0.18, 0.4, 0.42), 0.25, 0.5)
INNER = L.mat("trim", (0.08, 0.06, 0.08), 0.4, 0.6)
RED = L.mat("accent", (0.5, 0.08, 0.06), 0.2, 0.5)
TIP = L.mat("glow", (0.6, 0.25, 0.05), 0.0, 0.4, emit=(1.0, 0.5, 0.15))
CABLE = L.mat("hose", (0.35, 0.08, 0.07), 0.1, 0.7)


def spike(name, base, direction, length, r, parent, mat=TEAL):
    d = Vector(direction).normalized()
    a = Vector(base)
    b = a + d * length
    L.tube(name, [tuple(a), tuple(b)], r, mat, parent, sides=8)
    L.tube(name + "_tip", [tuple(b), tuple(b + d * length * 0.18)], r * 0.8, TIP, parent, sides=8)


pelvis = L.joint("Pelvis", (0, 0.5, 0.02))
torso = L.joint("Torso", (0, 0.56, 0.0), pelvis)

# --- body: hunched, layered plates over an exposed frame ----------------------------------------
L.loft("spine_core", [dict(y=0.5, w=0.1, d=0.08, n=2), dict(y=0.62, w=0.12, d=0.1, n=2, z=-0.02), dict(y=0.74, w=0.14, d=0.12, n=2, z=-0.06)], INNER, torso, ring=20)
for k in range(4):
    L.tube("cable%d" % k, L.bezier((-0.06 + k * 0.04, 0.55, -0.05), (-0.08 + k * 0.05, 0.62, -0.1), (-0.05 + k * 0.04, 0.7, -0.12), (-0.04 + k * 0.03, 0.76, -0.1), 10), 0.009, CABLE, torso, sides=8)
L.loft("chest", [dict(y=0.64, w=0.2, d=0.15, n=2.4, z=-0.06), dict(y=0.72, w=0.28, d=0.2, n=2.5, z=-0.09), dict(y=0.8, w=0.26, d=0.2, n=2.4, z=-0.1), dict(y=0.85, w=0.16, d=0.14, n=2.2, z=-0.1)], TEAL, torso, ring=32)
L.loft("chest_plate", [dict(y=0.66, w=0.16, d=0.05, n=2.6, z=-0.17), dict(y=0.76, w=0.18, d=0.05, n=2.6, z=-0.2)], TEAL2, torso, ring=24, sub=1)
L.box("belly_plate", (0.12, 0.08, 0.04), (0, 0.58, -0.1), TEAL, torso, rot_deg=(-10, 0, 0), bevel_w=0.015)
L.box("pelvis_plate", (0.1, 0.12, 0.035), (0, 0.45, -0.07), TEAL2, pelvis, rot_deg=(8, 0, 0), bevel_w=0.012, taper=0.7)
L.loft("hips", [dict(y=0.46, w=0.16, d=0.12, n=2.2), dict(y=0.53, w=0.2, d=0.13, n=2.3)], TEAL, pelvis, ring=24)
for i in range(5):
    L.sphere("dot%d" % i, 0.008, (-0.05 + i * 0.025, 0.73, -0.2 - (i % 2) * 0.005), RED, torso)

# --- head: low, forward, red visor, crest ------------------------------------------------------
head = L.joint("Head", (0, 0.770, -0.16), torso)
L.loft("head", [dict(y=0.720, w=0.09, d=0.1, n=2.2, z=-0.17), dict(y=0.770, w=0.12, d=0.12, n=2.4, z=-0.18), dict(y=0.820, w=0.1, d=0.1, n=2.2, z=-0.16)], TEAL, head, ring=24)
L.box("visor", (0.08, 0.025, 0.02), (0, 0.765, -0.245), RED, head, bevel_w=0.008)
for s in (1, -1):
    L.sphere("eye_%d" % s, 0.012, (s * 0.022, 0.766, -0.255), TIP, head)
L.joint("Eye", (0, 0.766, -0.26), head)
L.loft("crest", [dict(y=0.820, w=0.13, d=0.08, n=2.2, z=-0.14), dict(y=0.870, w=0.1, d=0.05, n=2.2, z=-0.12)], TEAL2, head, ring=20)
for i, (dx, dy) in enumerate(((-0.04, 0.08), (-0.015, 0.1), (0.015, 0.1), (0.04, 0.08))):
    spike("crest_spike%d" % i, (dx, 0.870, -0.12), (dx * 2, dy, 0.02), 0.07, 0.008, head)
for s in (1, -1):
    spike("antenna_%d" % s, (s * 0.06, 0.860, -0.1), (s * 0.9, 0.55, 0.15), 0.3, 0.012, head)

# --- shoulders: bulbous pads with spikes ------------------------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    Sh = Vector((s * 0.17, 0.79, -0.06))
    pad = L.joint("Pad_" + side, tuple(Sh), torso)
    L.loft("pad_" + side, [dict(y=0.74, w=0.12, d=0.13, n=2.2, x=s * 0.19, z=-0.06), dict(y=0.82, w=0.15, d=0.15, n=2.3, x=s * 0.2, z=-0.06), dict(y=0.87, w=0.11, d=0.11, n=2.2, x=s * 0.19, z=-0.05)], TEAL, pad, ring=24)
    for i, (dx, dy, dz) in enumerate(((0.5, 1.0, 0.2), (0.9, 0.6, -0.1), (0.2, 1.0, 0.5))):
        spike("pad_spike%d_%s" % (i, side), (s * 0.2, 0.85, -0.04 + i * 0.02), (s * dx, dy, dz), 0.08, 0.008, pad, mat=RED if i == 1 else TEAL)
    L.slot("Slot_shoulder_" + side, (s * 0.2, 0.9, -0.02), (0, 0, -1), pad)
    L.slot("Slot_back_" + side, (s * 0.08, 0.86, 0.08), (0, 0, -1), torso)

# --- arms: long, hanging forward, spindly clawed hands --------------------------------------------
ARMS = {"r": ((0.2, 0.79, -0.06), (0.3, 0.6, -0.12), (0.32, 0.36, -0.2)),
        "l": ((-0.2, 0.79, -0.06), (-0.3, 0.6, -0.1), (-0.34, 0.38, -0.18))}
for side, (Sh, El, Ha) in ARMS.items():
    s = 1 if side == "r" else -1
    Sh, El, Ha = Vector(Sh), Vector(El), Vector(Ha)
    sh = L.joint("Shoulder_" + side, tuple(Sh), torso)
    el = L.joint("Elbow_" + side, tuple(El), sh)
    ha = L.joint("Hand_" + side, tuple(Ha), el)
    L.tube("upper_" + side, [tuple(Sh), tuple(El)], 0.035, TEAL, sh, sides=14)
    L.sphere("elbow_" + side, 0.033, tuple(El), INNER, el)
    L.tube("fore_" + side, [tuple(El), tuple(Ha)], 0.03, TEAL2, el, sides=14)
    L.box("fore_plate_" + side, (0.02, 0.12, 0.05), tuple((El + Ha) / 2 + Vector((s * 0.03, 0, 0))), TEAL, el, bevel_w=0.008)
    L.sphere("wrist_" + side, 0.026, tuple(Ha), INNER, ha)
    d = (Ha - El).normalized()
    for k in range(4):
        side_v = Vector((s * (k - 1.5) * 0.03, 0, (k - 1.5) * 0.02))
        a = Ha + side_v
        L.tube("finger%d_%s" % (k, side), L.bezier(tuple(a), tuple(a + d * 0.05), tuple(a + d * 0.1 + Vector((0, -0.01, -0.03))), tuple(a + d * 0.13 + Vector((0, -0.03, -0.05))), 8), 0.007, TEAL2, ha, sides=8)
    L.slot("Slot_hand_" + side, tuple(Ha + d * 0.04), (0, 0, -1), ha)
    L.slot("Slot_forearm_" + side, tuple((El + Ha) / 2 + Vector((s * 0.04, 0, 0))), (0, 0, -1), el)

# --- legs: crouched, digitigrade, clawed feet -----------------------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    H = Vector((s * 0.09, 0.48, 0.02))
    K = Vector((s * 0.19, 0.32, -0.1))
    A = Vector((s * 0.17, 0.12, 0.06))
    hip = L.joint("Hip_" + side, tuple(H), pelvis)
    knee = L.joint("Knee_" + side, tuple(K), hip)
    ankle = L.joint("Ankle_" + side, tuple(A), knee)
    L.tube("thigh_" + side, [tuple(H), tuple(K)], 0.045, TEAL, hip, sides=16)
    L.sphere("knee_" + side, 0.05, tuple(K), TEAL2, knee)
    L.tube("shin_" + side, [tuple(K), tuple(A)], 0.032, TEAL, knee, sides=14)
    L.tube("shin_wire_" + side, [tuple(K + Vector((s * 0.03, 0, 0.02))), tuple(A + Vector((s * 0.025, 0.02, 0)))], 0.007, CABLE, knee, sides=6)
    L.sphere("ankle_" + side, 0.03, tuple(A), INNER, ankle)
    for k, (dx, dz) in enumerate(((-0.04, -0.09), (0.0, -0.11), (0.04, -0.09))):
        L.tube("toe%d_%s" % (k, side), L.bezier(tuple(A), tuple(A + Vector((dx * 0.5, -0.06, dz * 0.4))), tuple(A + Vector((dx, -0.1, dz * 0.8))), tuple(A + Vector((dx * 1.2, -0.11, dz))), 8), 0.012, TEAL2, ankle, sides=8)
    L.tube("heel_" + side, [tuple(A), tuple(A + Vector((0, -0.1, 0.05)))], 0.01, TEAL2, ankle, sides=8)

L.export(L.out_path("assets/mechs/mf_goblin.glb"))
