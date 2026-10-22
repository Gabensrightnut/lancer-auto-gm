"""GMS Everest (LL0 starter), from the user's reference description: a big rounded egg chest
in dark teal with a G.M.S. stencil and logo, no head (a green sensor cluster low on the
chest), red spherical armored pods at shoulders, hips and knees, open X-braced truss limbs
over pistons, chunky boxy forearms and shins, big four-fingered hands with red plates, flat
segmented feet, a shell harness, hoses under the chest, and a heavy, slightly hunched stance.
Run: blender --background --factory-startup --python tools/blender/everest.py -- assets/mechs/mf_standard_pattern_i_everest.glb
Game coordinates (x right, y up, -z forward), about 1 unit tall; see mechlib.py."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Matrix, Vector  # noqa: E402

import bpy  # noqa: E402
import mechlib as L  # noqa: E402

L.reset()

TEAL = L.mat("primary", (0.035, 0.085, 0.095), 0.35, 0.5)
TEAL2 = L.mat("secondary", (0.05, 0.12, 0.13), 0.35, 0.5)
RED = L.mat("accent", (0.42, 0.025, 0.02), 0.3, 0.45)
FRAME = L.mat("trim", (0.025, 0.027, 0.03), 0.75, 0.45)
STEEL = L.mat("metal", (0.35, 0.37, 0.38), 0.9, 0.3)
DARK = L.mat("dark", (0.01, 0.01, 0.012), 0.6, 0.5)
STRAP = L.mat("strap", (0.06, 0.045, 0.03), 0.05, 0.85)
SHELL = L.mat("shell", (0.4, 0.04, 0.02), 0.3, 0.5)
BRASS = L.mat("brass", (0.55, 0.38, 0.12), 0.9, 0.3)
WHITE = L.mat("stencil", (0.75, 0.75, 0.7), 0.0, 0.7)
GREY = L.mat("limb", (0.09, 0.09, 0.095), 0.4, 0.55)
GLOW = L.mat("glow", (0.05, 0.3, 0.05), 0.0, 0.4, emit=(0.35, 1.0, 0.35))


def place(obj, a, b):
    """Orient a part built along +y (game) so it spans a->b."""
    a, b = Vector(a), Vector(b)
    y = (b - a).normalized()
    hint = Vector((0, 0, -1)) if abs(y.z) < 0.9 else Vector((1, 0, 0))
    x = y.cross(hint).normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()


def between(name, a, b, w, d, material, parent, bevel_w=0.01, taper=1.0):
    a, b = Vector(a), Vector(b)
    rot = place(None, a, b)
    o = L.box(name, (w, (b - a).length, d), (0, 0, 0), material, None, bevel_w=bevel_w, taper=taper)
    L.set_world(o, Matrix.Translation(L.V((a + b) / 2)) @ (L.C @ rot @ L.C.inverted()).to_4x4())
    bpy.context.view_layer.update()
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o, rot


def pod(name, c, r, out, parent, holes=3):
    """Red armored joint pod: a slightly flattened sphere, a seam band and bolt holes."""
    s = L.sphere(name, r, tuple(c), RED, parent, scale=(1.0, 0.95, 1.0))
    L.subsurf(s, 1)
    o = Vector(out).normalized()
    side = o.cross(Vector((0, 1, 0)) if abs(o.y) < 0.9 else Vector((1, 0, 0))).normalized()
    L.torus(name + "_seam", r * 1.0, r * 0.06, tuple(c), DARK, parent, normal_g=tuple(side), segs=32)
    up = side.cross(o)
    for i in range(holes):
        a = math.tau * i / holes + 0.6
        d = (o * 0.8 + (side * math.cos(a) + up * math.sin(a)) * 0.5).normalized()
        h = L.cyl(name + "_h%d" % i, r * 0.15, r * 0.5, (0, 0, 0), None, bevel_w=0)
        rot = place(None, Vector((0, 0, 0)), d)
        L.set_world(h, Matrix.Translation(L.V(Vector(c) + d * r)) @ (L.C @ rot @ L.C.inverted()).to_4x4())
        L.cut(s, h)
    return s


def truss(name, a, b, w, parent):
    """Open lattice limb: four rails, X braces on every face, an inner piston."""
    a, b = Vector(a), Vector(b)
    rot = place(None, a, b)
    length = (b - a).length
    h = w / 2
    for sx in (-1, 1):
        for sz in (-1, 1):
            off = rot @ Vector((sx * h, 0, sz * h))
            between(name + "_rail%d%d" % (sx, sz), a + off, b + off, 0.012, 0.012, FRAME, parent, bevel_w=0.003)
    bays = max(1, round(length / (w * 1.4)))
    for k in range(bays):
        p0 = a + (b - a) * (k / bays)
        p1 = a + (b - a) * ((k + 1) / bays)
        for face in range(4):
            ax = rot @ (Vector((h, 0, 0)) if face < 2 else Vector((0, 0, h)))
            other = rot @ (Vector((0, 0, h)) if face < 2 else Vector((h, 0, 0)))
            sgn = 1 if face % 2 == 0 else -1
            between(name + "_x%d%da" % (k, face), p0 + ax * sgn - other, p1 + ax * sgn + other, 0.009, 0.009, FRAME, parent, bevel_w=0.002)
            between(name + "_x%d%db" % (k, face), p0 + ax * sgn + other, p1 + ax * sgn - other, 0.009, 0.009, FRAME, parent, bevel_w=0.002)
    L.cyl(name + "_piston", w * 0.2, length * 0.9, (0, 0, 0), STEEL, parent, rot_deg=None)
    pist = bpy.context.scene.objects[name + "_piston"]
    L.set_world(pist, Matrix.Translation(L.V((a + b) / 2)) @ (L.C @ rot @ L.C.inverted()).to_4x4())


def armored(name, a, b, w, d, parent, taper=0.9):
    """Chunky boxy forearm/shin with truss windows cut through its sides."""
    o, rot = between(name, a, b, w, d, TEAL2, parent, bevel_w=0.016, taper=taper)
    length = (Vector(b) - Vector(a)).length
    for sx in (-1, 1):
        for k in range(2):
            c = (Vector(a) + Vector(b)) / 2 + rot @ Vector((sx * w / 2, (k - 0.5) * length * 0.42, 0))
            win = L.box(name + "_win%d%d" % (sx, k), (0.04, length * 0.34, d * 0.55), (0, 0, 0), None, bevel_w=0)
            L.set_world(win, Matrix.Translation(L.V(c)) @ (L.C @ rot @ L.C.inverted()).to_4x4())
            L.cut(o, win)
            # The truss visible inside the window.
            p = c + rot @ Vector((-sx * 0.006, 0, 0))
            between(name + "_xa%d%d" % (sx, k), p + rot @ Vector((0, length * 0.16, -d * 0.26)), p + rot @ Vector((0, -length * 0.16, d * 0.26)), 0.007, 0.007, FRAME, parent, bevel_w=0)
            between(name + "_xb%d%d" % (sx, k), p + rot @ Vector((0, length * 0.16, d * 0.26)), p + rot @ Vector((0, -length * 0.16, -d * 0.26)), 0.007, 0.007, FRAME, parent, bevel_w=0)
    L.groove(o, Vector(a) + rot @ Vector((-w * 0.3, length * -0.25, -d / 2)), Vector(a) + rot @ Vector((w * 0.3, length * -0.25, -d / 2)), normal_g=tuple(rot @ Vector((0, 0, -1))))
    return o, rot


def xblock(name, a, b, w, d, parent, taper=1.0, plate=False):
    """Heavy dark-grey limb block with X-braced panels framed on its faces (the reference's
    signature look), optional teal armor plate on the outer face."""
    o, rot = between(name, a, b, w, d, GREY, parent, bevel_w=0.018, taper=taper)
    a, b = Vector(a), Vector(b)
    length = (b - a).length
    for face in range(4):
        n = rot @ (Vector((1, 0, 0)) if face < 2 else Vector((0, 0, 1)))
        sgn = 1 if face % 2 == 0 else -1
        half = (w if face < 2 else d) / 2 + 0.004
        side = rot @ (Vector((0, 0, 1)) if face < 2 else Vector((1, 0, 0)))
        span = (d if face < 2 else w) * 0.36
        c0, c1 = a + (b - a) * 0.12, a + (b - a) * 0.88
        off = n * sgn * half
        for q in (-1, 1):
            between(name + "_r%d%d" % (face, q), c0 + off + side * span * q, c1 + off + side * span * q, 0.012, 0.012, FRAME, parent, bevel_w=0.003)
        between(name + "_xa%d" % face, c0 + off - side * span, c1 + off + side * span, 0.01, 0.01, FRAME, parent, bevel_w=0.002)
        between(name + "_xb%d" % face, c0 + off + side * span, c1 + off - side * span, 0.01, 0.01, FRAME, parent, bevel_w=0.002)
    if plate:
        c = (a + b) / 2 + rot @ Vector((w / 2 + 0.01, 0, 0))
        pl = L.box(name + "_plate", (0.02, length * 0.55, d * 0.7), (0, 0, 0), TEAL2, None, bevel_w=0.008)
        L.set_world(pl, Matrix.Translation(L.V(c)) @ (L.C @ rot @ L.C.inverted()).to_4x4())
        bpy.context.view_layer.update()
        pl.parent = parent
        pl.matrix_parent_inverse = parent.matrix_world.inverted()
    return o, rot


# --- rig ---------------------------------------------------------------------------------
HIP_Y = 0.47
pelvis = L.joint("Pelvis", (0, HIP_Y, 0))
T0 = HIP_Y + 0.04
torso = L.joint("Torso", (0, T0, 0), pelvis)

L.box("pelvis_block", (0.2, 0.08, 0.15), (0, HIP_Y, 0), FRAME, pelvis, bevel_w=0.02)
L.box("pelvis_plate", (0.12, 0.06, 0.04), (0, HIP_Y - 0.01, -0.075), TEAL, pelvis, bevel_w=0.012, taper=1.2)

# --- legs: wide, slightly bent -----------------------------------------------------------
for s, side in ((1, "r"), (-1, "l")):
    H = Vector((s * 0.15, HIP_Y - 0.01, 0.0))
    K = Vector((s * 0.22, 0.27, -0.09))
    A = Vector((s * 0.21, 0.085, 0.0))
    hip = L.joint("Hip_" + side, tuple(H), pelvis)
    knee = L.joint("Knee_" + side, tuple(K), hip)
    ankle = L.joint("Ankle_" + side, tuple(A), knee)
    pod("hip_pod_" + side, H + Vector((s * 0.03, 0, 0)), 0.065, (s, 0, -0.4), hip)
    xblock("thigh_" + side, H + Vector((0, -0.03, 0)), K + Vector((0, 0.05, 0)), 0.17, 0.18, hip)
    pod("knee_pod_" + side, K + Vector((0, 0, -0.03)), 0.085, (0, 0, -1), knee)
    xblock("shin_" + side, K + Vector((0, -0.05, 0)), A + Vector((0, 0.03, 0)), 0.17, 0.18, knee, taper=1.1, plate=True)
    L.cyl("ankle_" + side, 0.028, 0.08, tuple(A), FRAME, ankle, axis="x")
    # Flat segmented foot.
    L.box("heel_" + side, (0.15, 0.05, 0.09), tuple(Vector((A.x, 0.022, A.z + 0.035))), TEAL2, ankle, bevel_w=0.01)
    for k in range(3):
        L.box("toe%d_%s" % (k, side), (0.15, 0.045, 0.055), tuple(Vector((A.x, 0.02, A.z - 0.015 - k * 0.042))), TEAL2, ankle, rot_deg=(k * 3.0, 0, 0), bevel_w=0.009)
        L.box("toe_seam%d_%s" % (k, side), (0.152, 0.012, 0.006), tuple(Vector((A.x, 0.03, A.z + 0.007 - k * 0.042))), DARK, ankle, bevel_w=0)
    L.box("foot_top_" + side, (0.07, 0.03, 0.08), tuple(Vector((A.x, 0.05, A.z - 0.01))), FRAME, ankle, bevel_w=0.008)

# --- torso: the big rounded egg chest ------------------------------------------------------
L.cyl("waist", 0.07, 0.06, (0, T0 + 0.02, 0), FRAME, torso)
chest = L.loft("chest", [
    dict(y=T0 + 0.03, w=0.168, d=0.151, n=2.1),
    dict(y=T0 + 0.1, w=0.302, d=0.260, n=2.15),
    dict(y=T0 + 0.22, w=0.386, d=0.328, n=2.2, z=-0.01),
    dict(y=T0 + 0.34, w=0.403, d=0.344, n=2.2, z=-0.015),
    dict(y=T0 + 0.44, w=0.361, d=0.311, n=2.15, z=-0.01),
    dict(y=T0 + 0.5, w=0.269, d=0.235, n=2.1),
    dict(y=T0 + 0.53, w=0.134, d=0.118, n=2.0),
], TEAL, torso, ring=40)
# Panel seams.
L.groove(chest, (-0.25, T0 + 0.16, -0.2), (0.25, T0 + 0.16, -0.2), width=0.008, depth=0.02)
L.groove(chest, (0.0, T0 + 0.2, -0.22), (0.0, T0 + 0.5, -0.19), width=0.007, depth=0.02)
for s in (1, -1):
    L.groove(chest, (s * 0.2, T0 + 0.18, -0.15), (s * 0.18, T0 + 0.45, -0.12), width=0.006, depth=0.02, normal_g=(s * 0.6, 0, -0.8))
# Upper chest plate with stencil and logo.
plate = L.loft("chest_plate", [dict(y=T0 + 0.33, w=0.34, d=0.07, n=3.0, z=-0.19), dict(y=T0 + 0.44, w=0.3, d=0.06, n=3.0, z=-0.17)], TEAL2, torso, ring=24, sub=1)
bpy.ops.object.text_add(location=(0, 0, 0))
txt = bpy.context.object
txt.data.body = "G.M.S."
txt.data.size = 0.055
txt.data.extrude = 0.002
txt.data.align_x = "CENTER"
txt.data.materials.append(WHITE)
txt.name = "stencil"
L.set_world(txt, Matrix.Translation(L.V((-0.06, T0 + 0.385, -0.222))) @ (L.C @ L._rot_g((-12, 192, 0)) @ L.C.inverted()).to_4x4() @ Matrix.Rotation(math.radians(90), 4, "X"))
bpy.ops.object.convert(target="MESH")
txt = bpy.context.object
bpy.context.view_layer.update()
txt.parent = torso
txt.matrix_parent_inverse = torso.matrix_world.inverted()
L.cyl("logo", 0.022, 0.006, (0.11, T0 + 0.4, -0.205), RED, torso, rot_deg=(-80, 0, -12), bevel_w=0.002)
L.cyl("logo_c", 0.011, 0.008, (0.11, T0 + 0.4, -0.207), DARK, torso, rot_deg=(-80, 0, -12), bevel_w=0)
# The "face": a recessed sensor cluster low in the chest centre.
head = L.joint("Head", (0, T0 + 0.17, -0.19), torso)
L.loft("sensor_brow", [dict(y=T0 + 0.205, w=0.14, d=0.05, n=3.0, z=-0.2), dict(y=T0 + 0.225, w=0.12, d=0.04, n=3.0, z=-0.195)], TEAL2, head, ring=20, sub=1)
L.loft("sensor_well", [dict(y=T0 + 0.13, w=0.11, d=0.05, n=2.6, z=-0.198), dict(y=T0 + 0.2, w=0.12, d=0.05, n=2.6, z=-0.2)], DARK, head, ring=20, sub=1)
for p, r in (((0, T0 + 0.18, -0.222), 0.012), ((-0.026, T0 + 0.162, -0.218), 0.008), ((0.026, T0 + 0.162, -0.218), 0.008), ((0, T0 + 0.148, -0.218), 0.007)):
    L.sphere("sensor_%d" % int(p[0] * 1000), r, p, GLOW, head)
L.joint("Eye", (0, T0 + 0.18, -0.23), head)
# Back: reactor block with two exhaust stacks and vents.
L.box("reactor", (0.28, 0.26, 0.12), (0, T0 + 0.3, 0.2), FRAME, torso, bevel_w=0.03)
for k in range(3):
    L.box("reactor_vent%d" % k, (0.22, 0.012, 0.02), (0, T0 + 0.22 + k * 0.05, 0.265), STEEL, torso, bevel_w=0.003)
for s in (1, -1):
    L.cyl("stack_%d" % s, 0.034, 0.13, (s * 0.08, T0 + 0.46, 0.22), STEEL, torso)
    L.cyl("stack_in_%d" % s, 0.025, 0.135, (s * 0.08, T0 + 0.465, 0.22), DARK, torso, bevel_w=0)
# Harness strap with shotgun shells (right shoulder to left hip).
strap = L.bezier((0.2, T0 + 0.47, -0.08), (0.14, T0 + 0.38, -0.25), (-0.1, T0 + 0.17, -0.24), (-0.2, T0 + 0.08, -0.1), 24)
L.tube("strap", strap, 0.013, STRAP, torso, sides=8)
for i in range(3, 21, 2):
    p, q = Vector(strap[i]), Vector(strap[i + 1])
    t = (q - p).normalized()
    n = t.cross(Vector((0, 0, 1))).normalized()
    sh = L.cyl("shell%d" % i, 0.009, 0.034, (0, 0, 0), SHELL, None, bevel_w=0.001)
    rot = place(None, Vector((0, 0, 0)), n)
    L.set_world(sh, Matrix.Translation(L.V(p + Vector((0, 0, -0.012)))) @ (L.C @ rot @ L.C.inverted()).to_4x4())
    bpy.context.view_layer.update()
    sh.parent = torso
    sh.matrix_parent_inverse = torso.matrix_world.inverted()
# Hoses from under the chest to the hips.
for s in (1, -1):
    for k in range(2):
        a = (s * (0.06 + k * 0.04), T0 + 0.07, -0.06 + k * 0.08)
        b = (s * 0.13, HIP_Y, -0.03 + k * 0.05)
        pts = L.bezier(a, (a[0] + s * 0.03, a[1] - 0.06, a[2]), (b[0], b[1] + 0.05, b[2]), b, 14)
        L.tube("hose%d_%d" % (k, s), L.resample(pts, 0.006), 0.01, DARK, torso, sides=8, ribs=0.15, rib_every=0.012)

# --- arms: red pods, truss uppers, boxy forearms, big hands -------------------------------
ARMS = {
    # Right: shotgun resting on the shoulder. Left: hanging low with the knife.
    "r": ((0.28, T0 + 0.36, 0.0), (0.44, T0 + 0.2, -0.08), (0.34, T0 + 0.42, -0.2), (-0.08, 0.6, 0.8)),
    "l": ((-0.28, T0 + 0.36, 0.0), (-0.44, T0 + 0.1, -0.02), (-0.43, T0 - 0.24, -0.12), (0.0, -0.25, -1.0)),
}
for side, (Sh, El, Ha, wdir) in ARMS.items():
    s = 1 if side == "r" else -1
    Sh, El, Ha = Vector(Sh), Vector(El), Vector(Ha)
    pad = L.joint("Pad_" + side, tuple(Sh), torso)
    pod("shoulder_pod_" + side, Sh + Vector((s * 0.01, 0.01, 0.0)), 0.11, (s, 0.3, -0.3), pad)
    L.slot("Slot_shoulder_" + side, tuple(Sh + Vector((s * 0.01, 0.08, 0.02))), (0, 0, -1), pad)
    L.slot("Slot_back_" + side, (s * 0.1, T0 + 0.5, 0.24), (0, 0, -1), torso)
    sh = L.joint("Shoulder_" + side, tuple(Sh), torso)
    el = L.joint("Elbow_" + side, tuple(El), sh)
    ha = L.joint("Hand_" + side, tuple(Ha), el)
    xblock("upper_" + side, Sh + (El - Sh).normalized() * 0.09, El - (El - Sh).normalized() * 0.03, 0.11, 0.12, sh)
    pod("elbow_pod_" + side, El, 0.05, (s, 0, 0), el, holes=2)
    fa, frot = xblock("fore_" + side, El + (Ha - El).normalized() * 0.04, Ha - (Ha - El).normalized() * 0.04, 0.14, 0.15, el, taper=1.12, plate=True)
    L.box("fore_plate_" + side, (0.028, (Ha - El).length * 0.6, 0.08), (0, 0, 0), RED, el, bevel_w=0.008)
    L.set_world(bpy.context.scene.objects["fore_plate_" + side], Matrix.Translation(L.V((El + Ha) / 2 + frot @ Vector((s * 0.085, 0, 0)))) @ (L.C @ frot @ L.C.inverted()).to_4x4())
    # Big four-fingered hand curled around the grip, red knuckle plates.
    d = (Ha - El).normalized()
    hrot = place(None, Ha, Ha + d)
    P = lambda v: tuple(Ha + hrot @ Vector(v))  # noqa: E731
    hand = L.box("palm_" + side, (0.11, 0.11, 0.12), (0, 0, 0), FRAME, ha, bevel_w=0.014)
    L.set_world(bpy.context.scene.objects["palm_" + side], Matrix.Translation(L.V(P((0, 0.05, 0)))) @ (L.C @ hrot @ L.C.inverted()).to_4x4())
    for k in range(4):
        for j, (ln, col) in enumerate(((0.032, FRAME), (0.028, FRAME))):
            fp = P(((k - 1.5) * 0.025, 0.11 + j * 0.042, -0.028 - j * 0.025))
            f = L.box("finger%d%d_%s" % (k, j, side), (0.026, ln * 1.4, 0.03), (0, 0, 0), col, ha, bevel_w=0.005)
            L.set_world(f, Matrix.Translation(L.V(fp)) @ (L.C @ hrot @ L._rot_g((-40 - j * 40, 0, 0)) @ L.C.inverted()).to_4x4())
        kp = P(((k - 1.5) * 0.025, 0.1, -0.017))
        kn = L.box("knuckle%d_%s" % (k, side), (0.027, 0.03, 0.033), (0, 0, 0), RED, ha, bevel_w=0.004)
        L.set_world(kn, Matrix.Translation(L.V(kp)) @ (L.C @ hrot @ L.C.inverted()).to_4x4())
    L.slot("Slot_hand_" + side, tuple(Ha + d * 0.05), wdir, ha)
    L.slot("Slot_forearm_" + side, tuple((El + Ha) / 2 + Vector((s * 0.06, 0, 0))), (0, 0, -1), el)

L.export(L.out_path("assets/mechs/mf_standard_pattern_i_everest.glb"))
