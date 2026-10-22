"""People for LANCER TTRPG: one rigged, animated base human plus outfit, hair and gear pieces,
exported as assets/people/human.glb. Our own model (no assets from anywhere else).

Look: normal human proportions with a slight push (a touch larger head and hands), clean
stylized shapes that read from the tactical camera, pilot gear in the spirit of the core
book's illustrations (flight suits, hardsuits, long coats, ponchos, scarves, visored helmets,
packs, slung rifles). Shading and ink outlines come from the game's shaders.

Built in Blender coordinates (Z up, the figure faces +Y, so glTF/Godot forward is -Z).
Everything is named so the game can pick pieces and colors:
  meshes: Body, Suit, Jacket, Coat, Hardsuit, Poncho, Collar, Scarf, Shemagh, Hair_<style>,
          Beard, Hat_<cap|beanie|helmet|headset|hood>, Glasses_<glasses|visor|goggles|eyepatch>,
          Gear_pack, Gear_rifle, Gear_rebreather, Gear_tags
  materials (roles): skin, hair, eye, in_p, in_s, out_p, out_s, hat, accent, scarf, metal, dark
  shape keys (Body and the deforming outfit shells): female, heavy, slim,
          face_round, face_square, face_long, face_heart
  actions: idle, walk, run, talk, sneak, sit, aim, hit, fall
Run: blender --background --factory-startup --python tools/blender/human.py -- assets/people/human.glb
"""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "human.glb"
FPS = 24


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


MATS = {}


def mat(role, color, metal=0.0, rough=0.7):
    if role in MATS:
        return MATS[role]
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    MATS[role] = m
    return m


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


# --- rig ---------------------------------------------------------------------------------

# name: (head, tail, parent). Left side (+X); the right side is mirrored.
BONES = {
    "hips": ((0, 0, 0.96), (0, 0, 1.06), None),
    "spine": ((0, 0, 1.06), (0, 0, 1.24), "hips"),
    "chest": ((0, 0, 1.24), (0, 0.0, 1.44), "spine"),
    "neck": ((0, 0, 1.44), (0, 0.01, 1.54), "chest"),
    "head": ((0, 0.01, 1.54), (0, 0.01, 1.80), "neck"),
    "shoulder.L": ((0.04, 0, 1.40), (0.17, 0, 1.41), "chest"),
    "upperarm.L": ((0.19, 0, 1.40), (0.24, 0, 1.13), "shoulder.L"),
    "forearm.L": ((0.24, 0, 1.13), (0.27, 0.03, 0.89), "upperarm.L"),
    "hand.L": ((0.27, 0.03, 0.89), (0.28, 0.04, 0.76), "forearm.L"),
    "thigh.L": ((0.10, 0, 0.94), (0.11, 0.01, 0.53), "hips"),
    "shin.L": ((0.11, 0.01, 0.53), (0.11, -0.02, 0.10), "thigh.L"),
    "foot.L": ((0.11, -0.02, 0.10), (0.11, 0.13, 0.02), "shin.L"),
}


def mirror_name(n):
    return n[:-2] + ".R" if n.endswith(".L") else n


def build_rig():
    arm = bpy.data.armatures.new("Rig")
    ob = link(bpy.data.objects.new("Rig", arm))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    made = {}
    for name, (h, t, p) in list(BONES.items()):
        for side in ([1, -1] if name.endswith(".L") else [1]):
            n = name if side == 1 else mirror_name(name)
            b = eb.new(n)
            b.head = Vector((h[0] * side, h[1], h[2]))
            b.tail = Vector((t[0] * side, t[1], t[2]))
            b.roll = 0.0
            if p:
                b.parent = made[p if side == 1 or not p.endswith(".L") else mirror_name(p)]
                b.use_connect = (b.parent.tail - b.head).length < 1e-4
            made[n] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


# --- body ----------------------------------------------------------------------------------

