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
	# 倒伏树干：长短不一、微微弯曲，沿途几根断枝桩（以前每棵都是同一根直棍，朝向也固定）
	var tl := 5.2 + TerrainHeight.hash2(seed_idx, 3, 131) * 3.6
	var bend := (TerrainHeight.hash2(seed_idx, 4, 131) - 0.5) * 1.4
	var mid := Vector3(tl * 0.5, 0.5, bend)
	var tip := Vector3(tl, 0.33, bend * 0.4 + (TerrainHeight.hash2(seed_idx, 5, 131) - 0.5) * 0.8)
	_frustum(st, Vector3(0.2, 0.55, 0), 0.42, mid, 0.3, 8)
	_frustum(st, mid, 0.3, tip, 0.18, 8)
	for b in range(3 + int(TerrainHeight.hash2(seed_idx, 6, 131) * 3.0)):
		var t := lerpf(0.3, 0.9, TerrainHeight.hash2(seed_idx, b, 133))
		var base := mid.lerp(tip, (t - 0.5) * 2.0) if t > 0.5 else Vector3(0.2, 0.55, 0).lerp(mid, t * 2.0)
		var side := 1.0 if TerrainHeight.hash2(seed_idx, b, 135) > 0.5 else -1.0
		_frustum(st, base, 0.07, base + Vector3(0.25, 0.35, side * (0.5 + 0.4 * TerrainHeight.hash2(seed_idx, b, 137))), 0.02, 4)
	st.generate_normals()
	return st.commit()


## 倒伏的大树干（装饰 + 倒木庇护所的现成脊梁）：原点在中点，沿 +X；放置时随机朝向、微微陷进雪里。
static func fallen_trunk(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := 3.6 + TerrainHeight.hash2(seed_idx, 2, 141) * 2.6
	var r0 := 0.3 + TerrainHeight.hash2(seed_idx, 3, 141) * 0.12
	var sag := (TerrainHeight.hash2(seed_idx, 4, 141) - 0.5) * 0.5
	var a := Vector3(-l * 0.5, 0.3, 0)
	var m := Vector3(0, 0.26, sag)
	var b := Vector3(l * 0.5, 0.3, sag * 0.3)
	_frustum(st, a, r0, m, r0 * 0.88, 7)
	_frustum(st, m, r0 * 0.88, b, r0 * 0.7, 7)
	for k in range(2 + int(TerrainHeight.hash2(seed_idx, 5, 141) * 3.0)):
		var t := lerpf(0.1, 0.9, TerrainHeight.hash2(seed_idx, k, 143))
		var base := a.lerp(m, t * 2.0) if t < 0.5 else m.lerp(b, (t - 0.5) * 2.0)
		var side := 1.0 if TerrainHeight.hash2(seed_idx, k, 145) > 0.5 else -1.0
		_frustum(st, base + Vector3(0, r0 * 0.6, 0), 0.06, base + Vector3(0.2, 0.55, side * (0.3 + 0.5 * TerrainHeight.hash2(seed_idx, k, 147))), 0.015, 4)
	st.generate_normals()
	return st.commit()


## 树桩：矮而粗，顶部歪斜（砍断 / 折断）。原点在底面中心。
static func stump(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.45 + TerrainHeight.hash2(seed_idx, 2, 151) * 0.5
	var r := 0.28 + TerrainHeight.hash2(seed_idx, 3, 151) * 0.16
	_frustum(st, Vector3(0, -0.1, 0), r * 1.25, Vector3(0.04, h, 0.03), r * 0.82, 8)
	_frustum(st, Vector3(0.04, h, 0.03), r * 0.82, Vector3(0.1, h + 0.14, 0.06), r * 0.45, 5)
	st.generate_normals()
	return st.commit()


## 枯灌木：一簇细而弯的枝条，从贴地处向外向上散开。原点在根部，约 0.8 m 高。
static func shrub(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12 + int(TerrainHeight.hash2(seed_idx, 1, 161) * 6.0)
	for k in range(n):
		var ang := TerrainHeight.hash2(seed_idx, k, 163) * TAU
		var spread := 0.15 + TerrainHeight.hash2(seed_idx, k, 165) * 0.55
		var h := 0.45 + TerrainHeight.hash2(seed_idx, k, 167) * 0.5
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var mid := out * spread * 0.5 + Vector3(0, h * 0.6, 0)
		var tip := out * spread + Vector3(0, h, 0)
		_frustum(st, Vector3(0, -0.05, 0), 0.022, mid, 0.014, 3)
		_frustum(st, mid, 0.014, tip, 0.004, 3)
		if k % 3 == 0:
			_frustum(st, mid, 0.01, mid + out.rotated(Vector3.UP, 0.9) * 0.18 + Vector3(0, 0.12, 0), 0.003, 3)
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


## 云杉低枝丛：贴地的一矮堆宽枝（不是小树）。约 1.9 m 宽、0.55 m 高，放置时不缩放。
## 两层重叠的宽枝，枝梢落到雪面，轮廓是闭合的矮丘，下面没有空隙（否则读成带腿的虫）。
## 枝片两面都画（snow_cover 只画正面）。
static func bough_clump(seed_idx: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # 平面法线：两面重合的顶点若一起平滑，法线相消、枝变成全黑
	for layer in [[9, 0.95, 0.34, 0.0], [6, 0.55, 0.52, 0.5]]:
		var count: int = layer[0]
		for b in range(count):
			var a := TAU * (float(b) + float(layer[3]) + (TerrainHeight.hash2(seed_idx, b, 111) - 0.5) * 0.35) / float(count)
			var out := Vector3(cos(a), 0.0, sin(a))
			var side := Vector3(-out.z, 0.0, out.x)
			var length: float = float(layer[1]) * (0.85 + TerrainHeight.hash2(seed_idx, b, 113) * 0.3)
			var rise: float = layer[2]
			var segs := 4
			var prev := Vector3.UP * rise
			for i in range(1, segs + 1):
				var t := float(i) / float(segs)
				var c := out * length * t + Vector3.UP * (rise * (1.0 - t * t) + 0.01)
				var w := lerpf(0.42, 0.16, t) * (length / 0.95 * 0.5 + 0.5)
				for sgn in [-1.0, 1.0]:
					# 枝片外缘一直垂到比枝低的位置，相邻枝互相盖住
					var edge_prev: Vector3 = prev + side * sgn * w * 0.8 + Vector3.DOWN * minf(prev.y * 0.8, 0.14)
					var edge: Vector3 = c + side * sgn * w + Vector3.DOWN * minf(c.y, 0.14)
					_two_sided(st, prev, c, edge)
					_two_sided(st, prev, edge, edge_prev)
				prev = c
	st.generate_normals()
	return st.commit()

static func _two_sided(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c, a, c, b]:
		st.add_vertex(v)


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
