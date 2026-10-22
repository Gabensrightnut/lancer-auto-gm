"""SSC Black Witch, from the core book art (reference only, never shipped): a slender,
elegant frame in dark teal with red accents. Halo ring behind an ivory slit-faced helmet,
an armored collar, a red chest disc over a ribbed red abdomen with straps, a narrow waist and
wide hips, long legs with clawed feet, red shoulder sockets trailing pale cloth streamers, a
red oval shield on the left forearm and red magnetic C-rings in both hands, and a staff
carried diagonally.
Run: blender --background --factory-startup --python tools/blender/black_witch.py -- assets/mechs/mf_black_witch.glb
Game coordinates (x right, y up, -z forward), about 1 unit tall; see mechlib.py."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Vector  # noqa: E402

import mechlib as L  # noqa: E402

L.reset()

TEAL = L.mat("primary", (0.05, 0.1, 0.12), 0.45, 0.4)
TEAL2 = L.mat("secondary", (0.08, 0.15, 0.17), 0.45, 0.4)
RED = L.mat("accent", (0.42, 0.07, 0.05), 0.3, 0.45)
IVORY = L.mat("face", (0.75, 0.72, 0.64), 0.2, 0.3)
FRAME = L.mat("trim", (0.03, 0.035, 0.04), 0.7, 0.45)
CLOTH = L.mat("cloth", (0.62, 0.66, 0.64), 0.0, 0.9)
GLOW = L.mat("glow", (0.5, 0.2, 0.05), 0.0, 0.4, emit=(1.0, 0.55, 0.2))


def limb(name, a, b, r0, r1, material, parent, sides=18):
    """A smooth tapered limb segment from a to b."""
    pts = [tuple(Vector(a).lerp(Vector(b), t / 6)) for t in range(7)]
    radii = [r0 + (r1 - r0) * t / 6 for t in range(7)]
    o = L.tube(name, pts, r0, material, parent, sides=sides)
    # Taper by scaling rings: mechlib tubes are constant radius, so add an end cap ring.
    L.sphere(name + "_cap", r1, tuple(b), material, parent)
    return o


pelvis = L.joint("Pelvis", (0, 0.52, 0))
torso = L.joint("Torso", (0, 0.58, 0), pelvis)

# --- torso: wide hips, narrow ribbed waist, armored chest -------------------------------------
L.loft("hips", [dict(y=0.45, w=0.12, d=0.09, n=2.2), dict(y=0.5, w=0.19, d=0.12, n=2.3), dict(y=0.555, w=0.15, d=0.1, n=2.2)], TEAL, pelvis, ring=32)
L.loft("abdomen", [dict(y=0.54, w=0.12, d=0.085, n=2.1), dict(y=0.62, w=0.085, d=0.07, n=2.1), dict(y=0.71, w=0.11, d=0.085, n=2.1)], RED, torso, ring=28)
for k in range(5):
    L.torus("rib%d" % k, 0.046 + abs(k - 2) * 0.004, 0.005, (0, 0.57 + k * 0.028, -0.002), RED, torso, normal_g=(0, 1, 0))
for s in (1, -1):
    L.tube("strap_%d" % s, [(s * 0.04, 0.56, -0.05), (s * 0.05, 0.7, -0.055)], 0.006, FRAME, torso, sides=6)
chest = L.loft("chest", [dict(y=0.7, w=0.13, d=0.1, n=2.6), dict(y=0.76, w=0.19, d=0.13, n=3.0, z=-0.005), dict(y=0.83, w=0.2, d=0.13, n=3.0), dict(y=0.86, w=0.12, d=0.1, n=2.4)], TEAL, torso, ring=36)
L.cyl("chest_disc", 0.04, 0.02, (0, 0.77, -0.07), RED, torso, axis="z")
for i in range(4):
    a = i * math.tau / 4 + 0.4
    L.sphere("disc_dot%d" % i, 0.006, (math.cos(a) * 0.02, 0.77 + math.sin(a) * 0.02, -0.082), GLOW, torso)
# Collar and red-rimmed sensor eyes.
L.torus("collar", 0.07, 0.022, (0, 0.85, 0.0), TEAL2, torso, normal_g=(0, 1, 0))
for s in (1, -1):
    L.torus("collar_eye_%d" % s, 0.018, 0.006, (s * 0.06, 0.835, -0.06), RED, torso, normal_g=(0, 0, -1))

# --- head: ivory slit face, red cheeks, halo ------------------------------------------------------
head = L.joint("Head", (0, 0.88, -0.005), torso)
L.loft("helmet", [dict(y=0.865, w=0.07, d=0.08, n=2.2), dict(y=0.91, w=0.085, d=0.1, n=2.4), dict(y=0.96, w=0.075, d=0.095, n=2.4), dict(y=0.985, w=0.05, d=0.07, n=2.2)], IVORY, head, ring=28)
L.box("face_slit", (0.05, 0.006, 0.01), (0, 0.93, -0.05), FRAME, head, bevel_w=0.002)
for s in (1, -1):
    L.box("cheek_%d" % s, (0.012, 0.03, 0.03), (s * 0.035, 0.895, -0.035), RED, head, bevel_w=0.004)
L.joint("Eye", (0, 0.93, -0.06), head)
L.torus("halo", 0.11, 0.016, (0, 0.985, 0.05), TEAL2, head, normal_g=(0, 0, 1))
for i in range(6):
    a = i * math.tau / 6
    L.sphere("halo_stud%d" % i, 0.008, (math.cos(a) * 0.11, 0.985 + math.sin(a) * 0.11, 0.035), RED, head)
for s in (1, -1):
    L.tube("antenna_%d" % s, L.bezier((s * 0.13, 0.86, 0.02), (s * 0.15, 0.93, 0.02), (s * 0.13, 0.95, 0.0), (s * 0.11, 0.93, -0.01), 10), 0.006, FRAME, torso, sides=6)

# --- legs: long, slim, clawed feet ----------------------------------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    H = Vector((s * 0.065, 0.5, 0.0))
    K = Vector((s * 0.075, 0.27, -0.04))
    A = Vector((s * 0.075, 0.06, 0.03))
    hip = L.joint("Hip_" + side, tuple(H), pelvis)
    knee = L.joint("Knee_" + side, tuple(K), hip)
    ankle = L.joint("Ankle_" + side, tuple(A), knee)
    L.loft("thigh_" + side, [dict(y=0.29, w=0.055, d=0.06, n=2.2, x=s * 0.074), dict(y=0.4, w=0.08, d=0.08, n=2.3, x=s * 0.07), dict(y=0.49, w=0.085, d=0.085, n=2.2, x=s * 0.066)], TEAL, hip, ring=24)
    L.box("thigh_plate_" + side, (0.02, 0.12, 0.06), tuple(H + Vector((s * 0.045, -0.11, -0.03))), TEAL2, hip, rot_deg=(0, 0, s * 6), bevel_w=0.01)
    L.sphere("knee_" + side, 0.032, tuple(K), TEAL2, knee)
    L.cyl("knee_dot_" + side, 0.01, 0.006, tuple(K + Vector((0, 0, -0.04))), GLOW, knee, axis="z")
    L.loft("shin_" + side, [dict(y=0.07, w=0.035, d=0.04, n=2.2, x=s * 0.075, z=0.03), dict(y=0.18, w=0.05, d=0.055, n=2.3, x=s * 0.075, z=-0.01), dict(y=0.26, w=0.05, d=0.05, n=2.2, x=s * 0.075, z=-0.04)], TEAL, knee, ring=24)
    L.sphere("ankle_" + side, 0.026, tuple(A), FRAME, ankle)
    for k, dx in enumerate((-0.025, 0.0, 0.025)):
        L.tube("claw%d_%s" % (k, side), L.bezier(tuple(A + Vector((dx, -0.02, -0.01))), tuple(A + Vector((dx * 1.3, -0.05, -0.06))), tuple(A + Vector((dx * 1.5, -0.065, -0.1))), tuple(A + Vector((dx * 1.6, -0.065, -0.12))), 8), 0.009, TEAL2, ankle, sides=8)
    L.tube("heel_claw_" + side, [tuple(A + Vector((0, -0.03, 0.01))), tuple(A + Vector((0, -0.065, 0.05)))], 0.008, TEAL2, ankle, sides=8)

# --- arms: red shoulder sockets with cloth streamers, slim limbs, shield and rings ---------------
ARMS = {"r": ((0.14, 0.81, 0.0), (0.2, 0.64, -0.03), (0.23, 0.48, -0.08)),
        "l": ((-0.14, 0.81, 0.0), (-0.21, 0.64, -0.02), (-0.23, 0.5, -0.1))}
for side, (Sh, El, Ha) in ARMS.items():
    s = 1 if side == "r" else -1
    Sh, El, Ha = Vector(Sh), Vector(El), Vector(Ha)
    pad = L.joint("Pad_" + side, tuple(Sh), torso)
    L.sphere("shoulder_" + side, 0.05, tuple(Sh + Vector((s * 0.01, 0.01, 0))), TEAL2, pad)
    L.torus("socket_" + side, 0.03, 0.011, tuple(Sh + Vector((s * 0.05, 0.0, -0.03))), RED, pad, normal_g=(s, 0, -0.6))
    # Cloth streamer from the shoulder to below the knee.
    L.box("cloth_" + side, (0.005, 0.68, 0.11), tuple(Sh + Vector((s * 0.05, -0.36, -0.04))), CLOTH, pad, rot_deg=(3, 0, s * 3), bevel_w=0.0)
    L.slot("Slot_shoulder_" + side, tuple(Sh + Vector((s * 0.02, 0.06, 0.02))), (0, 0, -1), pad)
    L.slot("Slot_back_" + side, (s * 0.06, 0.82, 0.08), (0, 0, -1), torso)
    sh = L.joint("Shoulder_" + side, tuple(Sh), torso)
    el = L.joint("Elbow_" + side, tuple(El), sh)
    ha = L.joint("Hand_" + side, tuple(Ha), el)
    L.tube("upper_" + side, [tuple(Sh + (El - Sh) * 0.15), tuple(El)], 0.022, TEAL, sh, sides=16)
    L.sphere("elbow_" + side, 0.024, tuple(El), FRAME, el)
    L.tube("fore_" + side, [tuple(El), tuple(Ha - (Ha - El).normalized() * 0.03)], 0.026, TEAL, el, sides=16)
    L.box("hand_" + side, (0.04, 0.05, 0.05), tuple(Ha + (Ha - El).normalized() * 0.01), TEAL2, ha, bevel_w=0.01)
    # A red magnetic C-ring held in each hand.
    L.torus("ring_" + side, 0.11, 0.009, tuple(Ha + Vector((s * 0.02, -0.07, -0.04))), RED, ha, normal_g=(1, 0, 0.2))
    L.slot("Slot_hand_" + side, tuple(Ha + (Ha - El).normalized() * 0.04), (0, 0, -1), ha)
    L.slot("Slot_forearm_" + side, tuple((El + Ha) / 2 + Vector((s * 0.04, 0, 0))), (0, 0, -1), el)
    if side == "l":
        # Red oval shield on the outer left forearm with mag studs.
        L.cyl("shield", 0.075, 0.014, tuple((El + Ha) / 2 + Vector((-0.05, 0, -0.01))), RED, el, axis="x")
        for i in range(4):
            a = i * math.tau / 4
            L.sphere("shield_stud%d" % i, 0.008, tuple((El + Ha) / 2 + Vector((-0.06, math.sin(a) * 0.035, math.cos(a) * 0.035))), GLOW, el)

# The staff carried diagonally across the back.
L.tube("staff", [(-0.2, 1.02, 0.12), (0.22, 0.42, 0.04)], 0.01, FRAME, torso, sides=8)
L.sphere("staff_tip", 0.018, (-0.2, 1.02, 0.12), FRAME, torso)

L.export(L.out_path("assets/mechs/mf_black_witch.glb"))
