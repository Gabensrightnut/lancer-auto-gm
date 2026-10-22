"""People for LANCER TTRPG, realistic tier: MakeHuman/MPFB2 base humans (CC0 base mesh,
targets and system assets; see CREDITS.md) with our own Lancer-style pilot gear, a game rig,
expression/blink/viseme shape keys and our own animations. Exports one glb per gender:
assets/people/human_male.glb, assets/people/human_female.glb.

Needs MPFB2 installed in a separate Blender profile (A:\\tools\\mpfb, see CREDITS.md):
  set BLENDER_USER_RESOURCES=A:\\tools\\mpfb\\blender_user
  blender --background --python tools/blender/people_mh.py -- assets/people male|female

Same piece, material and shape-key names as tools/blender/human.py, so HumanFigure drives
both. Blender space: the MakeHuman figure faces -Y.
"""
import bpy, bmesh, importlib, math, os, sys
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["assets/people", "male"]
OUT_DIR, GENDER = ARGS[0], ARGS[1]
svc = importlib.import_module("bl_ext.user_default.mpfb.services")
HumanService, TargetService, AssetService, FaceService = svc.HumanService, svc.TargetService, svc.AssetService, svc.FaceService
LocationService = svc.LocationService
faceservice_mod = importlib.import_module("bl_ext.user_default.mpfb.services.faceservice")
SYS = os.path.join(LocationService.get_user_data())
EXT = os.path.dirname(os.path.dirname(faceservice_mod.__file__))
UNITS = os.path.join(EXT, "data", "targets", "expression", "units", "caucasian")
HEADT = os.path.join(EXT, "data", "targets", "head")


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


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


# --- face keys ------------------------------------------------------------------------------

FACE_KEYS = {
    "blink": ["eye-left-closure", "eye-right-closure"],
    "eyes_wide": ["eye-left-opened-up", "eye-right-opened-up"],
    "brow_angry": ["eyebrows-left-down", "eyebrows-right-down"],
    "brow_worried": ["eyebrows-left-inner-up", "eyebrows-right-inner-up"],
    "brow_up": ["eyebrows-left-up", "eyebrows-right-up"],
    "mouth_open": ["mouth-open"],
    "smile": ["mouth-corner-puller", "mouth-upward-retraction"],
    "frown": ["mouth-depression"],
    "v_ee": ["mouth-retraction"],
    "v_oo": ["mouth-pursing"],
    "v_mm": ["mouth-compression"],
}
HEAD_KEYS = {"face_round": "head-round", "face_square": "head-square", "face_long": "head-oval", "face_heart": "head-invertedtriangular"}


def merged_key(ob, name, paths):
    """One shape key that is the sum of several MakeHuman targets."""
    tmp = []
    for i, p in enumerate(paths):
        TargetService.load_target(ob, p, weight=1.0, name="_tmp%d" % i)
        tmp.append("_tmp%d" % i)
    for kb in ob.data.shape_keys.key_blocks:
        kb.value = 1.0 if kb.name in tmp else 0.0
    k = ob.shape_key_add(name=name, from_mix=True)
    k.value = 0.0
    for t in tmp:
        ob.shape_key_remove(ob.data.shape_keys.key_blocks[t])


def target_path(folder, name):
    p = os.path.join(folder, name + ".target.gz")
    return p if os.path.exists(p) else None


# --- body -----------------------------------------------------------------------------------

def make_body(macro):
    md = TargetService.get_default_macro_info_dict()
    md.update(macro)
    ob = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True, feet_on_ground=True, scale=0.1, macro_detail_dict=md)
    TargetService.bake_targets(ob)
    return ob


def coords(ob):
    return [v.co.copy() for v in ob.data.vertices]


def add_build_keys(body):
    """heavy / slim / muscular from other macro settings of the same mesh (same topology)."""
    variants = {
        "heavy": {"weight": 1.0, "muscle": 0.55},
        "slim": {"weight": 0.15, "muscle": 0.45},
        "muscular": {"weight": 0.5, "muscle": 1.0},
    }
    base = GENDER_MACRO.copy()
    for name, extra in variants.items():
        m = base.copy()
        m.update(extra)
        other = make_body(m)
        co = coords(other)
        bpy.data.objects.remove(other, do_unlink=True)
        k = body.shape_key_add(name=name, from_mix=False)
        for i, c in enumerate(co):
            k.data[i].co = c


