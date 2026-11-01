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
	# 在 z=0 (wy=0.5) 处锚定在 i=17.8，向南北两侧呈自然 S 型蜿蜒，彻底消除尺子画出的直线白光带
	var s_curve := sin((wy - 0.5) * PI * 2.1) * 4.2
	var organic := (fbm(wy * 3.2, 1.7, SEED + 19, 3) - 0.5) * 3.8 * absf(wy - 0.5) * 2.0
	return 17.8 + s_curve + organic

static func _height_from_grid(i: float, j: float) -> float:
	var wx := i / float(GRID - 1)
	var wy := j / float(GRID - 1)
	var ridge_i := _ridge_center_i(j)

	# 1. 宏观地形：西北迎风高坡 -> 蜿蜒脊线 -> 东南背风深雪坡 -> 东北远景下沉谷口
	var windward := clampf((ridge_i - i) / 10.5, 0.0, 1.0)
	var slope := windward * (ridge_i - i) * 0.48
	var crest := exp(-pow((i - ridge_i) / 3.8, 2.0)) * 5.5
	var lee_shelf := 2.15 + exp(-pow((i - (ridge_i + 13.5)) / 7.5, 2.0)) * 0.55

	# 2. 中尺度风积雪丘 (Snow Drifts) 与阶梯台地柔化 (Box 1 -> Box 2)
	var rolling := (fbm(i / 8.5, j / 8.5, SEED, 4) - 0.5) * 1.85
	var drift_rib := (fbm((i * 0.85 + j * 0.52) / 4.2, (j * 0.85 - i * 0.52) / 6.5, SEED + 31, 3) - 0.5) * 0.68
	var gully := -exp(-(pow((i - 29.0) / 5.0, 2.0) + pow((j - 36.0) / 3.8, 2.0))) * 1.15
	var bench := exp(-(pow((i - 34.0) / 6.8, 2.0) + pow((j - 22.0) / 5.8, 2.0)))

	# 3. 东北/远端山谷自然下沉（让等距镜头右上角能透出远山与夕阳天际线）
	var valley_vista := smoothstep(0.62, 0.96, wx) * smoothstep(0.55, 0.10, wy) * 1.35

	var h := maxf(slope, 0.0) + crest * (1.0 - windward * 0.18)
	h = h * (1.0 - bench) + 2.10 * bench + lee_shelf * maxf(wx - 0.40, 0.0) * 0.42
	h += rolling + drift_rib + gully - valley_vista + sin(wy * PI) * 0.18

	# 4. 轻度阶梯化（保留参考图 Box 1 -> Box 2 的台地体块结构感，外覆厚雪柔化）
	var step_size: float = 1.15
	var step_frac: float = fmod(maxf(h, 0.0), step_size) / step_size
	var terraced: float = (floorf(h / step_size) + smoothstep(0.15, 0.85, step_frac)) * step_size
	var center_guard: float = smoothstep(1.5, 5.5, Vector2(i - 20.4, j - 25.5).length())
	h = lerpf(h, terraced, 0.22 * center_guard)

	return maxf(0.2, h)

static func height_at(x: float, z: float) -> float:
	return _height_from_grid(_grid_coord(x), _grid_coord(z))

static func snow_depth_at(x: float, z: float) -> float:
	var i := _grid_coord(x)
	var j := _grid_coord(z)
	var h := _height_from_grid(i, j)
	var hw := _height_from_grid(maxf(0.0, i - 3.0), j)
	var lee := clampf((hw - h) / 1.8, -1.2, 1.4)
	var base := 0.28 + fbm(i / 6.5, j / 6.5, SEED + 91) * 0.7
	var lee_band := smoothstep(0.52, 0.78, i / float(GRID - 1)) * 1.55
	return clampf(base + lee * 0.62 + lee_band - maxf(0.0, h - 5.2) * 0.14, 0.04, 3.0)

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
	var i := _grid_coord(x)
	var j := _grid_coord(z)
	var h := _height_from_grid(i, j)
	var hw := _height_from_grid(maxf(0.0, i - 3.0), j)
	var lee := clampf((hw - h) / 1.8, -1.2, 1.4)
	return clampf(lee / 1.4, 0.0, 1.0)

static func is_deep_snow(x: float, z: float) -> bool:
	return snow_depth_at(x, z) >= 1.5
