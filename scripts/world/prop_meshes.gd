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


## 白桦：白色树干 + 横向黑斑（顶点色）+ 稀疏细枝。高约 6 m。顶点色 R/G/B 直接用作颜色。
static func birch(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 5.5 + TerrainHeight.hash2(seed_idx, 1, 81) * 1.5
	var segs := 10
	for i in range(segs):
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var dark := TerrainHeight.hash2(seed_idx, i, 83) > 0.62
		var col := Color(0.12, 0.11, 0.10) if dark else Color(0.88, 0.86, 0.80)
		st.set_color(col)
		_frustum(st, Vector3(0, h * t0, 0), lerpf(0.16, 0.05, t0), Vector3(0, h * t1, 0), lerpf(0.16, 0.05, t1), 7)
	st.set_color(Color(0.35, 0.28, 0.22))
	for b in range(7):
		var bt := lerpf(0.45, 0.92, float(b) / 6.0)
		var ang := TerrainHeight.hash2(seed_idx, b, 87) * TAU
		var base := Vector3(0, h * bt, 0)
		_frustum(st, base, 0.03, base + Vector3(cos(ang), 0.55, sin(ang)) * lerpf(1.2, 0.6, bt), 0.006, 4)
	st.generate_normals()
	return st.commit()


## 翻倒树根盘（Root Ball）+ 倒伏树干：天然挡风物。树根盘立在原点，树干沿 +X 躺倒。
static func rootball(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 树根盘：竖起的扁圆盘 + 放射状根须
	var r := 1.5
	var n := 14
	var c := Vector3(0, r * 0.85, 0)
	for i in range(n):
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		var j0 := 0.8 + TerrainHeight.hash2(seed_idx, i, 91) * 0.35
		var j1 := 0.8 + TerrainHeight.hash2(seed_idx, (i + 1) % n, 91) * 0.35
		var p0 := c + Vector3(0, sin(a0) * r * j0, cos(a0) * r * j0)
		var p1 := c + Vector3(0, sin(a1) * r * j1, cos(a1) * r * j1)
		var f := Vector3(-0.35, 0, 0)
		st.add_vertex(c + f); st.add_vertex(p0 + f); st.add_vertex(p1 + f)
		st.add_vertex(c - f); st.add_vertex(p1 - f); st.add_vertex(p0 - f)
		_frustum(st, p0 - f, 0.18, p0 + f, 0.18, 4)
		_frustum(st, p0, 0.07, p0 + (p0 - c).normalized() * 0.6 + Vector3(0, -0.2, 0), 0.01, 3)
	# 倒伏树干
	_frustum(st, Vector3(0.2, 0.55, 0), 0.42, Vector3(7.5, 0.35, 0.4), 0.2, 8)
	st.generate_normals()
	return st.commit()


## 半埋湿倒木（反面教材：湿木不能烧）。
static func wet_log(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := 3.5 + TerrainHeight.hash2(seed_idx, 2, 95) * 1.5
	_frustum(st, Vector3(-l * 0.5, 0.12, 0), 0.26, Vector3(l * 0.5, 0.08, 0.1), 0.18, 7)
	st.generate_normals()
	return st.commit()


## 干草丛（垫层来源）：一簇细锥。
static func grass_tuft(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(9):
		var a := TerrainHeight.hash2(seed_idx, k, 97) * TAU
		var d := TerrainHeight.hash2(seed_idx, k, 99) * 0.25
		var base := Vector3(cos(a) * d, 0, sin(a) * d)
		var h := 0.45 + TerrainHeight.hash2(seed_idx, k, 101) * 0.35
		var lean := Vector3(cos(a), 0, sin(a)) * 0.18
		_frustum(st, base, 0.03, base + lean + Vector3(0, h, 0), 0.003, 3)
	st.generate_normals()
	return st.commit()


## 风积雪舌：迎风端（-Z）圆钝高起，向下风（+Z）拉长变薄成尖，单位尺寸约 1×0.5×2。
static func snow_drift() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 16   # 沿长度
	var nv := 12   # 横截面
	var pts: Array = []
	for i in range(nu + 1):
		var u := float(i) / nu                       # 0 迎风 → 1 下风
		var half_w := 0.5 * sin(pow(u, 0.35) * PI) * (1.0 - 0.6 * u)
		var hgt := 0.5 * pow(sin(pow(u, 0.5) * PI), 1.2) * (1.0 - 0.7 * u) + 0.0
		var z := -1.0 + 2.0 * u
		var row: Array = []
		for j in range(nv + 1):
			var v := float(j) / nv                   # 0..1 横向
			var x := (v * 2.0 - 1.0) * half_w
			var y := hgt * (1.0 - pow(absf(v * 2.0 - 1.0), 2.0))
			row.append(Vector3(x, y, z))
		pts.append(row)
	for i in range(nu):
		for j in range(nv):
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
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
