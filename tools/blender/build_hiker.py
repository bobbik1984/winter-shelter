"""Build the Snow Shelter hiker (char_survivor.glb) procedurally in Blender 4.x.

Run:  blender --background --python tools/blender/build_hiker.py -- assets/models/char_survivor.glb

v2 (2026-11-07): lofted, bevelled, smooth-shaded survivor (~9k tris) in the north-star palette (bright enough to read backlit — the game camera faces the afternoon sun):
olive parka with a fur-ruffed hood, goggles and neck gaiter, chest pockets and zip, snow pants with
knee pads and gaiters, leather boots with soles, mitts with thumbs; red expedition pack with lid,
front pocket, compression straps, shoulder straps and hip belt, a strapped shovel blade and a
rolled sleeping pad; black/white banded avalanche probe in the right hand.
Rigid skinning: every part is weighted 100 % to one bone (robust, no weight painting).
Actions: Idle-loop, Walk-loop (v4 gait: planted stance, soft knee under the pack, visible knee lift), Probe, Dig-loop, Chop-loop.  Character faces -Y in Blender (= +Z in Godot).
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
    m.diffuse_color = (*rgb, 1.0)   # 预览（Workbench）用
    return m

M = {
    "coat": mat("Coat", (0.40, 0.42, 0.28)),
    "coat_dark": mat("CoatDark", (0.20, 0.22, 0.15)),
    "fur": mat("Fur", (0.85, 0.78, 0.64), 1.0),
    "pants": mat("Pants", (0.13, 0.14, 0.17)),
    "gaiter": mat("Gaiter", (0.07, 0.07, 0.08)),
    "boot": mat("Boot", (0.30, 0.17, 0.08), 0.7),
    "sole": mat("Sole", (0.02, 0.02, 0.02), 0.9),
    "mitt": mat("Mitt", (0.10, 0.09, 0.08)),
    "face": mat("Face", (0.52, 0.32, 0.22), 0.8),
    "lens": mat("Lens", (0.10, 0.20, 0.26), 0.15),
    "scarf": mat("Scarf", (0.33, 0.07, 0.05)),
    "pack": mat("Pack", (0.80, 0.13, 0.06), 0.7),
    "pack_dark": mat("PackDark", (0.45, 0.07, 0.04), 0.7),
    "strap": mat("Strap", (0.03, 0.03, 0.03)),
    "pad": mat("Pad", (0.80, 0.42, 0.06), 0.6),
    "metal": mat("Metal", (0.16, 0.17, 0.19), 0.45),
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

def add_part(geom_fn, material, bone_name, smooth=True):
    bm = bmesh.new()
    geom_fn(bm)
    for f in bm.faces:
        f.smooth = smooth
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

# ---------------------------------------------------------------- v2 shape helpers
def _ring(bm, z, rx, ry, segs, cx=0.0, cy=0.0, noise=0.0, seed=0):
    vs = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        n = 1.0 + noise * math.sin(a * 7 + seed) * math.cos(a * 3 + seed * 1.7)
        vs.append(bm.verts.new((cx + math.cos(a) * rx * n, cy + math.sin(a) * ry * n, z)))
    return vs

def loft(rings, segs=16, cap0=True, cap1=True, matrix=None):
    """rings: [(z, rx, ry[, cx, cy])] bottom→top; elliptical tube with optional caps."""
    def fn(bm):
        rs = [_ring(bm, r[0], r[1], r[2], segs, r[3] if len(r) > 3 else 0.0, r[4] if len(r) > 4 else 0.0) for r in rings]
        for k in range(len(rs) - 1):
            lo, hi = rs[k], rs[k + 1]
            for i in range(segs):
                j = (i + 1) % segs
                bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        if cap0:
            bm.faces.new(list(reversed(rs[0])))
        if cap1:
            bm.faces.new(rs[-1])
        if matrix is not None:
            bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return fn

def limb(a, b, prof, segs=12):
    """Tapered tube from a to b; prof = [(t, rx, ry)] along the segment."""
    a, b = Vector(a), Vector(b)
    d = b - a
    m = Matrix.Translation(a) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    return loft([(t * d.length, rx, ry) for t, rx, ry in prof], segs, matrix=m)

def rbox(center, size, bevel=0.02, segs=2):
    def fn(bm):
        res = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=res["verts"])
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=segs,
                        affect="EDGES", profile=0.5)
        bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return fn

def ellipsoid(center, radii, segs=14, rings=9):
    def fn(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
        bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return fn

def torus_xz(center, rx, rz, minor, segs=22, msegs=6, noise=0.0):
    """Ring in the XZ plane (faces -Y): the hood's fur ruff."""
    def fn(bm):
        rings = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            n = 1.0 + noise * math.sin(a * 9.0) * 0.8 + noise * math.cos(a * 5.0 + 1.3)
            c = Vector((math.cos(a) * rx, 0.0, math.sin(a) * rz))
            out = Vector((math.cos(a), 0.0, math.sin(a)))
            ring = []
            for k in range(msegs):
                b = 2 * math.pi * k / msegs
                p = c + (out * math.cos(b) + Vector((0, -1, 0)) * math.sin(b)) * minor * n
                ring.append(bm.verts.new(Vector(center) + p))
            rings.append(ring)
        for i in range(segs):
            j = (i + 1) % segs
            for k in range(msegs):
                l = (k + 1) % msegs
                bm.faces.new((rings[i][k], rings[j][k], rings[j][l], rings[i][l]))
    return fn

