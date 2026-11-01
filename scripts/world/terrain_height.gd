class_name TerrainHeight
extends RefCounted

## M1->M2 多尺度雪原高度场（主创定标版）：
## 结合参考图 Box 1 (阶梯台地体块) -> Box 2/3 (蜿蜒主脊 + 背风风积雪包 + 局部雪枕 + 远景下沉谷口)。
## 纯函数、可测试、无节点依赖。

const GRID := 52
const WORLD_SIZE := 100.0
const HALF_SIZE := 50.0
## 噪声种子：只影响起伏 / 风积肋 / 雪深分布，不改迎风坡—脊线—背风坡的主结构。
## 默认 7（测试基准）；GameDirector 在重开时切换到下一个山谷（VALLEY_SEEDS）。
const VALLEY_SEEDS := [7, 13, 29, 41]
static var SEED: int = 7
## T4.7 方案 A：迎风脊上的低垭口（出生点西南视线方向），露出远景山谷与冰湖。默认关闭；由 Tuning.ridge_saddle 打开。
static var SADDLE: bool = false
## D12 关卡雪深旋钮（由 LevelState.apply_world 在场景加载前设置；默认 = 不变）。
## [TUNE] 雪深倍率；[TUNE] 斑驳度 0..1（风蚀）：低频噪声选出少数"保留斑块"，
## 斑块以外的雪按 (1 − 斑驳度) 削薄——背风深雪带断成几块，深雪只在少数地方，必须探测（第 2 关）。
## 只削不加：对称起伏会让深雪面积几乎不变（L2 实测）。
static var SNOW_SCALE: float = 1.0
static var SNOW_PATCHINESS: float = 0.0
## D12 / L3 风向随机 = 整图布局绕 Y 轴旋转（度，取 90° 的倍数；地图是正方形，旋转后边界不变）。
## 所有带世界坐标的公开采样函数先换回"地图坐标"再计算，所以迎风坡—脊线—背风坡与风一起转；
## 地图坐标里风永远来自 -X（WindData.direction 的基础值）。由 LevelState.apply_world 设置。
static var ROTATION_DEG: float = 0.0
## D13 / S1 地形配方（形态 × 起伏 × 树密度）。默认 = 旧的固定地图。由 LevelState.apply_world / 开发参数设置。
static var RECIPE: TerrainRecipe = TerrainRecipe.new()

## 地图坐标 → 世界坐标（脚本里写死的出生点、树根、枯木等都是地图坐标）。
static func to_world(map_xz: Vector2) -> Vector2:
	if ROTATION_DEG == 0.0:
		return map_xz
	var v := Vector3(map_xz.x, 0.0, map_xz.y).rotated(Vector3.UP, deg_to_rad(ROTATION_DEG))
	return Vector2(v.x, v.z)

static func to_world3(map_pos: Vector3) -> Vector3:
	var w := to_world(Vector2(map_pos.x, map_pos.z))
	return Vector3(w.x, map_pos.y, w.y)

## 世界坐标 → 地图坐标。
static func to_map(x: float, z: float) -> Vector2:
	if ROTATION_DEG == 0.0:
		return Vector2(x, z)
	var v := Vector3(x, 0.0, z).rotated(Vector3.UP, -deg_to_rad(ROTATION_DEG))
	return Vector2(v.x, v.z)

## 世界方向随地图旋转（风向用）。
static func rotate_dir(map_dir: Vector3) -> Vector3:
	return map_dir if ROTATION_DEG == 0.0 else map_dir.rotated(Vector3.UP, deg_to_rad(ROTATION_DEG))
## 斑驳噪声的空间尺度（网格单位，约 2 m/格 → 斑块约 10–15 m）与噪声值的拉伸系数（数学常量）。
const PATCH_NOISE_SCALE := 5.0
const PATCH_NOISE_STRETCH := 2.8
## 垭口中心（世界坐标 x, z）、半宽（m）、深度（m）。
const SADDLE_CENTER := Vector2(-6.0, 32.0)
const SADDLE_RADIUS := 9.0
const SADDLE_DEPTH := 4.2

static func hash2(x: int, y: int, seed: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + seed * 2246822519
	h = h & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h) / 4294967295.0

static func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

