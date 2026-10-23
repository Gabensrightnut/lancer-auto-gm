"""IPS-N Blackbeard, modeled from the core book art (p129). Reference viewed locally only.
Run: blender --background --factory-startup --python tools/blender/blackbeard.py -- assets/mechs/mf_blackbeard.glb
Game coordinates (x right, y up, -z forward), about 1 unit tall; see mechlib.py."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Matrix, Vector  # noqa: E402

import bpy  # noqa: E402
import mechlib as L  # noqa: E402

L.reset()

TAN = L.mat("primary", (0.33, 0.28, 0.18), 0.15, 0.72)
TAN2 = L.mat("secondary", (0.5, 0.44, 0.31), 0.15, 0.66)
SLATE = L.mat("trim", (0.13, 0.17, 0.18), 0.55, 0.5)
DARK = L.mat("dark", (0.04, 0.045, 0.05), 0.7, 0.45)
STEEL = L.mat("metal", (0.4, 0.42, 0.42), 0.9, 0.35)
HOSE = L.mat("hose", (0.3, 0.08, 0.05), 0.05, 0.75)
ROPE = L.mat("rope", (0.33, 0.1, 0.06), 0.0, 0.9)
RED = L.mat("accent", (0.55, 0.06, 0.03), 0.15, 0.55)
GLOW = L.mat("glow", (0.6, 0.18, 0.04), 0.0, 0.5, emit=(1.0, 0.35, 0.08))
ORANGE = L.mat("sensor", (0.85, 0.3, 0.08), 0.1, 0.45)


def between(name, a, b, w, d, material, parent, bevel_w=0.008, taper=1.0, offset=(0, 0, 0)):
    """Box spanning game points a->b (its y axis along the segment)."""
    a, b = Vector(a), Vector(b)
    y = (b - a).normalized()
    hint = Vector((0, 0, -1)) if abs(y.z) < 0.9 else Vector((1, 0, 0))
    x = y.cross(hint).normalized()
    z = x.cross(y)
    rot = Matrix((x, y, z)).transposed()
    o = L.box(name, (w, (b - a).length, d), (0, 0, 0), material, None, bevel_w=bevel_w, taper=taper)
    o.matrix_world = Matrix.Translation(L.V((a + b) / 2 + rot @ Vector(offset))) @ (L.C @ rot @ L.C.inverted()).to_4x4()
    if parent is not None:
        import bpy
        bpy.context.view_layer.update()
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o, rot


def holes(target, rot, center, cols, rows, dx, dy, radius, normal_local):
    """Drill a grid of round holes into a part through the face along normal_local."""
    for i in range(cols):
        for j in range(rows):
            off = Vector(((i - (cols - 1) / 2) * dx, (j - (rows - 1) / 2) * dy, 0))
            p = Vector(center) + rot @ (off + Vector(normal_local) * 0.0)
            n = rot @ Vector(normal_local)
            c = L.cyl("hole", radius, 0.04, tuple(p), None, axis="y", bevel_w=0)
            # Orient the drill along n.
            yv = n.normalized()
            hint = Vector((1, 0, 0)) if abs(yv.x) < 0.9 else Vector((0, 0, 1))
            xv = hint.cross(yv).normalized()
            zv = xv.cross(yv)
            r = Matrix((xv, yv, zv)).transposed()
            c.matrix_world = Matrix.Translation(L.V(p)) @ (L.C @ r @ L.C.inverted()).to_4x4()
            L.cut(target, c)


# --- rig ---------------------------------------------------------------------------------
HIP_Y = 0.52
pelvis = L.joint("Pelvis", (0, HIP_Y, 0))
torso = L.joint("Torso", (0, HIP_Y + 0.05, 0), pelvis)

# --- pelvis ------------------------------------------------------------------------------
L.box("pelvis_block", (0.22, 0.06, 0.12), (0, HIP_Y, 0), SLATE, pelvis, bevel_w=0.012)
L.box("codpiece", (0.1, 0.07, 0.05), (0, HIP_Y - 0.02, -0.06), TAN, pelvis, rot_deg=(-10, 0, 0), bevel_w=0.012, taper=1.15)
L.cyl("pelvis_axle", 0.012, 0.24, (0, HIP_Y - 0.035, -0.015), DARK, pelvis, axis="x")

# --- legs --------------------------------------------------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    H = Vector((s * 0.1, HIP_Y - 0.01, 0.0))
    K = Vector((s * 0.128, 0.315, -0.035))
    A = Vector((s * 0.1, 0.085, 0.0))
    hip = L.joint("Hip_" + side, tuple(H), pelvis)
    knee = L.joint("Knee_" + side, tuple(K), hip)
    ankle = L.joint("Ankle_" + side, tuple(A), knee)
    # Hip wheel.
    L.cyl("hip_wheel_" + side, 0.042, 0.06, tuple(H + Vector((s * 0.01, 0, 0))), DARK, hip, axis="x")
    L.cyl("hip_hub_" + side, 0.024, 0.066, tuple(H + Vector((s * 0.012, 0, 0))), TAN2, hip, axis="x")
    # Thigh: dark strut, tan outer plate with a drilled panel, rope wraps.
    strut, rot = between("thigh_strut_" + side, H, K, 0.048, 0.058, SLATE, hip)
    plate, rot = between("thigh_plate_" + side, H + Vector((s * 0.03, -0.02, 0)), K + Vector((s * 0.03, 0.05, 0)), 0.05, 0.1, TAN, hip, bevel_w=0.012)
    holes(plate, rot, (H + K) / 2 + Vector((s * 0.056, 0.01, 0)), 2, 3, 0.04, 0.035, 0.0065, (s, 0, 0))
    L.groove(plate, H + Vector((s * 0.056, -0.04, -0.045)), K + Vector((s * 0.056, 0.07, -0.045)), normal_g=(s, 0, 0))
    between("thigh_front_" + side, H + Vector((-s * 0.01, -0.03, -0.035)), H + Vector((-s * 0.01, -0.09, -0.035)), 0.05, 0.04, TAN, hip, bevel_w=0.01)
    L.cyl("thigh_piston_" + side, 0.011, 0.17, tuple((H + K) / 2 + Vector((-s * 0.03, 0, 0.022))), STEEL, hip)
    for k, y in enumerate((0.36, 0.385)):
        L.torus("thigh_rope%d_%s" % (k, side), 0.05, 0.0095, (H.x + s * 0.012, y, -0.02), ROPE, hip, normal_g=(0.1 * k, 1, 0.15))
    # Knee: big side wheels, cap.
    for k in (1, -1):
        L.cyl("knee_wheel_%s%d" % (side, k), 0.044, 0.02, tuple(K + Vector((k * 0.04, 0, 0))), DARK, knee, axis="x")
        L.cyl("knee_hub_%s%d" % (side, k), 0.021, 0.024, tuple(K + Vector((k * 0.042, 0, 0))), TAN2, knee, axis="x")
    L.box("knee_cap_" + side, (0.075, 0.06, 0.04), tuple(K + Vector((0, -0.005, -0.045))), TAN2, knee, rot_deg=(-12, 0, 0), bevel_w=0.012)
    # Shin: long tan front plate, perforated; dark frame and piston behind.
    shin_frame, rot = between("shin_frame_" + side, K, A, 0.045, 0.05, SLATE, knee, offset=(0, 0, -0.02))
    shin, rot = between("shin_plate_" + side, K + Vector((0, -0.03, 0)), A + Vector((0, 0.02, 0)), 0.072, 0.06, TAN, knee, bevel_w=0.012, taper=0.85, offset=(0, 0, 0.022))
    holes(shin, rot, (K + A) / 2 + rot @ Vector((0, 0, 0.052)), 2, 5, 0.03, 0.034, 0.0062, (0, 0, 1))
    L.cyl("shin_piston_" + side, 0.01, 0.2, tuple((K + A) / 2 + Vector((s * 0.026, 0, 0.04))), STEEL, knee)
    L.torus("shin_rope_" + side, 0.045, 0.008, tuple(K + Vector((0, -0.04, -0.005))), ROPE, knee)
    # Ankle and claw foot.
    L.cyl("ankle_" + side, 0.03, 0.062, tuple(A), DARK, ankle, axis="x")
    L.loft("foot_" + side, [dict(y=0.0, w=0.1, d=0.13, n=3.2, x=A.x, z=A.z - 0.025), dict(y=0.045, w=0.095, d=0.11, n=3.2, x=A.x, z=A.z - 0.02), dict(y=0.075, w=0.07, d=0.08, n=3.0, x=A.x, z=A.z)], TAN, ankle, ring=20, sub=1)
    for k in range(3):
        base = Vector((A.x + (k - 1) * 0.034, 0.035, A.z - 0.075))
        mid = base + Vector(((k - 1) * 0.014, 0.0, -0.06))  # splayed, longer toes
        tip = mid + Vector(((k - 1) * 0.01, -0.032, -0.045))
        between("toe%d_%s" % (k, side), base, mid, 0.03, 0.03, TAN, ankle, bevel_w=0.008, taper=0.85)
        between("claw%d_%s" % (k, side), mid, tip, 0.026, 0.024, SLATE, ankle, bevel_w=0.006, taper=0.4)
        L.cyl("toe_joint%d_%s" % (k, side), 0.016, 0.034, tuple(base), DARK, ankle, axis="x")
        L.cyl("toe_knuckle%d_%s" % (k, side), 0.014, 0.032, tuple(mid), DARK, ankle, axis="x")
    between("heel_" + side, Vector((A.x, 0.03, A.z + 0.04)), Vector((A.x, 0.005, A.z + 0.09)), 0.022, 0.02, SLATE, ankle, bevel_w=0.005, taper=0.5)

# --- torso -------------------------------------------------------------------------------
T0 = HIP_Y + 0.05  # torso joint height; torso parts use world positions
for i in range(3):
    L.torus("waist_ring%d" % i, 0.052 - i * 0.003, 0.012, (0, T0 - 0.01 + i * 0.019, 0), DARK, torso)
lower = L.loft("hull_lower", [dict(y=T0 + 0.02, w=0.1, d=0.09, n=2.6), dict(y=T0 + 0.07, w=0.15, d=0.14, n=2.8), dict(y=T0 + 0.14, w=0.2, d=0.19, n=3.0), dict(y=T0 + 0.21, w=0.235, d=0.21, n=3.2)], SLATE, torso, ring=32)
upper = L.loft("hull_upper", [dict(y=T0 + 0.15, w=0.21, d=0.2, n=2.6, z=-0.01), dict(y=T0 + 0.22, w=0.25, d=0.245, n=2.6, z=-0.025), dict(y=T0 + 0.3, w=0.26, d=0.255, n=2.6, z=-0.03), dict(y=T0 + 0.355, w=0.235, d=0.23, n=2.5, z=-0.025), dict(y=T0 + 0.39, w=0.15, d=0.15, n=2.3, z=-0.015)], TAN, torso, ring=32)
for s in (1, -1):
    L.loft("hull_side_%d" % s, [dict(y=T0 + 0.05, w=0.05, d=0.12, n=3.0, x=s * 0.1), dict(y=T0 + 0.17, w=0.05, d=0.13, n=3.0, x=s * 0.11)], TAN, torso, ring=16, sub=1)
# Ribbed belly bands.
for i in range(5):
    y = T0 + 0.065 + i * 0.03
    L.loft("belly_rib%d" % i, [dict(y=y - 0.009, w=0.12 + i * 0.028, d=0.02, n=4.0, z=-0.055 - i * 0.012), dict(y=y + 0.009, w=0.12 + i * 0.028, d=0.02, n=4.0, z=-0.06 - i * 0.012)], SLATE, torso, ring=16, sub=1)
# Front: centre plate with a slot and a tag, grilles with glowing slats, side lamps.
centre = L.box("chest_plate", (0.09, 0.14, 0.03), (0, T0 + 0.23, -0.142), SLATE, torso, rot_deg=(-6, 0, 0), bevel_w=0.008)
L.groove(centre, (-0.03, T0 + 0.19, -0.164), (0.03, T0 + 0.19, -0.164))
L.groove(centre, (-0.03, T0 + 0.21, -0.162), (0.03, T0 + 0.21, -0.162))
L.box("chest_tag", (0.045, 0.035, 0.01), (0, T0 + 0.255, -0.159), TAN2, torso, rot_deg=(-6, 0, 0), bevel_w=0.003)
for s in (1, -1):
    g = L.box("grille_%d" % s, (0.07, 0.036, 0.02), (s * 0.08, T0 + 0.22, -0.14), DARK, torso, rot_deg=(-6, s * 18, 0), bevel_w=0.004)
    for k in range(3):
        L.box("grille_slat%d_%d" % (k, s), (0.055, 0.004, 0.006), (s * 0.08, T0 + 0.21 + k * 0.01, -0.15), GLOW, torso, rot_deg=(-6, s * 18, 0), bevel_w=0)
    L.sphere("side_lamp_%d" % s, 0.016, (s * 0.12, T0 + 0.11, -0.08), GLOW, torso, scale=(1, 0.75, 0.8))
    L.box("chest_patch_%d" % s, (0.05, 0.03, 0.012), (s * 0.1, T0 + 0.29, -0.135), TAN2, torso, rot_deg=(-8, s * 22, 0), bevel_w=0.003)
L.cyl("chest_canister", 0.02, 0.045, (0, T0 + 0.05, -0.055), RED, torso, axis="x")
for k in range(4):
    L.groove(upper, (-0.11, T0 + 0.16 + k * 0.06, -0.15), (0.11, T0 + 0.16 + k * 0.06, -0.15), normal_g=(0, 0, -1))

# --- head: orange sensor wedge in a nest of coiled rope ---------------------------------
head = L.joint("Head", (0, T0 + 0.39, -0.04), torso)
L.box("sensor_wedge", (0.13, 0.085, 0.1), (0, T0 + 0.425, -0.05), ORANGE, head, rot_deg=(-18, 0, 0), bevel_w=0.012, taper=0.32)
L.cyl("sensor_collar", 0.08, 0.03, (0, T0 + 0.39, -0.03), DARK, head)
L.sphere("sensor_lens", 0.012, (0, T0 + 0.43, -0.098), GLOW, head)
L.joint("Eye", (0, T0 + 0.43, -0.1), head)
# One continuous cable coiled around the cockpit (the art's red coil), rising as it winds.
coil = []
for k in range(5 * 36 + 1):
    t = math.tau * k / 36
    r = 0.092 + 0.014 * (k / 36)
    coil.append((math.cos(t) * r * 1.05, T0 + 0.33 + 0.013 * (k / 36) + 0.005 * math.sin(t * 2), math.sin(t) * r * 0.92 - 0.02))
L.curve_tube("rope_coil", coil, 0.019, ROPE, torso)
# Cords hanging from the coil down the chest and over the right shoulder box, sagging.
for i in range(11):
    x = -0.15 + i * 0.03
    top = Vector((x * 0.9, T0 + 0.35, -0.09 + abs(x) * 0.25))
    drop = 0.08 + 0.04 * ((i * 7) % 4)
    L.curve_tube("rope_end%d" % i, [tuple(top), tuple(top + Vector((x * 0.1, -0.035, -0.04))), tuple(top + Vector((x * 0.25, -drop * 0.6, -0.045))),
                                   tuple(top + Vector((x * 0.3, -drop, -0.02)))], 0.0075, ROPE, torso, bevel_res=2)
for i in range(3):
    top = Vector((0.2 + i * 0.03, T0 + 0.33, -0.06))
    L.curve_tube("box_cord%d" % i, [tuple(top), tuple(top + Vector((0.01, -0.06, -0.02))), tuple(top + Vector((0.015, -0.13 - i * 0.03, -0.01)))], 0.006, ROPE, torso, bevel_res=2)

# --- shoulder boxes ----------------------------------------------------------------------
def shoulder_box(s, side):
    c = Vector((s * 0.205, T0 + 0.27, 0.05))  # the blockout sets the boxes ~2 cm further out
    pad = L.joint("Pad_" + side, tuple(c), torso)
    tilt = (-18, s * -28, s * -6)
    R = L._rot_g(tilt)
    P = lambda v: tuple(c + R @ Vector(v))  # noqa: E731
    body = L.box("box_" + side, (0.165, 0.24, 0.2), P((0, 0, 0)), TAN, pad, rot_deg=tilt, bevel_w=0.022, seg=4)
    L.groove(body, P((-0.08, 0.04, -0.101)), P((0.08, 0.04, -0.101)), normal_g=tuple(R @ Vector((0, 0, -1))))
    L.groove(body, P((s * 0.083, 0.11, -0.09)), P((s * 0.083, -0.11, -0.09)), normal_g=tuple(R @ Vector((s, 0, 0))))
    L.box("box_skirt_" + side, (0.17, 0.03, 0.19), P((0, -0.13, 0)), SLATE, pad, rot_deg=tilt, bevel_w=0.006)
    L.box("box_panel_" + side, (0.15, 0.09, 0.02), P((-s * 0.008, -0.075, -0.103)), SLATE, pad, rot_deg=tilt, bevel_w=0.006)
    for k in range(4):
        d = P((s * (-0.045 + 0.03 * (k % 2)), -0.05 - 0.036 * (k // 2), -0.115))
        L.cyl("dial%d_%s" % (k, side), 0.011, 0.01, d, TAN2, pad, rot_deg=(tilt[0] + 90, tilt[1], tilt[2]), bevel_w=0.002)
        L.cyl("dial_c%d_%s" % (k, side), 0.0045, 0.014, d, DARK, pad, rot_deg=(tilt[0] + 90, tilt[1], tilt[2]), bevel_w=0)
    holes(body, R, P((s * 0.04, -0.095, -0.1)), 4, 2, 0.015, 0.016, 0.005, (0, 0, -1))
    # Fan vent on the top-front edge: rim, glowing well, dark radial fins, a spike hub.
    vc = Vector((0, 0.1, -0.06))
    vR = R @ L._rot_g((-38, 0, 0))
    V2 = lambda v: tuple(c + R @ vc + vR @ Vector(v))  # noqa: E731
    rim = L.torus("vent_rim_" + side, 0.068, 0.012, V2((0, 0.012, 0)), TAN2, pad, normal_g=tuple(vR @ Vector((0, 1, 0))))
    L.cyl("vent_shroud_" + side, 0.072, 0.045, V2((0, -0.012, 0)), DARK, pad, rot_deg=(tilt[0] - 38, tilt[1], tilt[2]), bevel_w=0.003)
    L.cyl("vent_well_" + side, 0.064, 0.012, V2((0, 0.0, 0)), GLOW, pad, rot_deg=(tilt[0] - 38, tilt[1], tilt[2]), bevel_w=0)
    for k in range(14):
        a = math.tau * k / 14
        L.box("vent_fin%d_%s" % (k, side), (0.007, 0.012, 0.055), V2((math.sin(a) * 0.032, 0.01, math.cos(a) * 0.032)), DARK, pad,
              rot_deg=(tilt[0] - 38 + 22, tilt[1] + math.degrees(a) + 12, tilt[2]), bevel_w=0)  # pitched blades
    L.cyl("vent_hub_" + side, 0.016, 0.014, V2((0, 0.014, 0)), DARK, pad, rot_deg=(tilt[0] - 38, tilt[1], tilt[2]))
    L.cyl("vent_spike_" + side, 0.011, 0.05, V2((0, 0.045, 0)), DARK, pad, rot_deg=(tilt[0] - 38, tilt[1], tilt[2]), top_r=0.0, bevel_w=0)
    # Coil drum on the outer face.
    dc = P((s * 0.105, 0.0, 0.0))
    L.cyl("drum_" + side, 0.042, 0.065, dc, GLOW, pad, axis="x", bevel_w=0.003)
    for k in range(5):
        L.cyl("drum_rib%d_%s" % (k, side), 0.046, 0.007, tuple(Vector(dc) + Vector((s * (-0.03 + k * 0.015), 0, 0))), SLATE, pad, axis="x", bevel_w=0.002)
    L.cyl("drum_cap_" + side, 0.03, 0.012, tuple(Vector(dc) + Vector((s * 0.038, 0, 0))), DARK, pad, axis="x")
    L.box("box_clip_" + side, (0.05, 0.05, 0.05), P((s * 0.06, 0.125, 0.06)), TAN2, pad, rot_deg=tilt, bevel_w=0.01)
    L.slot("Slot_shoulder_" + side, P((0, 0.14, 0.06)), (0, 0, -1), pad)
    L.slot("Slot_back_" + side, (s * 0.1, T0 + 0.33, 0.14), (0, 0, -1), torso)
    return pad


shoulder_box(1, "r")
shoulder_box(-1, "l")
L.cyl("shoulder_rod", 0.007, 0.66, (-0.06, T0 + 0.16, -0.09), STEEL, torso, axis="x", bevel_w=0)

# --- arms (right hangs with the axe, left raised holding the pike) ------------------------
ARMS = {
    "r": ((0.23, T0 + 0.14, -0.02), (0.28, T0 - 0.04, -0.05), (0.26, T0 - 0.26, -0.04), (0.35, -1, 0.05)),
    "l": ((-0.23, T0 + 0.16, -0.02), (-0.38, T0 + 0.15, -0.07), (-0.35, T0 + 0.31, -0.09), (-0.12, 1, 0)),
}
for side, (Sh, El, Ha, wdir) in ARMS.items():
    Sh, El, Ha = Vector(Sh), Vector(El), Vector(Ha)
    sh = L.joint("Shoulder_" + side, tuple(Sh), torso)
    el = L.joint("Elbow_" + side, tuple(El), sh)
    ha = L.joint("Hand_" + side, tuple(Ha), el)
    L.sphere("shoulder_ball_" + side, 0.03, tuple(Sh), DARK, sh)
    between("upper_strut_" + side, Sh, El, 0.026, 0.026, SLATE, sh, bevel_w=0.005)
    between("upper_rod_" + side, Sh, El, 0.016, 0.016, DARK, sh, bevel_w=0, offset=(0.02, 0, 0.012))
    between("upper_cuff_" + side, Sh + (El - Sh) * 0.05, Sh + (El - Sh) * 0.4, 0.046, 0.046, TAN2, sh, bevel_w=0.01)
    d = (Ha - El).normalized()
    side_ax = d.cross(Vector((0, 0, -1))).normalized()
    L.cyl("elbow_wheel_" + side, 0.036, 0.04, tuple(El), DARK, el, axis="x")
    L.cyl("elbow_hub_" + side, 0.022, 0.046, tuple(El), TAN2, el, axis="x")
    between("fore_strut_" + side, El, Ha, 0.024, 0.024, SLATE, el, bevel_w=0.005)
    between("fore_shell_" + side, El + (Ha - El) * 0.15, Ha - (Ha - El) * 0.05, 0.056, 0.06, TAN, el, bevel_w=0.012, taper=1.25)
    # Red hand: a back plate and four two-segment fingers curled round the haft (which runs
    # through the grip along wdir), a thumb closing from the other side.
    hand = L.box("hand_" + side, (0.05, 0.06, 0.05), tuple(Ha + d * 0.02), RED, ha, bevel_w=0.012)
    axis = Vector(wdir).normalized()
    grip = Ha + d * 0.05
    u = axis.cross(Vector((0, 0, -1)))
    if u.length < 0.1:
        u = axis.cross(Vector((1, 0, 0)))
    u.normalize()
    w = axis.cross(u).normalized()
    ring = lambda c, a, r: c + (u * math.cos(a) + w * math.sin(a)) * r  # noqa: E731
    for k in range(4):
        c = grip + axis * ((k - 1.5) * 0.016)
        a0, a1, a2 = math.radians(20), math.radians(110), math.radians(200)
        between("finger%d_a_%s" % (k, side), ring(c, a0, 0.028), ring(c, a1, 0.028), 0.013, 0.015, DARK, ha, bevel_w=0.004)
        between("finger%d_b_%s" % (k, side), ring(c, a1, 0.028), ring(c, a2, 0.026), 0.012, 0.014, DARK, ha, bevel_w=0.004, taper=0.8)
    between("thumb_" + side, ring(grip - axis * 0.03, math.radians(-40), 0.03), ring(grip - axis * 0.01, math.radians(-120), 0.026), 0.014, 0.016, RED, ha, bevel_w=0.004)
    L.slot("Slot_hand_" + side, tuple(Ha + d * 0.03), wdir, ha)
    L.slot("Slot_forearm_" + side, tuple(El + (Ha - El) * 0.5 + Vector((0.03 if side == "r" else -0.03, 0, 0))), (0, 0, -1), el)

# --- hydraulic hoses: two big arcs from the back of the shoulder boxes up over the shoulders
# and down the outside of the arms to the forearm cuffs (the art's routing). Real curve tubes,
# each in two pieces so they follow two bones without stretching: the arc rides the torso,
# the run down the arm rides the upper arm, and a cuff hides the join.
HOSES = {
    "r": [(0.15, T0 + 0.36, 0.09), (0.2, T0 + 0.44, 0.08), (0.33, T0 + 0.45, 0.05), (0.42, T0 + 0.38, 0.0), (0.4, T0 + 0.28, -0.02)],
    "l": [(-0.14, T0 + 0.37, 0.09), (-0.19, T0 + 0.45, 0.07), (-0.32, T0 + 0.46, 0.03), (-0.43, T0 + 0.4, -0.02), (-0.43, T0 + 0.3, -0.05)],
}
ARM_RUN = {
    "r": [(0.4, T0 + 0.28, -0.02), (0.37, T0 + 0.14, -0.03), (0.31, T0 + 0.0, -0.05), (0.29, T0 - 0.08, -0.05)],
    "l": [(-0.43, T0 + 0.3, -0.05), (-0.42, T0 + 0.22, -0.07), (-0.39, T0 + 0.16, -0.08), (-0.36, T0 + 0.19, -0.09)],
}
for side, arc in HOSES.items():
    L.curve_tube("hose_arc_" + side, arc, 0.02, HOSE, torso)
    sh = bpy.data.objects["Shoulder_" + side]
    L.curve_tube("hose_arm_" + side, ARM_RUN[side], 0.019, HOSE, sh)
    for k, p in enumerate((arc[0], arc[2], arc[-1], ARM_RUN[side][2])):
        q = Vector(p)
        nxt = Vector(arc[min(k + 1, len(arc) - 1)]) if k < 2 else Vector(ARM_RUN[side][min(k, len(ARM_RUN[side]) - 1)])
        d = (nxt - q).normalized() if (nxt - q).length > 1e-4 else Vector((0, -1, 0))
        between("hose_cuff_%s%d" % (side, k), q - d * 0.016, q + d * 0.016, 0.052, 0.052, TAN2, torso if k < 3 else sh, bevel_w=0.008)
    # A smaller secondary loop off the back of each box.
    s = 1 if side == "r" else -1
    L.curve_tube("hose_loop_" + side, [(s * 0.12, T0 + 0.34, 0.12), (s * 0.15, T0 + 0.42, 0.15), (s * 0.24, T0 + 0.41, 0.14), (s * 0.25, T0 + 0.33, 0.12)], 0.012, HOSE, torso)

L.export(L.out_path("assets/mechs/mf_blackbeard.glb"))
