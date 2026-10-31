class_name WeatherController
extends Node

signal time_changed(current_time_str: String, sunset_remaining_str: String)
signal weather_updated(temp_celsius: float, wind_str: String)

@export var wind_data: WindData
@export var sun_light: DirectionalLight3D
## 游戏秒 / 现实秒；_ready 时由 Tuning.real_seconds_per_game_hour 推出（300 s/h → 12×）。
@export var time_scale: float = 12.0

const TUNING_PATH := "res://resources/tuning.tres"
## [GAME] 太阳光强与色温随高度角变化：低角度暖橙、高角度近白金。
const SUN_ENERGY_DAY := 1.35
const SUN_COLOR_LOW := Color(1.0, 0.52, 0.22)
const SUN_COLOR_HIGH := Color(1.0, 0.90, 0.76)

var tuning: Tuning
var current_time_minutes: float = 860.0
var sunset_minutes: float = 978.0
## 当前太阳高度角 / 方位角（°），供 HUD 或教学提示读取。
var sun_elevation_deg: float = 0.0
var sun_azimuth_deg: float = 0.0

func _ready() -> void:
	if wind_data == null:
		wind_data = WindData.new()
	tuning = load(TUNING_PATH) as Tuning
	if tuning == null:
		tuning = Tuning.new()
	current_time_minutes = float(tuning.start_minutes)
	time_scale = 3600.0 / maxf(tuning.real_seconds_per_game_hour, 1.0)
	sunset_minutes = SunModel.sunset_minutes(tuning.sun_latitude_deg, tuning.sun_declination_deg, tuning.solar_noon_minutes)
	_update_weather_signals()
	_apply_sun.call_deferred()

func _process(delta: float) -> void:
	current_time_minutes += (delta * time_scale) / 60.0

	var total_min = int(current_time_minutes)
	var time_str = "%02d:%02d" % [total_min / 60, total_min % 60]
	var rem_min = int(max(0.0, sunset_minutes - current_time_minutes))
	var rem_str = "%dh %02dm" % [rem_min / 60, rem_min % 60]
	time_changed.emit(time_str, rem_str)
	_apply_sun()

## 太阳沿真实日轨移动：方位自东南经南到西南，高度角先升后降——影子长→短→长。
func _apply_sun() -> void:
	if sun_light == null:
		return
	var p := SunModel.position(current_time_minutes, tuning.sun_latitude_deg,
		tuning.sun_declination_deg, tuning.solar_noon_minutes)
	sun_elevation_deg = p.x
	sun_azimuth_deg = p.y
	var to_sun := SunModel.direction(current_time_minutes, tuning.sun_latitude_deg,
		tuning.sun_declination_deg, tuning.solar_noon_minutes)
	# 光照方向 = 从太阳射来；DirectionalLight3D 沿自身 -Z 照射，所以 +Z 指向太阳
	sun_light.global_transform.basis = Basis.looking_at(-to_sun, Vector3.UP)
	var day := smoothstep(-1.0, 4.0, p.x)
	sun_light.light_energy = SUN_ENERGY_DAY * day
	sun_light.light_color = SUN_COLOR_LOW.lerp(SUN_COLOR_HIGH, smoothstep(2.0, 22.0, p.x))
	sun_light.shadow_enabled = day > 0.01
	get_tree().call_group("sun_receivers", "set_sun_dir", to_sun)

## 动作消耗游戏时间：时钟直接跳进（采集 / 建造 / 融雪），太阳随之更新。
func advance_minutes(minutes: float) -> void:
	current_time_minutes += maxf(minutes, 0.0)
	_apply_sun()

func minutes_to_sunset() -> float:
	return sunset_minutes - current_time_minutes

func clock_string() -> String:
	var m := int(current_time_minutes)
	return "%02d:%02d" % [m / 60, m % 60]

## 当前时刻的 HH:MM 日落字符串（HUD 用，不再写死 16:18）。
func sunset_clock() -> String:
	var m := int(round(sunset_minutes))
	return "%02d:%02d" % [m / 60, m % 60]

func _update_weather_signals() -> void:
	var wind_str = "W %d km/h" % [int(wind_data.speed_kmh)]
	weather_updated.emit(wind_data.temperature_celsius, wind_str)
