class_name AtmosphereState
extends RefCounted

## 时间与大气的唯一数据源（V7）。WeatherController 是唯一写入方；
## 天空 / 环境光 / 雾（AtmosphereSetup）、雪面（TerrainBuilder）、罗盘、降雪、头灯只读它（订阅 changed）。
## 以后加云量 / 降雪强度 / 暴风雪，只在这里加字段、在 WeatherController 里写。

signal changed(state: AtmosphereState)

var minutes: float = 0.0
## 指向太阳的世界方向。
var sun_dir: Vector3 = Vector3(0.0, 0.25, 1.0).normalized()
var sun_elevation_deg: float = 15.0
var sun_azimuth_deg: float = 215.0
## 0 = 夜，1 = 白天（按太阳高度平滑）。
var day: float = 1.0
## 傍晚降雪强度 0..1。
var snowfall: float = 0.0

func update(p_minutes: float, p_sun_dir: Vector3, elevation: float, azimuth: float, p_snowfall: float) -> void:
	minutes = p_minutes
	sun_dir = p_sun_dir
	sun_elevation_deg = elevation
	sun_azimuth_deg = azimuth
	day = smoothstep(-6.0, 6.0, elevation)
	snowfall = p_snowfall
	changed.emit(self)

## 场景里任何节点取得当前大气状态（WeatherController 在组 "weather" 中）。
static func of(tree: SceneTree) -> AtmosphereState:
	var w := tree.get_first_node_in_group("weather")
	return w.atmosphere if w else null
