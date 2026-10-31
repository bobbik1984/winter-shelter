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