def hood(center, radii, open_y):
    """Hood shell: an ellipsoid with the face opening cut out (faces whose centre is in front of open_y)."""
    def fn(bm):
        bmesh.ops.create_uvsphere(bm, u_segments=18, v_segments=12, radius=1.0)
        bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
        bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
        cut = [f for f in bm.faces if f.calc_center_median().y < open_y and abs(f.calc_center_median().z - center[2]) < radii[2] * 0.8]
        bmesh.ops.delete(bm, geom=cut, context="FACES")
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.012)
    return fn

# ---------------------------------------------------------------- v2 body
# 裤子与骨盆（hips 骨）：雪裤 + 腰带 + 外套下摆（下摆跟 hips 走，弯腰时不会穿模）
add_part(loft([(0.80, 0.155, 0.115), (0.92, 0.175, 0.125), (1.02, 0.17, 0.12)], 16), "pants", "hips")
add_part(loft([(0.86, 0.222, 0.168), (0.93, 0.212, 0.160), (1.05, 0.205, 0.152)], 18, cap0=False, cap1=False), "coat", "hips")
add_part(loft([(0.855, 0.226, 0.171), (0.875, 0.226, 0.171)], 18, cap0=False, cap1=False), "coat_dark", "hips")
add_part(loft([(0.965, 0.224, 0.170), (1.005, 0.224, 0.170)], 18, cap0=False, cap1=False), "strap", "hips")   # 背包腰带
for x in (-1, 1):
    add_part(rbox((0.15 * x, -0.135, 0.985), (0.07, 0.04, 0.05), 0.012), "metal" if x > 0 else "strap", "hips")

# 外套上身（chest 骨）：胸宽、收腰、肩线；拉链 + 两个胸袋 + 肩头
add_part(loft([(1.00, 0.205, 0.152), (1.12, 0.212, 0.155), (1.25, 0.226, 0.162), (1.35, 0.228, 0.160),
               (1.42, 0.205, 0.150), (1.47, 0.12, 0.105)], 20), "coat", "chest")
add_part(rbox((0, -0.158, 1.18), (0.022, 0.012, 0.56), 0.004, 1), "coat_dark", "chest", smooth=False)
for x in (-1, 1):
    add_part(rbox((0.095 * x, -0.160, 1.26), (0.085, 0.022, 0.095), 0.01), "coat_dark", "chest")
    add_part(ellipsoid((0.205 * x, 0.0, 1.375), (0.095, 0.098, 0.088)), "coat", "chest")

