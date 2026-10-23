"""Helpers for building mech models in Blender by script (run headless:
blender --background --factory-startup --python tools/blender/<frame>.py -- <out.glb>).

Coordinates are written in the game's convention (Godot: x right, y up, -z forward; the mech
is about 1 unit tall) and converted to Blender (z up, front toward +y) so the glTF export
lands in Godot facing -Z. Joints are empties named like the Godot rig (Pelvis, Torso, Head,
Eye, Hip_r/Knee_r/Ankle_r, Shoulder_r/Elbow_r/Hand_r, Pad_r, Slot_hand_r, ...), unrotated at
their joint positions; parts are modeled already posed and parented to their joint, so the
game can swing joints for walking and aiming. Materials are named by paint role (primary,
secondary, trim, dark, metal, glow, rope, hose, cloth...) so the game can repaint them.
Every mesh gets a vertex color layer: R = edge wear (convex edges), G = cavity grime.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# Game -> Blender: (x, y, z) -> (x, -z, y)
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def V(x, y=None, z=None):
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# --- materials ---------------------------------------------------------------------------

_mats = {}


def mat(role, color=(0.6, 0.6, 0.6), metal=0.3, rough=0.6, emit=None):
    """A material named by paint role. Colors here are the defaults the game can override."""
    if role in _mats:
        return _mats[role]
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    _mats[role] = m
    return m


# --- objects and joints ------------------------------------------------------------------

def _link(obj, parent=None):
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def joint(name, pos, parent=None, rot_g=None):
    """An empty at a game-space position. rot_g: optional game-space 3x3 rotation."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.03
    mw = Matrix.Translation(V(pos))
    if rot_g is not None:
        mw = mw @ (C @ rot_g @ C.inverted()).to_4x4()
    e.matrix_world = mw
    _link(e, parent)
    bpy.context.view_layer.update()
    return e


def slot(name, pos, forward_g, parent, up_g=(0, 1, 0)):
    """A weapon mount: weapons point along the empty's game-space -Z, i.e. `forward_g`."""
    f = Vector(forward_g).normalized()
    z = -f
    up = Vector(up_g)
    if abs(z.dot(up)) > 0.95:
        up = Vector((1, 0, 0))
    x = up.cross(z).normalized()
    y = z.cross(x)
    rot = Matrix((x, y, z)).transposed()
    return joint(name, pos, parent, rot)


