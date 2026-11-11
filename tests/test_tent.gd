extends RefCounted

## 帐篷套装（2026-11-12）：作为轻装路线的基础规则回归。
## 帐篷不学雪庇护所、背在背上不能带柴、支起后恢复；夜间：无火 DANGEROUS，有火+睡袋 COLD。

var _passed := 0
var _failures: Array[String] = []

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var t := load("res://resources/tuning.tres") as Tuning
	var tent := (ShelterPreset.create_all_presets()["Tent"] as ShelterPreset)
	_check(tent != null and tent.stage_costs.size() == 5, "Tent 有 5 阶")
	_check(int(tent.stage_costs[0].get("bedding", 0)) == 2, "Tent 第 1 阶要 2 bedding")
	_check(tent.allows_open_fire, "Tent 允许火盆")
	_check(tent.min_snow_depth <= 0.01, "Tent 不要求雪深")
	_check(bool(tent.validate_site(0.0, 2.0)["ok"]), "平地可以搭 Tent")
	_check(not bool(tent.validate_site(0.0, 30.0)["ok"]), "陡坡不能搭 Tent")
	var before := LevelState.tent_kit
	LevelState.tent_kit = true
	LevelState.begin(1, 11111, 1, 0)
	_check("Tent" in LevelState.available_presets(Records.learned_shelters()), "Tent 套装可用 Tent")
	_check(LevelState.gear().get("tent", false), "gear 带 tent 标记")
	_check(int(LevelState.gear().get("wood", 0)) == 0, "帐篷局开局不带木材")
	LevelState.tent_kit = before
	LevelState.reset()
	var base := {"shelter_type": "Tent", "wind_angle_diff": 180.0, "wind_speed_kmh": 20.0,
		"night_temp_c": -24.0, "terrain_shelter": 0.6, "snow_depth_meters": 0.2, "slope_deg": 2.0,
		"completion_ratio": 1.0, "has_vent": true, "vent_count": 1, "bedding_quality": 1.0,
		"roof_thickness_meters": 0.0, "starting_warmth": 90.0, "fire_lit": false,
		"fire_held": false, "fuel_hours": 0.0, "night_hours": 18.0, "dampness": 0.0,
		"tent_bag": true}
	var no_fire := NightSimulator.evaluate(base, t)
	_check(String(no_fire["outcome"]) == "DANGEROUS", "Tent 无火会危险（%s）" % String(no_fire["outcome"]))
	var with_fire := base.duplicate(true)
	with_fire["fire_lit"] = true
	with_fire["fire_held"] = true
	with_fire["fuel_hours"] = 6.0
	var fire_rep := NightSimulator.evaluate(with_fire, t)
	_check(String(fire_rep["outcome"]) == "COLD", "Tent 有火+睡袋是 COLD（%s）" % String(fire_rep["outcome"]))
	_check(int(fire_rep["scores"]["heat"]) > int(no_fire["scores"]["heat"]), "火盆提高 Heat")
	_check(t.tent_carry_speed_factor < 1.0, "背帐篷减速")
	return {"passed": _passed, "failures": _failures}

func _check(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures.append(msg)
