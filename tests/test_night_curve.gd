extends RefCounted

## D14 / N1 可玩的夜晚（CORE_GAMEPLAY §10）：标定表、A2 红线（冻死 / 窒息前一定醒过）、容错（±10% 不翻转结局）、事件与行动规则。

var _passed := 0
var _failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_failures.append(msg)

const BASE := {"starting_warmth": 90.0, "wind_angle_diff": 160.0, "wind_speed_kmh": 32.0, "night_temp_c": -24.0,
	"completion_ratio": 1.0, "terrain_shelter": 0.6, "slope_deg": 20.0}

func _case(extra: Dictionary) -> Dictionary:
	var d := BASE.duplicate()
	d.merge(extra, true)
	return d

func _cases() -> Dictionary:
	return {
		"none": _case({"shelter_type": "None", "snow_depth_meters": 1.0, "terrain_shelter": 0.0, "completion_ratio": 0.0, "wind_angle_diff": 90.0}),
		"raised_dry": _case({"shelter_type": "RaisedCave", "snow_depth_meters": 2.4, "bedding_quality": 0.95, "vent_count": 1, "has_vent": true,
			"has_cold_pit": true, "has_raised_bed": true, "roof_thickness_meters": 0.45}),
		"raised_wet": _case({"shelter_type": "RaisedCave", "snow_depth_meters": 2.4, "bedding_quality": 0.95, "vent_count": 1, "has_vent": true,
			"has_cold_pit": true, "has_raised_bed": true, "roof_thickness_meters": 0.45, "dampness": 1.0}),
		"trench": _case({"shelter_type": "SnowTrench", "snow_depth_meters": 1.1, "bedding_quality": 0.95, "vent_count": 1, "has_vent": true, "roof_thickness_meters": 0.3}),
		"treewell": _case({"shelter_type": "TreeWell", "snow_depth_meters": 1.6, "bedding_quality": 0.95, "roof_thickness_meters": 0.35}),
		"leanto_fire": _case({"shelter_type": "LeanTo", "snow_depth_meters": 0.6, "bedding_quality": 0.95, "terrain_shelter": 0.7, "wind_angle_diff": 180.0,
			"fire_lit": true, "fire_held": true, "firewood_logs": 8.0, "fire_exposure": 0.15, "has_reflector_wall": true}),
		"cave_novent": _case({"shelter_type": "BasicCave", "snow_depth_meters": 1.8, "bedding_quality": 0.95, "vent_count": 0, "roof_thickness_meters": 0.4}),
	}

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var t := load("res://resources/tuning.tres") as Tuning
	var c := _cases()

	# 1. 标定表（§10.2）
	var expect := {
		"none": ["DANGEROUS", "DANGEROUS"], "raised_dry": ["SAFE", "SAFE"], "raised_wet": ["COLD", "COLD"],
		"trench": ["COLD", "COLD"], "treewell": ["COLD", "COLD"], "leanto_fire": ["COLD", "COLD"], "cave_novent": ["DANGEROUS", "COLD"],
	}
	for k in expect:
		var sleep := NightCurve.run(c[k], t, "sleep")
		var smart := NightCurve.run(c[k], t, "smart")
		_check(String(sleep["outcome"]) == expect[k][0], "%s 一直睡：应为 %s（实际 %s，最低 %d）" % [k, expect[k][0], sleep["outcome"], int(sleep["min_warmth"])])
		_check(String(smart["outcome"]) == expect[k][1], "%s 醒来处理：应为 %s（实际 %s，最低 %d）" % [k, expect[k][1], smart["outcome"], int(smart["min_warmth"])])
	var rd := NightCurve.new(c["raised_dry"], t)
	_check(rd.base_loss <= 1.5, "完工高床雪洞、干衣：每小时掉 ≤ 1.5（%.2f）" % rd.base_loss)
	var nn := NightCurve.new(c["none"], t)
	_check(nn.base_loss >= 20.0, "露天：每小时掉得很快（%.1f）" % nn.base_loss)
	var tr := NightCurve.new(c["trench"], t)
	var tw := NightCurve.new(c["treewell"], t)
	_check(tr.base_loss > rd.base_loss and tw.base_loss > rd.base_loss and tr.base_loss < nn.base_loss, "保护度排序：高床雪洞 < 雪沟 / 树井 < 露天")
	# 倒棚：火灭后失温明显快于火在时；按时添柴比一直睡暖得多
	var lf_sleep := NightCurve.run(c["leanto_fire"], t, "sleep")
	var lf_smart := NightCurve.run(c["leanto_fire"], t, "smart")
	_check(float(lf_smart["min_warmth"]) > float(lf_sleep["min_warmth"]) + 20.0, "倒棚：醒来添柴比一直睡暖得多（%d vs %d）" % [int(lf_smart["min_warmth"]), int(lf_sleep["min_warmth"])])
	_check(int(lf_smart["wakes"]) >= 2, "倒棚的火要半夜添柴：至少醒 2 次（%d）" % int(lf_smart["wakes"]))
	_check(float(lf_smart["fire_out_at"]) < 0.0 and float(lf_sleep["fire_out_at"]) > 0.0, "添柴的火烧到天亮；不添柴的火半夜灭（记录熄灭时刻 %.0f）" % float(lf_sleep["fire_out_at"]))
	# 湿衣：好雪洞也会变冷（与 R1 一致）
	_check(float(NightCurve.run(c["raised_wet"], t, "sleep")["min_warmth"]) < float(NightCurve.run(c["raised_dry"], t, "sleep")["min_warmth"]) - 30.0, "湿衣入睡：同一个雪洞冷得多")

	# 2. A2 红线：任何输入下，冻到 0 或窒息之前一定醒过
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var shelters := ["None", "RaisedCave", "BasicCave", "SnowTrench", "TreeWell", "LeanTo"]
	var a2_ok := true
	var a2_msg := ""
	for i in range(300):
		var inp := _case({"shelter_type": shelters[rng.randi_range(0, shelters.size() - 1)], "snow_depth_meters": rng.randf_range(0.2, 3.0),
			"bedding_quality": rng.randf(), "starting_warmth": rng.randf_range(20.0, 100.0), "dampness": rng.randf(),
			"vent_count": rng.randi_range(0, 2), "vent_snow_clogged": rng.randf() < 0.3, "night_snowfall": rng.randf(),
			"night_temp_c": rng.randf_range(-35.0, -10.0), "completion_ratio": rng.randf(), "wind_angle_diff": rng.randf_range(0.0, 180.0),
			"fire_lit": rng.randf() < 0.4, "firewood_logs": float(rng.randi_range(0, 10)), "fire_exposure": rng.randf(), "has_reflector_wall": rng.randf() < 0.5})
		var n := NightCurve.new(inp, t)
		var first_event := INF
		while not n.is_over():
			var ev := n.step()
			if ev == "":
				break
			first_event = minf(first_event, n.minute)
			n.act(NightCurve.ACT_SLEEP)
		var r := n.result()
		var died := float(r["min_warmth"]) <= 0.0 or String(r["cause"]) == "suffocated"
		if died and first_event == INF:
			a2_ok = false
			a2_msg = "第 %d 个随机夜晚（%s）没醒就死了" % [i, inp["shelter_type"]]
			break
		if float(r["min_warmth"]) < t.night_wake_critical_w and first_event == INF:
			a2_ok = false
			a2_msg = "第 %d 个随机夜晚：跌破极危却一次没醒" % i
			break
	_check(a2_ok, "A2：300 个随机夜晚里，冻死 / 窒息 / 跌破极危之前都醒过 " + a2_msg)

	# 3. 容错：基础失温 ±10% 不翻转结局（醒来处理的玩家）
	# 真正的性质是"连续"：参数小改只让曲线移动几分；只有本来就贴着分界线（±6 分内）的夜晚才可能换结局。
	var bounds := [t.night_wake_critical_w, t.night_safe_min_w]
	for k in ["raised_dry", "trench", "treewell", "leanto_fire", "cave_novent"]:
		var r0 := NightCurve.run(c[k], t, "smart")
		var m0 := float(r0["min_warmth"])
		var near_edge := false
		for b in bounds:
			near_edge = near_edge or absf(m0 - float(b)) <= 6.0
		for f in [0.9, 1.1]:
			var t2 := t.duplicate() as Tuning
			t2.night_base_loss_per_h = t.night_base_loss_per_h * f
			var r := NightCurve.run(c[k], t2, "smart")
			_check(absf(float(r["min_warmth"]) - m0) <= 8.0, "连续：%s 基础失温 ×%.1f，最低体温只移动几分（%d → %d）" % [k, f, int(m0), int(r["min_warmth"])])
			if not near_edge:
				_check(String(r["outcome"]) == String(r0["outcome"]), "容错：%s（离分界线远）×%.1f 结局不变（%s → %s）" % [k, f, r0["outcome"], r["outcome"]])

	# 4. 事件与行动
	var cave := NightCurve.new(c["raised_dry"], t)
	_check(not (NightCurve.ACT_ADD_WOOD in cave.available_actions()), "雪洞里不能添柴（D3）")
	var lean := NightCurve.new(c["leanto_fire"], t)
	_check(lean.fire_minutes <= t.night_fire_initial_hours * 60.0 + 0.1 and lean.stock_logs > 0, "入睡时火里只架 %.1f h 的柴，其余是备柴（%d 根）" % [t.night_fire_initial_hours, lean.stock_logs])
	var ev := lean.step()
	_check(ev == NightCurve.EV_FIRE_DYING, "倒棚：火快灭时醒来（%s）" % ev)
	var fm := lean.fire_minutes
	_check(lean.act(NightCurve.ACT_ADD_WOOD) and lean.fire_minutes > fm + 60.0, "添柴让火多烧（%.0f → %.0f min）" % [fm, lean.fire_minutes])
	var blown: Dictionary = (c["leanto_fire"] as Dictionary).duplicate()
	blown["fire_exposure"] = 0.9
	_check(not NightCurve.new(blown, t).has_fire_place, "风口上的火整夜留不住")
	var wet := NightCurve.new(c["raised_wet"], t)
	var saw_wet := false
	while not wet.is_over():
		var e := wet.step()
		if e == "":
			break
		saw_wet = saw_wet or e == NightCurve.EV_WET_FEET
		wet.act(NightCurve.ACT_SLEEP)
	_check(saw_wet, "湿衣入睡：会因为脚冷醒来")
	var snowy: Dictionary = (c["treewell"] as Dictionary).duplicate()
	snowy["night_snowfall"] = 0.9
	var sn := NightCurve.new(snowy, t)
	var got_load := false
	while not sn.is_over():
		var e2 := sn.step()
		if e2 == "":
			break
		if e2 == NightCurve.EV_SNOW_LOAD:
			got_load = true
			_check(NightCurve.ACT_KNOCK_SNOW in sn.available_actions(), "积雪压顶时可以从里面顶落")
			sn.act(NightCurve.ACT_SLEEP)
			_check(sn.snow_load_active and sn.loss_per_hour() > sn.base_loss, "不顶落就继续睡：此后失温加快")
			break
		sn.act(NightCurve.ACT_SLEEP)
	_check(got_load, "大雪夜的树井：积雪压顶事件")
	var clog: Dictionary = (c["raised_dry"] as Dictionary).duplicate()
	clog["vent_snow_clogged"] = true
	_check(String(NightCurve.run(clog, t, "sleep")["outcome"]) == "COLD" and String(NightCurve.run(clog, t, "smart")["outcome"]) == "SAFE", "通风口被雪堵：不清理最多 COLD，清理了仍可 SAFE")
	_check(NightCurve.run(c["raised_dry"], t, "smart")["curve"].size() >= 20, "整夜体温曲线有足够的点")
	var r1 := NightCurve.run(c["trench"], t, "smart")
	var r2 := NightCurve.run(c["trench"], t, "smart")
	_check(r1["min_warmth"] == r2["min_warmth"] and r1["timeline"].size() == r2["timeline"].size(), "同一输入结果可复现")
	_n5(c, t)
	return {"passed": _passed, "failures": _failures}