GENDER_MACRO = {"gender": 1.0 if GENDER == "male" else 0.0, "age": 0.5, "muscle": 0.6 if GENDER == "male" else 0.5,
                "weight": 0.5, "height": 0.55 if GENDER == "male" else 0.45, "proportions": 0.6}


def asset(sub, name, ext="mhclo"):
    for root, _, files in os.walk(os.path.join(SYS, sub, name)):
        for f in files:
            if f.endswith("." + ext):
                return os.path.join(root, f)
    return None


def child_named(prefix):
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.lower().startswith(prefix.lower()):
            return o
    return None


def delete_helpers(body):
    """Remove MakeHuman's helper geometry (kept until now for fitting assets)."""
    groups = [g for g in body.vertex_groups if g.name.lower().startswith(("helper", "joint")) or g.name in ("HelperGeometry", "JointCubes")]
    idx = {g.index for g in groups}
    me = body.data
    bm = bmesh.new()
    bm.from_mesh(me)
    deform = bm.verts.layers.deform.active
    drop = [v for v in bm.verts if deform and any(gi in idx and w > 0.5 for gi, w in v[deform].items())]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    for m in list(body.modifiers):
        if m.type == "MASK":
            body.modifiers.remove(m)


# --- gear (our own, Lancer-style) -------------------------------------------------------------

def prim(kind, name, loc, scale, material, rot=(0, 0, 0), **kw):
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=kw.get("seg", 20), ring_count=kw.get("rings", 12), location=loc)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=kw.get("seg", 20), location=loc)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=kw.get("seg", 20), radius1=1, radius2=kw.get("top", 0.0), location=loc)
    elif kind == "torus":
        bpy.ops.mesh.primitive_torus_add(major_segments=28, minor_segments=10, major_radius=1, minor_radius=kw.get("minor", 0.25), location=loc)
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
        m.segments = 3
        bpy.ops.object.modifier_apply(modifier="bev")
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.clear()
    ob.data.materials.append(material)
    return ob


def join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    ob = parts[0]
    ob.name = name
    ob.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def bone_parent(ob, rig, bone):
    mw = ob.matrix_world.copy()
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    ob.matrix_world = mw


def dominant_bone(body):
    """Per vertex: the name of the bone with the most weight."""
    names = {g.index: g.name for g in body.vertex_groups}
    out = {}
    for v in body.data.vertices:
        best, bw = "", 0.0
        for g in v.groups:
            if g.weight > bw and names.get(g.group, "") in BONES_SET:
                best, bw = names[g.group], g.weight
        out[v.index] = best
    return out


BONES_SET = set()


def shell(body, name, push, keep_bones, material_rules, dom):
    """A layer of clothing: the body's faces whose vertices belong to keep_bones, pushed out
    along the normals (in every shape key too). Keeps the body's skin weights."""
    ob = body.copy()
    ob.data = body.data.copy()
    ob.name = name
    ob.data.name = name
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    keep = set(i for i, b in dom.items() if b in keep_bones)
    drop = [f for f in bm.faces if not all(v.index in keep for v in f.verts)]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bm.normal_update()
    normals = {v.index: v.normal.copy() for v in bm.verts}
    for v in bm.verts:
        v.co += v.normal * push
    for layer in bm.verts.layers.shape.values():
        for v in bm.verts:
            v[layer] = v[layer] + normals[v.index] * push
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.materials.clear()
    for m, _ in material_rules:
        ob.data.materials.append(m)
    vb = {}
    for v in ob.data.vertices:
        vb[v.index] = max(v.groups, key=lambda g: g.weight).group if len(v.groups) else -1
    gname = {g.index: g.name for g in ob.vertex_groups}
    for p in ob.data.polygons:
        b = gname.get(vb.get(p.vertices[0], -1), "")
        for i, (_, test) in enumerate(material_rules):
            if test(b, p.center):
                p.material_index = i
                break
    for m in list(ob.modifiers):
        if m.type not in ("ARMATURE",):
            ob.modifiers.remove(m)
    return ob


# --- animation ------------------------------------------------------------------------------

NAMES = {"hips": "pelvis", "spine": "spine_01", "spine2": "spine_02", "chest": "spine_03", "neck": "neck_01", "head": "head",
         "clavicle.L": "clavicle_l", "upperarm.L": "upperarm_l", "forearm.L": "lowerarm_l", "hand.L": "hand_l",
         "thigh.L": "thigh_l", "shin.L": "calf_l", "foot.L": "foot_l"}


