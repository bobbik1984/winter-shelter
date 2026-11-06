"""Build the seven shelter models (plus BasicCave) procedurally in Blender 4.x.

Run:  blender --background --python tools/blender/build_shelters.py -- assets/models/shelters [--only RaisedCave,LeanTo] [--preview <dir>]

For every shelter two files:
  <Preset>.glb          the shelter seen from outside. One object per build part, named
                        "s<a>_<b>__<label>": visible while a <= stage <= b. Materials are named
                        (Snow, SnowIn, Dark, Bough, Wood, Rock, Glow, Metal, Bag) and the game swaps
                        in its own snow / wood / bough materials by name.
  <Preset>_section.glb  the finished shelter cut along its entrance axis (local x = 0), only the
                        x <= 0 half, for the "Enter the shelter" view. Cut faces get their own lighter
                        material, and lighting (sky, sun from the camera side, ambient occlusion, the
                        candle) is baked into vertex colours: the game draws it unshaded, like a diagram.

Everything is modelled in Godot site-local coordinates (+Y up, +Z = entrance direction, origin on the
ground) and converted to Blender's Z-up only at export, so the numbers here match shelter_site.gd and
shelter_interior.gd (labels, figure spot, camera).
"""
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix, noise
from mathutils.bvhtree import BVHTree

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = ARGS[0] if ARGS else "assets/models/shelters"
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else []
PREVIEW = ARGS[ARGS.index("--preview") + 1] if "--preview" in ARGS else ""

# Godot (x, y, z) -> Blender (x, -z, y)
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

COLORS = {
    "Snow": (0.86, 0.90, 0.97), "SnowIn": (0.50, 0.62, 0.84), "SnowCut": (0.97, 0.98, 1.0),
    "Dark": (0.05, 0.07, 0.12), "Bough": (0.08, 0.22, 0.11), "BoughCut": (0.22, 0.40, 0.20),
    "Wood": (0.30, 0.20, 0.11), "WoodCut": (0.50, 0.37, 0.23), "Rock": (0.36, 0.34, 0.32),
    "RockCut": (0.52, 0.50, 0.47), "Bag": (0.66, 0.16, 0.08), "Pad": (0.78, 0.46, 0.08),
    "Glow": (1.0, 0.66, 0.30), "Candle": (0.95, 0.90, 0.75), "Metal": (0.40, 0.48, 0.60),
    "Grass": (0.62, 0.52, 0.28), "Pack": (0.70, 0.12, 0.06),
}
CUT_OF = {"Snow": "SnowCut", "SnowIn": "SnowCut", "Wood": "WoodCut", "Rock": "RockCut", "Bough": "BoughCut",
          "Bag": "Bag", "Pad": "Pad", "Metal": "Metal", "Grass": "Grass", "Pack": "Pack", "Candle": "Candle", "Glow": "Glow"}

rng = random.Random(7)

# ---------------------------------------------------------------- scene helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    c = COLORS[name]
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*c, 1.0)
    m.diffuse_color = (*c, 1.0)
    if name == "Glow":
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Emission Color"].default_value = (*c, 1.0)
        b.inputs["Emission Strength"].default_value = 3.0
    return m

