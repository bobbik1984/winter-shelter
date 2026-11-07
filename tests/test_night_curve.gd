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
		# 2026-11-07 平衡：冷醒在 SAFE 线之上（52），SAFE 允许 3 次被迫醒来——醒了就处理的人，树井 / 清了通风的雪洞能平安
		"trench": ["COLD", "COLD"], "treewell": ["COLD", "SAFE"], "leanto_fire": ["COLD", "SAFE"], "cave_novent": ["DANGEROUS", "SAFE"],
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
	var lf_nowatch: Dictionary = (c["leanto_fire"] as Dictionary).duplicate()
	lf_nowatch["fire_watch"] = false
	var lf_smart := NightCurve.run(lf_nowatch, t, "smart")
	_check(float(lf_smart["min_warmth"]) > float(lf_sleep["min_warmth"]) + 20.0, "倒棚：醒来添柴比一直睡暖得多（%d vs %d）" % [int(lf_smart["min_warmth"]), int(lf_sleep["min_warmth"])])
	_check(int(lf_smart["wakes"]) >= 1, "倒棚：火灭后冷下来会醒（%d）" % int(lf_smart["wakes"]))
	_check(float(lf_smart["fire_out_at"]) < 0.0 or float(lf_smart["fire_out_at"]) > float(lf_sleep["fire_out_at"]), "添过柴的火烧得更久（%.0f vs %.0f）" % [lf_smart["fire_out_at"], lf_sleep["fire_out_at"]])
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
	var lean := NightCurve.new(lf_nowatch, t)
	_check(lean.fire_minutes <= t.night_fire_initial_hours * 60.0 + 0.1 and lean.stock_logs > 0, "入睡时火里只架 %.1f h 的柴，其余是备柴（%d 根）" % [t.night_fire_initial_hours, lean.stock_logs])
	var ev := lean.step()
	_check(ev == NightCurve.EV_FIRE_OUT and lean.fire_minutes <= 0.0, "倒棚：暖和时火灭不叫醒人，冷下来才醒（%s）" % ev)
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
	# 2026-11-03 第四次评审后发现：夜晚长度不能取决于帧率（以前每帧至少走 5 分钟）
	for fps in [15.0, 60.0, 144.0, 240.0]:
		var pn := NightCurve.new(_fps_input(), t)
		var rate := pn.duration / t.night_real_seconds
		var secs := 0.0
		while secs < 10.0:
			pn.play(rate / fps)
			if pn.waiting():
				pn.act(NightCurve.ACT_SLEEP)
			secs += 1.0 / fps
		_check(absf(pn.minute - rate * 10.0) <= t.night_step_min + 1.0, "%d FPS：播放 10 秒走 %.0f 分钟（应约 %.0f）" % [int(fps), pn.minute, rate * 10.0])
	_get_up(c, t)
	_wake_and_score(c, t)
	return {"passed": _passed, "failures": _failures}

