extends RefCounted

## T2.4–T2.7 4 策略庇护所：选址推荐/校验、5 阶推进、Warmth/NightSim 联调。

const BuilderScript = preload("res://scripts/systems/shelter_builder.gd")
const WarmthScript = preload("res://scripts/player/warmth_controller.gd")

var _passed := 0
var _failures: Array[String] = []


func run() -> Dictionary:
	_passed = 0
	_failures = []
	var tuning := load("res://resources/tuning.tres") as Tuning
	if tuning == null:
		_failures.append("无法加载 resources/tuning.tres")
		return {"passed": 0, "failures": _failures}

	var builder = BuilderScript.new()
	builder.set_site_conditions(2.15, 16.0, false)
	_test_raised_cave(builder, tuning)
	_test_shallow_trench(builder)
	_test_lean_to(builder, tuning)
	_test_stage_titles(builder)
	builder.free()
	return {"passed": _passed, "failures": _failures}


func _test_raised_cave(builder, tuning: Tuning) -> void:
	builder.set_site_conditions(2.15, 16.0, false)
	var recommended: String = builder.recommend_preset_for_site(2.15, 16.0, false)
	_check(recommended == "RaisedCave", "深雪坡应推荐 RaisedCave，实际 %s" % recommended)
	_check(builder.validate_site("RaisedCave", 2.15, 16.0, false)["ok"], "RaisedCave 应通过校验")

	var begin: Dictionary = builder.begin_build("RaisedCave", 2.15, 16.0, false)
	_check(bool(begin.get("ok", false)), "begin_build RaisedCave 应成功")

	var last_stage := {}
	for _i in range(5):
		last_stage = builder.advance_stage()
	_check(builder.current_stage == 5, "5 阶推进后 current_stage 应为 5")
	_check(is_equal_approx(builder.completion_ratio, 1.0), "完工度应为 1.0")
	_check(int(last_stage.get("shelter_level", -1)) == 2, "第 5 阶 shelter_level 应为 2")
	_check(String(last_stage.get("stage_title", "")).length() > 0, "第 5 阶应有 stage_title")
	_check(float(last_stage.get("wind_muffle", 0.0)) >= 0.6, "第 5 阶风声衰减应 >=0.6")
	_check(not bool(builder.active_preset().allows_open_fire), "雪洞不允许明火")

	var warmth = WarmthScript.new()
	warmth.tuning = tuning
	warmth.body_warmth = 100.0
	var input: Dictionary = builder.build_night_sim_input(warmth)
	_check(input["shelter_type"] == "RaisedCave", "NightSim 输入类型应为 RaisedCave")
	_check(is_equal_approx(float(input["completion_ratio"]), 1.0), "输入完工度应为 1.0")
	_check(bool(input["has_cold_pit"]), "高床雪洞应含冷气坑")
	_check(bool(input["has_raised_bed"]), "高床雪洞应含抬高睡床")
	_check(int(input["vent_count"]) == 1, "第 5 阶应有通风管")
	_check(is_equal_approx(float(input["starting_warmth"]), 100.0), "应透传 Warmth 100")

	var report := NightSimulator.evaluate(input, tuning)
	_check(report["outcome"] == "SAFE", "满阶高床雪洞应 SAFE，实际 %s" % report["outcome"])
	_check(String(report["outcome_title"]).contains("SURVIVED"), "outcome_title 应可读")
	warmth.free()


func _test_shallow_trench(builder) -> void:
	builder.set_site_conditions(0.65, 10.0, false)
	var recommended: String = builder.recommend_preset_for_site(0.65, 10.0, false)
	_check(recommended == "SnowTrench", "浅雪区应推荐 SnowTrench，实际 %s" % recommended)

	var raised: Dictionary = builder.validate_site("RaisedCave", 0.65, 10.0, false)
	_check(not bool(raised["ok"]), "浅雪区 RaisedCave 应被拒绝")
	_check(String(raised["reason"]).contains("Snow too shallow"), "拒绝原因应说明雪深不足")
	var trench: Dictionary = builder.validate_site("SnowTrench", 0.65, 10.0, false)
	_check(bool(trench["ok"]), "浅雪区 SnowTrench 应通过")

	var begin: Dictionary = builder.begin_build("SnowTrench", 0.65, 10.0, false)
	_check(bool(begin.get("ok", false)), "begin_build SnowTrench 应成功")
	for _i in range(5):
		builder.advance_stage()
	var input: Dictionary = builder.build_night_sim_input(null)
	_check(bool(input["has_snow_wall"]), "浅雪雪沟应标记砌墙变体")
	_check(int(input["vent_count"]) == 1, "满阶雪沟应完成通风/封顶")
	_check(not bool(input["fire_lit"]), "雪沟不允许开放火")


func _test_lean_to(builder, tuning: Tuning) -> void:
	builder.set_site_conditions(0.20, 10.0, true)
	var recommended: String = builder.recommend_preset_for_site(0.20, 10.0, true)
	_check(recommended == "LeanTo", "树根旁浅雪应推荐 LeanTo，实际 %s" % recommended)
	var validation: Dictionary = builder.validate_site("LeanTo", 0.20, 10.0, true)
	_check(bool(validation["ok"]), "LeanTo 在树根旁应通过校验")

	builder.begin_build("LeanTo", 0.20, 10.0, true)
	var preset = builder.active_preset()
	_check(preset.allows_open_fire, "LeanTo 应允许开放反射火")
	for _i in range(5):
		builder.advance_stage()
	var warmth = WarmthScript.new()
	warmth.tuning = tuning
	warmth.body_warmth = 84.0
	var input: Dictionary = builder.build_night_sim_input(warmth)
	_check(bool(input["fire_lit"]), "满阶 LeanTo 应点火")
	_check(bool(input["fire_held"]), "满阶 LeanTo 火应保持")
	_check(bool(input["has_reflector_wall"]), "满阶 LeanTo 应有反射墙")
	_check(is_equal_approx(float(input["starting_warmth"]), 84.0), "应透传 Warmth 84")
	var report := NightSimulator.evaluate(input, tuning)
	_check(report["details"]["fire_reaches_dawn"], "备柴应能烧到天亮")
	warmth.free()


func _test_stage_titles(builder) -> void:
	builder.begin_build("RaisedCave", 2.15, 16.0, false)
	var seen: Array[String] = []
	for _i in range(5):
		var stage: Dictionary = builder.advance_stage()
		seen.append(str(stage["stage_title"]))
	_check(seen[4].contains("Lantern") or seen[4].contains("candle"),
		"RaisedCave 第 5 阶应点亮烛灯，实际 %s" % seen[4])
	_check(builder.current_stage == 5, "阶段应停在 5")
	var overflow: Dictionary = builder.advance_stage()
	_check(int(overflow["stage"]) == 5, "超过 5 阶不应继续增加")
	_check(is_equal_approx(float(overflow["completion_ratio"]), 1.0), "超过 5 阶完工度保持 1.0")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failures.append(message)
