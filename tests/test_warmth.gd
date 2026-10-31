extends RefCounted

## T2.3 核心体温：5 种核心场景 + 效率阈值 + NightSimulator 入夜联动。

const WarmthControllerScript = preload("res://scripts/player/warmth_controller.gd")

var _passed := 0
var _failures: Array[String] = []


func run() -> Dictionary:
	_passed = 0
	_failures = []
	var t := load("res://resources/tuning.tres") as Tuning
	if t == null:
		_failures.append("无法加载 resources/tuning.tres")
		return {"passed": 0, "failures": _failures}

	var c = WarmthControllerScript.new()
	c.tuning = t

	_test_exposed(t, c)
	_test_leeward(t, c)
	_test_clothing(t, c)
	_test_shelter(t, c)
	_test_fire_and_hot_drink(t, c)
	_test_efficiency(t, c)
	_test_update_clamps(t, c)
	_test_context_labels(t, c)
	_test_night_simulation(t)

	c.free()
	return {"passed": _passed, "failures": _failures}


func _test_exposed(t: Tuning, c) -> void:
	var rate: float = c.compute_warmth_rate(0.0, false, 0, 0.0)
	_check(
		is_equal_approx(rate, -t.warmth_cold_decay_exposed),
		"迎风暴露应等于 Tuning 掉温速率，实际 %.4f" % rate
	)
	_check(c.get_rate_indicator() == "▼▼▼", "暴露指示器应为 ▼▼▼")


func _test_leeward(t: Tuning, c) -> void:
	var rate: float = c.compute_warmth_rate(1.0, false, 0, 0.0)
	var expected := -t.warmth_cold_decay_exposed * (1.0 - t.warmth_windbreak_mitigation_max)
	_check(
		is_equal_approx(rate, expected),
		"背风区应约 %.2f/s，实际 %.4f" % [expected, rate]
	)
	_check(rate > -t.warmth_cold_decay_exposed * 0.5, "背风区掉温应不到暴露区一半，实际 %.4f" % rate)
	_check(c.get_rate_indicator() == "▼", "背风区指示器应为 ▼")


func _test_clothing(_t: Tuning, c) -> void:
	var without: float = c.compute_warmth_rate(1.0, false, 0, 0.0)
	var with_clothing: float = c.compute_warmth_rate(1.0, true, 0, 0.0)
	var expected := without * 0.65
	_check(
		is_equal_approx(with_clothing, expected),
		"额外衣物应再减缓 35%%：期望 %.4f，实际 %.4f" % [expected, with_clothing]
	)
	_check(with_clothing > without, "穿衣后的下降速率应更小（更接近 0）")


func _test_shelter(t: Tuning, c) -> void:
	var hold: float = c.compute_warmth_rate(0.0, false, 1, 0.0)
	_check(is_equal_approx(hold, t.warmth_shelter_hold_rate), "庇护所 1 级应保持 0.0/s")
	_check(c.get_rate_indicator() == "—", "庇护所 1 级指示器应为 —")

	var cozy: float = c.compute_warmth_rate(0.0, false, 2, 0.0)
	_check(
		is_equal_approx(cozy, t.warmth_shelter_cozy_gain_rate),
		"庇护所 2 级应约 +0.55/s，实际 %.4f" % cozy
	)
	_check(c.get_rate_indicator() == "▲", "庇护所 2 级指示器应为 ▲")


func _test_fire_and_hot_drink(t: Tuning, c) -> void:
	var fire: float = c.compute_warmth_rate(0.0, false, 0, 1.0)
	_check(
		is_equal_approx(fire, t.warmth_fire_recovery_rate),
		"篝火应约 +2.5/s，实际 %.4f" % fire
	)
	_check(c.get_rate_indicator() == "▲▲▲", "篝火指示器应为 ▲▲▲")

	c.set_body_warmth(90.0)
	var gained: float = c.apply_hot_drink()
	_check(is_equal_approx(gained, 10.0), "90 + 15 应只增加 10 到上限，实际 +%.2f" % gained)
	_check(is_equal_approx(c.body_warmth, 100.0), "热饮应钳制在 100.0")

	c.set_body_warmth(70.0)
	gained = c.apply_hot_drink()
	_check(is_equal_approx(gained, 15.0), "70 + 15 应增加 15，实际 +%.2f" % gained)
	_check(is_equal_approx(c.body_warmth, 85.0), "热饮后应为 85.0")


