extends RefCounted

## T0.6 NightSimulator headless 测试。
## 由 tests/run_all.gd 通过 run() 调用，返回 {"name", "passed", "failures"}。
## 不依赖场景树；所有阈值从 res://resources/tuning.tres 读取。

const TUNING_PATH := "res://resources/tuning.tres"
const AXES := ["site", "structure", "insulation", "isolation", "air", "heat"]

var _tuning: Tuning
var _passed: int = 0
var _failures: Array[String] = []


func run() -> Dictionary:
	var loaded: Resource = load(TUNING_PATH)
	if loaded == null or not (loaded is Tuning):
		_failures.append("无法加载 Tuning 资源：%s" % TUNING_PATH)
		return _result()

	_tuning = loaded as Tuning

	_test_tuning_defaults()
	_test_perfect_raised_cave()
	_test_no_vent()
	_test_entrance_windward()
	_test_no_bedding()
	_test_unfinished()
	_test_lean_to_enough_fuel()
	_test_lean_to_short_fuel()
	_test_lean_to_blown_out()
	_test_unknown_preset()
	_test_none_preset()
	_test_snow_trench_wall_variant()
	_test_snow_shelter_ignores_fire()

	return _result()


func _result() -> Dictionary:
	return {
		"name": "night_sim",
		"passed": _passed,
		"failures": _failures.duplicate(),
	}


# -----------------------------------------------------------------------------
# 用例
# -----------------------------------------------------------------------------

func _test_tuning_defaults() -> void:
	var label := "Tuning 默认值"
	_check(label + " 高床雪洞门槛 D5", is_equal_approx(_tuning.snow_depth_raised_cave_min_m, 2.0))
	_check(label + " 雪洞门槛 D5", is_equal_approx(_tuning.snow_depth_cave_min_m, 1.5))
	_check(label + " 标准雪沟 D5", is_equal_approx(_tuning.snow_depth_trench_standard_m, 1.0))
	_check(label + " 浅雪下限 D5", is_equal_approx(_tuning.snow_depth_trench_wall_min_m, 0.3))
	_check(label + " 顶厚下限 0.3", is_equal_approx(_tuning.roof_thickness_min_m, 0.3))
	_check(label + " 顶厚良好 0.45", is_equal_approx(_tuning.roof_thickness_good_m, 0.45))
	_check(label + " 风速为 km/h 量级", _tuning.wind_speed_kmh > 1.0)
	_check(
		label + " 六维权重均为正",
		_tuning.weight_site > 0.0
		and _tuning.weight_structure > 0.0
		and _tuning.weight_insulation > 0.0
		and _tuning.weight_isolation > 0.0
		and _tuning.weight_air > 0.0
		and _tuning.weight_heat > 0.0
	)


func _test_perfect_raised_cave() -> void:
	var label := "完美高床洞"
	var report := _run(_base_input("RaisedCave"))
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "SAFE")
	_expect_score_range(label, report, "structure", 80, 100)
	_expect_score_range(label, report, "insulation", 85, 100)
	_expect_score_range(label, report, "isolation", 75, 100)
	_expect_score_range(label, report, "air", 80, 100)
	_expect_score_range(label, report, "heat", 65, 100)


func _test_no_vent() -> void:
	var label := "无通风"
	var input := _base_input("RaisedCave")
	input["vent_count"] = 0
	input["has_vent"] = false
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "DANGEROUS")
	_expect_title_contains(label, report, "SUFFOCATED")
	_expect_score_range(label, report, "air", 0, 10)
	_expect_note_contains(label, report, 4, "窒息")


func _test_entrance_windward() -> void:
	var label := "入口迎风"
	var input := _base_input("RaisedCave")
	input["wind_angle_diff"] = 0.0
	input["terrain_shelter"] = 0.0
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "DANGEROUS")
	_expect_title_contains(label, report, "FROST")
	_expect_score_range(label, report, "site", 0, 35)
	_expect_note_contains(label, report, 0, "迎风")


func _test_no_bedding() -> void:
	var label := "无垫层"
	var input := _base_input("RaisedCave")
	input["bedding_quality"] = 0.0
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "DANGEROUS")
	_expect_title_contains(label, report, "FROST")
	_expect_score_range(label, report, "insulation", 0, 20)
	_expect_note_contains(label, report, 2, "直接接触")


func _test_unfinished() -> void:
	var label := "未完工"
	var input := _base_input("RaisedCave")
	input["completion_ratio"] = 0.4
	input["roof_thickness_meters"] = 0.3
	input["has_cold_pit"] = false
	input["has_raised_bed"] = false
	input["wood_left"] = 0.0
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "COLD")
	_expect_score_range(label, report, "structure", 0, 65)
	_expect_note_contains(label, report, 1, "完工度")


