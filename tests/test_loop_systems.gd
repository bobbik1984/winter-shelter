extends RefCounted

## M2 循环子系统：NightReportText（每个结局 / 每种庇护所都给出完整报告与教训）、Records（优先结局再比分）、
## AtmosphereState（昼夜系数）、ShelterSite 阶段材料表、Inventory.missing_text。

var _passed := 0
var _failures: Array[String] = []

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var t := load("res://resources/tuning.tres") as Tuning
	Loc.lang = "en"

	# 报告：4 种庇护所 + 露天，每份都有 6 行、标题、结论、教训
	for preset in ["RaisedCave", "BasicCave", "SnowTrench", "LeanTo", "None"]:
		var input := {"shelter_type": preset, "snow_depth_meters": 2.2, "completion_ratio": 1.0,
			"has_vent": preset != "LeanTo" and preset != "None", "vent_count": 1, "bedding_quality": 1.0,
			"wind_angle_diff": 170.0, "roof_thickness_meters": 0.45, "fire_lit": preset == "LeanTo",
			"fuel_hours": 6.0, "starting_warmth": 80.0}
		var rep := NightSimulator.evaluate(input, t)
		var data := NightReportText.build(rep, input, t)
		_check(data["rows"].size() == 6, "%s 报告应有 6 行" % preset)
		_check(String(data["title"]) != "" and String(data["conclusion"]) != "", "%s 报告应有标题与结论" % preset)
		_check(String(data["lesson"]) != "", "%s 报告应有教训" % preset)
		for r in data["rows"]:
			_check(String(r["note"]) != "", "%s / %s 归因不应为空" % [preset, r["key"]])
	# 入口迎风 → site 行提到 wind
	var bad := {"shelter_type": "RaisedCave", "snow_depth_meters": 2.2, "completion_ratio": 1.0, "has_vent": true,
		"vent_count": 1, "bedding_quality": 1.0, "wind_angle_diff": 10.0, "roof_thickness_meters": 0.45}
	var bad_data := NightReportText.build(NightSimulator.evaluate(bad, t), bad, t)
	_check(String(bad_data["rows"][0]["note"]).contains("into the wind"), "迎风入口归因应说明 into the wind")
	# 中文模式使用 NightSimulator 中文归因
	Loc.lang = "zh"
	var zh := NightReportText.build(NightSimulator.evaluate(bad, t), bad, t)
	_check(String(zh["rows"][0]["note"]).contains("迎风"), "中文报告应使用中文归因")
	Loc.lang = "en"

	# Records：结局优先
	var path := Records.RECORDS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Records.save("TestPreset", "COLD", 90)
	Records.save("TestPreset", "SAFE", 60)
	Records.save("TestPreset", "COLD", 99)
	var cfg := ConfigFile.new()
	cfg.load(path)
	_check(cfg.get_value("TestPreset", "outcome", "") == "SAFE", "更好的结局应覆盖更高的分数")
	_check(int(cfg.get_value("TestPreset", "nights", 0)) == 3, "夜数应累计")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# AtmosphereState 昼夜系数
	var a := AtmosphereState.new()
	a.update(720.0, Vector3.UP, 20.0, 180.0, 0.0)
	_check(is_equal_approx(a.day, 1.0), "正午 day = 1")
	a.update(1100.0, Vector3.DOWN, -12.0, 250.0, 0.9)
	_check(a.day < 0.01 and is_equal_approx(a.snowfall, 0.9), "入夜 day ≈ 0 且降雪写入")

	# ShelterSite 阶段材料表：每个预设 5 阶；高床第 3 阶需要垫层与木材；倒棚需要备柴
	for preset in ShelterSite.STAGE_COSTS:
		_check(ShelterSite.STAGE_COSTS[preset].size() == 5, "%s 应有 5 阶材料" % preset)
	_check(ShelterSite.STAGE_COSTS["RaisedCave"][2].has("bedding"), "高床第 3 阶需要垫层")
	var lean_wood := 0
	for c in ShelterSite.STAGE_COSTS["LeanTo"]:
		lean_wood += int(c.get("wood", 0))
	_check(lean_wood >= 6, "倒棚施工合计木材 >= 6（实际 %d）" % lean_wood)

	# Inventory.missing_text
	var inv := Inventory.new()
	inv.add("wood", 1)
	_check(inv.missing_text({"wood": 3, "bark": 1}) == "2 wood, 1 bark", "缺料文字，实际 '%s'" % inv.missing_text({"wood": 3, "bark": 1}))
	inv.free()
	return {"passed": _passed, "failures": _failures}

func _check(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures.append(msg)
