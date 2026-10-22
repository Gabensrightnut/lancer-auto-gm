"""IPS-N Raleigh, from the core book art (reference only, never shipped): a rust-red frontier
gunfighter. A low head under a wide flat hat-brim, big rounded shoulder blocks with teal ports
and patches, an armored chest with a round sensor port, a teal ribbed abdomen and belt, thick
legs with knee guards, bandage wraps and heavy boots, a tattered cloak over the left shoulder,
and two rods slung across the back. Weapons come from the loadout (a pick and a revolver in
the art).
Run: blender --background --factory-startup --python tools/blender/raleigh.py -- assets/mechs/mf_raleigh.glb
Game coordinates (x right, y up, -z forward), about 1 unit tall; see mechlib.py."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Vector  # noqa: E402

import mechlib as L  # noqa: E402

L.reset()

RUST = L.mat("primary", (0.36, 0.12, 0.08), 0.3, 0.55)
RUST2 = L.mat("secondary", (0.3, 0.1, 0.07), 0.3, 0.55)
TEAL = L.mat("accent", (0.08, 0.22, 0.26), 0.4, 0.45)
FRAME = L.mat("trim", (0.04, 0.05, 0.06), 0.7, 0.45)
WRAP = L.mat("cloth", (0.55, 0.42, 0.3), 0.0, 0.9)
CLOAK = L.mat("cloak", (0.3, 0.2, 0.12), 0.0, 0.9)
GLOW = L.mat("glow", (0.5, 0.15, 0.05), 0.0, 0.4, emit=(1.0, 0.4, 0.15))

pelvis = L.joint("Pelvis", (0, 0.46, 0))
torso = L.joint("Torso", (0, 0.52, -0.01), pelvis)

# --- torso: ribbed teal abdomen, belt, armored chest leaning forward ----------------------------
L.box("belt", (0.24, 0.05, 0.16), (0, 0.47, 0), TEAL, pelvis, bevel_w=0.012)
L.box("buckle", (0.05, 0.035, 0.01), (0, 0.47, -0.083), FRAME, pelvis, bevel_w=0.004)
L.loft("abdomen", [dict(y=0.49, w=0.2, d=0.15, n=2.4), dict(y=0.6, w=0.21, d=0.16, n=2.5, z=-0.01)], TEAL, torso, ring=28)
for k in range(5):
    L.box("ab_rib%d" % k, (0.18, 0.012, 0.012), (0, 0.5 + k * 0.022, -0.085), FRAME, torso, bevel_w=0.003)
L.loft("chest", [dict(y=0.58, w=0.24, d=0.18, n=2.6, z=-0.02), dict(y=0.68, w=0.3, d=0.22, n=2.8, z=-0.05), dict(y=0.78, w=0.28, d=0.2, n=2.8, z=-0.06), dict(y=0.82, w=0.2, d=0.16, n=2.4, z=-0.05)], RUST, torso, ring=36)
L.cyl("port_rim", 0.04, 0.03, (0.02, 0.68, -0.165), TEAL, torso, axis="z")
L.cyl("port", 0.026, 0.035, (0.02, 0.68, -0.17), FRAME, torso, axis="z")
L.sphere("port_eye", 0.01, (0.02, 0.68, -0.188), GLOW, torso)
L.box("chest_plate", (0.1, 0.04, 0.012), (-0.08, 0.75, -0.16), RUST2, torso, bevel_w=0.004)
L.sphere("chest_lamp", 0.012, (0.08, 0.77, -0.155), GLOW, torso)
for i in range(3):
    L.tube("chest_hose%d" % i, L.bezier((-0.1 + i * 0.03, 0.62, -0.13), (-0.12 + i * 0.03, 0.58, -0.15), (-0.08 + i * 0.03, 0.54, -0.12), (-0.06 + i * 0.03, 0.51, -0.09), 8), 0.006, FRAME, torso, sides=6)

# --- head under a wide flat brim ---------------------------------------------------------------------
head = L.joint("Head", (0, 0.810, -0.06), torso)
L.loft("head", [dict(y=0.750, w=0.1, d=0.1, n=2.4, z=-0.06), dict(y=0.810, w=0.11, d=0.11, n=2.6, z=-0.07), dict(y=0.850, w=0.09, d=0.09, n=2.4, z=-0.07)], RUST2, head, ring=24)
L.cyl("brim", 0.17, 0.014, (0, 0.855, -0.07), RUST, head, axis="y", top_r=0.16)
L.cyl("crown", 0.07, 0.03, (0, 0.875, -0.07), RUST2, head, axis="y", top_r=0.06)
L.box("visor_slit", (0.06, 0.012, 0.01), (0, 0.810, -0.126), FRAME, head, bevel_w=0.003)
L.sphere("eye", 0.009, (0.0, 0.810, -0.13), GLOW, head)
L.joint("Eye", (0, 0.810, -0.135), head)

# --- shoulders: big rounded blocks with teal ports, patches ----------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    Sh = Vector((s * 0.2, 0.77, -0.04))
    pad = L.joint("Pad_" + side, tuple(Sh), torso)
    L.box("pauldron_" + side, (0.15, 0.13, 0.19), tuple(Sh + Vector((s * 0.04, 0.03, 0))), RUST, pad, bevel_w=0.05)
    L.cyl("pauldron_port_" + side, 0.035, 0.02, tuple(Sh + Vector((s * 0.04, 0.03, -0.098))), TEAL, pad, axis="z")
    L.cyl("pauldron_vent_" + side, 0.03, 0.05, tuple(Sh + Vector((s * 0.12, 0.03, 0.0))), FRAME, pad, axis="x")
    L.box("patch_" + side, (0.006, 0.05, 0.05), tuple(Sh + Vector((s * 0.115, 0.0, -0.05))), WRAP, pad, bevel_w=0.0)
    L.slot("Slot_shoulder_" + side, tuple(Sh + Vector((s * 0.03, 0.11, 0.02))), (0, 0, -1), pad)
    L.slot("Slot_back_" + side, (s * 0.08, 0.8, 0.12), (0, 0, -1), torso)

# --- arms: thick, plated, forearm guards ---------------------------------------------------------------
ARMS = {"r": ((0.24, 0.73, -0.04), (0.29, 0.55, -0.06), (0.27, 0.38, -0.12)),
        "l": ((-0.24, 0.73, -0.04), (-0.3, 0.55, -0.04), (-0.3, 0.38, -0.1))}
for side, (Sh, El, Ha) in ARMS.items():
    s = 1 if side == "r" else -1
    Sh, El, Ha = Vector(Sh), Vector(El), Vector(Ha)
    sh = L.joint("Shoulder_" + side, tuple(Sh), torso)
    el = L.joint("Elbow_" + side, tuple(El), sh)
    ha = L.joint("Hand_" + side, tuple(Ha), el)
    L.tube("upper_" + side, [tuple(Sh), tuple(El)], 0.045, RUST2, sh, sides=16)
    L.cyl("elbow_" + side, 0.04, 0.09, tuple(El), TEAL, el, axis="x")
    L.tube("fore_" + side, [tuple(El), tuple(Ha + Vector((0, 0.03, 0)))], 0.05, RUST, el, sides=16)
    L.box("fore_plate_" + side, (0.03, 0.12, 0.08), tuple((El + Ha) / 2 + Vector((s * 0.045, 0, -0.01))), TEAL, el, bevel_w=0.01)
    L.torus("wrap_" + side, 0.045, 0.01, tuple(Ha + Vector((0, 0.05, 0))), WRAP, el, normal_g=(0, 1, 0))
    L.box("hand_" + side, (0.07, 0.07, 0.08), tuple(Ha + Vector((0, -0.03, -0.01))), TEAL, ha, bevel_w=0.015)
    L.slot("Slot_hand_" + side, tuple(Ha + Vector((0, -0.05, -0.02))), (0, 0, -1), ha)
    L.slot("Slot_forearm_" + side, tuple((El + Ha) / 2 + Vector((s * 0.05, 0, 0))), (0, 0, -1), el)

# --- legs: thick, knee guards, bandage wraps, heavy boots -----------------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    H = Vector((s * 0.09, 0.44, 0.0))
    K = Vector((s * 0.12, 0.26, -0.04))
    A = Vector((s * 0.12, 0.08, 0.0))
    hip = L.joint("Hip_" + side, tuple(H), pelvis)
    knee = L.joint("Knee_" + side, tuple(K), hip)
    ankle = L.joint("Ankle_" + side, tuple(A), knee)
    L.tube("thigh_" + side, [tuple(H), tuple(K)], 0.06, RUST, hip, sides=16)
    L.box("thigh_plate_" + side, (0.03, 0.1, 0.07), tuple((H + K) / 2 + Vector((s * 0.06, 0, -0.02))), TEAL, hip, bevel_w=0.01)
    L.cyl("knee_guard_" + side, 0.05, 0.03, tuple(K + Vector((0, 0, -0.05))), RUST2, knee, axis="z")
    L.tube("shin_" + side, [tuple(K), tuple(A + Vector((0, 0.03, 0)))], 0.055, RUST2, knee, sides=16)
    L.box("shin_plate_" + side, (0.08, 0.12, 0.03), tuple((K + A) / 2 + Vector((0, 0.02, -0.055))), RUST, knee, bevel_w=0.01)
    for k in range(3):
        L.torus("leg_wrap%d_%s" % (k, side), 0.052, 0.008, tuple(A + (K - A) * (0.45 + k * 0.08)), WRAP, knee, normal_g=(0, 1, 0.1))
    L.cyl("ankle_" + side, 0.05, 0.1, tuple(A + Vector((0, 0.0, 0))), FRAME, ankle, axis="x")
    L.box("boot_" + side, (0.11, 0.08, 0.17), tuple(A + Vector((0, -0.025, -0.03))), RUST, ankle, bevel_w=0.025)
    L.box("toe_cap_" + side, (0.105, 0.05, 0.05), tuple(A + Vector((0, -0.055, -0.1))), TEAL, ankle, bevel_w=0.015)

# --- cloak over the left shoulder, rods across the back ---------------------------------------------------
L.loft("cloak", [dict(y=0.4, w=0.3, d=0.02, n=2.0, x=-0.1, z=0.16), dict(y=0.6, w=0.28, d=0.03, n=2.0, x=-0.13, z=0.14), dict(y=0.78, w=0.2, d=0.05, n=2.0, x=-0.16, z=0.08)], CLOAK, torso, ring=20, caps=False)
L.tube("rod_a", [(-0.14, 0.62, 0.13), (0.06, 1.0, 0.12)], 0.009, TEAL, torso, sides=8)
L.tube("rod_b", [(-0.1, 0.6, 0.12), (0.12, 0.96, 0.13)], 0.01, WRAP, torso, sides=8)
L.torus("rod_ring", 0.02, 0.005, (0.06, 1.0, 0.12), FRAME, torso, normal_g=(1, 0, 0))

L.export(L.out_path("assets/mechs/mf_raleigh.glb"))