static func value_noise(x: float, y: float, noise_seed: int = 1) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var xf := smooth(x - float(xi))
	var yf := smooth(y - float(yi))
	var a := hash2(xi, yi, noise_seed)
	var b := hash2(xi + 1, yi, noise_seed)
	var c := hash2(xi, yi + 1, noise_seed)
	var d := hash2(xi + 1, yi + 1, noise_seed)
	return a + (b - a) * xf + (c - a) * yf + (a - b - c + d) * xf * yf

static func fbm(x: float, y: float, noise_seed: int, octaves: int = 4) -> float:
	var v := 0.0
	var amp := 1.0
	var freq := 1.0
	var norm := 0.0
	for i in range(octaves):
		v += value_noise(x * freq, y * freq, noise_seed + i * 17) * amp
		norm += amp
		amp *= 0.5
		freq *= 2.07
	return v / norm

static func _grid_coord(value: float) -> float:
	return clampf((value + HALF_SIZE) / WORLD_SIZE * float(GRID - 1), 0.0, float(GRID - 1))

static func _ridge_center_i(j: float) -> float:
	var wy := j / float(GRID - 1)
	# 在 z=0 (wy=0.5) 处锚定在 RECIPE.feature_i（旧值 17.8），向南北两侧呈自然 S 型蜿蜒
	var s_curve := sin((wy - 0.5) * PI * 2.1) * 4.2
	var organic := (fbm(wy * 3.2, 1.7, SEED + 19, 3) - 0.5) * 3.8 * absf(wy - 0.5) * 2.0
	return RECIPE.feature_i + s_curve + organic

## 湖岸线 / 崖线（规范帧网格 i，随 j 蜿蜒）。
static func _shore_i(j: float) -> float:
	var wy := j / float(GRID - 1)
	return RECIPE.feature_i + sin(wy * PI * 1.7 + float(SEED)) * 2.5 + (fbm(wy * 4.0, 3.3, SEED + 23, 3) - 0.5) * 4.0

static func _cliff_i(j: float) -> float:
	var wy := j / float(GRID - 1)
	return RECIPE.feature_i + sin(wy * PI * 1.3 + float(SEED) * 0.7) * 3.0 + (fbm(wy * 3.0, 5.1, SEED + 41, 3) - 0.5) * 5.0

## 湖面高度（m）：冰面平整。
const LAKE_ICE_H := 0.25

static func _height_from_grid(i: float, j: float) -> float:
	match RECIPE.shape:
		"basin": return _height_basin(i, j)
		"lakeshore": return _height_lakeshore(i, j)
		"cliff_band": return _height_cliff(i, j)
	return _height_ridge(i, j)

static func _rolling(i: float, j: float) -> float:
	return (fbm(i / 8.5, j / 8.5, SEED, 4) - 0.5) * 1.85 * RECIPE.roughness

static func _drift_rib(i: float, j: float) -> float:
	return (fbm((i * 0.85 + j * 0.52) / 4.2, (j * 0.85 - i * 0.52) / 6.5, SEED + 31, 3) - 0.5) * 0.68 * RECIPE.roughness

## 平坦盆地：开阔、缓碗形 + 小丘；背风窝少（雪沟 / 雪堆屋的地形）。
static func _height_basin(i: float, j: float) -> float:
	var wx := i / float(GRID - 1)
	var wy := j / float(GRID - 1)
	var bowl := (pow(wx - 0.5, 2.0) + pow(wy - 0.5, 2.0)) * 3.2
	var hummocks := (fbm(i / 3.5, j / 3.5, SEED + 57, 3) - 0.5) * 1.6 * RECIPE.roughness
	return maxf(0.2, 1.4 + bowl + _rolling(i, j) * 0.6 + _drift_rib(i, j) + hummocks)

## 湖岸：上风侧是冻湖（平整冰面），岸坎陡升，岸后是起伏林地。
static func _height_lakeshore(i: float, j: float) -> float:
	var t := i - _shore_i(j)
	if t < 0.0:
		return LAKE_ICE_H
	var land := smoothstep(1.0, 6.0, t)
	var rise := RECIPE.feature_h * smoothstep(-0.2, 2.2, t)
	return LAKE_ICE_H + rise + (_rolling(i, j) * 0.7 + _drift_rib(i, j)) * land + t * 0.02