# Skin-modifier skeleton: (position, (radius x, radius y)) and edges. Shapes are slightly
# stylized: clean volumes, a touch larger head and hands.
NODES = [
    ((0, 0, 0.92), (0.15, 0.10)),    # 0 pelvis
    ((0, 0, 1.08), (0.135, 0.095)),  # 1 waist
    ((0, 0, 1.26), (0.155, 0.105)),  # 2 ribs
    ((0, 0, 1.40), (0.17, 0.105)),   # 3 chest top
    ((0, 0.005, 1.50), (0.055, 0.055)),  # 4 neck
]
EDGES = [(0, 1), (1, 2), (2, 3), (3, 4)]


def add_limb(points, start_index):
    idx = []
    for p, r in points:
        NODES.append((p, r))
        idx.append(len(NODES) - 1)
    EDGES.append((start_index, idx[0]))
    for a, b in zip(idx, idx[1:]):
        EDGES.append((a, b))
    return idx


for s in (1, -1):
    add_limb([((0.17 * s, 0, 1.40), (0.065, 0.06)), ((0.22 * s, 0, 1.25), (0.055, 0.055)),
              ((0.24 * s, 0, 1.13), (0.047, 0.047)), ((0.265 * s, 0.025, 0.93), (0.04, 0.038)),
              ((0.275 * s, 0.035, 0.86), (0.056, 0.036)), ((0.28 * s, 0.045, 0.76), (0.048, 0.03))], 3)
    add_limb([((0.10 * s, 0, 0.88), (0.085, 0.085)), ((0.11 * s, 0.01, 0.70), (0.07, 0.07)),
              ((0.11 * s, 0.01, 0.53), (0.055, 0.055)), ((0.11 * s, -0.015, 0.30), (0.05, 0.05)),
              ((0.11 * s, -0.02, 0.11), (0.042, 0.042)), ((0.11 * s, 0.05, 0.05), (0.05, 0.04)),
              ((0.11 * s, 0.13, 0.04), (0.045, 0.03))], 0)


def skin_mesh(name, nodes, edges, scale=1.0, sub=1):
    me = bpy.data.meshes.new(name)
    me.from_pydata([n[0] for n in nodes], edges, [])
    ob = link(bpy.data.objects.new(name, me))
    mod = ob.modifiers.new("skin", "SKIN")
    mod.use_smooth_shade = True
    for i, v in enumerate(me.skin_vertices[0].data):
        v.radius = (nodes[i][1][0] * scale, nodes[i][1][1] * scale)
        if i == 0:
            v.use_root = True
    ob.modifiers.new("sub", "SUBSURF").levels = sub
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return ob


def head_mesh():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        # Stylized head: rounded skull, narrower jaw, slight chin forward (+Y is the face).
        # A touch larger than true scale, so faces and hats read from the tactical camera.
        w = 0.116 * (1.0 - 0.18 * max(0.0, -z) ** 1.5)
        v.co = Vector((x * w, y * 0.13 + (0.013 * max(0.0, -z) if y > 0 else 0.0), z * 0.148))
    me = bpy.data.meshes.new("Head")
    bm.to_mesh(me)
    ob = link(bpy.data.objects.new("Head", me))
    ob.location = (0, 0.012, 1.665)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return objs[0]


def region_weights(ob):
    """Rough body regions from height, for material splits and shape keys."""
    out = {}
    for v in ob.data.vertices:
        out[v.index] = v.co.copy()
    return out


