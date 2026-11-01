"""Build 3 angular rock outcrops (rock_outcrop_A/B/C.glb) procedurally in Blender 4.x.

Run:  blender --background --python tools/blender/build_rocks.py -- assets/models
Faceted, broken-slab boulders ~1 m unit size (scaled in game), flat shaded, no material
(the game applies snow_cover.gdshader so the tops get snow automatically).
"""
import bpy, bmesh, sys, random, math
from mathutils import Vector, noise

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."

def build(name, seed, squash, lean):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    off = Vector((seed * 3.1, seed * 1.7, seed * 0.9))
    for v in bm.verts:
        n = noise.noise(v.co * 1.3 + off)
        v.co *= 1.0 + 0.35 * n
        v.co.z *= squash
        v.co.x += lean * max(v.co.z, 0.0)
        if v.co.z < -0.15:
            v.co.z = -0.15
    # 平切几刀：做出层理断面（棱角）
    for k in range(4):
        a = random.uniform(0, math.tau)
        nrm = Vector((math.cos(a), math.sin(a), random.uniform(-0.2, 0.6))).normalized()
        d = random.uniform(0.55, 0.8)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=nrm * d, plane_no=nrm, clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.select_set(True)
    path = f"{OUT}/{name}.glb"
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    print("EXPORTED", path, "tris", len(me.polygons))

build("rock_outcrop_A", 1, 0.75, 0.10)
build("rock_outcrop_B", 2, 0.55, -0.15)
build("rock_outcrop_C", 3, 0.95, 0.05)