## 悬崖带：上风侧是高台，崖面陡降（约 65–70°），崖脚有碎石坡；下风侧低地。
static func _height_cliff(i: float, j: float) -> float:
	var t := i - _cliff_i(j)
	var plateau := smoothstep(0.9, -0.6, t)
	var talus := exp(-pow((t - 1.6) / 1.2, 2.0)) * 0.8
	var windward_rise := maxf(-t, 0.0) * 0.06
	return maxf(0.2, 1.6 + _rolling(i, j) * 0.7 + _drift_rib(i, j) + RECIPE.feature_h * plateau + talus + windward_rise)

## 是否湖面（世界坐标）。湖面上不长树、不摆资源，雪被风吹得很薄。
static func is_lake_at(x: float, z: float) -> bool:
	if RECIPE.shape != "lakeshore":
		return false
	var m := to_map(x, z)
	return _grid_coord(m.x) < _shore_i(_grid_coord(m.y))

## 脊线山谷（旧的固定地图；RECIPE 默认值时逐字节一致）。
static func _height_ridge(i: float, j: float) -> float:
	var wx := i / float(GRID - 1)
	var wy := j / float(GRID - 1)
	var ridge_i := _ridge_center_i(j)
	var dshift := RECIPE.feature_i - 17.8

	# 1. 宏观地形：西北迎风高坡 -> 蜿蜒脊线 -> 东南背风深雪坡 -> 东北远景下沉谷口
	var windward := clampf((ridge_i - i) / 10.5, 0.0, 1.0)
	var slope := windward * (ridge_i - i) * 0.48
	var crest := exp(-pow((i - ridge_i) / 3.8, 2.0)) * RECIPE.feature_h
	var lee_shelf := 2.15 + exp(-pow((i - (ridge_i + 13.5)) / 7.5, 2.0)) * 0.55

	# 2. 中尺度风积雪丘 (Snow Drifts) 与阶梯台地柔化 (Box 1 -> Box 2)
	var rolling := _rolling(i, j)
	var drift_rib := _drift_rib(i, j)
	var gully := -exp(-(pow((i - 29.0 - dshift) / 5.0, 2.0) + pow((j - 36.0) / 3.8, 2.0))) * 1.15
	var bench := exp(-(pow((i - 34.0 - dshift) / 6.8, 2.0) + pow((j - 22.0) / 5.8, 2.0)))

	# 3. 东北/远端山谷自然下沉（让等距镜头右上角能透出远山与夕阳天际线）
	var valley_vista := smoothstep(0.62, 0.96, wx) * smoothstep(0.55, 0.10, wy) * 1.35

	var h := maxf(slope, 0.0) + crest * (1.0 - windward * 0.18)
	h = h * (1.0 - bench) + 2.10 * bench + lee_shelf * maxf(wx - 0.40, 0.0) * 0.42
	h += rolling + drift_rib + gully - valley_vista + sin(wy * PI) * 0.18

	# 3b. 垭口（可选）：沿脊线方向拉长的椭圆凹陷，只削低脊顶，不改两侧坡向
	if SADDLE:
		var wpos := Vector2(i / float(GRID - 1) * WORLD_SIZE - HALF_SIZE, j / float(GRID - 1) * WORLD_SIZE - HALF_SIZE)
		var dq := (wpos - SADDLE_CENTER)
		var e := pow(dq.x / (SADDLE_RADIUS * 0.8), 2.0) + pow(dq.y / (SADDLE_RADIUS * 1.6), 2.0)
		h -= SADDLE_DEPTH * exp(-e) * clampf(h / 4.0, 0.0, 1.0)

	# 4. 轻度阶梯化（保留参考图 Box 1 -> Box 2 的台地体块结构感，外覆厚雪柔化）
	var step_size: float = 1.15
	var step_frac: float = fmod(maxf(h, 0.0), step_size) / step_size
	var terraced: float = (floorf(h / step_size) + smoothstep(0.15, 0.85, step_frac)) * step_size
	var center_guard: float = smoothstep(1.5, 5.5, Vector2(i - 20.4 - dshift, j - 25.5).length())
	h = lerpf(h, terraced, 0.22 * center_guard)

	return maxf(0.2, h)