def to_obj(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(mat(material))
    return o

def apply_mod(o, mod):
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        bpy.ops.object.modifier_apply(modifier=mod.name)

def boolean(o, cutter, op="DIFFERENCE"):
    """Exact boolean; new faces take the cutter's material (so a cavity cutter paints the inside)."""
    m = o.modifiers.new("b", "BOOLEAN")
    m.operation = op
    m.object = cutter
    m.solver = "EXACT"
    m.material_mode = "TRANSFER"
    apply_mod(o, m)

def kill(o):
    bpy.data.objects.remove(o, do_unlink=True)

# ---------------------------------------------------------------- shapes (Godot coordinates)
def bm_ell(c, r, segs=40, rings=20):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(r), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    return bm

def bm_box(c, size, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=2, affect="EDGES", profile=0.5)
    bmesh.ops.translate(bm, vec=Vector(c), verts=bm.verts)
    return bm

def bm_cyl(a, b, r1, r2=None, segs=10):
    r2 = r1 if r2 is None else r2
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=d.length)
    m = Matrix.Translation((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm

def lumpy(bm, amp, scale=1.2, seed=0.0, up_only=False):
    """Organic snow: push vertices along their normal by smooth 3-D noise."""
    bm.normal_update()
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in bm.verts:
        n = noise.noise(v.co * scale + off) + 0.5 * noise.noise(v.co * scale * 2.3 + off)
        if up_only and v.normal.y < 0.2:
            continue
        v.co += v.normal * amp * n
    return bm

def transform(bm, m):
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm

def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")

def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")

def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")

# ---------------------------------------------------------------- parts
class Part:
    """One build part. make() returns a fresh bmesh in Godot coords.
    stages: (a, b) exterior visibility, or None = section only. sec: drawn in the section.
    cut: 'bool' (closed solid, boolean-cut at x = 0), 'drop' (keep whole if its centre is at x <= 0.05),
    'none' (keep as is)."""
    def __init__(self, label, make, material, stages=(1, 5), sec=True, cut="bool", cutters=(), shade=True):
        self.label, self.make, self.material, self.stages, self.sec, self.cut = label, make, material, stages, sec, cut
        self.cutters = cutters  # [(make, material)] subtracted before anything else (cavities, doors)
        self.shade = shade

def build_obj(p, name, half=False):
    # 精确布尔偶尔会退化（整件只剩几个顶点）：换一个切面位置重来
    for off in (0.0123, 0.0171, 0.0237, 0.0309):
        o = _build_once(p, name, half, off)
        if not half or len(o.data.vertices) >= 40 or len(p.make().verts) < 60:
            return o
        print("WARN boolean degenerated for", name, "at", off, "- retrying")
        kill(o)
    print("WARN boolean still degenerate for", name)
    return _build_once(p, name, half, 0.0123)

def _build_once(p, name, half, off):
    o = to_obj(name, p.make(), p.material)
    if half:
        # 剖面：先把实体切成一半，再挖洞（顺序反过来时，挖空后的网格切开会退化）
        # 切面放在 x ≈ 0.01：正好 x = 0 会穿过通风管 / 隧道圆柱的顶点，精确布尔会退化
        cutter = to_obj("cutter", bm_box((50.0 + off, 0, 0), (100, 100, 100)), CUT_OF.get(p.material, p.material))
        boolean(o, cutter)
        kill(cutter)
    for mk, m in p.cutters:
        c = to_obj(name + "_cut", mk(), m)
        boolean(o, c)
        kill(c)
    return o

# ---------------------------------------------------------------- shared furniture
def bed_parts(x, y, z, half_w=0.36, length=2.0, bag=True):
    out = [Part("bed", lambda: lumpy(bm_box((x, y + 0.035, z), (half_w * 2, 0.07, length), 0.03), 0.015, 6.0, 3), "Bough", None)]
    if bag:
        out.append(Part("bag", lambda: lumpy(bm_ell((x, y + 0.13, z - 0.05), (half_w * 0.62, 0.075, length * 0.44), 18, 10), 0.01, 5.0, 4), "Bag", None))
        out.append(Part("pillow", lambda: bm_ell((x, y + 0.13, z - length * 0.44), (half_w * 0.5, 0.07, 0.13), 12, 8), "Pad", None))
    return out

def candle_parts(p):
    x, y, z = p
    return [Part("candle", lambda: bm_cyl((x, y, z), (x, y + 0.12, z), 0.03), "Candle", None),
            Part("flame", lambda: bm_ell((x, y + 0.16, z), (0.022, 0.04, 0.022), 10, 6), "Glow", None)]

def gear_parts(x, z, yaw=20.0, y=0.0):
    """Backpack leaning on the wall + a snow shovel: the north star's cave has the same."""
    return [Part("pack", lambda: transform(bm_box((0, 0.3, 0), (0.42, 0.6, 0.26), 0.07), Matrix.Translation((x, y, z)) @ rot_y(yaw) @ rot_x(-10)), "Pack", None),
            Part("packlid", lambda: transform(bm_box((0, 0.62, 0), (0.40, 0.12, 0.28), 0.05), Matrix.Translation((x, y, z)) @ rot_y(yaw) @ rot_x(-10)), "Bag", None),
            Part("shovel_shaft", lambda: bm_cyl((x + 0.35, y, z - 0.15), (x + 0.30, y + 0.85, z - 0.32), 0.018), "Wood", None),
            Part("shovel_blade", lambda: transform(bm_box((0, 0.12, 0), (0.22, 0.26, 0.02), 0.01), Matrix.Translation((x + 0.36, y, z - 0.1)) @ rot_x(-18)), "Metal", None)]

def bough_clump(c, size, length_dir, up_hint=(0, 1, 0), spin=0.0):
    """One spruce bough: a flat, slightly arched spray (low poly). Its length runs along `length_dir`
    and it lies flat against the surface whose normal is roughly `up_hint` (a roof, the ground)."""
    za = Vector(length_dir).normalized()
    xa = Vector(up_hint).cross(za)
    if xa.length < 1e-4:
        xa = Vector((1, 0, 0))
    xa.normalize()
    ya = za.cross(xa).normalized()
    basis = Matrix((xa, ya, za)).transposed().to_4x4()
    def mk():
        bm = bm_ell((0, 0, 0), (size * 0.32, size * 0.06, size * 0.5), 8, 5)
        for v in bm.verts:
            v.co.y += -0.25 * (v.co.z / (size * 0.5)) ** 2 * size * 0.3   # 枝梢下垂
            v.co.x *= 1.0 + 0.35 * math.sin(v.co.z * 23.0)               # 锯齿边
        return transform(bm, Matrix.Translation(c) @ basis @ Matrix.Rotation(math.radians(spin), 4, "Y"))
    return mk

def thatch(origin, along, down, n_along, n_down, size, jitter=0.12, seed=1):
    """Shingled boughs over a roof plane: rows from the top (origin) going `down`, each row along `along`."""
    r = random.Random(seed)
    o, a, d = Vector(origin), Vector(along), Vector(down)
    normal = a.cross(d).normalized()
    if normal.y < 0:
        normal = -normal
    makers = []
    for i in range(n_down):
        for k in range(n_along):
            t = (k + (0.5 if i % 2 else 0.0)) / max(n_along - 1, 1)
            if t > 1.0:
                continue
            c = o + a * t + d * (i / max(n_down - 1, 1)) + normal * (0.05 + 0.02 * (i % 2))
            c += Vector((r.uniform(-1, 1), 0, r.uniform(-1, 1))) * jitter
            makers.append(bough_clump(tuple(c), size * r.uniform(0.85, 1.15), d, normal, r.uniform(-14, 14)))
    def mk():
        bm = bmesh.new()
        for m in makers:
            b = m()
            me = bpy.data.meshes.new("tmp")
            b.to_mesh(me)
            b.free()
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        return bm
    return mk

def roof_slab(origin, along, down, thick=0.12, sag=0.0):
    """Solid thatch layer under the bough clumps: a parallelogram plate (closed, so it cuts cleanly and
    the section shows a continuous green roof line)."""
    def mk():
        o, a, d = Vector(origin), Vector(along), Vector(down)
        n = a.cross(d).normalized()
        if n.y < 0:
            n = -n
        bm = bmesh.new()
        steps = 6
        top, bot = [], []
        for i in range(steps + 1):
            t = i / steps
            for j in (0, 1):
                p = o + d * t + a * j - n * (sag * math.sin(t * math.pi))
                top.append(bm.verts.new(p))
                bot.append(bm.verts.new(p - n * thick))
        for i in range(steps):
            a0, a1, b0, b1 = i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 3
            bm.faces.new((top[a0], top[a1], top[b1], top[b0]))
            bm.faces.new((bot[a0], bot[b0], bot[b1], bot[a1]))
            bm.faces.new((top[a0], top[b0], bot[b0], bot[a0]))
            bm.faces.new((top[a1], bot[a1], bot[b1], top[b1]))
        bm.faces.new((top[0], bot[0], bot[1], top[1]))
        k = steps * 2
        bm.faces.new((top[k], top[k + 1], bot[k + 1], bot[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return bm
    return mk

def merge(*makers):
    def mk():
        bm = bmesh.new()
        for m in makers:
            b = m()
            me = bpy.data.meshes.new("tmp")
            b.to_mesh(me)
            b.free()
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        return bm
    return mk

def half_ell_cutter(c, r):
    """Ellipsoid with everything below y = 0 removed: a cavity with a flat floor."""
    def mk():
        o = to_obj("tmp_cav", bm_ell(c, r, 40, 20), "SnowIn")
        g = to_obj("tmp_ground", bm_box((0, -5.0, 0), (20, 10, 20)), "SnowIn")
        boolean(o, g)
        kill(g)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        kill(o)
        return bm
    return mk

# ---------------------------------------------------------------- presets
def cave(raised):
    """Snow cave dug into a deep drift. Inner chamber ~2.9 x 2.8 m, roof ~0.55 m; tunnel to +Z."""
    cav_c, cav_r = (0, 0, -0.3), (1.45, 1.35, 1.40)
    # 拱形隧道：方盒 + 圆柱。尺寸故意错开（盒宽 0.80、圆柱半径 0.43、高度不同），重合的面会让精确布尔退化
    tunnel = [(lambda: bm_box((0, 0.3, 1.9), (0.80, 0.6, 2.6)), "SnowIn"),
              (lambda: bm_cyl((0, 0.553, 0.61), (0, 0.553, 3.21), 0.43, 0.43, 15), "SnowIn")]
    drift = lambda: lumpy(bm_ell((0, -0.35, -0.25), (2.25, 2.2, 2.25), 56, 28), 0.08, 1.1, 1)
    ground = (lambda: bm_box((0, -5.3, 0), (20, 10, 20)), "Snow")
    parts = [Part("mound", drift, "Snow", (1, 5), cutters=[ground, (half_ell_cutter(cav_c, cav_r), "SnowIn")] + tunnel
                  + ([(lambda: bm_cyl((0, 1.0, 0.1), (0, 2.6, 0.1), 0.07), "SnowIn")] if True else []))]
    # 入口前挖出的引道：两侧弃雪埂 + 弃雪堆（外观）
    for sx in (-1, 1):
        parts.append(Part(f"berm{sx}", lambda sx=sx: lumpy(bm_ell((sx * 0.95, -0.1, 3.0), (0.42, 0.45, 0.9), 16, 10), 0.06, 2.0, 2 + sx), "Snow", (1, 5), sec=False))
    for i, (px, pz, s0) in enumerate([(-1.9, 2.6, 1), (1.8, 2.9, 1), (-2.4, 1.6, 2), (2.3, 1.9, 2)]):
        parts.append(Part(f"spoil{i}", lambda px=px, pz=pz, i=i: lumpy(bm_ell((px, -0.05, pz), (0.55, 0.42, 0.5), 14, 8), 0.07, 2.5, 5 + i), "Snow", (s0, 5), sec=False))
    if raised:
        # 高床：后半个洞的雪台（顺着洞壁），前半低下去就是冷气坑
        plat = Part("platform", lambda: bm_box((0, 0.225, -0.75), (2.8, 0.45, 2.0)), "SnowIn", (3, 5),
                    cutters=[])
        plat_cav = half_ell_cutter(cav_c, cav_r)
        def plat_mk():
            o = to_obj("tmp_plat", bm_box((0, 0.225, -0.75), (2.8, 0.45, 2.0)), "SnowIn")
            c = to_obj("tmp_cav2", plat_cav(), "SnowIn")
            boolean(o, c, "INTERSECT")
            kill(c)
            bm = bmesh.new()
            bm.from_mesh(o.data)
            kill(o)
            return bm
        plat.make = plat_mk
        parts.append(plat)
        parts += bed_parts(-0.55, 0.45, -0.65, 0.36, 1.9)
        parts += candle_parts((-0.95, 0.45, -1.2))
        parts += gear_parts(-1.0, 0.75, 70.0)
    else:
        parts += bed_parts(-0.55, 0.0, -0.4, 0.36, 2.0)
        parts += candle_parts((-1.0, 0.0, -1.05))
        parts += gear_parts(-1.05, 0.65, 70.0)
        # 第 5 阶段：入口挡风的雪砖
        parts.append(Part("doorblock", lambda: lumpy(bm_box((0.32, 0.32, 2.75), (0.5, 0.64, 0.32), 0.05), 0.02, 4.0, 9), "Snow", (5, 5)))
    # 通风管（第 4 阶段）+ 第二根（只在 vent_count >= 2 时显示，见 shelter_site.gd）
    parts.append(Part("vent", lambda: bm_cyl((0, 1.0, 0.1), (0, 2.2, 0.1), 0.045, 0.045, 10), "Metal", (4, 5)))
    parts.append(Part("vent2", lambda: bm_cyl((-0.55, 0.9, -0.8), (-0.55, 2.05, -0.8), 0.045, 0.045, 10), "Metal", (4, 5), sec=False,
                      cutters=[]))
    parts.append(Part("offcuts", merge(bough_clump((1.15, 0.08, 2.3), 0.9, (1, 0, 0.4)), bough_clump((1.3, 0.14, 2.0), 0.8, (0.6, 0, -1))), "Bough", (3, 5), sec=False, cut="none"))
    # 完工：洞口的烛光（外观；灯光由 shelter_site.gd 加）
    parts.append(Part("glow", lambda: bm_box((0, 0.35, 1.25), (0.7, 0.6, 0.04)), "Glow", (5, 5), sec=False, cut="none"))
    return parts

def quinzhee():
    cav_c, cav_r = (0, 0, 0), (1.45, 1.15, 1.45)
    mound = lambda: lumpy(bm_ell((0, -0.3, 0), (2.15, 1.75, 2.15), 56, 28), 0.06, 1.3, 11)
    ground = (lambda: bm_box((0, -5.3, 0), (20, 10, 20)), "Snow")
    door = [(lambda: bm_box((0, 0.3, 1.9), (0.80, 0.6, 1.6)), "SnowIn"), (lambda: bm_cyl((0, 0.553, 1.01), (0, 0.553, 2.81), 0.43, 0.43, 15), "SnowIn")]
    vent = (lambda: bm_cyl((0.0, 0.9, -0.1), (0.0, 2.0, -0.1), 0.06), "SnowIn")
    parts = [Part("heap", mound, "Snow", (1, 2), sec=False, cutters=[ground]),
             Part("mound", mound, "Snow", (3, 5), cutters=[ground, (half_ell_cutter(cav_c, cav_r), "SnowIn")] + door + [vent])]
    # 厚度标尺：插进去的木棍（第 2 阶段露在外面，掏空后从里面看得到棍头）
    sticks = []
    for i in range(9):
        a = 2 * math.pi * i / 9 + 0.3
        e = math.radians(25 + 40 * ((i * 37) % 3) / 2)
        out = Vector((math.cos(a) * math.cos(e) * 2.15, -0.3 + math.sin(e) * 1.75, math.sin(a) * math.cos(e) * 2.15))
        inn = out + (Vector((0, 0.1, 0)) - out).normalized() * 0.42
        sticks.append((tuple(out + (out - Vector((0, -0.3, 0))).normalized() * 0.12), tuple(inn)))
    parts.append(Part("sticks", merge(*[lambda a=a, b=b: bm_cyl(a, b, 0.018, 0.018, 6) for a, b in sticks]), "Wood", (2, 5), cut="drop"))
    parts.append(Part("vent", lambda: bm_cyl((0.0, 1.0, -0.1), (0.0, 1.62, -0.1), 0.04, 0.04, 10), "Wood", (4, 5)))
    parts.append(Part("vent2", lambda: bm_cyl((-0.55, 0.9, -0.6), (-0.55, 1.5, -0.6), 0.04, 0.04, 10), "Wood", (4, 5), sec=False))
    parts += bed_parts(-0.6, 0.0, -0.3, 0.36, 2.0)
    parts.append(Part("floor", lambda: lumpy(bm_box((0.0, 0.025, -0.1), (2.2, 0.05, 2.2)), 0.012, 6.0, 12), "Bough", (5, 5), sec=False))
    parts += candle_parts((-1.05, 0.0, -0.6))
    parts += gear_parts(-1.0, 0.85, 75.0)
    parts.append(Part("doorblock", lambda: lumpy(bm_box((0.0, 0.3, 2.5), (0.86, 0.62, 0.3), 0.05), 0.02, 4.0, 13), "Snow", (5, 5), sec=False))
    for i, (px, pz) in enumerate([(-1.7, 2.4), (1.6, 2.6)]):
        parts.append(Part(f"spoil{i}", lambda px=px, pz=pz, i=i: lumpy(bm_ell((px, -0.05, pz), (0.5, 0.38, 0.45), 14, 8), 0.06, 2.5, 14 + i), "Snow", (3, 5), sec=False))
    parts.append(Part("glow", lambda: bm_box((0, 0.3, 1.45), (0.7, 0.55, 0.04)), "Glow", (5, 5), sec=False, cut="none"))
    return parts

def trench():
    """Snow-block trench, body length along Z (closed end at -Z), open end at +Z."""
    parts = []
    z0, z1 = -2.0, 1.0
    parts.append(Part("floor_cut", lambda: bm_box((0, 0.015, (z0 + z1) / 2), (1.24, 0.03, z1 - z0)), "Dark", (1, 2), sec=False, cut="none"))
    # 弃雪：沟两侧挖出来的雪（第 1 阶段）
    for sx in (-1, 1):
        parts.append(Part(f"spoil{sx}", lambda sx=sx: lumpy(bm_ell((sx * 1.6, -0.15, -0.5), (0.6, 0.45, 1.9), 20, 10), 0.06, 1.8, 20 + sx), "Snow", (1, 1), sec=False))
    # 雪砖墙：每边三层，错缝（第 2 阶段起）
    blocks = []
    for sx in (-1, 1):
        for row in range(3):
            n = 6
            for k in range(n + (1 if row % 2 else 0)):
                zz = z0 + (k - (0.5 if row % 2 else 0.0)) * (z1 - z0) / n + (z1 - z0) / n / 2
                if zz < z0 + 0.1 or zz > z1 - 0.1:
                    continue
                c = (sx * 0.80, 0.12 + row * 0.24, zz)
                blocks.append(lambda c=c, s=(row * 7 + k + sx): lumpy(bm_box(c, (0.36, 0.23, (z1 - z0) / n - 0.03), 0.04), 0.012, 5.0, s))
    parts.append(Part("walls", merge(*blocks), "Snow", (2, 5)))
    parts.append(Part("boughs", lambda: lumpy(bm_box((0, 0.04, (z0 + z1) / 2), (1.2, 0.07, z1 - z0 - 0.1)), 0.02, 6.0, 25), "Bough", (3, 5)))
    # 屋顶：横木 + 雪板（第 4 阶段）
    poles = [lambda zz=zz: bm_cyl((-1.05, 0.78, zz), (1.05, 0.78, zz), 0.045, 0.045, 8) for zz in [z0 + 0.25 + i * 0.45 for i in range(7)]]
    parts.append(Part("poles", merge(*poles), "Wood", (4, 5)))
    parts.append(Part("slabs", lambda: lumpy(bm_box((0, 0.93, (z0 + z1) / 2 - 0.05), (2.15, 0.22, z1 - z0 + 0.1), 0.06), 0.03, 2.0, 26, up_only=True), "Snow", (4, 5)))
    # 封住上风那头（第 5 阶段）
    parts.append(Part("endwall", lambda: lumpy(bm_box((0, 0.45, z0 - 0.18), (2.0, 0.9, 0.36), 0.05), 0.02, 4.0, 27), "Snow", (5, 5)))
    parts += bed_parts(-0.3, 0.07, -0.6, 0.26, 1.9)
    parts += candle_parts((-0.5, 0.08, z0 + 0.25))
    parts.append(Part("glow", lambda: bm_box((0, 0.35, z1 - 0.05), (0.9, 0.55, 0.04)), "Glow", (5, 5), sec=False, cut="none"))
    return parts

def leanto():
    """Ridgepole on two forked posts at z = 1.0, roof thatch slopes back to the ground at z = -1.5;
    bed under the roof, fire at z = 2.0 (Campfire node from code), log reflector wall at z = 3.0."""
    parts = []
    ridge_y, ridge_z, back_z = 1.5, 1.0, -1.5
    posts = [lambda x=x: bm_cyl((x, 0.0, ridge_z), (x, ridge_y + 0.15, ridge_z), 0.06, 0.05, 8) for x in (-1.45, 1.45)]
    forks = [lambda x=x, s=s: bm_cyl((x, ridge_y - 0.05, ridge_z), (x + s * 0.12, ridge_y + 0.2, ridge_z), 0.03, 0.025, 6) for x in (-1.45, 1.45) for s in (-1, 1)]
    parts.append(Part("posts", merge(*posts, *forks), "Wood", (1, 5), cut="drop"))   # 不跨切面；叉枝和柱子相交，不能布尔
    parts.append(Part("ridge", lambda: bm_cyl((-1.75, ridge_y, ridge_z), (1.75, ridge_y, ridge_z), 0.07, 0.06, 10), "Wood", (1, 5)))
    rafters = [lambda x=x: bm_cyl((x, ridge_y + 0.05, ridge_z + 0.15), (x, -0.05, back_z - 0.1), 0.04, 0.035, 8) for x in (-1.3, -0.65, 0.0, 0.65, 1.3)]
    parts.append(Part("rafters", merge(*rafters), "Wood", (1, 5)))   # 不相交的圆柱：可以一起布尔切开
    parts.append(Part("roofmat", roof_slab((-1.55, ridge_y + 0.08, ridge_z + 0.12), (3.1, 0, 0), (0, -ridge_y, back_z - ridge_z - 0.1), 0.14), "Bough", (2, 5)))
    parts.append(Part("thatch", thatch((-1.5, ridge_y + 0.04, ridge_z + 0.1), (3.0, 0, 0), (0, -ridge_y + 0.1, back_z - ridge_z), 8, 7, 0.75, jitter=0.07, seed=31), "Bough", (2, 5), cut="drop"))
    parts += bed_parts(-0.6, 0.0, -0.35, 0.4, 1.9)
    parts.append(Part("grass", lambda: lumpy(bm_box((0.35, 0.05, -0.3), (0.6, 0.1, 1.6), 0.04), 0.02, 6.0, 33), "Grass", (3, 5)))
    # 反射墙：两根木桩夹住的一垛木头（第 4 阶段）
    stakes = [lambda x=x: bm_cyl((x, 0, 3.05), (x, 0.95, 3.05), 0.05, 0.045, 8) for x in (-1.3, 1.3)]
    logs = [lambda k=k: bm_cyl((-1.4, 0.13 + k * 0.23, 3.0 - (k % 2) * 0.02), (1.4, 0.13 + k * 0.23, 3.0 + (k % 2) * 0.02), 0.115, 0.11, 12) for k in range(4)]
    parts.append(Part("reflector", merge(*stakes, *logs), "Wood", (4, 5)))
    return parts

def treewell():
    """Pit scooped around the trunk (origin) inside a berm of snow, the spruce's lower boughs as roof.
    Outside, the real tree stands in the world; the section draws its own trunk and boughs."""
    parts = []
    pit = lambda: bm_cyl((0, -0.4, 0), (0, 1.3, 0), 1.75, 1.45, 32)
    berm = lambda: lumpy(bm_ell((0, -0.3, 0), (2.55, 1.25, 2.55), 48, 20), 0.08, 1.4, 41)
    ground = (lambda: bm_box((0, -5.3, 0), (20, 10, 20)), "Snow")
    door = (lambda: bm_box((0, 0.45, 2.2), (0.9, 0.9, 1.6)), "SnowIn")
    parts.append(Part("berm", berm, "Snow", (1, 5), cutters=[ground, (pit, "SnowIn"), door]))
    parts.append(Part("pitfloor", lambda: bm_cyl((0, 0.0, 0), (0, 0.02, 0), 1.7, 1.7, 32), "Dark", (1, 2), sec=False, cut="none"))
    parts.append(Part("trimmings", merge(bough_clump((2.4, 0.12, -1.6), 1.0, (0.5, 0, -1)), bough_clump((2.75, 0.18, -1.0), 0.9, (1, 0, -0.3))), "Bough", (2, 5), sec=False, cut="none"))
    parts.append(Part("floor", lambda: lumpy(bm_cyl((0, 0.0, 0), (0, 0.06, 0), 1.5, 1.5, 28), 0.015, 6.0, 42), "Bough", (3, 5)))
    # 补顶（第 4 阶段，外观）：围着树干一圈向外斜下的枝条，补在真树的低枝之间
    ring = []
    for tier, (y, rad, n) in enumerate([(1.45, 1.75, 12), (1.85, 1.4, 10)]):
        for k in range(n):
            a = 2 * math.pi * (k + 0.5 * tier) / n
            out = Vector((math.sin(a), 0, math.cos(a)))
            c = out * rad * 0.55 + Vector((0, y, 0))
            ring.append(bough_clump(tuple(c), rad * 0.95, out + Vector((0, -0.45, 0)), (0, 1, 0)))
    parts.append(Part("roof", merge(*ring), "Bough", (4, 5), sec=False, cut="none"))
    parts.append(Part("door", merge(bough_clump((-0.25, 0.45, 2.15), 0.9, (0.1, -1, 0.15), (0, 0, 1)), bough_clump((0.3, 0.5, 2.2), 0.85, (-0.1, -1, 0.1), (0, 0, 1))), "Bough", (5, 5), sec=False, cut="none"))
    # 剖面专用：自己的树（外面是世界里那棵真树）——树干 + 一层层圆锥形的枝条层，切开后是绿色的截面。
    # 最低一层就是庇护所的屋顶（第 4 阶段补过的枝条），低到雪墙上。
    parts.append(Part("trunk", lambda: bm_cyl((-0.24, -0.1, 0), (-0.24, 4.2, 0), 0.2, 0.08, 12), "Wood", None))   # 在切面后面：看到的是圆树干
    def tier(y0, y1, r0, r1, thick, seed):
        def mk():
            o = to_obj("tmp_tier", lumpy(bm_cyl((0, y0, 0), (0, y1, 0), r0, r1, 24), 0.06, 2.2, seed), "Bough")
            inner = to_obj("tmp_tier_in", bm_cyl((0, y0 - 0.01, 0), (0, y1 - thick, 0), r0 - thick * 1.6, max(r1 - thick, 0.02), 24), "Bough")
            boolean(o, inner)
            kill(inner)
            bm = bmesh.new()
            bm.from_mesh(o.data)
            kill(o)
            return bm
        return mk
    for i, (y0, y1, r0, r1) in enumerate([(0.95, 2.35, 2.25, 0.35), (2.1, 3.1, 1.6, 0.25), (2.85, 3.75, 1.05, 0.15), (3.5, 4.4, 0.6, 0.04)]):
        parts.append(Part(f"tier{i}", tier(y0, y1, r0, r1, 0.28, 70 + i), "Bough", None))
    parts += bed_parts(-0.85, 0.06, -0.3, 0.34, 1.8)
    parts += candle_parts((-0.35, 0.06, -1.15))
    parts.append(Part("glow", lambda: bm_box((0, 0.4, 1.55), (0.7, 0.6, 0.04)), "Glow", (5, 5), sec=False, cut="none"))
    return parts

def rock_overhang():
    """A rock wall along Z on the -X side, poles leaning from its top to the ground at +X, thatched;
    entrance at +Z, the far (-Z) end blocked with a log at stage 5."""
    parts = []
    def rock():
        # 几块圆滚滚的大石头挤在一起 + 顶上一块向外伸的岩檐
        blocks = [((-1.9, 0.7, -1.6), (1.0, 1.25, 1.3)), ((-2.0, 0.85, 0.2), (1.1, 1.35, 1.25)),
                  ((-1.85, 0.6, 1.5), (0.9, 1.05, 0.9)), ((-1.35, 1.75, -0.4), (0.95, 0.45, 2.2))]
        bm = bmesh.new()
        for c, r in blocks:
            b = lumpy(bm_ell(c, r, 24, 14), 0.1, 1.4, 51 + c[2])
            me = bpy.data.meshes.new("tmp")
            b.to_mesh(me)
            b.free()
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
        return bm
    parts.append(Part("rock", rock, "Rock", (1, 5), cut="drop"))   # 石块彼此相交，不能布尔；整体在切面后面
    parts.append(Part("cleared", lambda: bm_box((0.0, 0.012, -0.3), (2.4, 0.024, 4.0)), "Dark", (1, 2), sec=False, cut="none"))
    poles = [lambda zz=zz: bm_cyl((-0.75, 1.95, zz), (1.45, -0.05, zz), 0.045, 0.04, 8) for zz in (-2.1, -1.2, -0.3, 0.6, 1.5)]
    parts.append(Part("poles", merge(*poles), "Wood", (2, 5)))
    parts += bed_parts(-0.55, 0.0, -0.35, 0.4, 2.0)
    parts.append(Part("bedthick", lambda: lumpy(bm_box((-0.55, 0.03, -0.35), (0.95, 0.06, 2.1), 0.03), 0.015, 6.0, 52), "Bough", (3, 5)))
    parts.append(Part("roofmat", roof_slab((-0.75, 2.02, 1.75), (0, 0, -4.1), (2.25, -2.07, 0), 0.13), "Bough", (4, 5)))
    parts.append(Part("thatch", thatch((-0.7, 2.04, 1.7), (0, 0, -4.0), (2.2, -2.0, 0), 11, 7, 0.6, jitter=0.07, seed=53), "Bough", (4, 5), cut="drop"))
    parts.append(Part("endlog", lambda: bm_cyl((-1.1, 0.16, -2.35), (1.5, 0.16, -2.35), 0.16, 0.15, 12), "Wood", (5, 5)))
    parts.append(Part("endlog2", lambda: bm_cyl((-0.8, 0.46, -2.35), (1.0, 0.46, -2.35), 0.14, 0.13, 12), "Wood", (5, 5)))
    return parts

def fallen_log():
    """Fallen trunk as the ridge along Z (top ~1.35 m), lying just behind the section cut so it shows
    as a round log; ribs lean on both sides, thatch, bed inside, snow banked on the windward (-X) side."""
    parts = []
    lx = -0.27
    parts.append(Part("log", lambda: bm_cyl((lx, 1.12, -2.3), (lx, 1.2, 2.7), 0.23, 0.18, 16), "Wood", (1, 5)))
    parts.append(Part("rootplate", lambda: lumpy(bm_ell((lx, 1.0, -2.48), (0.75, 0.85, 0.18), 16, 8), 0.06, 3.0, 61), "Wood", (1, 5)))
    parts.append(Part("stubs", merge(*[lambda z=z, s=s: bm_cyl((lx, 1.25, z), (lx + s * 0.45, 1.6, z + 0.2), 0.035, 0.02, 6) for z, s in ((-1.2, -1), (0.4, -1), (1.6, -1))]), "Wood", (1, 5)))
    ribs = []
    for zz in [-1.9 + i * 0.4 for i in range(11)]:
        for sx in (-1, 1):
            ribs.append(lambda zz=zz, sx=sx: bm_cyl((lx + sx * 0.18, 1.3, zz), (lx + sx * 1.25, -0.05, zz), 0.035, 0.03, 6))
    parts.append(Part("ribs", merge(*ribs), "Wood", (2, 5)))
    for sx in (-1, 1):
        parts.append(Part(f"roofmat{sx}", roof_slab((lx + sx * 0.16, 1.4, 2.4), (0, 0, -4.6), (sx * 1.12, -1.42, 0), 0.12), "Bough", (3, 5)))
        parts.append(Part(f"thatch{sx}", thatch((lx + sx * 0.2, 1.42, 2.35), (0, 0, -4.5), (sx * 1.05, -1.3, 0), 10, 5, 0.7, jitter=0.08, seed=62 + sx), "Bough", (3, 5), cut="drop"))
    parts += bed_parts(-0.4, 0.0, -0.3, 0.34, 1.9)
    # 上风侧堆雪（第 5 阶段）：贴在斜墙外面，只到半高
    parts.append(Part("snowbank", lambda: lumpy(bm_ell((lx - 1.55, -0.2, 0.15), (0.6, 0.85, 2.7), 28, 14), 0.08, 1.5, 64), "Snow", (5, 5)))
    return parts

PRESETS = {
    "RaisedCave": lambda: cave(True), "BasicCave": lambda: cave(False), "Quinzhee": quinzhee,
    "SnowTrench": trench, "LeanTo": leanto, "TreeWell": treewell, "RockOverhang": rock_overhang, "FallenLog": fallen_log,
}

# ---------------------------------------------------------------- section: cut + baked light
SUN = Vector((0.55, 1.0, 0.45)).normalized()      # from the camera's side (+X), above, a little toward the door

def section_objects(parts):
    objs = []
    for p in parts:
        if not p.sec:
            continue
        if p.stages is not None and p.stages[1] < 5:
            continue
        o = build_obj(p, "sec_" + p.label, half=(p.cut == "bool"))
        if p.cut == "drop":
            # 散件（枝条、木棍）：整件留下或整件去掉，不切
            bm = bmesh.new()
            bm.from_mesh(o.data)
            for isl in _islands(bm):
                if max(v.co.x for v in isl) > 0.15:
                    bmesh.ops.delete(bm, geom=list(isl), context="VERTS")
            bm.to_mesh(o.data)
            bm.free()
        if len(o.data.vertices) == 0:
            kill(o)
            continue
        objs.append(o)
    return objs

def _islands(bm):
    bm.verts.ensure_lookup_table()
    seen = set()
    out = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        isl = []
        seen.add(v.index)
        while stack:
            a = stack.pop()
            isl.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    stack.append(b)
        out.append(isl)
    return out

def full_occluder(parts):
    """The finished shelter uncut (both halves): light is baked as if the cave were closed, so the inside
    is dim and the candle carries it, the way it really is, even though we look in through the cut."""
    bm_all = bmesh.new()
    for p in parts:
        if not p.sec or (p.stages is not None and p.stages[1] < 5):
            continue
        o = build_obj(p, "occ_" + p.label)
        bm_all.from_mesh(o.data)
        kill(o)
    return bm_all

def bake(objs, candle, occluder):
    """Per-corner colour = material colour x (sky AO + sun with shadow + candle). Godot draws it unshaded.
    Cut faces get a flat bright tone (a diagram's section fill) with a faint warm edge near the candle."""
    bm_all = occluder
    g = bmesh.ops.create_grid(bm_all, x_segments=1, y_segments=1, size=12.0)   # 地面（只挡光，不导出）
    for v in g["verts"]:
        v.co = Vector((v.co.x, -0.02, v.co.y))
    bvh = BVHTree.FromBMesh(bm_all)
    bm_all.free()
    dirs = []
    r = random.Random(3)
    while len(dirs) < 20:
        d = Vector((r.uniform(-1, 1), r.uniform(0, 1), r.uniform(-1, 1)))
        if 0.05 < d.length <= 1.0:
            dirs.append(d.normalized())
    for o in objs:
        me = o.data
        me.calc_normals_split()
        col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        cache = {}
        mats = [m.name.split(".")[0] for m in me.materials]
        for poly in me.polygons:
            mname = mats[poly.material_index]
            base = Vector(COLORS[mname])
            glow = mname in ("Glow",)
            is_cut = mname.endswith("Cut") and poly.normal.x > 0.9
            for li in poly.loop_indices:
                loop = me.loops[li]
                p = me.vertices[loop.vertex_index].co
                n = Vector(loop.normal)
                key = (round(p.x, 3), round(p.y, 3), round(p.z, 3), round(n.x, 1), round(n.y, 1), round(n.z, 1))
                if key not in cache:
                    cache[key] = _light(bvh, p + n * 0.012, n, dirs, candle)
                if glow:
                    c = Vector((1.0, 0.8, 0.5))
                elif is_cut:
                    k = 0.9 + 0.1 * min(max(p.y / 2.0, 0.0), 1.0)
                    c = base * k
                    if candle is not None:
                        d = (Vector(candle) - p).length
                        c += Vector((0.12, 0.05, -0.02)) * max(0.0, 1.0 - d / 2.2)
                else:
                    sky, warm = cache[key]
                    c = Vector((base.x * sky, base.y * sky, base.z * sky)) + warm * (base + Vector((0.4, 0.3, 0.2))) * 0.5
                col.data[li].color = (min(c.x, 1.0), min(c.y, 1.0), min(c.z, 1.0), 1.0)
        me.color_attributes.active_color = col

def _light(bvh, p, n, dirs, candle):
    # 天光遮蔽：法线半球内的方向
    open_ = 0
    tot = 0
    for d in dirs:
        if d.dot(n) <= 0.05:
            d = -d if (-d).dot(n) > 0.05 else None
        if d is None:
            continue
        tot += 1
        if bvh.ray_cast(p, d, 1.6)[0] is None:
            open_ += 1
    ao = open_ / max(tot, 1)
    sun = max(0.0, n.dot(SUN))
    if sun > 0 and bvh.ray_cast(p, SUN, 8.0)[0] is not None:
        sun *= 0.25
    sky = 0.45 + 0.42 * ao + 0.3 * sun     # 洞里也有雪透进来的蓝光：底子不能太暗
    warm = Vector((0, 0, 0))
    if candle is not None:
        to = Vector(candle) - p
        dist = to.length
        if dist < 3.4 and n.dot(to) > 0:
            hit = bvh.ray_cast(p, to.normalized(), dist - 0.05)[0]
            if hit is None:
                k = (1.0 - dist / 3.4) ** 2 * (0.4 + 0.6 * n.dot(to.normalized()))
                warm = Vector((1.0, 0.55, 0.2)) * k * 3.0
    return sky, warm

# ---------------------------------------------------------------- export
def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.data.transform(TO_BLENDER)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_colors=True, export_normals=True, export_materials="EXPORT")

def stage_name(p):
    a, b = p.stages
    return f"s{a}_{b}__{p.label}"

def build(preset):
    os.makedirs(OUT_DIR, exist_ok=True)
    reset()
    parts = PRESETS[preset]()
    # 外观
    ext = []
    for p in parts:
        if p.stages is None:
            continue
        o = build_obj(p, stage_name(p))
        for poly in o.data.polygons:
            poly.use_smooth = p.material in ("Snow", "SnowIn", "Rock")
        ext.append(o)
    export(ext, f"{OUT_DIR}/{preset}.glb")
    tris_ext = sum(len(pp.vertices) - 2 for o in ext for pp in o.data.polygons)
    for o in ext:
        kill(o)
    # 剖面
    sec = section_objects(parts)
    candle = None
    for p in parts:
        if p.label == "flame":
            bm = p.make()
            candle = tuple(sum((v.co for v in bm.verts), Vector()) / len(bm.verts) + Vector((0.06, 0.08, 0.0)))
            bm.free()
    bake(sec, candle, full_occluder(parts))
    for o in sec:
        for poly in o.data.polygons:
            poly.use_smooth = True
    tris_sec = sum(len(pp.vertices) - 2 for o in sec for pp in o.data.polygons)
    if PREVIEW:
        _preview(sec, preset)
    export(sec, f"{OUT_DIR}/{preset}_section.glb")
    print("BUILT", preset, "exterior tris", tris_ext, "section tris", tris_sec)

def _preview(objs, preset):
    """Quick look at the baked section from the game's section camera direction (before export transform)."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "FLAT"
    sh.color_type = "VERTEX"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    world.color = (0.18, 0.22, 0.30)
    scene.world = world
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(36)
    scene.collection.objects.link(cam)
    scene.camera = cam
    # Godot 相机：aim + (cos26*5.6, sin26*5.6, -0.9) → 转成 Blender 坐标
    aim = Vector((0, 0.75, 0.3))
    loc = aim + Vector((math.cos(math.radians(24)) * 6.4, math.sin(math.radians(24)) * 6.4, -0.9))
    tb = lambda v: Vector((v.x, -v.z, v.y))
    for o in objs:
        o.matrix_world = TO_BLENDER
    cam.location = tb(loc)
    cam.rotation_euler = (tb(aim) - tb(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = f"{PREVIEW}/{preset}_section.png"
    bpy.ops.render.render(write_still=True)
    for o in objs:
        o.matrix_world = Matrix.Identity(4)
    bpy.data.objects.remove(cam, do_unlink=True)

for name in PRESETS:
    if ONLY and name not in ONLY:
        continue
    build(name)