# 手臂：上臂 + 肘 + 前臂 + 袖口 + 连指手套（带拇指）
for s, x in (("L", 1), ("R", -1)):
    add_part(limb((0.215 * x, 0, 1.38), (0.255 * x, 0, 1.11), [(0, 0.085, 0.087), (0.5, 0.079, 0.081), (1, 0.069, 0.071)]), "coat", f"upper_arm.{s}")
    add_part(ellipsoid((0.255 * x, 0, 1.11), (0.069, 0.071, 0.069), 12, 8), "coat", f"upper_arm.{s}")
    add_part(limb((0.255 * x, 0, 1.11), (0.268 * x, -0.02, 0.90), [(0, 0.069, 0.071), (0.75, 0.06, 0.063), (1, 0.056, 0.059)]), "coat", f"forearm.{s}")
    add_part(limb((0.266 * x, -0.017, 0.93), (0.268 * x, -0.02, 0.895), [(0, 0.064, 0.066), (1, 0.064, 0.066)]), "coat_dark", f"forearm.{s}")
    add_part(ellipsoid((0.27 * x, -0.03, 0.845), (0.047, 0.055, 0.068), 12, 8), "mitt", f"forearm.{s}")
    add_part(ellipsoid((0.245 * x, -0.07, 0.87), (0.02, 0.026, 0.035), 8, 6), "mitt", f"forearm.{s}")

# 腿：大腿 + 护膝 + 小腿 + 雪套 + 皮靴（鞋底、鞋头）
for s, x in (("L", 1), ("R", -1)):
    add_part(limb((0.10 * x, 0, 0.95), (0.105 * x, -0.01, 0.50), [(0, 0.10, 0.105), (0.5, 0.09, 0.095), (1, 0.074, 0.08)]), "pants", f"thigh.{s}")
    add_part(ellipsoid((0.105 * x, -0.055, 0.52), (0.062, 0.035, 0.065), 10, 7), "coat_dark", f"thigh.{s}")
    add_part(limb((0.105 * x, -0.01, 0.50), (0.10 * x, 0, 0.13), [(0, 0.074, 0.08), (0.4, 0.07, 0.074), (1, 0.064, 0.068)]), "pants", f"shin.{s}")
    add_part(limb((0.10 * x, -0.002, 0.33), (0.10 * x, 0, 0.11), [(0, 0.074, 0.078), (1, 0.074, 0.078)]), "gaiter", f"shin.{s}")
    add_part(rbox((0.10 * x, -0.04, 0.075), (0.115, 0.25, 0.11), 0.035), "boot", f"shin.{s}")
    add_part(ellipsoid((0.10 * x, -0.15, 0.06), (0.058, 0.06, 0.05), 10, 6), "boot", f"shin.{s}")
    add_part(rbox((0.10 * x, -0.045, 0.016), (0.128, 0.29, 0.032), 0.012), "sole", f"shin.{s}")

# 头：脸 + 护目镜（镜片 + 绑带）+ 脖套 + 兜帽（开口）+ 毛领
add_part(ellipsoid((0, -0.025, 1.585), (0.082, 0.088, 0.102), 14, 10), "face", "head")
add_part(loft([(1.605, 0.094, 0.096, 0, -0.012), (1.64, 0.094, 0.096, 0, -0.012)], 16, cap0=False, cap1=False), "strap", "head")
add_part(rbox((0, -0.103, 1.622), (0.15, 0.035, 0.058), 0.016), "lens", "head")
add_part(loft([(1.44, 0.092, 0.088, 0, -0.01), (1.50, 0.088, 0.088, 0, -0.02), (1.555, 0.082, 0.082, 0, -0.03)], 16, cap0=False, cap1=False), "scarf", "head")
add_part(hood((0, 0.012, 1.60), (0.135, 0.138, 0.16), -0.06), "coat", "head")
add_part(torus_xz((0, -0.075, 1.595), 0.098, 0.118, 0.034, noise=0.12), "fur", "head")

