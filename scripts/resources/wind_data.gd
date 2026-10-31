class_name WindData
extends Resource

## 风的**来向**（气象惯例：西风 = 从西来）。(-1, 0) = 来自 -X（西）。
@export var direction: Vector2 = Vector2(-1.0, 0.0)
@export var speed_kmh: float = 32.0 # 32 km/h
@export var gust_frequency: float = 0.5
@export var temperature_celsius: float = -17.0

## 风的来向（指向上风）。
func get_wind_direction_3d() -> Vector3:
	return Vector3(direction.x, 0.0, direction.y).normalized()

## 风的去向（空气流动方向，指向下风）：树冠偏向、雪粒飘向都用这个。
func get_blow_direction_3d() -> Vector3:
	return -get_wind_direction_3d()