## 2026-11-07：自己醒来、守火、睡眠和夜晚得分。
func _wake_and_score(c: Dictionary, t: Tuning) -> void:
	# 自己醒来：睡着时随时可以，不算被冻醒；等选择时不能再"醒"一次
	var n := NightCurve.new(c["trench"], t)
	n.advance_to(60.0)
	_check(n.wake_now() and n.pending_event() == NightCurve.EV_SELF and n.planned_wakes == 1 and n.wakes == 0, "随时可以自己醒来，不算被冻醒")
	_check(not n.wake_now(), "已经醒着时不能再醒一次")
	_check(NightCurve.ACT_EXERCISE in n.available_actions() and NightCurve.ACT_SLEEP in n.available_actions(), "自己醒来后能活动、能接着睡")
	n.act(NightCurve.ACT_SLEEP)
	# 守火：人还暖和时按约好的醒来添柴；关掉就睡到被冻醒
	var watch := NightCurve.run(c["leanto_fire"], t, "smart")
	var off: Dictionary = (c["leanto_fire"] as Dictionary).duplicate()
	off["fire_watch"] = false
	var nowatch := NightCurve.run(off, t, "smart")
	_check(int(watch["planned_wakes"]) >= 1, "守火：火快烧完时醒来添柴（%d 次）" % int(watch["planned_wakes"]))
	_check(float(watch["min_warmth"]) >= float(nowatch["min_warmth"]), "守火比等冻醒暖（%d vs %d）" % [int(watch["min_warmth"]), int(nowatch["min_warmth"])])
	var lw := NightCurve.new(c["leanto_fire"], t)
	var ev := lw.step()
	_check(ev == NightCurve.EV_FIRE_WATCH and lw.warmth > t.night_wake_cold_w and lw.fire_minutes > 0.0, "守火在火灭之前、人还暖和时叫醒（%s，W=%d）" % [ev, int(lw.warmth)])
	# 冷醒在 SAFE 线之上：发抖把人冻醒时还来得及
	_check(t.night_wake_cold_w > t.night_safe_min_w, "冷醒（%d）在 SAFE 线（%d）之上" % [int(t.night_wake_cold_w), int(t.night_safe_min_w)])
	# 睡眠：醒得越多睡得越少；越冷睡得越浅
	var calm := NightCurve.run(c["raised_dry"], t, "sleep")
	var broken := NightCurve.new(c["raised_dry"], t)
	while not broken.is_over():
		broken.advance_to(broken.minute + 60.0)
		if broken.waiting():
			broken.act(NightCurve.ACT_SLEEP)
		elif not broken.is_over() and broken.wake_now():
			broken.act(NightCurve.ACT_SLEEP)
	var br := broken.result()
	_check(float(br["sleep_h"]) < float(calm["sleep_h"]) - 2.0, "每小时醒一次，睡得少得多（%.1f vs %.1f h）" % [float(br["sleep_h"]), float(calm["sleep_h"])])
	_check(int(br["score_sleep"]) < int(calm["score_sleep"]) and int(br["score"]) < int(calm["score"]), "睡得少，睡眠分和总分都低")
	var cold := NightCurve.run(c["none"], t, "sleep")
	_check(float(cold["sleep_frac"]) < float(calm["sleep_frac"]), "冷得发抖睡得浅（%.2f vs %.2f）" % [float(cold["sleep_frac"]), float(calm["sleep_frac"])])
	# 得分：0..100，三项都在；危险的一夜封顶；早上衣服湿着不算 SAFE
	for k in c:
		for pol in ["sleep", "smart", "vigilant"]:
			var r := NightCurve.run(c[k], t, pol)
			var ok := int(r["score"]) >= 0 and int(r["score"]) <= 100 and r.has("score_warmth") and r.has("score_sleep") and r.has("score_health")
			if String(r["outcome"]) == "DANGEROUS":
				ok = ok and int(r["score"]) <= int(t.night_score_dangerous_cap)
			if String(r["outcome"]) == "SAFE":
				ok = ok and NightSimulator.wet_fraction(float(r["end_damp"]), t) < 0.5
			_check(ok, "得分合法：%s / %s → %s %d" % [k, pol, r["outcome"], int(r["score"])])
	_check(int(NightCurve.run(c["raised_dry"], t, "sleep")["score"]) > int(NightCurve.run(c["raised_wet"], t, "sleep")["score"]), "同一个雪洞：干衣得分高于湿衣")
	# 自己醒来照看的人，不比只等冻醒的人差
	for k in ["trench", "treewell", "leanto_fire"]:
		var sm := NightCurve.run(c[k], t, "smart")
		var vg := NightCurve.run(c[k], t, "vigilant")
		_check(float(vg["min_warmth"]) >= float(sm["min_warmth"]) - 1.0, "%s：自己醒来照看，最低体温不比等冻醒低（%d vs %d）" % [k, int(vg["min_warmth"]), int(sm["min_warmth"])])

