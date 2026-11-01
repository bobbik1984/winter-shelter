class_name OldSpruces
extends RefCounted

## D13 / S5 树井庇护所的自然条件：低枝浓密的老云杉。
## ForestScatter / SceneryBuilder 摆树时登记"老云杉"（缩放 ≥ Tuning.old_spruce_min_scale）；
## SnowField.snow_at 在老云杉树冠下按距离削薄积雪——树冠接住了雪，树干周围是一个浅坑（tree well）。
## 每张图重建一次（MainLevel._init 调 reset）。

static var points: PackedVector2Array = PackedVector2Array()
static var _tuning: Tuning

static func reset() -> void:
	points = PackedVector2Array()

static func add(p: Vector2) -> void:
	points.append(p)

static func tuning() -> Tuning:
	if _tuning == null:
		_tuning = load("res://resources/tuning.tres") as Tuning
	return _tuning

## 最近的老云杉（世界 xz）与距离；没有时距离为 INF。
static func nearest(p: Vector2) -> Dictionary:
	var best := Vector2.ZERO
	var bd := INF
	for q in points:
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	return {"point": best, "distance": bd}

## 树冠下的积雪保留比例（1 = 不削薄）：树干处 = 1 − reduction，到树冠边缘线性恢复。
static func canopy_factor(x: float, z: float) -> float:
	if points.is_empty():
		return 1.0
	var t := tuning()
	var r := t.tree_well_canopy_radius_m
	var f := 1.0
	for q in points:
		var dx := q.x - x
		var dz := q.y - z
		if absf(dx) > r or absf(dz) > r:
			continue
		var d := sqrt(dx * dx + dz * dz)
		if d < r:
			f = minf(f, 1.0 - t.tree_well_canopy_snow_reduction * (1.0 - d / r))
	return f