func _test_lean_to_enough_fuel() -> void:
	var label := "倒棚备柴足"
	var report := _run(_lean_to_input())
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "COLD")
	_expect_score_range(label, report, "heat", 65, 100)
	_expect_details_bool(label, report, "fire_reaches_dawn", true)
	_expect_note_contains(label, report, 5, "烧到天亮")


func _test_lean_to_short_fuel() -> void:
	var label := "倒棚备柴不足"
	var input := _lean_to_input()
	input["fuel_hours"] = 3.5
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "COLD")
	_expect_score_range(label, report, "heat", 30, 55)
	_expect_details_bool(label, report, "fire_reaches_dawn", false)
	_expect_details_string(label, report, "fire_out_clock", "20:40")
	_expect_note_contains(label, report, 5, "熄火")
	_expect_note_contains(label, report, 5, "20:40")


func _test_lean_to_blown_out() -> void:
	var label := "倒棚火被吹灭"
	var input := _lean_to_input()
	input["fire_exposure"] = 0.8
	input["fuel_hours"] = 14.0
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "DANGEROUS")
	_expect_score_range(label, report, "heat", 0, 40)
	_expect_note_contains(label, report, 5, "吹灭")


func _test_unknown_preset() -> void:
	var label := "未知预设"
	var input := _base_input("Igloo")
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "DANGEROUS")
	_expect_details_bool(label, report, "unknown_preset", true)
	_expect_note_contains(label, report, 1, "未知")


func _test_none_preset() -> void:
	var label := "None 预设"
	var input := _base_input("None")
	input["bedding_quality"] = 0.5
	input["vent_count"] = 0
	input["has_vent"] = false
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "DANGEROUS")
	_expect_note_contains(label, report, 1, "未选择庇护所")
	_expect_note_contains(label, report, 4, "露天")


func _test_snow_trench_wall_variant() -> void:
	var label := "砌墙雪沟"
	var input := _base_input("SnowTrench")
	input["snow_depth_meters"] = 0.7
	input["has_snow_wall"] = true
	input["roof_thickness_meters"] = 0.3
	input["completion_ratio"] = 1.0
	input["has_cold_pit"] = false
	input["has_raised_bed"] = false
	input["bedding_quality"] = 0.6
	input["wood_left"] = 0.0
	input["prewarmed"] = true
	var report := _run(input)
	if not _expect_shape(label, report):
		return
	_expect_outcome(label, report, "DANGEROUS")
	_expect_details_bool(label, report, "wall_variant", true)
	_expect_note_contains(label, report, 1, "砌墙")


func _test_snow_shelter_ignores_fire() -> void:
	var label := "雪庇护所忽略洞内火"
	var with_fire := _base_input("RaisedCave")
	with_fire["fire_lit"] = true
	with_fire["fire_held"] = true
	with_fire["fuel_hours"] = 14.0
	var without_fire := _base_input("RaisedCave")
	var fire_report := _run(with_fire)
	var no_fire_report := _run(without_fire)
	if not _expect_shape(label, fire_report) or not _expect_shape(label, no_fire_report):
		return

	for key in AXES:
		_check(
			"%s / %s 不因洞内火改变" % [label, key],
			int(fire_report["scores"][key]) == int(no_fire_report["scores"][key]),
			"有火 %d vs 无火 %d" % [
				int(fire_report["scores"][key]),
				int(no_fire_report["scores"][key]),
			]
		)
	_expect_details_bool(label, fire_report, "fire_ignored_in_snow_shelter", true)
	_expect_note_contains(label, fire_report, 5, "禁止明火")


# -----------------------------------------------------------------------------
# 输入与断言工具
# -----------------------------------------------------------------------------

func _run(input: Dictionary) -> Dictionary:
	return NightSimulator.evaluate(input, _tuning)


func _base_input(shelter_type: String) -> Dictionary:
	return {
		"shelter_type": shelter_type,
		"wind_angle_diff": 180.0,
		"wind_speed_kmh": _tuning.wind_speed_kmh,
		"night_temp_c": _tuning.temp_at_night_c,
		"terrain_shelter": 0.4,
		"has_cold_pit": true,
		"has_raised_bed": true,
		"has_snow_wall": false,
		"has_reflector_wall": true,
		"vent_count": 1,
		"has_vent": true,
		"vent_snow_clogged": false,
		"bedding_quality": 1.0,
		"roof_thickness_meters": 0.6,
		"completion_ratio": 1.0,
		"snow_depth_meters": 2.4,
		"slope_deg": 6.0,
		"wood_left": 2.0,
		"fire_lit": false,
		"fire_held": false,
		"fire_exposure": 0.1,
		"fuel_hours": 0.0,
		"night_hours": _tuning.night_duration_hours,
		"prewarmed": false,
	}


