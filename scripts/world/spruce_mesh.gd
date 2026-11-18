class_name SpruceMesh
extends RefCounted

## 程序化云杉网格：带锯齿、下垂的枝层 + 树干，单 surface。
## 形态规则（玩家可由此读风向）：
##   * 迎风侧枝条更短（风蚀），背风侧更长；
##   * 树冠整体向背风侧偏（lean）。
## wind_dir 为「风吹向」（下风）的水平单位向量（WindData.get_blow_direction_3d()）。
## 纯几何，不含任何玩法数值；比例常量是艺术参数，保留在此。

const TIERS := 6
const SPIKES := 11

## spikes：每层枝尖数（远景可降到 6 省面数）。
static func build(seed_idx: int, wind_dir: Vector3, wind_bias: float = 0.38, spikes: int = SPIKES) -> ArrayMesh:
	# 远景保留原来的低面数轮廓，近景改成分离枝簇；不使用透明叶片。
	if spikes >= SPIKES:
		return _branched(seed_idx, wind_dir, wind_bias)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wd := Vector2(wind_dir.x, wind_dir.z)
	wd = wd.normalized() if wd.length() > 0.001 else Vector2(1.0, 0.0)

	_trunk(st, 2.2, 0.20, 0.07)

	var y := 1.0
	for t in range(TIERS):
		var f := float(t) / float(TIERS - 1)            # 0 底层 → 1 顶层
		var radius := lerpf(1.95, 0.55, f)
		var height := lerpf(1.75, 1.15, f)
		var droop := lerpf(0.62, 0.30, f)
		var lean := wind_bias * 0.18 * (0.4 + f)        # 越高越偏
		var rot := TerrainHeight.hash2(seed_idx * 13 + t, t + 5, 307) * TAU
		_tier(st, seed_idx * 31 + t, Vector3(wd.x * lean, y, wd.y * lean), radius, height, droop, rot, wd, wind_bias, spikes)
		y += height * 0.56
	st.generate_normals()
	return st.commit()


static func _trunk(st: SurfaceTool, h: float, r_bot: float, r_top: float) -> void:
	var n := 7
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var b0 := Vector3(cos(a0) * r_bot, 0.0, sin(a0) * r_bot)
		var b1 := Vector3(cos(a1) * r_bot, 0.0, sin(a1) * r_bot)
		var t0 := Vector3(cos(a0) * r_top, h, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, h, sin(a1) * r_top)
		_tri(st, b0, t0, b1)
		_tri(st, b1, t0, t1)


## 一层枝：顶点 → 内环（略抬起）→ 外环锯齿（长枝尖下垂、凹口收进）。
static func _tier(st: SurfaceTool, s: int, center: Vector3, radius: float, height: float,
		droop: float, rot: float, wd: Vector2, wind_bias: float, spikes: int) -> void:
	var n := spikes * 2
	var apex := center + Vector3(0.0, height, 0.0)
	var inner: Array[Vector3] = []
	var outer: Array[Vector3] = []
	for i in range(n):
		var a := rot + TAU * float(i) / float(n)
		var dir := Vector2(cos(a), sin(a))
		var is_tip := (i % 2) == 0
		var rnd := TerrainHeight.hash2(s * 7 + i, i + 1, 521)
		# 迎风侧 = dot(dir, wd) < 0 → 缩短；背风侧略长
		var lee := dir.dot(wd)
		var wind_k := 1.0 + wind_bias * lee * 0.55
		var r := radius * (0.82 + 0.18 * rnd) * wind_k
		if not is_tip:
			r *= 0.58
		var tip_y := center.y + (-droop * r / radius) if is_tip else center.y + 0.16
		outer.append(Vector3(center.x + dir.x * r, tip_y, center.z + dir.y * r))
		var ri := r * 0.52
		inner.append(Vector3(center.x + dir.x * ri, center.y + height * 0.34 + (0.10 if is_tip else 0.0), center.z + dir.y * ri))
	for i in range(n):
		var j := (i + 1) % n
		_tri(st, apex, inner[i], inner[j])
		_tri(st, inner[i], outer[i], outer[j])
		_tri(st, inner[i], outer[j], inner[j])
		# 底面（仰视可见）
		_tri(st, Vector3(center.x, center.y + 0.04, center.z), outer[j], outer[i])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## 近景单 surface：黑色顶点标树干、灰白顶点标针叶，由统一积雪材质区分。
