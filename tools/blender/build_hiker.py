"""Build the Snow Shelter hiker (char_survivor.glb) procedurally in Blender 4.x.

Run:  blender --background --python tools/blender/build_hiker.py -- assets/models/char_survivor.glb

Low-poly (~2k tris) survivor: brown hooded parka, dark trousers, boots, mitts, red backpack with a
yellow sleeping pad, black/white banded avalanche probe in the right hand.
Rigid skinning: every part is weighted 100 % to one bone (robust, no weight painting).
Actions: Idle-loop, Walk-loop, Probe, Dig-loop.  Character faces -Y in Blender (= +Z in Godot).
"""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "char_survivor.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30

# ---------------------------------------------------------------- materials
def mat(name, rgb, rough=0.85):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    return m

M = {
    "coat": mat("Coat", (0.36, 0.25, 0.14)),
    "hood": mat("Hood", (0.28, 0.19, 0.11)),
    "fur": mat("Fur", (0.80, 0.74, 0.62), 1.0),
    "pants": mat("Pants", (0.11, 0.12, 0.15)),
    "boot": mat("Boot", (0.07, 0.06, 0.06)),
    "mitt": mat("Mitt", (0.55, 0.12, 0.08)),
    "face": mat("Face", (0.55, 0.38, 0.28)),
    "pack": mat("Pack", (0.72, 0.12, 0.08), 0.7),
    "strap": mat("Strap", (0.12, 0.10, 0.09)),
    "pad": mat("Pad", (0.90, 0.68, 0.12), 0.6),
    "white": mat("ProbeWhite", (0.88, 0.88, 0.86), 0.5),
    "black": mat("ProbeBlack", (0.05, 0.05, 0.06), 0.5),
}

# ---------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new("HikerRig")
rig = bpy.data.objects.new("Hiker", arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones

def bone(name, head, tail, parent=None):
    b = eb.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent:
        b.parent = eb[parent]
    return b

bone("hips", (0, 0, 0.92), (0, 0, 1.02))
bone("chest", (0, 0, 1.02), (0, 0, 1.42), "hips")
bone("head", (0, 0, 1.45), (0, 0, 1.72), "chest")
for s, x in (("L", 1), ("R", -1)):
    bone(f"upper_arm.{s}", (0.22 * x, 0, 1.38), (0.26 * x, 0, 1.10), "chest")
    bone(f"forearm.{s}", (0.26 * x, 0, 1.10), (0.27 * x, -0.02, 0.86), f"upper_arm.{s}")
    bone(f"thigh.{s}", (0.10 * x, 0, 0.92), (0.10 * x, 0, 0.50), "hips")
    bone(f"shin.{s}", (0.10 * x, 0, 0.50), (0.10 * x, 0, 0.08), f"thigh.{s}")
# 探针杆独立骨骼（挂在 hips 下），避免手臂摆动时 1.8 m 的杆子扫过全身
bone("probe", (-0.28, -0.05, 0.10), (-0.28, -0.05, 1.86), "hips")
bpy.ops.object.mode_set(mode="OBJECT")

# ---------------------------------------------------------------- mesh building
# 每个部件单独成对象（整个对象 100% 绑定到一根骨骼），最后 join：Blender 按组名合并顶点组，
# 不依赖顶点索引顺序（之前按索引分组导致权重错位、动作时拉出长三角）。
part_objects = []

def add_part(geom_fn, material, bone_name):
    bm = bmesh.new()
    geom_fn(bm)
    me_ = bpy.data.meshes.new(f"part_{len(part_objects)}")
    bm.to_mesh(me_)
    bm.free()
    o = bpy.data.objects.new(me_.name, me_)
    scene.collection.objects.link(o)
    me_.materials.append(M[material])
    vg = o.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(me_.vertices))), 1.0, "REPLACE")
    part_objects.append(o)

def cyl(center, r1, r2, h, segs=8, rot=None):
    def fn(bm):
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=h)
        m = Matrix.Translation(Vector(center))
        if rot:
            m = m @ rot
        bmesh.ops.transform(bm, matrix=m, verts=res["verts"])
    return fn

def box(center, size):
    def fn(bm):
        res = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=res["verts"])
        bmesh.ops.translate(bm, vec=Vector(center), verts=res["verts"])
    return fn

def sphere(center, r, scale=(1, 1, 1), segs=10, rings=6):
    def fn(bm):
        res = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
        bmesh.ops.scale(bm, vec=Vector(scale), verts=res["verts"])
        bmesh.ops.translate(bm, vec=Vector(center), verts=res["verts"])
    return fn

def seg_cyl(a, b, r1, r2, segs=8):
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    return cyl(((a + b) / 2), r1, r2, d.length, segs, rot)