## N5：活动不能代替庇护所；冻醒不受上限限制；醒着做事也花时间；每章目标路线在第 1 / 5 / 10 阶都活得下来。
func _n5(c: Dictionary, t: Tuning) -> void:
	# 连按活动：露天怎么按都熬不过去（修复前按 8 次 = COLD，最低 39）
	for presses in [1, 3, 8, 20]:
		var n := NightCurve.new(c["none"], t)
		var guard := 0
		while not n.is_over() and guard < 300:
			guard += 1
			if n.step() == "":
				break
			for i in presses:
				n.act(NightCurve.ACT_EXERCISE)
			n.act(NightCurve.ACT_SLEEP)
		_check(String(n.result()["outcome"]) == "DANGEROUS", "露天每次醒来连按活动 %d 次也是 DANGEROUS（%s，最低 %d）" % [presses, n.result()["outcome"], int(n.result()["min_warmth"])])
	var ex := NightCurve.new(c["trench"], t)
	var g0 := ex.exercise_gain()
	ex.act(NightCurve.ACT_EXERCISE)
	var g1 := ex.exercise_gain()
	_check(is_equal_approx(g0, t.night_exercise_warmth) and g1 < g0 * 0.6, "同一次醒来再活动，效果明显递减（%.1f → %.1f）" % [g0, g1])
	ex.act(NightCurve.ACT_SLEEP)
	var g2 := ex.exercise_gain()
	_check(g2 > g1 and g2 < g0, "下一次醒来恢复，但人已经累了（%.1f，第一次 %.1f）" % [g2, g0])
	# 醒着做事也花时间：火在烧、人在冷
	var lean := NightCurve.new(c["leanto_fire"], t)
	var fm := lean.fire_minutes
	lean.dampness = 1.0
	lean.act(NightCurve.ACT_DRY_SOCKS)
	_check(is_equal_approx(lean.fire_minutes, fm - 15.0), "烘袜子 15 分钟，火也烧了 15 分钟")
	var w0 := lean.warmth
	lean.act(NightCurve.ACT_DRY_SOCKS)
	_check(lean.warmth < w0, "醒着做事时体温照样在掉")
	# 冻醒不受上限限制：醒的次数用完后，也不会一路睡到极危才醒
	var wet: Dictionary = (c["trench"] as Dictionary).duplicate()
	wet["dampness"] = 1.0
	var capped := t.duplicate() as Tuning
	capped.night_max_wakes = 0
	var cn := NightCurve.new(wet, capped)
	var first := cn.step()
	_check(first == NightCurve.EV_COLD, "上限用完后仍然先冻醒，而不是直接极危（%s）" % first)
	# 每章目标路线（合成输入：中等背风、完工；真实地图上的路线是 S7）
	var routes := {1: ["RaisedCave", "BasicCave"], 2: ["TreeWell"], 3: ["LeanTo"], 4: ["SnowTrench"], 5: ["RaisedCave", "SnowTrench", "LeanTo"]}
	var keys := {"RaisedCave": "raised_dry", "BasicCave": "cave_vented", "TreeWell": "treewell", "LeanTo": "leanto_fire", "SnowTrench": "trench"}
	var cases: Dictionary = c.duplicate()
	cases["cave_vented"] = _case({"shelter_type": "BasicCave", "snow_depth_meters": 1.8, "bedding_quality": 0.95, "vent_count": 1, "has_vent": true, "roof_thickness_meters": 0.4})
	for ch in routes:
		var def: LevelDef = LevelState.load_level(ch)
		var prev := {}
		for st in [1, 5, 10]:
			var roll: Dictionary = LevelState.roll_for(def, 1, LevelState.difficulty_of(st))
			var storm: bool = ch == 5
			var temp: float = t.temp_at_night_c + float(roll["night_temp_offset_c"]) - (t.storm_extra_cold_c if storm else 0.0)
			var wind: float = maxf(t.wind_speed_kmh + float(roll["wind_speed_offset_kmh"]) + (t.storm_extra_wind_kmh if storm else 0.0), 0.0)
			for sh in routes[ch]:
				var inp: Dictionary = (cases[keys[sh]] as Dictionary).duplicate()
				inp.merge({"starting_warmth": 100.0, "prewarmed": true, "dampness": 0.0, "night_temp_c": temp, "wind_speed_kmh": wind}, true)
				var r := NightCurve.run(inp, t, "smart")
				var tag := "第 %d 章第 %d 阶 %s" % [ch, st, sh]
				_check(String(r["outcome"]) != "DANGEROUS", "%s：准备充分 + 夜里处理 ≥ COLD（%s，最低 %d）" % [tag, r["outcome"], int(r["min_warmth"])])
				_check(float(r["min_warmth"]) >= float(NightCurve.run(inp, t, "sleep")["min_warmth"]), "%s：夜里处理不比一直睡差" % tag)
				for f in [0.9, 1.1]:
					var t2 := t.duplicate() as Tuning
					t2.night_base_loss_per_h = t.night_base_loss_per_h * f
					_check(String(NightCurve.run(inp, t2, "smart")["outcome"]) != "DANGEROUS", "%s：基础失温 ×%.1f 仍 ≥ COLD" % [tag, f])
				if prev.has(sh):
					_check(float(r["base_loss"]) >= float(prev[sh]), "%s：阶越高失温不会变慢（%.1f ≥ %.1f）" % [tag, r["base_loss"], prev[sh]])
				prev[sh] = float(r["base_loss"])
