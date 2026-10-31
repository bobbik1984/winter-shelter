class_name WarmthController
extends Node

## 0–100 核心体温（Body Warmth）实时控制器。
## 规则来源：CORE_GAMEPLAY.md §4 / ARCHITECTURE_GODOT.md §3.5。
## 这里只做纯数值与速率；风源/火源/庇护所侦测由后续 T1.5 / T2.6 / T2.7 接入。

signal warmth_changed(body_warmth: float, rate: float, indicator: String)

@export var tuning: Tuning
@export_range(0.0, 100.0, 0.1) var body_warmth: float = 100.0
@export var has_extra_clothing: bool = false
@export_range(0, 2) var in_shelter_level: int = 0
@export_range(0.0, 1.0, 0.01) var near_fire_intensity: float = 0.0
@export_range(0.0, 1.0, 0.01) var windbreak_factor: float = 0.0
@export var auto_update: bool = true

var last_rate: float = 0.0

func _ready() -> void:
	add_to_group("warmth_controller")
	_get_tuning()
	body_warmth = clampf(body_warmth, 0.0, _get_tuning().warmth_max)

func _process(delta: float) -> void:
	if not auto_update:
		return
	update_warmth(
		delta,
		windbreak_factor,
		has_extra_clothing,
		in_shelter_level,
		near_fire_intensity
	)

## 纯函数：返回当前条件下的 Warmth/s 速率，并写入 last_rate 供 HUD 读取。
func compute_warmth_rate(
	windbreak: float,
	has_clothing: bool,
	shelter_level: int,
	fire_intensity: float,
	env_cold_scale: float = 1.0
) -> float:
	var t := _get_tuning()
	var fire := clampf(fire_intensity, 0.0, 1.0)

	if fire > 0.0:
		last_rate = t.warmth_fire_recovery_rate * fire
	elif shelter_level >= 2:
		last_rate = t.warmth_shelter_cozy_gain_rate
	elif shelter_level >= 1:
		last_rate = t.warmth_shelter_hold_rate
	else:
		var wb := clampf(windbreak, 0.0, 1.0)
		var clothing := t.warmth_clothing_mitigation_bonus if has_clothing else 0.0
		last_rate = -t.warmth_cold_decay_exposed * maxf(env_cold_scale, 0.0) \
			* (1.0 - wb * t.warmth_windbreak_mitigation_max) \
			* (1.0 - clothing)
	return last_rate

## 推进体温并在 0..warmth_max 内钳制；返回实际速率。
func update_warmth(
	delta: float,
	windbreak: float,
	has_clothing: bool,
	shelter_level: int,
	fire_intensity: float,
	env_cold_scale: float = 1.0
) -> float:
	var t := _get_tuning()
	var rate := compute_warmth_rate(
		windbreak, has_clothing, shelter_level, fire_intensity, env_cold_scale
	)
	var before := body_warmth
	body_warmth = clampf(body_warmth + rate * delta, 0.0, t.warmth_max)
	if not is_equal_approx(before, body_warmth):
		warmth_changed.emit(body_warmth, rate, get_rate_indicator())
	return rate

## 速率箭头：阈值相对 Tuning 掉温 / 回温速率，调参后不需要改这里。
func get_rate_indicator() -> String:
	var t := _get_tuning()
	var cold := t.warmth_cold_decay_exposed
	if last_rate <= -cold * 0.8:
		return "▼▼▼"
	if last_rate < -cold * 0.1:
		return "▼"
	if last_rate < cold * 0.1:
		return "—"
	if last_rate < t.warmth_fire_recovery_rate * 0.4:
		return "▲"
	return "▲▲▲"

func get_action_efficiency() -> float:
	var t := _get_tuning()
	if body_warmth >= t.warmth_tier_warm:
		return 1.0
	if body_warmth >= t.warmth_tier_chilled:
		return 0.75
	return 0.5

func get_context_label() -> String:
	if near_fire_intensity > 0.0:
		return Loc.t("Campfire Warmth")
	if in_shelter_level >= 2:
		return Loc.t("Sheltered / Cozy")
	if in_shelter_level >= 1:
		return Loc.t("Shelter Hold")
	if windbreak_factor >= 0.5:
		return Loc.t("Leeward Shelter")
	return Loc.t("Exposed Ridge")

## 热饮瞬间 +warmth_hot_drink_instant_boost，并钳制到上限。
func apply_hot_drink() -> float:
	var t := _get_tuning()
	var before := body_warmth
	body_warmth = minf(t.warmth_max, body_warmth + t.warmth_hot_drink_instant_boost)
	last_rate = 0.0
	warmth_changed.emit(body_warmth, last_rate, get_rate_indicator())
	return body_warmth - before

func set_body_warmth(value: float) -> void:
	body_warmth = clampf(value, 0.0, _get_tuning().warmth_max)
	warmth_changed.emit(body_warmth, last_rate, get_rate_indicator())

func _get_tuning() -> Tuning:
	if tuning == null:
		tuning = load("res://resources/tuning.tres") as Tuning
	if tuning == null:
		tuning = Tuning.new()
	return tuning