# torso / parka (slightly A-line), hips
add_part(cyl((0, 0, 1.18), 0.25, 0.19, 0.56, 10), "coat", "chest")
add_part(cyl((0, 0, 0.90), 0.21, 0.24, 0.20, 10), "coat", "hips")
# hood, fur ruff, face
add_part(sphere((0, 0.02, 1.58), 0.16, (1.0, 1.05, 1.12)), "hood", "head")
add_part(cyl((0, -0.09, 1.57), 0.12, 0.12, 0.05, 12, Matrix.Rotation(math.radians(90), 4, "X")), "fur", "head")
add_part(sphere((0, -0.10, 1.57), 0.085, (1, 0.5, 1.1), 8, 5), "face", "head")
# arms + mitts
for s, x in (("L", 1), ("R", -1)):
    add_part(seg_cyl((0.22 * x, 0, 1.38), (0.26 * x, 0, 1.10), 0.075, 0.065), "coat", f"upper_arm.{s}")
    add_part(seg_cyl((0.26 * x, 0, 1.10), (0.27 * x, -0.02, 0.88), 0.065, 0.055), "coat", f"forearm.{s}")
    add_part(sphere((0.27 * x, -0.03, 0.84), 0.055, (1, 1.1, 1.2), 8, 5), "mitt", f"forearm.{s}")
    add_part(seg_cyl((0.10 * x, 0, 0.92), (0.10 * x, 0, 0.50), 0.095, 0.08), "pants", f"thigh.{s}")
    add_part(seg_cyl((0.10 * x, 0, 0.50), (0.10 * x, 0, 0.10), 0.075, 0.07), "pants", f"shin.{s}")
    add_part(box((0.10 * x, -0.04, 0.05), (0.12, 0.26, 0.10)), "boot", f"shin.{s}")
# backpack on the back (+Y), straps, sleeping pad on top
add_part(box((0, 0.24, 1.17), (0.40, 0.22, 0.56)), "pack", "chest")
add_part(box((0, 0.36, 1.08), (0.30, 0.06, 0.26)), "pack", "chest")
for x in (-0.13, 0.13):
    add_part(box((x, -0.02, 1.25), (0.05, 0.40, 0.04)), "strap", "chest")
add_part(cyl((0, 0.24, 1.52), 0.08, 0.08, 0.52, 10, Matrix.Rotation(math.radians(90), 4, "Y")), "pad", "chest")
# avalanche probe in the right hand (banded)
for i in range(8):
    z0 = 0.10 + i * 0.22
    add_part(cyl((-0.28, -0.05, z0 + 0.11), 0.017, 0.017, 0.22, 6), "white" if i % 2 == 0 else "black", "probe")

bpy.ops.object.select_all(action="DESELECT")
for o in part_objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = part_objects[0]
bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
obj.name = "HikerMesh"
me = obj.data
for p in me.polygons:
    p.use_smooth = False

obj.parent = rig
mod = obj.modifiers.new("Armature", "ARMATURE")
mod.object = rig

# ---------------------------------------------------------------- animation
pb = rig.pose.bones
for b in pb:
    b.rotation_mode = "XYZ"

def key(action_name, frames, fn, loop=True):
    act = bpy.data.actions.new(action_name)
    rig.animation_data_create()
    rig.animation_data.action = act
    for f in frames:
        for b in pb:
            b.rotation_euler = (0, 0, 0)
            b.location = (0, 0, 0)
        fn(f)
        for b in pb:
            b.keyframe_insert("rotation_euler", frame=f)
            b.keyframe_insert("location", frame=f)
    act.use_fake_user = True
    track = rig.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, int(frames[0]), act)
    rig.animation_data.action = None
    return act

R = math.radians

def idle(f):
    t = f / 60.0 * 2 * math.pi
    pb["chest"].rotation_euler = (R(2) * math.sin(t), 0, 0)
    pb["upper_arm.L"].rotation_euler = (0, 0, R(6))
    pb["upper_arm.R"].rotation_euler = (0, 0, R(-6))

def walk(f):
    t = f / 30.0 * 2 * math.pi
    s = math.sin(t)
    pb["thigh.L"].rotation_euler = (R(28) * s, 0, 0)
    pb["thigh.R"].rotation_euler = (R(-28) * s, 0, 0)
    pb["shin.L"].rotation_euler = (R(-30) * max(0.0, -s), 0, 0)
    pb["shin.R"].rotation_euler = (R(-30) * max(0.0, s), 0, 0)
    pb["upper_arm.L"].rotation_euler = (R(-22) * s, 0, R(6))
    pb["upper_arm.R"].rotation_euler = (R(22) * s, 0, R(-6))
    pb["chest"].rotation_euler = (R(8), 0, R(4) * s)   # 顶风前倾
    pb["hips"].location = (0, 0.03 * abs(math.cos(t)), 0)

