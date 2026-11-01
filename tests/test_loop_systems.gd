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

	# 章节 × 阶进度（D13 / S3）
	_check(Records.key_for("SnowTrench", 3, false, 7) == "C3-7:SnowTrench" and Records.key_for("LeanTo", 0, true) == "LeanTo@day"
		and Records.key_for("None", 0, false) == "None", "记录键：章节 C<章>-<阶>:，自由模式沿用旧键")
	_check(Records.chapter_progress() == {1: 1} and Records.default_selection() == Vector2i(1, 1) and not Records.free_open(), "新存档只开第 1 章第 1 阶")
	var n0 := Records.record_stage_result(1, 1, "DANGEROUS")
	_check(int(n0["stage"]) == 0 and Records.chapter_highest(1) == 1, "DANGEROUS 不开放新阶")
	var n1 := Records.record_stage_result(1, 1, "COLD")
	_check(int(n1["stage"]) == 2 and Records.stage_unlocked(1, 2) and not Records.stage_unlocked(1, 3), "第 1 阶 COLD → 开放第 2 阶并写盘")
	for st in range(2, 5):
		Records.record_stage_result(1, st, "COLD")
	_check(not Records.stage_unlocked(2, 1), "过第 4 阶还不开第 2 章")
	var n5 := Records.record_stage_result(1, 5, "SAFE")
	_check(int(n5["chapter"]) == 2 and Records.stage_unlocked(2, 1) and Records.stage_unlocked(1, 6), "过第 5 阶 → 开第 6 阶 + 第 2 章（用户定：第 5 阶开下一章）")
	_check(int(Records.record_stage_result(1, 5, "SAFE")["chapter"]) == 0, "重玩不重复报告新开放")
	Records.set_last_selection(1, 6)
	_check(Records.default_selection() == Vector2i(1, 6), "默认 = 上次选的章 / 阶（仍开放）")
	Records.set_last_selection(3, 2)
	_check(Records.default_selection() == Vector2i(1, 1), "上次选的未开放时回到第 1 章第 1 阶")
	for ch in range(2, 6):
		Records.record_stage_result(ch, 5, "COLD")
	_check(Records.free_open() and Records.stage_unlocked(0, 1), "第 5 章过第 5 阶 → 开放自由模式")
	_check(Records.map_index(2, 3) == 0 and Records.next_map(2, 3) == 1 and Records.map_index(2, 3) == 1 and Records.map_index(2, 4) == 0, "每阶独立的「第 k 张图」计数")
	Records.save(Records.key_for("SnowTrench", 3, false, 2), "COLD", 55)
	Records.save(Records.key_for("BasicCave", 3, false, 2), "DANGEROUS", 80)
	_check(Records.stage_best(3, 2).contains("COLD") and Records.stage_best(3, 2).contains("Trench"), "本阶最好：结局优先（%s）" % Records.stage_best(3, 2))
	_check(Records.stage_best(3, 3) == "", "没玩过的阶没有最好记录")
	# 旧存档迁移：D12 的 highest_unlocked = 4 → 前 4 章各开第 1 阶
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var old := ConfigFile.new()
	old.set_value("progress", "highest_unlocked", 4)
	old.set_value("progress", "last_level", 3)
	old.save(path)
	_check(Records.chapter_progress() == {1: 1, 2: 1, 3: 1, 4: 1} and not Records.free_open() and Records.default_selection() == Vector2i(3, 1), "旧存档迁移：前 4 章开放，默认第 3 章第 1 阶")
	old.set_value("progress", "highest_unlocked", 6)
	old.save(path)
	_check(Records.free_open(), "旧存档已开自由模式的仍开放")

	# 庇护所学习（D13 §9.2）
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Records.learned_shelters() == PackedStringArray(["SnowTrench"]), "新存档只会雪沟")
	_check(not Records.learn_shelter("BasicCave", "DANGEROUS"), "DANGEROUS 的一夜学不会")
	_check(not Records.learn_shelter("None", "SAFE") and not Records.learn_shelter("SnowTrench", "SAFE"), "露天 / 已会的不算新学会")
	_check(Records.learn_shelter("BasicCave", "COLD") and "BasicCave" in Records.learned_shelters(), "雪洞 COLD 熬过一夜 → 学会雪洞并写盘")
	_check(not Records.learn_shelter("BasicCave", "SAFE"), "学会后不再重复提示")
	LevelState.begin(4, 1)
	var av := LevelState.available_presets(Records.learned_shelters())
	_check(av == PackedStringArray(["BasicCave", "SnowTrench"]), "第 4 章可用 = 已会（雪沟、雪洞）∪ 本章引入（雪沟）：%s" % str(av))
	LevelState.begin(3, 1)
	_check("LeanTo" in LevelState.available_presets(Records.learned_shelters()) and not ("RaisedCave" in LevelState.available_presets(Records.learned_shelters())), "第 3 章（风倒区）引入倒棚；没学过的高床雪洞不可用")
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

	# R1（第一次评审）：入睡时衣服湿 → 过夜 Heat 下降，报告说明原因，教训指向烘干
	var cave := {"shelter_type": "RaisedCave", "snow_depth_meters": 2.6, "terrain_shelter": 1.0, "completion_ratio": 1.0,
		"wind_angle_diff": 180.0, "bedding_quality": 0.9, "starting_warmth": 90.0, "prewarmed": false, "vent_count": 1, "has_vent": true,
		"has_cold_pit": true, "has_raised_bed": true, "roof_thickness_meters": 0.45, "slope_deg": 25.0}
	var dry_rep := NightSimulator.evaluate(cave, t)
	var wet_in := cave.duplicate()
	wet_in["dampness"] = 1.0
	var wet_rep := NightSimulator.evaluate(wet_in, t)
	_check(float(wet_rep["scores"]["heat"]) <= float(dry_rep["scores"]["heat"]) * (1.0 - t.night_wet_heat_penalty) + 1.0, "湿透入睡：Heat 下降约 %.0f%%（%d → %d）" % [t.night_wet_heat_penalty * 100.0, int(dry_rep["scores"]["heat"]), int(wet_rep["scores"]["heat"])])
	_check(String(dry_rep["outcome"]) == "SAFE" and String(wet_rep["outcome"]) == "COLD", "评审那一局：深雪高床洞干衣 SAFE，湿衣 COLD（%s / %s）" % [String(dry_rep["outcome"]), String(wet_rep["outcome"])])
	var weak := cave.duplicate()
	weak["shelter_type"] = "SnowTrench"
	weak["snow_depth_meters"] = 0.9
	weak["bedding_quality"] = 0.2
	weak["dampness"] = 1.0
	var weak_rep := NightSimulator.evaluate(weak, t)
	if String(weak_rep["outcome"]) == "DANGEROUS" and String(weak_rep["details"]["min_axis"]) == "heat":
		_check(String(weak_rep["outcome_title"]).begins_with("SOAKED"), "湿衣导致失败时标题如实说湿透，而不是庇护所失效（%s）" % String(weak_rep["outcome_title"]))
	var damp_in := cave.duplicate()
	damp_in["dampness"] = 0.1
	_check(int(NightSimulator.evaluate(damp_in, t)["scores"]["heat"]) == int(dry_rep["scores"]["heat"]), "轻微受潮（< 门槛一半）不扣分")
	var wet_txt := NightReportText.build(wet_rep, wet_in, t)
	_check(String(wet_txt["rows"][5]["note"]).contains("wet"), "报告 Heat 一行说明衣服湿了")
	_check(String(wet_rep["notes"][5]).contains("湿透"), "中文归因也说明湿透")
	if String(wet_rep["details"]["min_axis"]) == "heat":
		_check(String(wet_txt["lesson"]).contains("Dry them by a fire"), "最弱项是 Heat 且湿着睡：教训 = 睡前烘干")

	# 第二次评审：施工提示要提前说出"完工还缺什么"（倒棚最后一阶要桦皮）
	var ss := ShelterSite.new()
	ss.builder = ShelterBuilder.new()
	ss.preset_id = "LeanTo"
	ss.builder.current_stage = 3
	var rc := ss.remaining_cost()
	_check(int(rc.get("bark", 0)) == 1 and int(rc.get("wood", 0)) == 4, "倒棚第 3 阶后：完工还要 4 木 + 1 桦皮（%s）" % str(rc))
	ss.builder.current_stage = 5
	_check(ss.remaining_cost().is_empty(), "完工后不再缺材料")
	ss.builder.free()
	ss.free()

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