## 2026-11-07 试玩报告 P1：白天醒来可以起床回到白天；天黑以后、或离日落太近，没有这个选项。
func _get_up(c: Dictionary, t: Tuning) -> void:
	var early := (c["raised_wet"] as Dictionary).duplicate()
	early["daylight_minutes"] = 240.0
	var n := NightCurve.new(early, t)
	var ev := n.step()
	_check(ev != "", "湿衣早睡：天黑前就冻醒")
	_check(n.light_left() >= t.night_get_up_min_light_min and NightCurve.ACT_GET_UP in n.available_actions(), "白天醒来有起床选项（离日落 %.0f 分钟）" % n.light_left())
	_check(n.available_actions()[-1] == NightCurve.ACT_SLEEP, "接着睡始终是最后一项")
	var w := n.warmth
	_check(n.act(NightCurve.ACT_GET_UP) and n.got_up and n.is_over() and not n.waiting(), "起床：这一夜结束、不再等选择")
	_check(n.step() == "" and n.warmth == w, "起床后模型不再推进")
	var late := NightCurve.new(c["raised_wet"], t)
	late.step()
	_check(not (NightCurve.ACT_GET_UP in late.available_actions()), "天黑后醒来没有起床选项")
	var edge := (c["raised_wet"] as Dictionary).duplicate()
	edge["daylight_minutes"] = 1.0
	var en := NightCurve.new(edge, t)
	en.step()
	_check(not (NightCurve.ACT_GET_UP in en.available_actions()), "离日落不到 %d 分钟：没有起床选项" % int(t.night_get_up_min_light_min))
	# 机器人策略不会起床（不改原来的结局）
	_check(not bool(NightCurve.run(early, t, "smart").get("got_up", false)), "smart 策略不起床")
	# 网页版风声循环的交叉淡化：迎风端 0、闷声端 1、单调
	_check(is_zero_approx(AmbientAudio.loop_mix(2600.0)) and is_equal_approx(AmbientAudio.loop_mix(60.0), 1.0), "风声循环：两端各是一段")
	_check(AmbientAudio.loop_mix(1000.0) < AmbientAudio.loop_mix(400.0), "风声循环：截止越低越闷")

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
	var awake := NightCurve.new(c["trench"], t)
	var w0 := awake.warmth
	awake.act(NightCurve.ACT_EXERCISE)
	_check(awake.warmth < w0 + t.night_exercise_warmth, "醒着做事时体温照样在掉")
	# 火：所有庇护所同一条规则（用户定调 2026-11-02）
	var fire_base: Dictionary = (c["leanto_fire"] as Dictionary).duplicate()
	var calm: Dictionary = fire_base.duplicate()
	calm["wind_speed_kmh"] = t.night_fire_wind_ref_kmh
	var gale: Dictionary = fire_base.duplicate()
	gale["wind_speed_kmh"] = t.night_fire_wind_ref_kmh * 1.6
	var snowing: Dictionary = fire_base.duplicate()
	snowing["night_snowfall"] = 0.9
	var lm := NightCurve.new(calm, t).log_minutes
	_check(NightCurve.new(gale, t).log_minutes < lm, "风越大，一根柴烧得越快")
	_check(NightCurve.new(snowing, t).log_minutes < lm, "下雪时，一根柴烧得更快")
	var exposed: Dictionary = gale.duplicate()
	exposed["fire_exposure"] = t.fire_blowout_dot * 0.8
	var ok_now: Dictionary = exposed.duplicate()
	ok_now["wind_speed_kmh"] = t.night_fire_wind_ref_kmh
	_check(NightCurve.new(ok_now, t).has_fire_place and NightCurve.new(exposed, t).fire_blocked == "wind", "同一个火位：平常留得住，大风留不住")
	# 火灭：暖和就接着睡，有柴能重新点
	var warm: Dictionary = calm.duplicate()
	warm["starting_warmth"] = 100.0
	warm["fire_watch"] = false
	var wn := NightCurve.new(warm, t)
	var first_ev := wn.step()
	_check(wn.fire_minutes <= 0.0 and wn.minute > wn.log_minutes + 60.0 and wn.warmth <= t.night_fire_wake_w + 1.0, "火灭之后还暖和，不会醒（%s，%d 分钟，W=%d）" % [first_ev, int(wn.minute), int(wn.warmth)])
	var w_before := wn.warmth
	_check(wn.act(NightCurve.ACT_ADD_WOOD) and wn.fire_minutes > 0.0 and wn.fire_out_at < 0.0, "火灭了，有柴就能重新点")
	wn.act(NightCurve.ACT_SLEEP)
	wn.advance_to(wn.minute + 60.0)
	_check(wn.warmth > w_before, "重新点着后回暖（%d → %d）" % [int(w_before), int(wn.warmth)])
	var no_logs: Dictionary = calm.duplicate()
	no_logs["firewood_logs"] = 1.0
	var nl := NightCurve.new(no_logs, t)
	_check(not (NightCurve.ACT_ADD_WOOD in nl.available_actions()), "没有备柴就没有添柴选项")
	# 极寒 / 很差的庇护所：火快灭时一定叫醒
	var harsh: Dictionary = calm.duplicate()
	harsh["terrain_shelter"] = -0.5
	harsh["wind_angle_diff"] = 40.0
	harsh["bedding_quality"] = 0.3
	harsh["night_temp_c"] = -38.0
	var hn := NightCurve.new(harsh, t)
	if hn.has_fire_place and hn._fireless_loss() >= t.night_fire_wake_loss_per_h:
		_check(hn.step() == NightCurve.EV_FIRE_DYING, "没火时掉得很快：火快灭就会醒")
	else:
		_check(false, "极寒用例应当有火且失温很快（失温 %.1f/h）" % hn._fireless_loss())
	# 雪沟 / 树井门口的火有帮助；雪洞里没有（D3）
	var tr_fire: Dictionary = (c["trench"] as Dictionary).duplicate()
	tr_fire.merge({"campfire_near": true, "firewood_logs": 6.0, "fire_exposure": 0.15}, true)
	_check(float(NightCurve.run(tr_fire, t, "smart")["min_warmth"]) >= float(NightCurve.run(c["trench"], t, "smart")["min_warmth"]) and NightCurve.new(tr_fire, t).loss_per_hour() < NightCurve.new(c["trench"], t).loss_per_hour(), "雪沟门口有火：失温更慢")
	var cave_fire: Dictionary = (c["raised_dry"] as Dictionary).duplicate()
	cave_fire.merge({"campfire_near": true, "firewood_logs": 6.0, "fire_exposure": 0.15}, true)
	_check(is_equal_approx(NightCurve.new(cave_fire, t).loss_per_hour(), NightCurve.new(c["raised_dry"], t).loss_per_hour()), "雪洞：火在外面，睡着时没有作用（D3）")
	# 第三次评审后：报告说具体原因，不说分数名
	var leak_in := {"shelter_type": "SnowTrench", "completion_ratio": 1.0, "prewarmed": true}
	var leak_res := {"had_fire": false, "fire_out_at": -1.0, "logs_left": 0, "end_damp": 0.0}
	_check(NightText.heat_leak(leak_in, {"end_damp": 1.0}, "heat", t) == "wet clothes", "湿透：热量漏在湿衣服")
	_check(NightText.heat_leak({"shelter_type": "None"}, leak_res, "heat", t) == "no shelter at all", "没有庇护所")
	_check(NightText.heat_leak({"shelter_type": "SnowTrench", "completion_ratio": 0.4}, leak_res, "heat", t) == "an unfinished shelter", "没建完")
	_check(NightText.heat_leak(leak_in, {"had_fire": true, "fire_out_at": 300.0, "logs_left": 0, "end_damp": 0.0}, "heat", t) == "a fire that ran out of wood", "柴烧完了")
	_check(NightText.heat_leak(leak_in, leak_res, "isolation", t).contains("cold air"), "隔冷最弱：说冷空气")
	# S5：其余三种庇护所的夜晚
	var qz := _case({"shelter_type": "Quinzhee", "snow_depth_meters": 1.4, "bedding_quality": 0.95, "vent_count": 1, "has_vent": true, "roof_thickness_meters": 0.35})
	var rk := _case({"shelter_type": "RockOverhang", "snow_depth_meters": 0.4, "bedding_quality": 0.95, "terrain_shelter": 0.9, "wind_angle_diff": 180.0, "has_reflector_wall": true, "campfire_near": true, "firewood_logs": 6.0, "fire_exposure": 0.1})
	var fl := _case({"shelter_type": "FallenLog", "snow_depth_meters": 0.6, "bedding_quality": 0.95, "wind_angle_diff": 180.0, "campfire_near": true, "firewood_logs": 6.0, "fire_exposure": 0.15})
	for pair in [["雪堆屋", qz], ["岩檐", rk], ["倒木斜棚", fl]]:
		_check(String(NightCurve.run(pair[1], t, "smart")["outcome"]) != "DANGEROUS", "%s：完工、准备好：至少 COLD（%s，最低 %d）" % [pair[0], NightCurve.run(pair[1], t, "smart")["outcome"], int(NightCurve.run(pair[1], t, "smart")["min_warmth"])])
	var qz_novent: Dictionary = qz.duplicate()
	qz_novent["vent_count"] = 0
	qz_novent["has_vent"] = false
	_check(String(NightCurve.run(qz_novent, t, "sleep")["cause"]) == "suffocated", "雪堆屋也是密闭雪室：没通风孔一样窒息")
	var qz_fire: Dictionary = qz.duplicate()
	qz_fire.merge({"campfire_near": true, "firewood_logs": 6.0, "fire_exposure": 0.1}, true)
	_check(is_equal_approx(NightCurve.new(qz_fire, t).loss_per_hour(), NightCurve.new(qz, t).loss_per_hour()), "雪堆屋：火在外面，睡着时没有作用（D3）")
	var fl_nofire: Dictionary = fl.duplicate()
	fl_nofire.erase("campfire_near")
	_check(float(NightCurve.run(fl, t, "smart")["min_warmth"]) >= float(NightCurve.run(fl_nofire, t, "sleep")["min_warmth"]), "倒木斜棚：有火比没火好")
	_check(NightCurve.new(rk, t).loss_per_hour() < NightCurve.new(fl, t).loss_per_hour(), "岩壁反射火的热量：同样有火，岩檐比倒木斜棚暖")
	# 第三次评审后：夜晚到日出为止；早睡要熬更久，但日落前那段还没到夜间气温
	var early: Dictionary = (c["trench"] as Dictionary).duplicate()
	early.merge({"night_hours": 16.0, "daylight_minutes": 60.0}, true)
	var en := NightCurve.new(early, t)
	_check(is_equal_approx(en.duration, 16.0 * 60.0), "给了 night_hours 就按它算夜长")
	_check(is_equal_approx(en.loss_per_hour(), en.base_loss * t.night_daylight_loss_factor), "日落前失温打折")
	en.advance_to(70.0)
	_check(is_equal_approx(en.loss_per_hour(), en.base_loss), "日落后恢复夜间失温")
	var late: Dictionary = (c["trench"] as Dictionary).duplicate()
	late["night_hours"] = t.night_duration_hours
	_check(float(NightCurve.run(early, t, "sleep")["min_warmth"]) < float(NightCurve.run(late, t, "sleep")["min_warmth"]), "太早躺下：要多熬几个小时，比天黑才睡更冷")
	# 第三次评审（核实后不是 bug）：时间线严格按时间、跨午夜写 00:xx，不会出现 24:xx
	var lr := NightCurve.run(c["trench"], t, "smart")
	var mono := true
	var last_min := -1.0
	for e in lr["timeline"]:
		mono = mono and float(e["minute"]) >= last_min
		last_min = float(e["minute"])
	_check(mono, "夜间时间线按时间递增")
	_check(NightText.clock(1000.0, 500.0) == "01:00" and NightText.clock(959.0, 481.0) == "00:00", "跨午夜的时钟写 00:xx（%s）" % NightText.clock(1000.0, 500.0))
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

func _fps_input() -> Dictionary:
	return {"shelter_type": "RaisedCave", "structure_quality": 1.0, "stage": 5, "snow_depth": 2.5, "wind_angle_diff": 180.0,
		"bedding": 3, "vent_open": true, "dampness": 0.0, "body_warmth": 90.0, "night_hours": 14.0, "temp_c": -18.0}