def probe(f):
    t = min(f / 20.0, 1.0)
    thrust = math.sin(t * math.pi)
    pb["chest"].rotation_euler = (R(25) * t, 0, 0)
    pb["upper_arm.R"].rotation_euler = (R(-20) * t, 0, R(-6))
    pb["upper_arm.L"].rotation_euler = (R(-30) * t, 0, R(10))
    pb["thigh.L"].rotation_euler = (R(-25) * t, 0, 0)
    pb["thigh.R"].rotation_euler = (R(-25) * t, 0, 0)
    pb["shin.L"].rotation_euler = (R(40) * t, 0, 0)
    pb["shin.R"].rotation_euler = (R(40) * t, 0, 0)
    pb["hips"].location = (0, -0.10 * t, 0)
    pb["probe"].location = (0, -0.35 * thrust, 0)

def dig(f):
    t = f / 30.0 * 2 * math.pi
    s = math.sin(t)
    pb["chest"].rotation_euler = (R(35) + R(12) * s, 0, 0)
    pb["upper_arm.R"].rotation_euler = (R(-50) + R(30) * s, 0, R(-8))
    pb["upper_arm.L"].rotation_euler = (R(-50) + R(30) * s, 0, R(8))
    pb["forearm.R"].rotation_euler = (R(-20), 0, 0)
    pb["forearm.L"].rotation_euler = (R(-20), 0, 0)
    pb["probe"].location = (0, -0.25, 0)
    pb["thigh.L"].rotation_euler = (R(-30), 0, 0)
    pb["thigh.R"].rotation_euler = (R(-10), 0, 0)
    pb["shin.L"].rotation_euler = (R(45), 0, 0)
    pb["shin.R"].rotation_euler = (R(20), 0, 0)
    pb["hips"].location = (0, -0.10, 0)

def chop(f):
    # 双手举过头顶向前下劈（斧 / 断枝），30 帧一循环
    t = f / 30.0 * 2 * math.pi
    swing = 0.5 - 0.5 * math.cos(t)          # 0 举起 → 1 劈下
    pb["chest"].rotation_euler = (R(-8) + R(30) * swing, 0, 0)
    pb["upper_arm.R"].rotation_euler = (R(-150) + R(120) * swing, 0, R(-6))
    pb["upper_arm.L"].rotation_euler = (R(-150) + R(120) * swing, 0, R(6))
    pb["forearm.R"].rotation_euler = (R(-20) * (1 - swing), 0, 0)
    pb["forearm.L"].rotation_euler = (R(-20) * (1 - swing), 0, 0)
    pb["thigh.L"].rotation_euler = (R(-15), 0, 0)
    pb["shin.L"].rotation_euler = (R(15), 0, 0)
    pb["hips"].location = (0, -0.04 * swing, 0)

key("Idle-loop", [0, 15, 30, 45, 60], idle)
key("Walk-loop", list(range(0, 31, 5)), walk)
key("Probe", [0, 5, 10, 15, 20, 25], probe, loop=False)
key("Dig-loop", list(range(0, 31, 5)), dig)
key("Chop-loop", list(range(0, 31, 5)), chop)

# ---------------------------------------------------------------- export
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format="GLB", use_selection=True,
    export_animations=True, export_animation_mode="NLA_TRACKS",
    export_apply=False, export_skins=True, export_yup=True,
)
tris = sum(len(p.vertices) - 2 for p in me.polygons)
print("EXPORTED", OUT, "tris", tris, "verts", len(me.vertices))

# 注：chest 骨朝上，绕 X 正转 = 前倾；手臂 / 大腿骨朝下，绕 X 负转 = 向前。
# 可选：渲染姿势检查图（--preview <dir>）
if "--preview" in sys.argv:
    outdir = sys.argv[sys.argv.index("--preview") + 1]
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 480
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, loc in (("side", (3.2, 0, 1.0)), ("front", (0.6, -3.2, 1.0))):
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 0.9)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        for act_name, frame in (("Idle-loop", 0), ("Walk-loop", 8), ("Probe", 10), ("Dig-loop", 8), ("Chop-loop", 0), ("Chop-loop", 15)):
            rig.animation_data.action = bpy.data.actions[act_name]
            for tr in rig.animation_data.nla_tracks:
                tr.mute = True
            scene.frame_set(frame)
            scene.render.filepath = f"{outdir}/b_{view}_{act_name}_{frame}.png"
            bpy.ops.render.render(write_still=True)
