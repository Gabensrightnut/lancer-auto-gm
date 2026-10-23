"""Soldiers for LANCER TTRPG: one light MakeHuman/MPFB2 base soldier (CC0 base mesh and skin,
see CREDITS.md) with our own Lancer-style military gear, sharing the people rig and animations
(tools/blender/people_mh.py) plus fire, cover and down. Built light for squads of ten: no face
keys, no hair, the body decimated and painted as a uniform (no cloth shells), 512 px textures.

Gear, one set per faction (shown/hidden and recolored in game by SoldierFigure from
data/game/soldiers.json): Helmet_<faction>, Armor_<faction>; Weapon_rifle in the right hand,
Weapon_launcher on the shoulder, Gear_pack. Material names are roles the game recolors:
uniform, armor, trim, skin, dark, metal, visor.

Needs MPFB2 (A:\\tools\\mpfb, see CREDITS.md):
  set BLENDER_USER_RESOURCES=A:\\tools\\mpfb\\blender_user
  blender --background --python tools/blender/soldier_mh.py -- assets/people male
Blender space: the figure faces -Y, Z up.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
from mathutils import Vector  # noqa: E402

import people_mh as P  # noqa: E402

FACTIONS = ["union", "corpro", "pirate", "militia"]
BODY_TRIS = 3600


def flatten_keys(ob):
    if ob.data.shape_keys:
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)


def decimate(ob, tris):
    """Collapse the body to about `tris` triangles (weights and UVs carry over)."""
    now = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if now <= tris:
        return
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new("lite", "DECIMATE")
    m.ratio = tris / now
    bpy.ops.object.modifier_move_to_index(modifier="lite", index=0)
    bpy.ops.object.modifier_apply(modifier="lite")


def paint_uniform(body, dom, skin_mat, uniform, dark):
    """The body as a soldier in uniform: skin on the head and neck, gloves and boots dark, the
    rest uniform cloth, by each face's dominant bone."""
    mats = [skin_mat, uniform, dark]
    body.data.materials.clear()
    for m in mats:
        body.data.materials.append(m)
    for p in body.data.polygons:
        bones = [dom.get(v, "") for v in p.vertices]
        b = max(set(bones), key=bones.count)
        if b in ("head", "neck_01") or b.startswith(("eye", "jaw", "tongue", "teeth")):
            p.material_index = 0
        elif b.startswith(("hand", "thumb", "index", "middle", "ring", "pinky", "foot", "ball")):
            p.material_index = 2
        else:
            p.material_index = 1


def extra_animations(rig):
    """Fire (the aim pose with recoil), cover (kneeling, rifle up), on top of the people set."""
    ARM = P.ARM
    aim = {"upperarm.R": (80, ARM + 20, 0), "forearm.R": (40, 0, 0), "upperarm.L": (70, ARM + 10, 0), "forearm.L": (25, 0, 0),
           "chest": (0, 0, -15), "head": (0, 0, 10), "spine": (-5, 0, 0)}
    keys = {k: [(0, v), (12, v)] for k, v in aim.items()}
    keys["chest"] = [(0, (0, 0, -15)), (2, (-6, 0, -15)), (5, (0, 0, -15)), (7, (-6, 0, -15)), (12, (0, 0, -15))]
    P.pose_action(rig, "fire", 12, keys)
    kneel = dict((k, [(0, v)]) for k, v in aim.items())
    kneel.update({"thigh.L": [(0, (85, 0, 0))], "shin.L": [(0, (-85, 0, 0))], "thigh.R": [(0, (5, 0, 0))], "shin.R": [(0, (-105, 0, 0))],
                  "spine": [(0, (12, 0, 0))]})
    P.pose_action(rig, "cover", 2, kneel, root=[(0, (0, 0, -0.42))])


