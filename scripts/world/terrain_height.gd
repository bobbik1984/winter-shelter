class_name TerrainHeight
extends RefCounted

## M1 高度场：从 Web 原型 world.ts 的 buildTerrain() 移植。
## 纯函数、可测试、无节点依赖。世界坐标 x 向西(-) / 向东(+)，z 向南(-) / 向北(+)。
## 布局：西侧迎风坡 -> 脊线 -> 东侧背风缓坡 -> 雪棚平台 -> 南侧沟谷。

const GRID := 52
const WORLD_SIZE := 100.0
const HALF_SIZE := 50.0
const SEED := 7

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

static func _height_from_grid(i: float, j: float) -> float:
	var wx := i / float(GRID - 1)
	var wy := j / float(GRID - 1)
	var windward := clampf((18.0 - i) / 10.0, 0.0, 1.0)
	var slope := windward * (18.0 - i) * 0.55
	var crest := exp(-pow((i - 18.0) / 3.4, 2.0)) * 5.6
	var lee_shelf := 2.15 + exp(-pow((i - 32.0) / 7.0, 2.0)) * 0.35
	var rolling := (fbm(i / 11.0, j / 11.0, SEED) - 0.5) * 1.55
	var gully := -exp(-(pow((i - 28.0) / 4.5, 2.0) + pow((j - 36.0) / 3.2, 2.0))) * 1.1
	var bench := exp(-(pow((i - 34.0) / 6.5, 2.0) + pow((j - 22.0) / 5.5, 2.0)))

	var h := maxf(slope, 0.0) + crest * (1.0 - windward * 0.15)
	h = h * (1.0 - bench) + 2.05 * bench + lee_shelf * maxf(wx - 0.42, 0.0) * 0.4
	h += rolling + gully + sin(wy * PI) * 0.15
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
	# 背风 shelf 的深雪带：对应参考图的东南深雪坡，供雪洞/高床雪洞选址。
	var lee_band := smoothstep(0.55, 0.78, i / float(GRID - 1)) * 1.55
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