def real(n):
    if n.endswith(".R"):
        return NAMES[n[:-2] + ".L"][:-2] + "_r"
    return NAMES[n]


def world_rot(rig, bone, fwd, out, yaw):
    """A rotation in body terms as the bone's local rotation. fwd: the bone's tip moves toward
    the figure's front; out: the tip moves up and away from straight down (negative lowers
    a raised arm); yaw: turn about the vertical. Independent of how the rig's bones are rolled."""
    b = rig.data.bones[bone]
    M = b.matrix_local.to_3x3()
    inv = rig.matrix_world.to_3x3().inverted()
    down = (inv @ Vector((0, 0, -1))).normalized()
    front = (inv @ Vector((0, -1, 0))).normalized()
    up = -down
    d = (b.tail_local - b.head_local).normalized()
    R = Matrix.Identity(3)
    if abs(yaw) > 1e-6:
        R = Matrix.Rotation(math.radians(yaw), 3, up) @ R
    ax_f = d.cross(front)
    if ax_f.length > 1e-4 and abs(fwd) > 1e-6:
        R = Matrix.Rotation(math.radians(fwd), 3, ax_f.normalized()) @ R
    ax_d = d.cross(down)
    if ax_d.length > 1e-4 and abs(out) > 1e-6:
        R = Matrix.Rotation(math.radians(-out), 3, ax_d.normalized()) @ R
    return (M.inverted() @ R @ M).to_quaternion()


def pose_action(rig, name, frames, keys, root=None):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    for logical, ks in keys.items():
        bn = real(logical)
        pb = rig.pose.bones[bn]
        for f, (fw, ou, ya) in ks:
            pb.rotation_quaternion = world_rot(rig, bn, fw, ou, ya)
            pb.keyframe_insert("rotation_quaternion", frame=f)
    if root:
        pb = rig.pose.bones["pelvis"]
        M = rig.data.bones["pelvis"].matrix_local.to_3x3()
        for f, d in root:
            pb.location = M.inverted() @ Vector(d)
            pb.keyframe_insert("location", frame=f)
    act.frame_range = (0, frames)
    tr = rig.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 0, act)
    rig.animation_data.action = None


def cycle(a, b, n=8, frames=32, phase=0.0):
    out = []
    for i in range(n + 1):
        t = i / n
        k = 0.5 + 0.5 * math.sin((t + phase) * math.tau)
        out.append((round(t * frames), tuple(a[j] + (b[j] - a[j]) * k for j in range(3))))
    return out


ARM = -38.0  # MakeHuman rests in an A-pose: bring the arms down to the sides