def main():
    P.clear_scene()
    body = P.make_body(P.GENDER_MACRO)
    body.name = "Body"
    rig = P.HumanService.add_builtin_rig(body, "game_engine", import_weights=True)
    rig.name = "Rig"
    P.BONES_SET.update(b.name for b in rig.data.bones)
    skin = "young_caucasian_male"
    P.HumanService.set_character_skin(P.asset("skins", skin, "mhmat"), body, skin_type="MAKESKIN")
    eyes = P.asset("eyes", "low-poly")
    if eyes:
        P.HumanService.add_mhclo_asset(eyes, body, asset_type="Eyes", subdiv_levels=0, material_type="MAKESKIN")
    P.delete_helpers(body)
    for o in bpy.data.objects:
        if o.type == "MESH":
            for m in list(o.modifiers):
                if m.type == "SUBSURF":
                    o.modifiers.remove(m)
            if o != body and "eye" in o.name.lower():
                o.name = "Face_eyes"
    flatten_keys(body)
    decimate(body, BODY_TRIS)

    uniform = P.mat("uniform", (0.32, 0.36, 0.3), 0.0, 0.85)
    armor = P.mat("armor", (0.42, 0.45, 0.48), 0.25, 0.5)
    trim = P.mat("trim", (0.75, 0.6, 0.25), 0.2, 0.5)
    dark = P.mat("dark", (0.09, 0.09, 0.1), 0.2, 0.7)
    metal = P.mat("metal", (0.45, 0.47, 0.5), 0.8, 0.35)
    visor = P.mat("visor", (0.2, 0.7, 0.85), 0.4, 0.2)
    cloth = P.mat("cloth", (0.5, 0.18, 0.14), 0.0, 0.9)
    skin_mat = body.data.materials[0] if body.data.materials else P.mat("skin", (0.7, 0.55, 0.45), 0.0, 0.6)
    dom = P.dominant_bone(body)
    paint_uniform(body, dom, skin_mat, uniform, dark)

    def bh(name):
        return rig.matrix_world @ rig.data.bones[name].head_local

    def bt(name):
        return rig.matrix_world @ rig.data.bones[name].tail_local
    H = bh("head") + (bt("head") - bh("head")) * 0.45
    hr = (bt("head") - bh("head")).length * 0.62
    C = (bh("spine_03") + bt("spine_03")) * 0.5
    N = bh("neck_01")
    rigid = []

    def add(ob, bone):
        rigid.append((ob, bone))
        return ob
    prim = P.prim
    lo = dict(seg=12, rings=8)

    # Helmets, one per faction.
    add(P.join([prim("sphere", "shell", H + Vector((0, 0.005, hr * 0.15)), (hr * 1.3, hr * 1.36, hr * 1.3), armor, **lo),
                prim("cube", "visor", H + Vector((0, -hr * 1.16, hr * 0.02)), (hr * 1.0, hr * 0.22, hr * 0.36), visor, bevel=0.01),
                prim("cube", "ridge", H + Vector((0, 0, hr * 1.35)), (hr * 0.18, hr * 1.1, hr * 0.12), trim, bevel=0.006)], "Helmet_union"), "head")
    add(P.join([prim("sphere", "shell", H + Vector((0, 0, hr * 0.08)), (hr * 1.25, hr * 1.32, hr * 1.38), armor, **lo),
                prim("cube", "faceplate", H + Vector((0, -hr * 1.12, -hr * 0.2)), (hr * 0.95, hr * 0.3, hr * 0.85), dark, bevel=0.015),
                prim("cube", "slit", H + Vector((0, -hr * 1.27, hr * 0.08)), (hr * 0.8, hr * 0.08, hr * 0.12), visor, bevel=0.004)], "Helmet_corpro"), "head")
    add(P.join([prim("sphere", "wrap", H + Vector((0, 0.01, hr * 0.38)), (hr * 1.12, hr * 1.16, hr * 0.8), cloth, **lo),
                prim("cube", "tail", H + Vector((0, hr * 1.05, hr * 0.1)), (hr * 0.3, hr * 0.12, hr * 0.7), cloth, rot=(20, 0, 0)),
                prim("cyl", "goggle", H + Vector((hr * 0.36, -hr * 0.98, hr * 0.12)), (hr * 0.28, hr * 0.28, hr * 0.15), visor, rot=(90, 0, 0), seg=10),
                prim("cyl", "goggle2", H + Vector((-hr * 0.36, -hr * 0.98, hr * 0.12)), (hr * 0.28, hr * 0.28, hr * 0.15), visor, rot=(90, 0, 0), seg=10)], "Helmet_pirate"), "head")
    add(P.join([prim("sphere", "crown", H + Vector((0, 0, hr * 0.5)), (hr * 1.1, hr * 1.14, hr * 0.75), uniform, **lo),
                prim("cyl", "brim", H + Vector((0, 0, hr * 0.42)), (hr * 1.75, hr * 1.75, hr * 0.06), uniform, seg=16)], "Helmet_militia"), "head")

    # Body armor, one set per faction.
    def plates(name, chest, back, pads, knees, extra=()):
        parts = [prim("cube", "chest", C + Vector((0, -0.105, 0.0)), chest, armor, bevel=0.025),
                 prim("cube", "back", C + Vector((0, 0.105, 0.0)), back, armor, bevel=0.025)] + list(extra)
        ob = add(P.join(parts, name), "spine_03")
        for s, sfx in ((1, "l"), (-1, "r")):
            if pads:
                add(P.join([prim("sphere", "pad", bh("upperarm_" + sfx) + Vector((0.025 * s, 0, 0.025)), pads, armor, **lo)], name + "_pad_" + sfx), "upperarm_" + sfx)
            if knees:
                k = bh("calf_" + sfx)
                add(P.join([prim("cube", "knee", k + Vector((0, -0.06, 0)), knees, armor, bevel=0.012)], name + "_knee_" + sfx), "calf_" + sfx)
        return ob
    plates("Armor_union", (0.16, 0.06, 0.14), (0.15, 0.05, 0.15), (0.085, 0.085, 0.06), (0.05, 0.035, 0.06),
           [prim("cube", "stripe", C + Vector((0, -0.17, 0.06)), (0.12, 0.008, 0.02), trim)])
    plates("Armor_corpro", (0.15, 0.055, 0.15), (0.14, 0.045, 0.14), (0.075, 0.075, 0.07), (0.045, 0.03, 0.055),
           [prim("torus", "collar", N, (0.095, 0.095, 0.06), dark, minor=0.3)])
    plates("Armor_pirate", (0.12, 0.05, 0.1), (0.1, 0.04, 0.12), None, None,
           [prim("cube", "strap", C + Vector((0, -0.13, 0.0)), (0.025, 0.01, 0.2), dark, rot=(0, 30, 0)),
            prim("sphere", "pad", bh("upperarm_l") + Vector((0.03, 0, 0.03)), (0.09, 0.09, 0.07), metal, **lo)])
    plates("Armor_militia", (0.15, 0.06, 0.13), (0.14, 0.05, 0.14), None, None,
           [prim("cube", "pouch%d" % i, C + Vector((-0.08 + i * 0.055, -0.17, -0.07)), (0.022, 0.018, 0.03), uniform, bevel=0.004) for i in range(4)])

    # Weapons and pack.
    hand = bh("hand_r")
    fore = (bh("hand_r") - bh("lowerarm_r")).normalized()
    # Along the forearm (a Y-long box: Rx(pitch) then Rz(yaw) turns +Y onto `fore`).
    yaw = math.degrees(math.atan2(-fore.x, fore.y))
    pitch = math.degrees(math.asin(max(-1.0, min(1.0, fore.z))))
    add(P.join([prim("cube", "body", hand + fore * 0.12, (0.02, 0.2, 0.035), dark, rot=(pitch, 0, yaw), bevel=0.005),
                prim("cube", "mag", hand + fore * 0.08 + Vector((0, 0, -0.04)), (0.014, 0.02, 0.04), metal, rot=(pitch, 0, yaw)),
                prim("cyl", "barrel", hand + fore * 0.34, (0.009, 0.009, 0.08), metal, rot=(pitch - 90, 0, yaw), seg=8)], "Weapon_rifle"), "hand_r")
    sh = bh("clavicle_r")
    add(P.join([prim("cyl", "tube", sh + Vector((-0.02, 0.0, 0.08)), (0.045, 0.045, 0.32), dark, rot=(90, 0, 0), seg=10),
                prim("cyl", "mouth", sh + Vector((-0.02, -0.33, 0.08)), (0.05, 0.05, 0.02), metal, rot=(90, 0, 0), seg=10)], "Weapon_launcher"), "spine_03")
    add(P.join([prim("cube", "pack", C + Vector((0, 0.18, -0.03)), (0.11, 0.06, 0.14), uniform, bevel=0.015),
                prim("cyl", "roll", C + Vector((0, 0.17, 0.13)), (0.03, 0.03, 0.11), dark, rot=(0, 90, 0), seg=10)], "Gear_pack"), "spine_03")
    for ob, bone in rigid:
        P.bone_parent(ob, rig, bone)

    P.animations(rig)
    extra_animations(rig)
    for img in bpy.data.images:
        if img.size[0] > 512:
            k = 512.0 / img.size[0]
            img.scale(512, max(1, int(img.size[1] * k)))
    os.makedirs(P.OUT_DIR, exist_ok=True)
    out = os.path.join(P.OUT_DIR, "soldier.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_morph=False, export_skins=True, export_apply=False, export_yup=True,
                              export_image_format="WEBP", export_image_quality=80)
    tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print("EXPORTED", out, "faces:", tris, "body:", len(body.data.polygons))


if __name__ == "__main__":
    main()
