class_name WindData
extends Resource

@export var direction: Vector2 = Vector2(-1.0, 0.0) # 默认西风 (自西向东吹)
@export var speed_kmh: float = 32.0 # 32 km/h
@export var gust_frequency: float = 0.5
@export var temperature_celsius: float = -17.0

func get_wind_direction_3d() -> Vector3:
	return Vector3(direction.x, 0.0, direction.y).normalized()