static func height_at(x: float, z: float) -> float:
	var m := to_map(x, z)
	return _height_from_grid(_grid_coord(m.x), _grid_coord(m.y))

static func snow_depth_at(x: float, z: float) -> float:
	var m := to_map(x, z)
	var i := _grid_coord(m.x)
	var j := _grid_coord(m.y)
	var h := _height_from_grid(i, j)
	var hw := _height_from_grid(maxf(0.0, i - 3.0), j)
	var lee := clampf((hw - h) / 1.8, -1.2, 1.4)
	var base := 0.28 + fbm(i / 6.5, j / 6.5, SEED + 91) * 0.7
	var lee_band := _lee_band(i, j)
	if lee_band < -90.0:
		# 湖面：开阔无遮挡，风把冰上的雪压实吹薄（约 0.1–0.25 m，局部扫出明冰）
		return clampf((0.12 + (base - 0.28) * 0.2) * SNOW_SCALE, 0.04, 0.3)
	# 高处风蚀：超过 5.2 m 的脊顶雪变薄；悬崖高台从台面起算（否则整片高台都会被当成脊顶吹秃）
	var exposed_h0 := 5.2 + (RECIPE.feature_h if RECIPE.shape == "cliff_band" else 0.0)
	var d := clampf(base + lee * 0.62 + lee_band - maxf(0.0, h - exposed_h0) * 0.14, 0.04, 3.0)
	if SNOW_SCALE == 1.0 and SNOW_PATCHINESS == 0.0:
		return d
	if SNOW_PATCHINESS > 0.0:
		var k := clampf((fbm(i / PATCH_NOISE_SCALE, j / PATCH_NOISE_SCALE, SEED + 137, 3) - 0.5) * PATCH_NOISE_STRETCH, -1.0, 1.0)
		var keep := smoothstep(0.0, 0.5, k)
		d *= 1.0 - SNOW_PATCHINESS * (1.0 - keep)
	return clampf(d * SNOW_SCALE, 0.04, 3.0)

## 形态决定的"背风积雪带"（m，叠加在噪声 + 局部背风之上）。返回 < -90 表示湖面。
static func _lee_band(i: float, j: float) -> float:
	match RECIPE.shape:
		"basin":
			return 0.35
		"lakeshore":
			var t := i - _shore_i(j)
			if t < 0.0:
				return -99.0
			# 岸坎后方风速骤降，雪堆在岸后 2–6 格
			return exp(-pow((t - 4.0) / 3.0, 2.0)) * 1.3 + 0.35
		"cliff_band":
			var tc := i - _cliff_i(j)
			if tc < -1.0:
				return -0.05   # 崖顶高台：风蚀，雪薄但仍覆盖（局部露出岩石 / 帚石楠）
			# 崖脚背风侧堆出深雪（雪檐 / 风积），向下风渐薄
			return exp(-pow((tc - 3.0) / 3.2, 2.0)) * 1.8 + 0.3 * smoothstep(0.0, 8.0, tc)
	var dshift := RECIPE.feature_i - 17.8
	return smoothstep(0.52, 0.78, (i - dshift) / float(GRID - 1)) * 1.55

static func gradient_at(x: float, z: float) -> Vector2:
	var e := 0.4
	var dx := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var dz := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return Vector2(dx, dz)

static func slope_at(x: float, z: float) -> float:
	var g := gradient_at(x, z)
	return rad_to_deg(atan(g.length()))

static func normal_at(x: float, z: float) -> Vector3:
	var g := gradient_at(x, z)
	return Vector3(-g.x, 1.0, -g.y).normalized()

static func lee_factor_at(x: float, z: float) -> float:
	var m := to_map(x, z)
	var i := _grid_coord(m.x)
	var j := _grid_coord(m.y)
	var h := _height_from_grid(i, j)
	var hw := _height_from_grid(maxf(0.0, i - 3.0), j)
	var lee := clampf((hw - h) / 1.8, -1.2, 1.4)
	return clampf(lee / 1.4, 0.0, 1.0)

static func is_deep_snow(x: float, z: float) -> bool:
	return snow_depth_at(x, z) >= 1.5
