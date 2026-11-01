class_name SnowField
extends RefCounted

## M1 雪深场门面：把 TerrainHeight 的雪深/坡度/背风因子收成稳定 API。
## 后续 T1.2 的探针与热力图只依赖这里，不再直接读碰撞体 meta。

static func snow_at(x: float, z: float) -> float:
	return TerrainHeight.snow_depth_at(x, z)

static func slope_at(x: float, z: float) -> float:
	return TerrainHeight.slope_at(x, z)

static func lee_factor_at(x: float, z: float) -> float:
	return TerrainHeight.lee_factor_at(x, z)

static func height_at(x: float, z: float) -> float:
	return TerrainHeight.height_at(x, z)

static func is_snow_cave_depth(x: float, z: float) -> bool:
	return snow_at(x, z) >= 1.5

static func is_raised_cave_depth(x: float, z: float) -> bool:
	return snow_at(x, z) >= 2.0


## 本张地图的雪深事实（D12 / L5：报告"本关要点"与教训只引用实测值，不写死）。
## 2 m 网格采样可玩区（±48 m），按 (山谷, 雪深倍率, 斑驳度, 旋转) 缓存。
static var _facts_key := ""
static var _facts: Dictionary = {}

static func map_facts(t: Tuning) -> Dictionary:
	var key := "%d|%f|%f|%f|%s" % [TerrainHeight.SEED, TerrainHeight.SNOW_SCALE, TerrainHeight.SNOW_PATCHINESS, TerrainHeight.ROTATION_DEG, TerrainHeight.RECIPE.describe()]
	if key == _facts_key:
		return _facts
	var n := 0
	var mx := 0.0
	var c_trench := 0
	var c_cave := 0
	var c_raised := 0
	var x := -48.0
	while x <= 48.0:
		var z := -48.0
		while z <= 48.0:
			var s := snow_at(x, z)
			n += 1
			mx = maxf(mx, s)
			if s >= t.snow_depth_trench_wall_min_m: c_trench += 1
			if s >= t.snow_depth_cave_min_m: c_cave += 1
			if s >= t.snow_depth_raised_cave_min_m: c_raised += 1
			z += 2.0
		x += 2.0
	_facts = {"max_depth": mx, "frac_trench": float(c_trench) / n, "frac_cave": float(c_cave) / n, "frac_raised": float(c_raised) / n}
	_facts_key = key
	return _facts
