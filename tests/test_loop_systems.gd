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

	# Records：结局优先（写临时文件，绝不碰玩家的 user://records.cfg）
	var real_path := Records.path
	Records.path = "user://test_records_loop.cfg"
	var path := Records.path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Records.save("TestPreset", "COLD", 90)
	Records.save("TestPreset", "SAFE", 60)
	Records.save("TestPreset", "COLD", 99)
	var cfg := ConfigFile.new()
	cfg.load(path)
	_check(cfg.get_value("TestPreset", "outcome", "") == "SAFE", "更好的结局应覆盖更高的分数")
	_check(int(cfg.get_value("TestPreset", "nights", 0)) == 3, "夜数应累计")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 关卡进度（D12 / L4）
	_check(Records.key_for("SnowTrench", 3, false) == "L3:SnowTrench" and Records.key_for("LeanTo", 0, true) == "LeanTo@day"
		and Records.key_for("None", 0, false) == "None", "记录键：关卡 L<N>:，自由模式沿用旧键")
	_check(Records.highest_unlocked() == 1 and Records.default_level() == 1, "新存档只开第 1 关，默认第 1 关")
	_check(Records.record_level_result(1, "DANGEROUS") == 1, "第 1 关 DANGEROUS 不解锁")
	_check(Records.record_level_result(1, "COLD") == 2 and Records.highest_unlocked() == 2, "第 1 关 COLD 解锁第 2 关并写盘")
	Records.set_last_level(1)
	_check(Records.default_level() == 1, "默认 = 上次选的关（仍解锁）")
	Records.set_last_level(4)
	_check(Records.default_level() == 2, "上次选的关未解锁时 = 已解锁最高关")
	_check(Records.record_level_result(1, "SAFE") == 2, "重玩旧关不降低进度")
	for i in range(2, 6):
		Records.record_level_result(i, "COLD")
	_check(Records.highest_unlocked() == 6 and LevelState.is_unlocked(0, Records.highest_unlocked()), "通过第 5 关开放自由模式")
	Records.set_last_level(0)
	_check(Records.default_level() == 0, "自由模式解锁后可作为默认")
	Records.save(Records.key_for("SnowTrench", 3, false), "COLD", 55)
	Records.save(Records.key_for("BasicCave", 3, false), "DANGEROUS", 80)
	_check(Records.level_best(3).contains("COLD") and Records.level_best(3).contains("Trench"), "本关最好：结局优先（%s）" % Records.level_best(3))
	_check(Records.level_best(4) == "", "没玩过的关没有最好记录")
	_check(LevelState.step_unlocked(1, 1, 2) == 2 and LevelState.step_unlocked(2, 1, 2) == 1 and LevelState.step_unlocked(1, -1, 2) == 2, "←/→ 只在已解锁的关之间循环")
	_check(LevelState.step_unlocked(1, 1, 1) == 1, "只有第 1 关时 ←/→ 不动")
	_check(LevelState.step_unlocked(5, 1, 6) == 0 and LevelState.step_unlocked(0, 1, 6) == 1, "第 5 关之后是自由模式，再之后回到第 1 关")
	# 庇护所学习（D13 §9.2）
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Records.learned_shelters() == PackedStringArray(["SnowTrench"]), "新存档只会雪沟")
	_check(not Records.learn_shelter("BasicCave", "DANGEROUS"), "DANGEROUS 的一夜学不会")
	_check(not Records.learn_shelter("None", "SAFE") and not Records.learn_shelter("SnowTrench", "SAFE"), "露天 / 已会的不算新学会")
	_check(Records.learn_shelter("BasicCave", "COLD") and "BasicCave" in Records.learned_shelters(), "雪洞 COLD 熬过一夜 → 学会雪洞并写盘")
	_check(not Records.learn_shelter("BasicCave", "SAFE"), "学会后不再重复提示")
	LevelState.begin(3, 1)
	var av := LevelState.available_presets(Records.learned_shelters())
	_check(av == PackedStringArray(["BasicCave", "SnowTrench"]), "第 3 关可用 = 已会（雪沟、雪洞）∪ 本关引入（雪沟）：%s" % str(av))
	LevelState.begin(4, 1)
	_check("LeanTo" in LevelState.available_presets(Records.learned_shelters()) and not ("RaisedCave" in LevelState.available_presets(Records.learned_shelters())), "第 4 关引入倒棚；没学过的高床雪洞不可用")
	LevelState.begin(1, 1)
	_check(LevelState.available_presets(PackedStringArray(["SnowTrench"])) == PackedStringArray(["RaisedCave", "BasicCave", "SnowTrench"]), "第 1 关引入两种雪洞")
	LevelState.reset()
	_check(LevelState.available_presets(PackedStringArray()) == PackedStringArray(BuildMode.PRESETS), "非关卡模式（测试 / 机器人）全部可用")
	var bm := BuildMode.new()
	bm.available = PackedStringArray(["BasicCave", "SnowTrench"])
	bm.preset_id = "BasicCave"
	bm.cycle_preset()
	var c1 := bm.preset_id
	bm.cycle_preset()
	_check(c1 == "SnowTrench" and bm.preset_id == "BasicCave", "Tab 只在可用的庇护所之间循环")
	bm.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Records.path = real_path

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