def add_shape_keys(ob):
    ob.shape_key_add(name="Basis")
    base = [v.co.copy() for v in ob.data.vertices]

    def key(name, f):
        k = ob.shape_key_add(name=name, from_mix=False)
        for i, co in enumerate(base):
            k.data[i].co = f(co.copy())

    def female(c):
        z = c.z
        if 1.22 < z < 1.48 and abs(c.x) < 0.2:  # narrower shoulders and chest
            c.x *= 0.9
        if 1.26 < z < 1.38 and c.y > 0.02 and abs(c.x) < 0.14:  # bust
            c.y += 0.03 * math.sin((z - 1.26) / 0.12 * math.pi)
        if 0.82 < z < 1.02:  # hips
            c.x *= 1.08
        if 1.0 < z < 1.16:  # waist
            c.x *= 0.9
        if z > 1.52:  # head slightly smaller
            c.x *= 0.96
            c.y *= 0.96
        return c

    def heavy(c):
        if 0.6 < c.z < 1.5:
            k = 1.0 + 0.16 * math.sin((c.z - 0.6) / 0.9 * math.pi)
            c.x *= k
            c.y *= 1.0 + 0.22 * math.sin((c.z - 0.6) / 0.9 * math.pi)
        return c

    def slim(c):
        if c.z < 1.52:
            c.x *= 0.9
            c.y *= 0.92
        return c

    def face(sx, sz, jaw):
        def f(c):
            if c.z > 1.52:
                d = c.z - 1.66
                c.x *= sx * (1.0 + jaw * max(0.0, -d) * 4.0)
                c.z = 1.66 + d * sz
            return c
        return f

    key("female", female)
    key("heavy", heavy)
    key("slim", slim)
    key("face_round", face(1.06, 0.94, 0.1))
    key("face_square", face(1.04, 1.0, 0.25))
    key("face_long", face(0.95, 1.08, 0.0))
    key("face_heart", face(1.03, 1.0, -0.35))


def bind(ob, rig):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def bone_parent(ob, rig, bone):
    """Rigid piece that follows one bone (helmets, glasses, packs...)."""
    mw = ob.matrix_world.copy()
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    ob.matrix_world = mw


def assign(ob, material):
    ob.data.materials.clear()
    ob.data.materials.append(material)


def split_by(ob, rules):
    """Per-face materials: rules = [(material, test(center) -> bool)], first match wins."""
    ob.data.materials.clear()
    for m, _ in rules:
        ob.data.materials.append(m)
    for p in ob.data.polygons:
        c = p.center
        for i, (_, t) in enumerate(rules):
            if t(c):
                p.material_index = i
                break