## 下面的长度/比例都是模型内部几何，不是玩法或环境参数。每棵 <= 660 三角形。
static func _branched(seed_idx: int, wind_dir: Vector3, wind_bias: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wd := wind_dir.normalized() if wind_dir.length_squared() > 0.0001 else Vector3.RIGHT
	var lean := wd * wind_bias * 0.42
	st.set_color(Color.BLACK)
	for section in 3:
		var a := float(section) / 3.0
		var b := float(section + 1) / 3.0
		_branch_wood(st, Vector3(0, a * 6.6, 0) + lean * a * a,
			Vector3(0, b * 6.6, 0) + lean * b * b, lerpf(0.18, 0.025, a))
	for tier in TIERS:
		var f := float(tier) / float(TIERS - 1)
		var y := lerpf(1.25, 5.85, f)
		var radius := lerpf(1.95, 0.48, f)
		var phase := TerrainHeight.hash2(seed_idx, tier, 811) * TAU
		var center := Vector3(0, y, 0) + lean * f * f
		for branch in 6:
			var rnd := TerrainHeight.hash2(seed_idx * 13 + tier, branch, 813)
			var angle := phase + TAU * float(branch) / 6.0 + (rnd - 0.5) * 0.3
			var dir := Vector3(cos(angle), 0, sin(angle))
			var side := Vector3(-dir.z, 0, dir.x)
			var length := radius * (0.76 + 0.3 * rnd) * (1.0 + wind_bias * dir.dot(wd) * 0.55)
			var start := center + dir * 0.14
			var end := center + dir * length + Vector3(0, -length * 0.24, 0)
			st.set_color(Color.BLACK)
			_branch_wood(st, start, end, lerpf(0.045, 0.018, f))
			st.set_color(Color.WHITE * (0.78 + 0.22 * rnd))
			_bough(st, start.lerp(end, 0.22), end + dir * 0.12, side, length * 0.29, length * 0.11)
			# 每根枝条的侧枝是一簇四面体，不增加透明叠层或材质槽。
			var fork := start.lerp(end, 0.6)
			var tip := fork + side * length * (0.26 if branch % 2 == 0 else -0.26) + dir * length * 0.2
			_twig(st, fork, tip, length * 0.16)
	st.set_color(Color.WHITE)
	_bough(st, Vector3(0, 5.7, 0) + lean, Vector3(0, 6.85, 0) + lean, Vector3.RIGHT, 0.22, 0.15)
	st.generate_normals()
	return st.commit()


## 四面体木枝，连续三节树干也用相同封闭几何。
static func _branch_wood(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.01: side = Vector3.RIGHT
	var up := axis.cross(side).normalized()
	var p := a + side * r
	var q := a - side * r * 0.5 + up * r
	var t := a - side * r * 0.5 - up * r
	_near_tri(st, p, q, b); _near_tri(st, q, t, b); _near_tri(st, t, p, b); _near_tri(st, p, t, q)


## 厚枝簇：上表面接雪，尖端下垂，枝间空隙能透出树干。
static func _bough(st: SurfaceTool, a: Vector3, b: Vector3, side: Vector3, width: float, height: float) -> void:
	var mid := a.lerp(b, 0.55)
	var l := mid - side * width
	var r := mid + side * width
	var top := mid + Vector3.UP * height
	var bottom := mid - Vector3.UP * height * 0.24
	_near_tri(st, a, top, l); _near_tri(st, l, top, b); _near_tri(st, b, top, r); _near_tri(st, r, top, a)
	_near_tri(st, a, l, bottom); _near_tri(st, l, b, bottom); _near_tri(st, b, r, bottom); _near_tri(st, r, a, bottom)


static func _twig(st: SurfaceTool, a: Vector3, b: Vector3, width: float) -> void:
	var side := (b - a).cross(Vector3.UP).normalized() * width
	var top := a.lerp(b, 0.4) + Vector3.UP * width * 0.5
	_near_tri(st, a - side, top, b); _near_tri(st, b, top, a + side)
	_near_tri(st, a + side, top, a - side); _near_tri(st, a - side, b, a + side)


## Godot front faces use clockwise winding. Keep the legacy far mesh unchanged.
static func _near_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	_tri(st, a, c, b)