func _test_efficiency(t: Tuning, c) -> void:
	c.set_body_warmth(100.0)
	_check(is_equal_approx(c.get_action_efficiency(), 1.0), "100 体温效率应为 1.0")
	c.set_body_warmth(t.warmth_tier_warm)
	_check(is_equal_approx(c.get_action_efficiency(), 1.0), "70 体温效率应为 1.0")
	c.set_body_warmth(t.warmth_tier_warm - 0.1)
	_check(is_equal_approx(c.get_action_efficiency(), 0.75), "69.9 体温效率应为 0.75")
	c.set_body_warmth(t.warmth_tier_chilled)
	_check(is_equal_approx(c.get_action_efficiency(), 0.75), "35 体温效率应为 0.75")
	c.set_body_warmth(t.warmth_tier_chilled - 0.1)
	_check(is_equal_approx(c.get_action_efficiency(), 0.5), "34.9 体温效率应为 0.5")


func _test_update_clamps(t: Tuning, c) -> void:
	c.set_body_warmth(0.5)
	c.update_warmth(10.0, 0.0, false, 0, 0.0)
	_check(is_equal_approx(c.body_warmth, 0.0), "体温不应低于 0")

	c.set_body_warmth(t.warmth_max - 0.5)
	c.update_warmth(1.0, 0.0, false, 0, 1.0)
	_check(is_equal_approx(c.body_warmth, t.warmth_max), "体温不应高于 100")


func _test_context_labels(_t: Tuning, c) -> void:
	c.windbreak_factor = 0.0
	c.in_shelter_level = 0
	c.near_fire_intensity = 0.0
	_check(c.get_context_label() == "Exposed Ridge", "露天 label 应为 Exposed Ridge")
	c.windbreak_factor = 1.0
	_check(c.get_context_label() == "Leeward Shelter", "背风 label 应为 Leeward Shelter")
	c.in_shelter_level = 1
	_check(c.get_context_label() == "Shelter Hold", "1 级庇护所 label 应为 Shelter Hold")
	c.in_shelter_level = 2
	_check(c.get_context_label() == "Sheltered / Cozy", "2 级庇护所 label 应为 Sheltered / Cozy")
	c.near_fire_intensity = 1.0
	_check(c.get_context_label() == "Campfire Warmth", "篝火 label 应为 Campfire Warmth")


func _test_night_simulation(_t: Tuning) -> void:
	var t := load("res://resources/tuning.tres") as Tuning
	var base := {
		"shelter_type": "BasicCave",
		"wind_angle_diff": 180.0,
		"snow_depth_meters": 1.8,
		"roof_thickness_meters": 0.5,
		"completion_ratio": 1.0,
		"bedding_quality": 0.8,
		"has_cold_pit": true,
		"has_raised_bed": false,
		"vent_count": 1,
		"slope_deg": 5.0,
		"wood_left": 2.0,
		"starting_warmth": 100.0,
	}
	var cold := base.duplicate()
	cold["starting_warmth"] = 30.0
	var warm_report := NightSimulator.evaluate(base, t)
	var cold_report := NightSimulator.evaluate(cold, t)
	_check(
		int(cold_report["scores"]["heat"]) < int(warm_report["scores"]["heat"]),
		"入夜低体温应降低 Heat 分：%d vs %d" % [
			int(cold_report["scores"]["heat"]), int(warm_report["scores"]["heat"])
		]
	)
	_check(
		String(cold_report["notes"][5]).contains("核心体温"),
		"低体温应在 heat note 写出核心体温归因"
	)
	_check(
		is_equal_approx(float(cold_report["details"]["starting_warmth"]), 30.0),
		"details 应记录 starting_warmth=30"
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failures.append(message)
