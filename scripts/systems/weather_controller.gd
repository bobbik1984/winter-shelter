class_name WeatherController
extends Node

signal time_changed(current_time_str: String, sunset_remaining_str: String)
signal weather_updated(temp_celsius: float, wind_str: String)

@export var wind_data: WindData
@export var sun_light: DirectionalLight3D
@export var time_scale: float = 12.0 # 现实 1 秒 = 游戏 12 秒

# 14:20 = 860 分钟，16:18 = 978 分钟
var current_time_minutes: float = 860.0
const SUNSET_MINUTES: float = 978.0

func _ready() -> void:
	if wind_data == null:
		wind_data = WindData.new()
	_update_weather_signals()

func _process(delta: float) -> void:
	current_time_minutes += (delta * time_scale) / 60.0
	
	# 格式化时间
	var total_min = int(current_time_minutes)
	var hrs = total_min / 60
	var mins = total_min % 60
	var time_str = "%02d:%02d" % [hrs, mins]
	
	var rem_min = int(max(0.0, SUNSET_MINUTES - current_time_minutes))
	var rem_hrs = rem_min / 60
	var rem_m = rem_min % 60
	var rem_str = "%dh %02dm" % [rem_hrs, rem_m]
	
	time_changed.emit(time_str, rem_str)
	
	# 更新落日光线
	if sun_light:
		var progress = clamp((current_time_minutes - 860.0) / (SUNSET_MINUTES - 860.0), 0.0, 1.0)
		# [GAME] 低角度逆光：俯角从 8° 降到 0.5°（太阳要留在移轴镜头的画面上沿内）
		sun_light.rotation_degrees.x = lerp(-8.0, -0.5, progress)
		# 颜色从微冷白渐变到低角度落日金黄
		sun_light.light_color = Color(1.0, 0.82, 0.60).lerp(Color(1.0, 0.48, 0.15), progress)
		get_tree().call_group("sun_receivers", "set_sun_dir", sun_light.global_transform.basis.z.normalized())

func _update_weather_signals() -> void:
	var wind_str = "W %d km/h" % [int(wind_data.speed_kmh)]
	weather_updated.emit(wind_data.temperature_celsius, wind_str)