def _mesh_obj(name, bm, material, parent, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    if material is not None:
        obj.data.materials.append(material)
    _link(obj)
    if parent is not None:
        bpy.context.view_layer.update()
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def set_world(obj, mw):
    """Place an object in world space, keeping its parent (re-parents without jumping)."""
    p = obj.parent
    obj.parent = None
    obj.matrix_world = mw
    bpy.context.view_layer.update()
    if p is not None:
        obj.parent = p
        obj.matrix_parent_inverse = p.matrix_world.inverted()
    return obj


def subsurf(obj, levels=2, crease_edges=None):
    m = obj.modifiers.new("Subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return obj


def bevel(obj, width=0.01, segments=3, limit="ANGLE", angle=35.0):
    m = obj.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = limit
    if limit == "ANGLE":
        m.angle_limit = math.radians(angle)
    m.harden_normals = False
    return obj


def weighted_normals(obj):
    obj.modifiers.new("WN", "WEIGHTED_NORMAL").keep_sharp = True
    return obj


# --- primitives (game-space parameters) -------------------------------------------------

def _se(t, a, b, n):
    c, s = math.cos(t), math.sin(t)
    return (a * math.copysign(abs(c) ** (2.0 / n), c), b * math.copysign(abs(s) ** (2.0 / n), s))


def loft(name, sections, material, parent=None, ring=24, caps=True, sub=2, xform=None):
    """Lofted shell through rounded sections (bottom to top). Section: dict(y, w, d, n=2, x=0, z=0).
    `xform`: optional game-space Matrix (4x4) applied to every point (to tilt/aim the part)."""
    bm = bmesh.new()
    rings = []
    for s in sections:
        r = []
        for j in range(ring):
            t = math.tau * j / ring
            px, pz = _se(t, s["w"] / 2.0, s["d"] / 2.0, s.get("n", 2.0))
            p = Vector((px + s.get("x", 0.0), s["y"], pz + s.get("z", 0.0)))
            if xform is not None:
                p = xform @ p
            r.append(bm.verts.new(V(p)))
        rings.append(r)
    for i in range(len(rings) - 1):
        for j in range(ring):
            jn = (j + 1) % ring
            bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
    if caps:
        for end, flip in ((0, True), (len(rings) - 1, False)):
            s = sections[end]
            inner = []
            for j in range(ring):
                t = math.tau * j / ring
                px, pz = _se(t, s["w"] * 0.32, s["d"] * 0.32, s.get("n", 2.0))
                p = Vector((px + s.get("x", 0.0), s["y"], pz + s.get("z", 0.0)))
                if xform is not None:
                    p = xform @ p
                inner.append(bm.verts.new(V(p)))
            for j in range(ring):
                jn = (j + 1) % ring
                q = (rings[end][j], rings[end][jn], inner[jn], inner[j])
                bm.faces.new(q if not flip else tuple(reversed(q)))
            f = bm.faces.new(inner if flip else list(reversed(inner)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _mesh_obj(name, bm, material, parent)
    if sub:
        subsurf(obj, sub)
    return obj


def box(name, size, pos, material, parent=None, rot_deg=(0, 0, 0), bevel_w=0.01, seg=3, taper=1.0):
    """Hard-surface box (game-space size/pos/rotation in degrees XYZ) with beveled edges.
    `taper` scales the top face (x, z)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        # v.co is in Blender space of a unit cube; convert scale in game axes.
        gx, gy, gz = v.co.x, v.co.z, -v.co.y
        k = taper if gy > 0 else 1.0
        g = Vector((gx * size[0] * k, gy * size[1], gz * size[2] * k))
        g = _rot_g(rot_deg) @ g + Vector(pos)
        v.co = V(g)
    obj = _mesh_obj(name, bm, material, parent, smooth=False)
    if bevel_w > 0:
        bevel(obj, bevel_w, seg)
        weighted_normals(obj)
    return obj


def _rot_g(deg):
    rx, ry, rz = (math.radians(a) for a in deg)
    # Godot's default Euler order is YXZ.
    return (Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(rz, 3, "Z"))


def cyl(name, radius, length, pos, material, parent=None, axis="y", rot_deg=None, sides=24, bevel_w=0.004, top_r=None):
    """Cylinder along a game axis ('x','y','z') or rotated by rot_deg."""
    bm = bmesh.new()
    r2 = radius if top_r is None else top_r
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius, radius2=r2, depth=length)
    base = {"x": Matrix.Rotation(math.radians(90), 3, "Z") @ Matrix.Rotation(math.radians(90), 3, "X"),
            "y": Matrix.Identity(3), "z": Matrix.Rotation(math.radians(90), 3, "X")}[axis]
    rg = _rot_g(rot_deg) if rot_deg else Matrix.Identity(3)
    for v in bm.verts:
        # create_cone builds along Blender z; treat as game y.
        g = Vector((v.co.x, v.co.z, -v.co.y))
        if axis == "x":
            g = Vector((g.y, -g.x, g.z))
        elif axis == "z":
            g = Vector((g.x, g.z, -g.y))
        v.co = V(rg @ g + Vector(pos))
    obj = _mesh_obj(name, bm, material, parent)
    for p in obj.data.polygons:
        p.use_smooth = abs(p.normal.dot(V(rg @ Vector({"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis])))) < 0.7
    if bevel_w > 0:
        bevel(obj, bevel_w, 2, angle=50)
        weighted_normals(obj)
    return obj


def sphere(name, radius, pos, material, parent=None, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=radius)
    for v in bm.verts:
        g = Vector((v.co.x * scale[0], v.co.z * scale[1], -v.co.y * scale[2]))
        v.co = V(g + Vector(pos))
    return _mesh_obj(name, bm, material, parent)


def torus(name, major, minor, pos, material, parent=None, normal_g=(0, 1, 0), segs=40):
    bm = bmesh.new()
    n = Vector(normal_g).normalized()
    a = n.orthogonal().normalized()
    b = n.cross(a)
    rings = []
    for i in range(segs):
        t = math.tau * i / segs
        c = a * math.cos(t) + b * math.sin(t)
        r = []
        for j in range(10):
            u = math.tau * j / 10
            p = Vector(pos) + c * (major + minor * math.cos(u)) + n * (minor * math.sin(u))
            r.append(bm.verts.new(V(p)))
        rings.append(r)
    for i in range(segs):
        for j in range(10):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % 10], rings[(i + 1) % segs][(j + 1) % 10], rings[(i + 1) % segs][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj(name, bm, material, parent)


def bezier(a, b, c, d, steps=20):
    a, b, c, d = (Vector(p) for p in (a, b, c, d))
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append(a * u ** 3 + b * 3 * u * u * t + c * 3 * u * t * t + d * t ** 3)
    return out


def tube(name, points, radius, material, parent=None, sides=12, ribs=0.0, rib_every=0.0):
    """Tube along game-space points (parallel-transport frames). `ribs` adds corrugation
    (radius variation) every `rib_every` units of length, like wrapped hoses."""
    bm = bmesh.new()
    pts = [Vector(p) for p in points]
    rings = []
    prev_side = None
    dist = 0.0
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if i > 0:
            dist += (pts[i] - pts[i - 1]).length
        if prev_side is None:
            side = t.cross(Vector((0, 1, 0)))
            if side.length < 0.01:
                side = t.cross(Vector((1, 0, 0)))
        else:
            side = prev_side - t * prev_side.dot(t)
        side.normalize()
        prev_side = side
        bi = t.cross(side).normalized()
        r = radius
        if ribs and rib_every:
            r *= 1.0 + ribs * (0.5 + 0.5 * math.cos(math.tau * dist / rib_every))
        ring = []
        for j in range(sides):
            u = math.tau * j / sides
            ring.append(bm.verts.new(V(p + (side * math.cos(u) + bi * math.sin(u)) * r)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(sides):
            jn = (j + 1) % sides
            bm.faces.new((rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]))
    for end in (0, len(rings) - 1):
        f = bm.faces.new(rings[end] if end else list(reversed(rings[end])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj(name, bm, material, parent)


def curve_tube(name, points, radius, material, parent=None, bevel_res=2, smooth=True, res_u=6):
    """A hose or cable as a real Blender curve: a smooth (NURBS-like, auto handles) curve through
    game-space points with a round bevel, converted to a mesh. Cleaner than a polyline tube
    for long routed hoses (no kinks where the route turns)."""
    cu = bpy.data.curves.new(name + "_curve", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = bevel_res
    cu.use_fill_caps = True
    cu.resolution_u = res_u
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = V(p)
        bp.handle_left_type = bp.handle_right_type = "AUTO" if smooth else "VECTOR"
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.clear()
    ob.data.materials.append(material)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    if parent is not None:
        bpy.context.view_layer.update()
        mw = ob.matrix_world.copy()
        ob.parent = parent
        ob.matrix_world = mw
    return ob


def resample(points, step):
    """Even spacing along a polyline (so corrugated tubes rib evenly)."""
    pts = [Vector(p) for p in points]
    out = [pts[0]]
    acc = 0.0
    for i in range(1, len(pts)):
        seg = pts[i] - pts[i - 1]
        L = seg.length
        while acc + L >= step:
            t = (step - acc) / L
            pts[i - 1] = pts[i - 1] + seg * t
            seg = pts[i] - pts[i - 1]
            L = seg.length
            out.append(pts[i - 1].copy())
            acc = 0.0
        acc += L
    out.append(pts[-1])
    return out


def cut(target, cutter, apply=False):
    """Boolean difference (panel grooves, vents, holes). The cutter object is hidden."""
    m = target.modifiers.new("Cut_" + cutter.name, "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    m.solver = "EXACT"
    cutter.hide_render = True
    cutter.hide_viewport = True
    cutter["cutter"] = True
    # Booleans should run before bevel/subsurf already on the stack.
    while target.modifiers.find(m.name) > 0:
        bpy.context.view_layer.objects.active = target
        with bpy.context.temp_override(object=target):
            bpy.ops.object.modifier_move_up(modifier=m.name)
    return target


def groove(target, a, b, width=0.006, depth=0.012, normal_g=(0, 0, -1)):
    """A panel line from game point a to b, cut into `target`'s surface facing normal_g."""
    a, b = Vector(a), Vector(b)
    mid = (a + b) / 2
    d = b - a
    n = Vector(normal_g).normalized()
    side = d.cross(n).normalized()
    rot = Matrix((d.normalized(), side, n)).transposed()
    c = box("cut_" + target.name, (1, 1, 1), (0, 0, 0), None, bevel_w=0)
    mw = Matrix.Translation(V(mid)) @ (C @ rot @ C.inverted()).to_4x4() @ Matrix.Diagonal((d.length, width, depth * 2, 1))
    c.matrix_world = mw
    return cut(target, c)


# --- finishing and export ----------------------------------------------------------------

def _apply_modifiers():
    dg = bpy.context.evaluated_depsgraph_get()
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or obj.get("cutter"):
            continue
        ev = obj.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev, depsgraph=dg)
        obj.modifiers.clear()
        old = obj.data
        obj.data = me
        bpy.data.meshes.remove(old)
    for obj in list(bpy.context.scene.objects):
        if obj.get("cutter"):
            bpy.data.objects.remove(obj)


def bake_wear(strength=3.0):
    """Vertex colors from curvature: R = edge wear on convex edges, G = grime in cavities."""
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        me = obj.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        conv = []
        for v in bm.verts:
            if not v.link_edges:
                conv.append(0.0)
                continue
            acc = 0.0
            for e in v.link_edges:
                o = e.other_vert(v)
                d = (v.co - o.co)
                if d.length > 1e-6:
                    acc += v.normal.dot(d.normalized())
            conv.append(acc / len(v.link_edges))
        bm.free()
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        for i, c in enumerate(conv):
            wear = max(0.0, min(1.0, c * strength))
            grime = max(0.0, min(1.0, -c * strength))
            attr.data[i].color = (wear, grime, 0.0, 1.0)
        me.color_attributes.active_color = attr


def export(path):
    _apply_modifiers()
    bake_wear()
    tris = sum(len(o.data.loop_triangles) if o.data.loop_triangles else (o.data.calc_loop_triangles() or len(o.data.loop_triangles))
               for o in bpy.context.scene.objects if o.type == "MESH")
    kw = dict(filepath=path, export_format="GLB", export_apply=False, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("EXPORTED", path, "triangles:", tris)


def out_path(default):
    argv = sys.argv
    if "--" in argv and len(argv) > argv.index("--") + 1:
        return argv[argv.index("--") + 1]
    return default