# 背包（+Y = 背后）：主仓、顶包、前袋、压缩带、肩带、雪铲、防潮垫卷
add_part(rbox((0, 0.255, 1.17), (0.36, 0.22, 0.50), 0.06, 3), "pack", "chest")
add_part(rbox((0, 0.245, 1.44), (0.34, 0.25, 0.11), 0.045, 3), "pack_dark", "chest")
add_part(rbox((0, 0.37, 1.10), (0.26, 0.07, 0.25), 0.03, 2), "pack_dark", "chest")
for z in (1.02, 1.30):
    add_part(rbox((0, 0.369, z), (0.375, 0.012, 0.03), 0.005, 1), "strap", "chest", smooth=False)
add_part(rbox((0, 0.412, 1.12), (0.19, 0.012, 0.23), 0.02, 2), "metal", "chest")
add_part(limb((0, 0.412, 1.24), (0, 0.405, 1.40), [(0, 0.012, 0.012), (1, 0.012, 0.012)], 6), "strap", "chest")
for x in (-1, 1):
    path = [(0.11 * x, 0.15, 1.43), (0.12 * x, 0.0, 1.475), (0.125 * x, -0.150, 1.40), (0.12 * x, -0.168, 1.25), (0.13 * x, -0.165, 1.08)]
    for p0, p1 in zip(path, path[1:]):
        add_part(limb(p0, p1, [(0, 0.032, 0.012), (1, 0.032, 0.012)], 6), "strap", "chest")
    add_part(rbox((0, -0.172, 1.30), (0.20, 0.01, 0.022), 0.004, 1), "strap", "chest", smooth=False)
add_part(cyl((0, 0.25, 1.565), 0.078, 0.078, 0.52, 14, Matrix.Rotation(math.radians(90), 4, "Y")), "pad", "chest")
for xx in (-0.16, 0.16):
    add_part(cyl((xx, 0.25, 1.565), 0.083, 0.083, 0.03, 14, Matrix.Rotation(math.radians(90), 4, "Y")), "strap", "chest")

# 探针杆（右手，黑白分段）
for i in range(8):
    z0 = 0.10 + i * 0.22
    add_part(cyl((-0.28, -0.05, z0 + 0.11), 0.017, 0.017, 0.22, 8), "white" if i % 2 == 0 else "black", "probe")

bpy.ops.object.select_all(action="DESELECT")
for o in part_objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = part_objects[0]
bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
obj.name = "HikerMesh"
me = obj.data
# 平滑着色 + 35° 以上的折角保持锐利（盒子边、鞋底），外形柔和但不糊
me.use_auto_smooth = True
me.auto_smooth_angle = math.radians(35)

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

# 步态（v4，见 _leg）：24 帧一步态周期（0.8 s）。支撑相 60 %：脚踩住不动（大腿匀速后摆，sin 空间线性）；
# 摆动相 40 %：膝盖往后弯（正 X = 屈膝，之前写反了，膝盖往前折、靴子往前踢）。
# 骨盆高度按两条腿里较长的那条算，脚始终落在地面上（双脚着地时最低、单脚支撑中段最高）。
WALK_FRAMES = 24
THIGH, SHIN = 0.42, 0.42
TH_FWD, TH_BACK, STANCE = -27.0, 23.0, 0.6

def _gauss(p, c, w):
    d = abs(p - c)
    d = min(d, 1.0 - d)   # 循环相位，首尾接得上
    return math.exp(-(d / w) ** 2)