def animations(rig):
    pose_action(rig, "idle", 48, {
        "chest": cycle((-1.5, 0, 0), (1.5, 0, 0), 4, 48), "head": cycle((0, 0, -3), (0, 0, 3), 4, 48, 0.25),
        "upperarm.L": cycle((3, ARM, 0), (-3, ARM + 3, 0), 4, 48), "upperarm.R": cycle((-3, ARM, 0), (3, ARM + 3, 0), 4, 48),
        "forearm.L": [(0, (12, 0, 0))], "forearm.R": [(0, (12, 0, 0))],
    })

    def gait(name, frames, leg, knee, arm, elbow, lean, bob, crouch=0.0):
        pose_action(rig, name, frames, {
            "thigh.L": cycle((-leg + crouch, 0, 0), (leg + crouch, 0, 0), 8, frames),
            "thigh.R": cycle((leg + crouch, 0, 0), (-leg + crouch, 0, 0), 8, frames),
            "shin.L": cycle((-knee - crouch * 1.6, 0, 0), (-5 - crouch * 1.6, 0, 0), 8, frames, 0.15),
            "shin.R": cycle((-5 - crouch * 1.6, 0, 0), (-knee - crouch * 1.6, 0, 0), 8, frames, 0.15),
            "upperarm.L": cycle((-arm, ARM + 4, 0), (arm, ARM + 4, 0), 8, frames),
            "upperarm.R": cycle((arm, ARM + 4, 0), (-arm, ARM + 4, 0), 8, frames),
            "forearm.L": [(0, (elbow, 0, 0))], "forearm.R": [(0, (elbow, 0, 0))],
            "spine": [(0, (lean, 0, 0))], "chest": cycle((0, 0, -4), (0, 0, 4), 8, frames),
        }, root=[(int(frames * i / 4), (0, 0, -crouch * 0.006 - bob * (0.5 + 0.5 * math.cos(i * math.pi)))) for i in range(5)])
    gait("walk", 32, 24, 40, 18, 15, 4, 0.025)
    gait("run", 20, 40, 75, 35, 75, 12, 0.05)
    gait("sneak", 40, 18, 35, 8, 50, 22, 0.01, crouch=35)
    pose_action(rig, "talk", 48, {
        "chest": cycle((-1, 0, -3), (1, 0, 3), 4, 48), "head": cycle((-4, 0, -6), (3, 0, 6), 4, 48, 0.3),
        "upperarm.R": cycle((25, ARM + 12, 0), (40, ARM + 18, 0), 4, 48), "forearm.R": cycle((60, 0, 10), (80, 0, -10), 4, 48, 0.2),
        "upperarm.L": cycle((10, ARM + 6, 0), (20, ARM + 8, 0), 4, 48, 0.5), "forearm.L": [(0, (35, 0, 0))],
    })
    pose_action(rig, "sit", 2, {
        "thigh.L": [(0, (88, 0, 0))], "thigh.R": [(0, (88, 0, 0))], "shin.L": [(0, (-88, 0, 0))], "shin.R": [(0, (-88, 0, 0))],
        "spine": [(0, (-6, 0, 0))], "forearm.L": [(0, (40, 0, 0))], "forearm.R": [(0, (40, 0, 0))],
        "upperarm.L": [(0, (20, ARM, 0))], "upperarm.R": [(0, (20, ARM, 0))],
    }, root=[(0, (0, 0, -0.45))])
    pose_action(rig, "aim", 2, {
        "upperarm.R": [(0, (80, ARM + 20, 0))], "forearm.R": [(0, (40, 0, 0))],
        "upperarm.L": [(0, (70, ARM + 10, 0))], "forearm.L": [(0, (25, 0, 0))],
        "chest": [(0, (0, 0, -15))], "head": [(0, (0, 0, 10))], "spine": [(0, (-5, 0, 0))],
    })
    pose_action(rig, "hit", 14, {
        "spine": [(0, (0, 0, 0)), (3, (-18, 0, 0)), (14, (0, 0, 0))], "head": [(0, (0, 0, 0)), (3, (-20, 0, 0)), (14, (0, 0, 0))],
        "upperarm.L": [(0, (0, ARM, 0)), (3, (30, ARM + 25, 0)), (14, (0, ARM, 0))], "upperarm.R": [(0, (0, ARM, 0)), (3, (30, ARM + 25, 0)), (14, (0, ARM, 0))],
    }, root=[(0, (0, 0, 0)), (3, (0, 0.06, -0.02)), (14, (0, 0, 0))])
    pose_action(rig, "fall", 30, {
        "hips": [(0, (0, 0, 0)), (16, (-60, 0, 0)), (30, (-88, 0, 0))],
        "thigh.L": [(0, (0, 0, 0)), (12, (40, 0, 0)), (30, (10, 8, 0))], "thigh.R": [(0, (0, 0, 0)), (12, (30, 0, 0)), (30, (20, 8, 0))],
        "shin.L": [(0, (0, 0, 0)), (12, (-60, 0, 0)), (30, (-15, 0, 0))], "shin.R": [(0, (0, 0, 0)), (12, (-50, 0, 0)), (30, (-30, 0, 0))],
        "upperarm.L": [(0, (0, ARM, 0)), (30, (20, 30, 0))], "upperarm.R": [(0, (0, ARM, 0)), (30, (30, 20, 0))],
    }, root=[(0, (0, 0, 0)), (16, (0, 0.2, -0.45)), (30, (0, 0.3, -0.8))])


# --- build ----------------------------------------------------------------------------------

