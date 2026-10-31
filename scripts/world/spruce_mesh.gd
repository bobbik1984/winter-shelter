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
