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
## V7：时间与大气的唯一数据源（只有本节点写入）。
var atmosphere := AtmosphereState.new()
## [GAME] 傍晚降雪：16:00 起 70 分钟内渐密到 0.9。
const SNOW_START_MINUTES := 960.0
const SNOW_RAMP_MINUTES := 70.0

## 本局天气（每局开局抽取；测试可用命令行 -- --weather=storm 指定）。
var weather_kind: String = "clear"
## 本局开局时刻（分钟）：关卡（D12）或全天模式会改它；报告时间线从这里读。
var day_start_minutes: float = 860.0
## D12 关卡风速偏移（km/h），叠加在 WindData.speed_kmh 上。
var wind_offset_kmh: float = 0.0
var _last_wind_int := -1
var _last_temp_int := 999

func _ready() -> void:
	add_to_group("weather")
	if wind_data == null:
		wind_data = WindData.new()
	tuning = load(TUNING_PATH) as Tuning
	if tuning == null:
		tuning = Tuning.new()
	current_time_minutes = float(tuning.start_minutes)
	if LevelState.active():
		current_time_minutes = float(LevelState.roll.get("start_minutes", tuning.start_minutes))
		wind_offset_kmh = float(LevelState.roll.get("wind_speed_offset_kmh", 0.0))
	day_start_minutes = current_time_minutes
	time_scale = 3600.0 / maxf(tuning.real_seconds_per_game_hour, 1.0)
	sunset_minutes = SunModel.sunset_minutes(tuning.sun_latitude_deg, tuning.sun_declination_deg, tuning.solar_noon_minutes)
	weather_kind = _roll_weather()
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
	var cloud := current_cloud()
	sun_light.light_energy = SUN_ENERGY_DAY * day * (1.0 - 0.65 * cloud)
	sun_light.light_color = SUN_COLOR_LOW.lerp(SUN_COLOR_HIGH, smoothstep(2.0, 22.0, p.x))
	sun_light.shadow_enabled = day > 0.01
	var snow_start := SNOW_START_MINUTES - (30.0 if weather_kind == "storm" else 0.0)
	var snow := clampf((current_time_minutes - snow_start) / SNOW_RAMP_MINUTES, 0.0, 1.0) * (1.0 if weather_kind == "storm" else 0.9)
	var wind := current_wind_kmh()
	atmosphere.update(current_time_minutes, to_sun, p.x, p.y, snow, cloud, wind, weather_kind)
	var temp := current_temp_c()
	if int(wind) != _last_wind_int or int(round(temp)) != _last_temp_int:
		_last_wind_int = int(wind)
		_last_temp_int = int(round(temp))
		_update_weather_signals()

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

func _roll_weather() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			return a.substr(10)
	if LevelState.active():
		return String(LevelState.roll.get("weather", "clear"))
	var total := tuning.weather_weight_clear + tuning.weather_weight_overcast + tuning.weather_weight_storm
	var r := randf() * maxf(total, 0.001)
	if r < tuning.weather_weight_clear:
		return "clear"
	if r < tuning.weather_weight_clear + tuning.weather_weight_overcast:
		return "overcast"
	return "storm"

## 暴风雪进程 0..1（其余天气恒为 0）。
func storm_progress() -> float:
	if weather_kind != "storm":
		return 0.0
	return clampf((current_time_minutes - tuning.storm_start_minutes) / tuning.storm_ramp_minutes, 0.0, 1.0)

func current_cloud() -> float:
	match weather_kind:
		"overcast": return tuning.overcast_cloud
		"storm": return lerpf(0.25, 0.9, storm_progress())
	return 0.0

func current_wind_kmh() -> float:
	return maxf(wind_data.speed_kmh + wind_offset_kmh + tuning.storm_extra_wind_kmh * storm_progress(), 0.0)

## 当前气温：从开局 temp_at_start_c 线性降到入夜（night_minutes）的夜间气温。
func current_temp_c() -> float:
	var start := float(tuning.start_minutes)
	var k := clampf((current_time_minutes - start) / maxf(float(tuning.night_minutes) - start, 1.0), 0.0, 1.0)
	if current_time_minutes < start:
		k = 0.0
	return lerpf(tuning.temp_at_start_c, night_temp_c(), k)

## 夜间气温：暴风雪夜更冷。
func night_temp_c() -> float:
	return tuning.temp_at_night_c - (tuning.storm_extra_cold_c if weather_kind == "storm" else 0.0)

func forecast_text() -> String:
	match weather_kind:
		"overcast": return Loc.t("Forecast: overcast — a weak, hazy sun. Shadows will be faint; keep an eye on the clock.")
		"storm": return Loc.t("Forecast: a storm is coming in this afternoon — stronger wind, early snow, a colder night.")
	return Loc.t("Forecast: clear and cold — long, sharp shadows to read the time by.")

func _update_weather_signals() -> void:
	var wind_str = "W %d km/h" % [int(current_wind_kmh() if tuning else wind_data.speed_kmh)]
	weather_updated.emit(current_temp_c() if tuning else wind_data.temperature_celsius, wind_str)