def main():
    clear_scene()
    body = make_body(GENDER_MACRO)
    body.name = "Body"
    # Face keys from MakeHuman's expression units, head shapes, then build variants.
    for key, names in FACE_KEYS.items():
        merged_key(body, key, [p for p in (target_path(UNITS, n) for n in names) if p])
    for key, name in HEAD_KEYS.items():
        p = target_path(HEADT, name)
        if p:
            merged_key(body, key, [p])
    add_build_keys(body)
    # Rig, then body parts and hair fitted to the (still complete) base mesh.
    rig = HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    rig.name = "Rig"
    BONES_SET.update(b.name for b in rig.data.bones)
    skin = "young_caucasian_male" if GENDER == "male" else "young_caucasian_female"
    HumanService.set_character_skin(asset("skins", skin, "mhmat"), body, skin_type="MAKESKIN")
    parts = {"Eyes": asset("eyes", "low-poly"), "Eyebrows": asset("eyebrows", "eyebrow001" if GENDER == "male" else "eyebrow010"),
             "Eyelashes": asset("eyelashes", "eyelashes01"), "Teeth": asset("teeth", "teeth_base")}
    for kind, path in parts.items():
        if path:
            HumanService.add_mhclo_asset(path, body, asset_type=kind if kind != "Teeth" else "Teeth", subdiv_levels=0, material_type="MAKESKIN")
    hair = {"short": "short02", "buzz": "short04", "long": "long01", "bun": "ponytail01", "braids": "braid01",
            "swept": "short03", "bob": "bob01", "afro": "afro01", "mohawk": "short01"}
    for style, asset_name in hair.items():
        before = set(bpy.data.objects)
        p = asset("hair", asset_name)
        if p:
            HumanService.add_mhclo_asset(p, body, asset_type="Hair", subdiv_levels=0, material_type="MAKESKIN")
            new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
            if new:
                new[0].name = "Hair_" + style
    # Face keys follow onto eyes, brows, lashes, teeth (MPFB interpolates known key names).
    faceservice_mod.MICROSOFT_VISEMES.extend(list(FACE_KEYS.keys()))
    FaceService.interpolate_targets(body)
    delete_helpers(body)
    for o in bpy.data.objects:
        if o.type == "MESH":
            for m in list(o.modifiers):
                if m.type == "SUBSURF":
                    o.modifiers.remove(m)
    # Name body parts the way HumanFigure expects.
    for o in bpy.data.objects:
        n = o.name.lower()
        if o.type != "MESH" or o == body or o.name.startswith("Hair_"):
            continue
        for key, new in (("eyebrow", "Face_brows"), ("eyelash", "Face_lashes"), ("teeth", "Face_teeth"), ("eye", "Face_eyes")):
            if key in n:
                o.name = new
                break
    # Lancer-style gear on top.
    in_p = mat("in_p", (0.24, 0.30, 0.38), 0.0, 0.8)
    in_s = mat("in_s", (0.75, 0.6, 0.25), 0.1, 0.6)
    out_p = mat("out_p", (0.35, 0.33, 0.28), 0.0, 0.85)
    out_s = mat("out_s", (0.55, 0.22, 0.15), 0.1, 0.7)
    hat = mat("hat", (0.3, 0.32, 0.3), 0.2, 0.6)
    accent = mat("accent", (0.3, 0.75, 0.9), 0.4, 0.25)
    scarf = mat("scarf", (0.6, 0.2, 0.15), 0.0, 0.9)
    metal = mat("metal", (0.5, 0.52, 0.55), 0.8, 0.35)
    dark = mat("dark", (0.1, 0.1, 0.11), 0.2, 0.7)
    dom = dominant_bone(body)
    torso = {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"}
    arms = {"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"}
    legs = {"thigh_l", "thigh_r", "calf_l", "calf_r"}
    feet = {"foot_l", "foot_r", "ball_l", "ball_r"}
    shell(body, "Suit", 0.006, torso | arms | legs | {"neck_01"} - {"neck_01"},
          [(in_s, lambda b, c: b in ("clavicle_l", "clavicle_r") or b.startswith("calf")), (in_p, lambda b, c: True)], dom)
    shell(body, "Boots", 0.012, feet | {"calf_l", "calf_r"}, [(dark, lambda b, c: b in feet or c.z < 0.38), (in_p, lambda b, c: True)], dom)
    jacket = shell(body, "Jacket", 0.02, torso | arms, [(out_s, lambda b, c: b.startswith("clavicle")), (out_p, lambda b, c: True)], dom)
    coat = shell(body, "Coat", 0.026, torso | arms | {"thigh_l", "thigh_r"}, [(out_s, lambda b, c: b.startswith("clavicle")), (out_p, lambda b, c: True)], dom)
    # Hands in gloves.
    shell(body, "Gloves", 0.004, {b for b in BONES_SET if b.startswith(("hand", "thumb", "index", "middle", "ring", "pinky"))}, [(dark, lambda b, c: True)], dom)

    def bh(name):
        return rig.matrix_world @ rig.data.bones[name].head_local

    def bt(name):
        return rig.matrix_world @ rig.data.bones[name].tail_local
    H = bh("head") + (bt("head") - bh("head")) * 0.45  # head center
    hr = (bt("head") - bh("head")).length * 0.62
    C = (bh("spine_03") + bt("spine_03")) * 0.5
    N = bh("neck_01")
    rigid = []

    def add(ob, bone):
        rigid.append((ob, bone))
        return ob
    add(join([prim("cube", "chestplate", C + Vector((0, -0.11, 0.0)), (0.16, 0.06, 0.13), out_p, bevel=0.03),
              prim("cube", "backplate", C + Vector((0, 0.11, 0.0)), (0.15, 0.05, 0.15), out_p, bevel=0.03),
              prim("torus", "collar", N + Vector((0, 0, 0.0)), (0.095, 0.095, 0.07), out_s, minor=0.3)], "Hardsuit"), "spine_03")
    add(join([prim("cube", "belt", bh("pelvis") + Vector((0, 0, 0.06)), (0.17, 0.12, 0.035), out_s, bevel=0.01)], "Hardsuit_belt"), "pelvis")
    for s, sfx in ((1, "l"), (-1, "r")):
        add(join([prim("sphere", "pauldron", bh("upperarm_" + sfx) + Vector((0.02 * s, 0, 0.02)), (0.085, 0.085, 0.065), out_s)], "Hardsuit_pauldron_" + sfx), "upperarm_" + sfx)
        k = bh("calf_" + sfx)
        add(join([prim("cube", "knee", k + Vector((0, -0.06, 0)), (0.055, 0.035, 0.07), out_p, bevel=0.015),
                  prim("cube", "shin", k + Vector((0, -0.055, -0.2)), (0.05, 0.03, 0.11), out_p, bevel=0.015)], "Hardsuit_leg_" + sfx), "calf_" + sfx)
        w = (bh("lowerarm_" + sfx) + bh("hand_" + sfx)) * 0.5
        add(join([prim("cyl", "gauntlet", w, (0.05, 0.05, 0.07), out_s, rot=(0, 0, 0))], "Hardsuit_gauntlet_" + sfx), "lowerarm_" + sfx)
    add(join([prim("cone", "poncho", C + Vector((0, 0, -0.08)), (0.32, 0.22, 0.32), out_p, seg=24, top=0.3),
              prim("torus", "hem", C + Vector((0, 0, -0.39)), (0.32, 0.22, 0.3), out_s, minor=0.05)], "Poncho"), "spine_03")
    add(join([prim("cyl", "collar", N + Vector((0, 0, 0.02)), (0.065, 0.06, 0.04), in_p)], "Collar"), "neck_01")
    add(join([prim("torus", "scarf", N + Vector((0, -0.01, 0.0)), (0.085, 0.08, 0.1), scarf, minor=0.35),
              prim("cube", "tail", C + Vector((0.05, -0.12, 0.05)), (0.035, 0.012, 0.12), scarf, rot=(8, 0, 6))], "Scarf"), "neck_01")
    add(join([prim("cone", "shem", N + Vector((0, 0, -0.06)), (0.16, 0.14, 0.09), scarf, seg=18, top=0.55),
              prim("torus", "wrap", N + Vector((0, 0, 0.02)), (0.075, 0.075, 0.1), scarf, minor=0.45)], "Shemagh"), "neck_01")
    hats = {
        "cap": [prim("sphere", "cap", H + Vector((0, 0.0, hr * 0.38)), (hr * 1.08, hr * 1.12, hr * 0.78), hat), prim("cube", "brim", H + Vector((0, -hr * 1.15, hr * 0.25)), (hr * 0.7, hr * 0.5, 0.008), hat, bevel=0.005)],
        "beanie": [prim("sphere", "beanie", H + Vector((0, 0.0, hr * 0.42)), (hr * 1.1, hr * 1.14, hr * 0.95), hat), prim("torus", "cuff", H + Vector((0, 0, hr * 0.1)), (hr * 1.06, hr * 1.12, hr), hat, minor=0.18)],
        "helmet": [prim("sphere", "helmet", H + Vector((0, 0.0, hr * 0.12)), (hr * 1.3, hr * 1.35, hr * 1.33), hat), prim("cube", "visor", H + Vector((0, -hr * 1.18, hr * 0.05)), (hr * 0.95, hr * 0.25, hr * 0.32), accent, bevel=0.012), prim("cyl", "ant", H + Vector((hr * 0.9, hr * 0.5, hr * 1.1)), (0.005, 0.005, 0.07), metal)],
        "headset": [prim("torus", "band", H + Vector((0, 0, hr * 0.5)), (hr * 1.1, hr * 1.1, hr * 1.1), dark, rot=(0, 90, 0), minor=0.05)] + [prim("cyl", "cup", H + Vector((hr * 1.02 * s, 0, -hr * 0.1)), (0.038, 0.038, 0.016), hat, rot=(0, 90, 0)) for s in (1, -1)],
        "hood": [prim("sphere", "hood", H + Vector((0, hr * 0.12, hr * 0.12)), (hr * 1.35, hr * 1.4, hr * 1.45), out_p)],
    }
    for k, v in hats.items():
        add(join(v, "Hat_" + k), "head")
    ey = H + Vector((0, -hr * 0.95, -hr * 0.05))
    glasses = {
        "glasses": [prim("torus", "lens", ey + Vector((0.032 * s, -0.005, 0)), (0.02, 0.02, 0.02), metal, rot=(90, 0, 0), minor=0.12) for s in (1, -1)],
        "visor": [prim("cube", "visor", ey + Vector((0, -0.01, 0)), (hr * 0.85, 0.02, 0.022), accent, bevel=0.008)],
        "goggles": [prim("cyl", "gog", ey + Vector((0.034 * s, -0.01, 0)), (0.026, 0.026, 0.02), accent, rot=(90, 0, 0)) for s in (1, -1)] + [prim("torus", "strap", H + Vector((0, 0, -hr * 0.05)), (hr * 1.04, hr * 1.1, hr), dark, minor=0.05)],
        "eyepatch": [prim("cube", "patch", ey + Vector((-0.032, -0.008, 0)), (0.022, 0.008, 0.018), dark, bevel=0.005)],
    }
    for k, v in glasses.items():
        add(join(v, "Glasses_" + k), "head")
    add(join([prim("cube", "mask", H + Vector((0, -hr * 0.92, -hr * 0.55)), (0.05, 0.03, 0.035), dark, bevel=0.012)] +
             [prim("cyl", "filter", H + Vector((0.04 * s, -hr * 1.05, -hr * 0.6)), (0.02, 0.02, 0.015), metal, rot=(90, 0, 0)) for s in (1, -1)], "Gear_rebreather"), "head")
    add(join([prim("cube", "pack", C + Vector((0, 0.19, -0.05)), (0.12, 0.07, 0.15), out_s, bevel=0.02),
              prim("cyl", "roll", C + Vector((0, 0.18, 0.13)), (0.035, 0.035, 0.12), out_p, rot=(0, 90, 0))], "Gear_pack"), "spine_03")
    add(join([prim("cube", "rifle", C + Vector((0.05, 0.15, -0.1)), (0.025, 0.03, 0.32), dark, rot=(0, 35, 0), bevel=0.006),
              prim("cube", "mag", C + Vector((0.09, 0.13, -0.14)), (0.015, 0.02, 0.05), metal, rot=(0, 35, 0))], "Gear_rifle"), "spine_03")
    add(join([prim("cube", "tag", C + Vector((0, -0.115, 0.05)), (0.012, 0.003, 0.018), metal)], "Gear_tags"), "spine_03")
    for ob, bone in rigid:
        bone_parent(ob, rig, bone)
    animations(rig)
    # Textures at 1024 px at most (faces still hold up at 1.25 m; keeps each glb small).
    for img in bpy.data.images:
        if img.size[0] > 1024:
            k = 1024.0 / img.size[0]
            img.scale(1024, max(1, int(img.size[1] * k)))
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "human_%s.glb" % GENDER)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_morph=True, export_skins=True, export_apply=False, export_yup=True, export_image_format="AUTO")
    tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print("EXPORTED", out, "faces:", tris, "keys:", [k.name for k in body.data.shape_keys.key_blocks][:30])


main()
