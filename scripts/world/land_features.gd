class_name LandFeatures
extends RefCounted

## D13 / S5 岩檐与倒木斜棚的自然条件（CORE_GAMEPLAY §9.3）。
## 摆放地物时登记；每张图重建一次（main.gd 调 reset）。悬崖不用登记，从地形算。

static var rocks: PackedVector2Array = PackedVector2Array()
static var logs: PackedVector2Array = PackedVector2Array()

static func reset() -> void:
	rocks = PackedVector2Array()
	logs = PackedVector2Array()

## 最近的点与距离；没有时距离为 INF。
static func nearest(points: PackedVector2Array, p: Vector2) -> Dictionary:
	var best := Vector2.ZERO
	var bd := INF
	for q in points:
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	return {"point": best, "distance": bd}

## 地物下风侧、离树干够远的工地位置：正下风优先，其次两侧（地物周围常有云杉，工地不能压在树底下）。
static func clear_spot_downwind(feature: Vector2, wind_from: Vector3, dist: float, trees: PackedVector2Array, clearance: float) -> Vector2:
	var blow := Vector2(-wind_from.x, -wind_from.z).normalized()
	var best := feature + blow * dist
	var best_gap := -INF
	for ang in [0.0, 35.0, -35.0, 70.0, -70.0]:
		var c: Vector2 = feature + blow.rotated(deg_to_rad(ang)) * dist
		var gap := INF
		for q in trees:
			gap = minf(gap, q.distance_to(c))
		if gap >= clearance:
			return c
		if gap > best_gap:
			best_gap = gap
			best = c
	return best

## 这里的上风方向有没有陡崖（往上风走 run 米，地面升高 ≥ rise 米）：悬崖脚的背风处。
static func cliff_upwind(x: float, z: float, wind_from: Vector3, run: float, rise: float) -> bool:
	var q := Vector3(x, 0.0, z) + wind_from.normalized() * run
	return TerrainHeight.height_at(q.x, q.z) - TerrainHeight.height_at(x, z) >= rise
