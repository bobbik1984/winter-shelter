class_name PropMeshes
extends RefCounted

## 程序化道具网格：枯立木（snag）与岩石露头。均为单 surface、平面着色，
## 配合 snow_cover.gdshader 自动积雪。纯几何，无玩法数值。

## 枯立木：渐细略弯的树干 + 断枝 + 折断的树梢。高约 7 m。
static func snag(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 6.2 + TerrainHeight.hash2(seed_idx, 1, 71) * 2.0
	var lean := Vector2(TerrainHeight.hash2(seed_idx, 2, 71) - 0.5, TerrainHeight.hash2(seed_idx, 3, 71) - 0.5) * 0.5
	var segs := 6
	var prev_c := Vector3.ZERO
	var prev_r := 0.24
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var c := Vector3(lean.x * t * t, h * t, lean.y * t * t)
		var r := lerpf(0.24, 0.035, pow(t, 0.8))
		_frustum(st, prev_c, prev_r, c, r, 7)
		prev_c = c
		prev_r = r
	# 断枝：下半部分短而下垂，上半部分更细
	var branches := 9
	for b in range(branches):
		var bt := lerpf(0.25, 0.88, float(b) / float(branches - 1)) + (TerrainHeight.hash2(seed_idx, b, 91) - 0.5) * 0.06
		var base := Vector3(lean.x * bt * bt, h * bt, lean.y * bt * bt)
		var ang := TerrainHeight.hash2(seed_idx, b, 93) * TAU
		var length := lerpf(1.5, 0.5, bt) * (0.5 + TerrainHeight.hash2(seed_idx, b, 97) * 0.7)
		var droop := lerpf(-0.45, 0.15, bt)
		var tip := base + Vector3(cos(ang), droop, sin(ang)).normalized() * length
		_frustum(st, base, lerpf(0.06, 0.025, bt), tip, 0.008, 4)
	st.generate_normals()
	return st.commit()


## 岩石：位移噪声的扁球，底部压平，平面着色。约 1 m 半径，放置时再缩放。
static func rock(seed_idx: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 7
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(verts.size()):
		var v := verts[i]
		# 用量化坐标做哈希，保证接缝处重复顶点位移一致（否则会裂开）
		var q := Vector3i(roundi(v.x * 100.0), roundi(v.y * 100.0), roundi(v.z * 100.0))
		var n1 := TerrainHeight.hash2(q.x + q.y * 7, q.z + seed_idx * 13, 301)
		var n2 := TerrainHeight.value_noise(v.x * 1.7 + float(seed_idx), v.z * 1.7 + v.y, seed_idx)
		var k := 0.78 + n2 * 0.38 + n1 * 0.10
		v *= k
		v.y = maxf(v.y, -0.15) * 0.72   # 压平底部、整体略扁
		verts[i] = v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		st.add_vertex(verts[i])
	st.generate_normals()
	return st.commit()


static func _frustum(st: SurfaceTool, a: Vector3, ra: float, b: Vector3, rb: float, sides: int) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := u * cos(a0) + w * sin(a0)
		var d1 := u * cos(a1) + w * sin(a1)
		var p0 := a + d0 * ra
		var p1 := a + d1 * ra
		var q0 := b + d0 * rb
		var q1 := b + d1 * rb
		st.add_vertex(p0)
		st.add_vertex(q0)
		st.add_vertex(p1)
		st.add_vertex(p1)
		st.add_vertex(q0)
		st.add_vertex(q1)