func _lean_to_input() -> Dictionary:
	var input := _base_input("LeanTo")
	input["snow_depth_meters"] = 0.2
	input["roof_thickness_meters"] = 0.0
	input["wind_angle_diff"] = 160.0
	input["terrain_shelter"] = 0.3
	input["has_cold_pit"] = false
	input["has_raised_bed"] = false
	input["bedding_quality"] = 0.8
	input["wood_left"] = 2.0
	input["has_reflector_wall"] = true
	input["fire_lit"] = true
	input["fire_held"] = true
	input["fire_exposure"] = 0.1
	input["fuel_hours"] = _tuning.night_duration_hours + 1.0
	input["prewarmed"] = false
	return input


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		return
	var suffix := "" if detail.is_empty() else " — " + detail
	_failures.append(label + suffix)


func _expect_shape(label: String, report: Dictionary) -> bool:
	var ok := true
	var scores: Variant = report.get("scores", null)
	if not (scores is Dictionary):
		_failures.append(label + ": scores 不是 Dictionary")
		return false
	for key in AXES:
		if not scores.has(key):
			_failures.append("%s: scores 缺少 %s" % [label, key])
			ok = false
			continue
		var value: Variant = scores[key]
		if not (value is int or value is float):
			_failures.append("%s: scores.%s 不是数值" % [label, key])
			ok = false
			continue
		var score := int(value)
		if score < 0 or score > 100:
			_failures.append("%s: scores.%s=%d 超出 0–100" % [label, key, score])
			ok = false

	var notes: Variant = report.get("notes", null)
	if not (notes is Array):
		_failures.append(label + ": notes 不是 Array")
		ok = false
	elif notes.size() != AXES.size():
		_failures.append("%s: notes 为 %d 条，期望 6 条" % [label, notes.size()])
		ok = false
	else:
		for index in range(notes.size()):
			if not (notes[index] is String) or str(notes[index]).strip_edges().is_empty():
				_failures.append("%s: notes[%d] 为空或不是 String" % [label, index])
				ok = false

	var outcome := str(report.get("outcome", ""))
	if not (outcome in ["SAFE", "COLD", "DANGEROUS"]):
		_failures.append(label + ": outcome 非法（" + outcome + "）")
		ok = false
	var title := str(report.get("outcome_title", ""))
	if title.strip_edges().is_empty():
		_failures.append(label + ": outcome_title 为空")
		ok = false
	var details: Variant = report.get("details", null)
	if not (details is Dictionary):
		_failures.append(label + ": details 不是 Dictionary")
		ok = false

	if ok:
		_passed += 1
	else:
		_failures.append(label + ": 输出结构不合法")
	return ok


func _expect_outcome(label: String, report: Dictionary, expected: String) -> void:
	var actual := str(report.get("outcome", ""))
	_check(
		"%s / outcome" % label,
		actual == expected,
		"实际 %s，期望 %s" % [actual, expected]
	)


func _expect_title_contains(label: String, report: Dictionary, needle: String) -> void:
	var title := str(report.get("outcome_title", ""))
	_check("%s / outcome_title 包含 %s" % [label, needle], title.contains(needle), "实际: " + title)


func _expect_score_range(
	label: String,
	report: Dictionary,
	key: String,
	min_score: int,
	max_score: int
) -> void:
	var scores: Dictionary = report["scores"]
	var actual := int(scores.get(key, -1))
	_check(
		"%s / %s 分数 %d–%d" % [label, key, min_score, max_score],
		actual >= min_score and actual <= max_score,
		"实际 %d" % actual
	)


func _expect_note_contains(
	label: String,
	report: Dictionary,
	index: int,
	needle: String
) -> void:
	var notes: Array = report["notes"]
	if index < 0 or index >= notes.size():
		_check("%s / notes[%d]" % [label, index], false, "索引越界")
		return
	_check(
		"%s / notes[%d] 包含 %s" % [label, index, needle],
		str(notes[index]).contains(needle),
		"实际: " + str(notes[index])
	)


func _expect_details_bool(
	label: String,
	report: Dictionary,
	key: String,
	expected: bool
) -> void:
	var details: Dictionary = report["details"]
	var actual := bool(details.get(key, not expected))
	_check(
		"%s / details.%s" % [label, key],
		actual == expected,
		"实际 %s，期望 %s" % [str(actual), str(expected)]
	)


func _expect_details_string(
	label: String,
	report: Dictionary,
	key: String,
	expected: String
) -> void:
	var details: Dictionary = report["details"]
	var actual := str(details.get(key, ""))
	_check(
		"%s / details.%s" % [label, key],
		actual == expected,
		"实际 %s，期望 %s" % [actual, expected]
	)