def _leg(p):
    """一条腿在步态相位 p（0 = 脚跟着地）的 (大腿角, 屈膝角)，度；大腿正 = 向后。
    v4：背着包，支撑腿膝盖一直微屈（~10°）；摆动腿抬膝明显（峰值 ~80°），大腿往前送到头时膝盖还弯着，
    落地前才伸直——游戏镜头从斜后上方看，这一段是看得见的（v3 的屈膝只在腿在身后时出现，被背包挡住，看着像直腿）。"""
    p %= 1.0
    if p < STANCE:
        a = math.sin(R(TH_FWD)) + (math.sin(R(TH_BACK)) - math.sin(R(TH_FWD))) * (p / STANCE)
        th = math.degrees(math.asin(a))
    else:
        u = (p - STANCE) / (1.0 - STANCE)
        e = 0.5 - 0.5 * math.cos(u * math.pi)
        th = TH_BACK + (TH_FWD - TH_BACK) * e - 9.0 * math.sin(u * math.pi) * u   # 往前送过头一点再落下
    k = 10.0 + 6.0 * _gauss(p, 0.12, 0.08) + 70.0 * _gauss(p, 0.80, 0.12)
    return th, k

def _extent(th, k):
    return THIGH * math.cos(R(th)) + SHIN * math.cos(R(th + k))

def _reach(th, k):
    return THIGH * math.sin(R(th)) + SHIN * math.sin(R(th + k))

def walk(f):
    p = f / WALK_FRAMES
    tl, kl = _leg(p)
    tr, kr = _leg(p + 0.5)
    pb["thigh.L"].rotation_euler = (R(tl), 0, 0)
    pb["thigh.R"].rotation_euler = (R(tr), 0, 0)
    pb["shin.L"].rotation_euler = (R(kl), 0, 0)
    pb["shin.R"].rotation_euler = (R(kr), 0, 0)
    drop = (THIGH + SHIN) - max(_extent(tl, kl), _extent(tr, kr))
    pb["hips"].location = (0, -drop, 0)
    # 手臂与对侧腿同摆，前臂微屈；顶风背包前倾，胸口随手臂轻扭，头回正
    pb["upper_arm.L"].rotation_euler = (R(-0.7 * tl), 0, R(7))
    pb["upper_arm.R"].rotation_euler = (R(-0.7 * tr), 0, R(-7))
    pb["forearm.L"].rotation_euler = (R(-12 - 10 * max(0.0, -tl) / 27.0), 0, 0)
    pb["forearm.R"].rotation_euler = (R(-12 - 10 * max(0.0, -tr) / 27.0), 0, 0)
    tw = (tl - tr) / (TH_BACK - TH_FWD)
    pb["chest"].rotation_euler = (R(10), 0, R(-5) * tw)
    pb["head"].rotation_euler = (R(-6), 0, R(4) * tw)

def walk_speed_mps():
    """支撑脚相对骨盆的后移速度 = 角色前进速度（脚不打滑时）。"""
    a = _reach(*_leg(0.0))
    b = _reach(*_leg(STANCE - 1e-6))
    return (b - a) / (STANCE * WALK_FRAMES / 30.0)

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
key("Walk-loop", list(range(0, WALK_FRAMES + 1, 2)), walk)
print("WALK_MPS %.3f" % walk_speed_mps())
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
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_shadows = True
    sh.show_cavity = True
    scene.display.shadow_focus = 0.3
    scene.render.resolution_x = 420
    scene.render.resolution_y = 560
    scene.render.film_transparent = False
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 85
    scene.collection.objects.link(cam)
    scene.camera = cam
    # 3/4 前、3/4 后（游戏镜头大多从斜后上方看）、正侧
    for view, loc in (("front34", (2.6, -4.2, 2.4)), ("back34", (-2.6, 4.2, 2.6)), ("side", (5.0, 0, 1.4))):
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 0.95)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        for act_name, frame in (("Idle-loop", 0), ("Walk-loop", 3), ("Walk-loop", 9), ("Walk-loop", 15), ("Dig-loop", 8), ("Chop-loop", 15)):
            rig.animation_data.action = bpy.data.actions[act_name]
            for tr in rig.animation_data.nla_tracks:
                tr.mute = True
            scene.frame_set(frame)
            scene.render.filepath = f"{outdir}/b_{view}_{act_name}_{frame}.png"
            bpy.ops.render.render(write_still=True)