def shell(src, name, push, keep, material_rules):
    """A deforming outfit layer: the body's faces where keep(center) is true, pushed out
    along the normals (in every shape key too, so builds still fit)."""
    ob = src.copy()
    ob.data = src.data.copy()
    ob.name = name
    ob.data.name = name
    link(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    drop = [f for f in bm.faces if not keep(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bm.normal_update()
    normals = {v.index: v.normal.copy() for v in bm.verts}
    for v in bm.verts:
        v.co += v.normal * push(v.co)
    # Shape keys: same push on every key.
    for layer in bm.verts.layers.shape.values():
        for v in bm.verts:
            v[layer] = v[layer] + normals[v.index] * push(v.co)
    bm.to_mesh(ob.data)
    bm.free()
    split_by(ob, material_rules)
    return ob


def prim(kind, name, loc, scale, material, rot=(0, 0, 0), **kw):
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=kw.get("seg", 16), ring_count=kw.get("rings", 10), location=loc)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=kw.get("seg", 16), location=loc)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=kw.get("seg", 16), radius1=1, radius2=kw.get("top", 0.0), location=loc)
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=8, major_radius=1, minor_radius=kw.get("minor", 0.25), location=loc)
    else:
        bpy.ops.mesh.primitive_cube_add(location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = scale
    ob.rotation_euler = [math.radians(a) for a in rot]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if kind == "cube" and kw.get("bevel", 0.0) > 0:
        m = ob.modifiers.new("bev", "BEVEL")
        m.width = kw["bevel"]
        m.segments = 2
        bpy.ops.object.modifier_apply(modifier="bev")
    for p in ob.data.polygons:
        p.use_smooth = kind != "cube"
    assign(ob, material)
    return ob


def piece(name, parts):
    if len(parts) > 1:
        return join(parts, name)
    parts[0].name = name
    bpy.ops.object.select_all(action="DESELECT")
    parts[0].select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return parts[0]


# --- animation -----------------------------------------------------------------------------

def pose_action(rig, name, frames, keys, loop=True, root=None):
    """keys: {bone: [(frame, (x, y, z) degrees)]}; root: [(frame, (dx, dy, dz))] on hips."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
    for bone, ks in keys.items():
        pb = rig.pose.bones[bone]
        for f, deg in ks:
            # Values are written as "+X = forward/bend, +Z = outward"; with roll-0 bones that
            # is -X and -Z in bone space.
            pb.rotation_euler = [math.radians(-deg[0]), math.radians(deg[1]), math.radians(-deg[2])]
            pb.keyframe_insert("rotation_euler", frame=f)
    if root:
        pb = rig.pose.bones["hips"]
        for f, d in root:
            pb.location = d
            pb.keyframe_insert("location", frame=f)
    act.frame_range = (0, frames)
    # Push to an NLA track so the exporter writes every action.
    tr = rig.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 0, act)
    rig.animation_data.action = None


def cycle(a, b, n=4, frames=32, phase=0.0):
    """Keys swinging between a and b over a loop (sine)."""
    out = []
    for i in range(n + 1):
        t = i / n
        k = 0.5 + 0.5 * math.sin((t + phase) * math.tau)
        out.append((round(t * frames), tuple(a[j] + (b[j] - a[j]) * k for j in range(3))))
    return out


def animations(rig):
    # Bone-local X bends limbs forward/back (bones roll 0); arms hang along -Z.
    arms_down = {"upperarm.L": [(0, (0, 0, 8))], "upperarm.R": [(0, (0, 0, -8))]}
    pose_action(rig, "idle", 48, {
        "chest": cycle((-1.5, 0, 0), (1.5, 0, 0), 4, 48),
        "head": cycle((0, -3, 0), (0, 3, 0), 4, 48, 0.25),
        "upperarm.L": cycle((3, 0, -6), (-3, 0, -4), 4, 48), "upperarm.R": cycle((-3, 0, 6), (3, 0, 4), 4, 48),
        "forearm.L": [(0, (-12, 0, 0))], "forearm.R": [(0, (-12, 0, 0))],
    })
    def gait(name, frames, leg, knee, arm, elbow, lean, bob, crouch=0.0):
        pose_action(rig, name, frames, {
            "thigh.L": cycle((-leg - crouch, 0, 0), (leg - crouch, 0, 0), 8, frames),
            "thigh.R": cycle((leg - crouch, 0, 0), (-leg - crouch, 0, 0), 8, frames),
            "shin.L": cycle((knee + crouch * 1.6, 0, 0), (5 + crouch * 1.6, 0, 0), 8, frames, 0.15),
            "shin.R": cycle((5 + crouch * 1.6, 0, 0), (knee + crouch * 1.6, 0, 0), 8, frames, 0.15),
            "upperarm.L": cycle((arm, 0, -5), (-arm, 0, -5), 8, frames),
            "upperarm.R": cycle((-arm, 0, 5), (arm, 0, 5), 8, frames),
            "forearm.L": [(0, (-elbow, 0, 0))], "forearm.R": [(0, (-elbow, 0, 0))],
            "spine": [(0, (lean, 0, 0))], "chest": cycle((0, -4, 0), (0, 4, 0), 8, frames),
        }, root=[(int(frames * i / 4), (0, 0, -crouch * 0.006 - bob * (0.5 + 0.5 * math.cos(i * math.pi)))) for i in range(5)])
    gait("walk", 32, 24, 40, 18, 15, 4, 0.025)
    gait("run", 20, 40, 75, 35, 75, 12, 0.05)
    gait("sneak", 40, 18, 35, 8, 50, 22, 0.01, crouch=35)
    pose_action(rig, "talk", 48, {
        "chest": cycle((-1, -3, 0), (1, 3, 0), 4, 48),
        "head": cycle((-4, -6, 0), (3, 6, 0), 4, 48, 0.3),
        "upperarm.R": cycle((-25, 0, -15), (-40, 0, -25), 4, 48), "forearm.R": cycle((-60, 0, 10), (-80, 0, -10), 4, 48, 0.2),
        "upperarm.L": cycle((-10, 0, 10), (-20, 0, 14), 4, 48, 0.5), "forearm.L": [(0, (-35, 0, 0))],
    })
    pose_action(rig, "sit", 2, {
        "thigh.L": [(0, (-88, 0, -4))], "thigh.R": [(0, (-88, 0, 4))],
        "shin.L": [(0, (88, 0, 0))], "shin.R": [(0, (88, 0, 0))],
        "spine": [(0, (6, 0, 0))], "forearm.L": [(0, (-40, 0, 0))], "forearm.R": [(0, (-40, 0, 0))],
        "upperarm.L": [(0, (-20, 0, 8))], "upperarm.R": [(0, (-20, 0, -8))],
    }, root=[(0, (0, 0, -0.45))])
    pose_action(rig, "aim", 2, {
        "upperarm.R": [(0, (-80, 0, -20))], "forearm.R": [(0, (-40, 0, 30))],
        "upperarm.L": [(0, (-70, 0, 25))], "forearm.L": [(0, (-20, 0, -40))],
        "chest": [(0, (0, 0, -15))], "head": [(0, (0, 0, 10))], "spine": [(0, (5, 0, 0))],
        "thigh.L": [(0, (-12, 0, 0))], "shin.L": [(0, (14, 0, 0))],
    })
    pose_action(rig, "hit", 14, {
        "spine": [(0, (0, 0, 0)), (3, (-18, 0, 0)), (14, (0, 0, 0))],
        "head": [(0, (0, 0, 0)), (3, (-20, 0, 0)), (14, (0, 0, 0))],
        "upperarm.L": [(0, (0, 0, 8)), (3, (-30, 0, 30)), (14, (0, 0, 8))],
        "upperarm.R": [(0, (0, 0, -8)), (3, (-30, 0, -30)), (14, (0, 0, -8))],
    }, loop=False, root=[(0, (0, 0, 0)), (3, (0, -0.06, -0.02)), (14, (0, 0, 0))])
    pose_action(rig, "fall", 30, {
        "hips": [(0, (0, 0, 0)), (16, (-60, 0, 0)), (30, (-88, 0, 0))],
        "thigh.L": [(0, (0, 0, 0)), (12, (-40, 0, 0)), (30, (-10, 0, -8))],
        "thigh.R": [(0, (0, 0, 0)), (12, (-30, 0, 0)), (30, (-20, 0, 8))],
        "shin.L": [(0, (0, 0, 0)), (12, (60, 0, 0)), (30, (15, 0, 0))],
        "shin.R": [(0, (0, 0, 0)), (12, (50, 0, 0)), (30, (30, 0, 0))],
        "upperarm.L": [(0, (0, 0, 8)), (30, (-20, 0, 70))], "upperarm.R": [(0, (0, 0, -8)), (30, (-30, 0, -60))],
        "head": [(0, (0, 0, 0)), (30, (15, 0, 20))],
    }, loop=False, root=[(0, (0, 0, 0)), (16, (0, -0.2, -0.45)), (30, (0, -0.3, -0.8))])


# --- build ---------------------------------------------------------------------------------

def main():
    reset()
    skin = mat("skin", (0.78, 0.56, 0.42), 0.0, 0.6)
    hair = mat("hair", (0.2, 0.14, 0.1), 0.0, 0.8)
    eye = mat("eye", (0.05, 0.05, 0.06), 0.0, 0.3)
    in_p = mat("in_p", (0.24, 0.30, 0.38), 0.0, 0.8)
    in_s = mat("in_s", (0.75, 0.6, 0.25), 0.1, 0.6)
    out_p = mat("out_p", (0.35, 0.33, 0.28), 0.0, 0.85)
    out_s = mat("out_s", (0.55, 0.22, 0.15), 0.1, 0.7)
    hat = mat("hat", (0.3, 0.32, 0.3), 0.2, 0.6)
    accent = mat("accent", (0.3, 0.75, 0.9), 0.4, 0.25)
    scarf = mat("scarf", (0.6, 0.2, 0.15), 0.0, 0.9)
    metal = mat("metal", (0.5, 0.52, 0.55), 0.8, 0.35)
    dark = mat("dark", (0.1, 0.1, 0.11), 0.2, 0.7)

    rig = build_rig()
    body = skin_mesh("Body", NODES, EDGES)
    head = head_mesh()
    # Face: eyes (dark), brows, nose and ears, simple and readable.
    parts = [body, head]
    for s in (1, -1):
        parts.append(prim("sphere", "eye", (0.045 * s, 0.124, 1.68), (0.016, 0.008, 0.012), eye, seg=10, rings=6))
        parts.append(prim("cube", "brow", (0.047 * s, 0.122, 1.712), (0.024, 0.007, 0.006), hair, rot=(0, -8 * s, 0)))
        parts.append(prim("sphere", "ear", (0.115 * s, 0.0, 1.668), (0.013, 0.027, 0.035), skin, seg=10, rings=6))
    parts.append(prim("cone", "nose", (0, 0.14, 1.648), (0.014, 0.014, 0.032), skin, rot=(-75, 0, 0), seg=10))
    body = join(parts, "Body")
    split_by(body, [(skin, lambda c: True)])
    # Keep the face parts' own materials: re-split by original material order is lost on
    # join, so color by position: eyes/brows by small regions.
    body.data.materials.clear()
    for m in (skin, eye, hair):
        body.data.materials.append(m)
    for p in body.data.polygons:
        c = p.center
        if c.y > 0.11 and 1.665 < c.z < 1.695 and 0.028 < abs(c.x) < 0.063:
            p.material_index = 1
        elif c.y > 0.11 and 1.704 < c.z < 1.72 and 0.02 < abs(c.x) < 0.073:
            p.material_index = 2
    add_shape_keys(body)

    lower = lambda c: c.z < 1.47 and not (abs(c.x) > 0.25 and c.z < 0.9)  # neck down, not hands
    suit = shell(body, "Suit", lambda co: 0.012, lambda c: c.z < 1.47 and c.z > 0.115 and not (abs(c.x) > 0.262 and c.z < 0.9),
                 [(in_s, lambda c: 0.94 < c.z < 0.99 or (1.38 < c.z < 1.42 and abs(c.x) > 0.16) or (0.5 < c.z < 0.56)), (in_p, lambda c: True)])
    jacket = shell(body, "Jacket", lambda co: 0.03, lambda c: 0.9 < c.z < 1.47 and not (abs(c.x) > 0.25 and c.z < 1.0),
                   [(out_s, lambda c: c.z > 1.42 or (c.y > 0.08 and abs(c.x) < 0.03) or (0.9 < c.z < 0.94)), (out_p, lambda c: True)])
    coat = shell(body, "Coat", lambda co: 0.035 + (0.06 * max(0.0, 0.95 - co.z) if co.z < 0.95 else 0.0),
                 lambda c: 0.45 < c.z < 1.47 and not (abs(c.x) > 0.25 and c.z < 1.0) and not (c.z < 0.92 and c.y > 0.04),
                 [(out_s, lambda c: c.z > 1.42 or 0.9 < c.z < 0.95), (out_p, lambda c: True)])
    shells = [suit, jacket, coat]

    # Boots and gloves (always on, dark), part of the Suit layer.
    boots = []
    for s in (1, -1):
        boots.append(prim("cyl", "boot", (0.11 * s, 0.0, 0.17), (0.058, 0.06, 0.14), dark))
        boots.append(prim("cube", "toe", (0.11 * s, 0.08, 0.04), (0.055, 0.085, 0.04), dark, bevel=0.02))
    bootm = piece("Boots", boots)

    # Hardsuit: chest and back plates, pauldrons, belt, knee and shin guards, gauntlets.
    hp = []
    hp.append(prim("cube", "chestplate", (0, 0.07, 1.31), (0.155, 0.06, 0.13), out_p, bevel=0.03))
    hp.append(prim("cube", "backplate", (0, -0.08, 1.31), (0.15, 0.05, 0.14), out_p, bevel=0.03))
    hp.append(prim("cube", "belt", (0, 0.0, 0.98), (0.165, 0.115, 0.035), out_s, bevel=0.01))
    hp.append(prim("torus", "collar", (0, 0, 1.46), (0.1, 0.1, 0.08), out_s, minor=0.3))
    hpm = piece("Hardsuit", hp)
    pads = []
    for s in (1, -1):
        pads.append((prim("sphere", "pauldron", (0.2 * s, 0, 1.40), (0.085, 0.085, 0.065), out_s, seg=14, rings=8), "upperarm" + (".L" if s > 0 else ".R")))
        pads.append((prim("cube", "knee", (0.11 * s, 0.06, 0.5), (0.055, 0.035, 0.07), out_p, bevel=0.015), "shin" + (".L" if s > 0 else ".R")))
        pads.append((prim("cube", "shin", (0.11 * s, 0.055, 0.3), (0.05, 0.03, 0.11), out_p, bevel=0.015), "shin" + (".L" if s > 0 else ".R")))
        pads.append((prim("cyl", "gauntlet", (0.27 * s, 0.03, 0.93), (0.05, 0.05, 0.06), out_s, rot=(8, 0, 0)), "forearm" + (".L" if s > 0 else ".R")))

    poncho = piece("Poncho", [prim("cone", "poncho", (0, 0, 1.16), (0.3, 0.2, 0.32), out_p, seg=20, top=0.3),
                              prim("torus", "poncho_hem", (0, 0, 0.855), (0.3, 0.2, 0.3), out_s, minor=0.05)])
    collar = piece("Collar", [prim("cyl", "collar", (0, 0.0, 1.48), (0.07, 0.065, 0.04), in_p)])
    scarfm = piece("Scarf", [prim("torus", "scarf", (0, 0.01, 1.47), (0.085, 0.08, 0.1), scarf, minor=0.35),
                             prim("cube", "tail", (0.05, 0.1, 1.33), (0.035, 0.012, 0.12), scarf, rot=(8, 0, 6))])
    shemagh = piece("Shemagh", [prim("cone", "shem", (0, 0.0, 1.43), (0.16, 0.14, 0.09), scarf, seg=16, top=0.55),
                                prim("torus", "shem_wrap", (0, 0.0, 1.5), (0.075, 0.075, 0.1), scarf, minor=0.45)])

    # Hair styles (rigid on the head).
    def cap(name, sx, sz, z, m=hair, back=0.0):
        return prim("sphere", name, (0, -0.005 - back, z + 0.01), (0.123 * sx, 0.136 * sx, 0.12 * sz), m, seg=18, rings=10)
    hairs = {
        "short": [cap("h", 1.0, 0.75, 1.72)],
        "buzz": [cap("h", 0.98, 0.65, 1.715)],
        "long": [cap("h", 1.02, 0.78, 1.72), prim("cube", "back", (0, -0.075, 1.56), (0.1, 0.04, 0.17), hair, bevel=0.03)],
        "bun": [cap("h", 1.0, 0.72, 1.72), prim("sphere", "bun", (0, -0.1, 1.76), (0.05, 0.05, 0.05), hair)],
        "mohawk": [prim("cube", "crest", (0, -0.01, 1.79), (0.018, 0.12, 0.05), hair, bevel=0.01)],
        "braids": [cap("h", 1.0, 0.72, 1.72)] + [prim("cyl", "braid", (0.09 * s, -0.05, 1.55), (0.022, 0.022, 0.14), hair) for s in (1, -1)],
        "swept": [cap("h", 1.03, 0.8, 1.725), prim("sphere", "sweep", (0.03, 0.06, 1.78), (0.09, 0.07, 0.04), hair)],
    }
    hair_obs = {k: piece("Hair_" + k, v) for k, v in hairs.items()}
    beard = piece("Beard", [prim("sphere", "beard", (0, 0.08, 1.585), (0.092, 0.066, 0.066), hair, seg=14, rings=8)])

    hats = {
        "cap": [prim("sphere", "cap", (0, 0, 1.745), (0.13, 0.143, 0.093), hat, seg=18, rings=10), prim("cube", "brim", (0, 0.155, 1.725), (0.08, 0.06, 0.008), hat, bevel=0.005)],
        "beanie": [prim("sphere", "beanie", (0, -0.005, 1.75), (0.132, 0.143, 0.121), hat, seg=18, rings=10), prim("torus", "cuff", (0, 0, 1.71), (0.127, 0.138, 0.13), hat, minor=0.18)],
        "helmet": [prim("sphere", "helmet", (0, 0, 1.695), (0.156, 0.167, 0.165), hat, seg=20, rings=12), prim("cube", "visor", (0, 0.145, 1.68), (0.11, 0.03, 0.038), accent, bevel=0.012), prim("cyl", "ant", (0.1, -0.06, 1.82), (0.005, 0.005, 0.07), metal)],
        "headset": [prim("torus", "band", (0, 0, 1.73), (0.13, 0.13, 0.13), dark, rot=(0, 90, 0), minor=0.06)] + [prim("cyl", "cup", (0.123 * s, 0, 1.67), (0.038, 0.038, 0.015), hat, rot=(0, 90, 0)) for s in (1, -1)],
        "hood": [prim("sphere", "hood", (0, -0.02, 1.685), (0.165, 0.176, 0.176), out_p, seg=18, rings=10)],
    }
    hat_obs = {k: piece("Hat_" + k, v) for k, v in hats.items()}
    glasses = {
        "glasses": [prim("torus", "lens", (0.045 * s, 0.13, 1.68), (0.024, 0.024, 0.024), metal, rot=(90, 0, 0), minor=0.15) for s in (1, -1)],
        "visor": [prim("cube", "visor", (0, 0.125, 1.68), (0.11, 0.025, 0.022), accent, bevel=0.008)],
        "goggles": [prim("cyl", "gog", (0.045 * s, 0.125, 1.68), (0.03, 0.03, 0.02), accent, rot=(90, 0, 0)) for s in (1, -1)] + [prim("torus", "strap", (0, 0, 1.68), (0.123, 0.134, 0.13), dark, minor=0.06)],
        "eyepatch": [prim("cube", "patch", (-0.045, 0.13, 1.68), (0.024, 0.008, 0.02), dark, bevel=0.005)],
    }
    glass_obs = {k: piece("Glasses_" + k, v) for k, v in glasses.items()}

    pack = piece("Gear_pack", [prim("cube", "pack", (0, -0.17, 1.22), (0.12, 0.07, 0.15), out_s, bevel=0.02),
                               prim("cyl", "roll", (0, -0.16, 1.39), (0.035, 0.035, 0.12), out_p, rot=(0, 90, 0))])
    rifle = piece("Gear_rifle", [prim("cube", "rifle", (0.05, -0.13, 1.16), (0.025, 0.03, 0.32), dark, rot=(0, 35, 0), bevel=0.006),
                                 prim("cube", "mag", (0.09, -0.11, 1.12), (0.015, 0.02, 0.05), metal, rot=(0, 35, 0))])
    rebreather = piece("Gear_rebreather", [prim("cube", "mask", (0, 0.125, 1.615), (0.05, 0.03, 0.035), dark, bevel=0.012)] +
                       [prim("cyl", "filter", (0.045 * s, 0.145, 1.6), (0.02, 0.02, 0.015), metal, rot=(90, 0, 0)) for s in (1, -1)])
    tags = piece("Gear_tags", [prim("cube", "tag", (0, 0.105, 1.36), (0.012, 0.003, 0.018), metal)])

    # Skinning: the body and shells deform; the rest rides on bones.
    for ob in [body] + shells:
        bind(ob, rig)
    bind(bootm, rig)
    for ob in [hpm, poncho, pack, rifle, tags]:
        bone_parent(ob, rig, "chest")
    for ob, b in pads:
        bone_parent(piece(ob.name.capitalize(), [ob]), rig, b)
    for ob in [collar, scarfm, shemagh]:
        bone_parent(ob, rig, "neck")
    for ob in list(hair_obs.values()) + [beard, rebreather] + list(hat_obs.values()) + list(glass_obs.values()):
        bone_parent(ob, rig, "head")
    # Pads are part of the hardsuit set: name them so the game toggles them together.
    for ob in bpy.data.objects:
        if ob.name.lower().startswith(("pauldron", "knee", "shin", "gauntlet")) and ob.type == "MESH":
            ob.name = "Hardsuit_" + ob.name

    animations(rig)
    tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_morph=True, export_skins=True, export_apply=False, export_yup=True)
    print("EXPORTED", OUT, "faces:", tris)


main()
