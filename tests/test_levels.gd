extends RefCounted

## L1（D12）：关卡数据与抽取。种子可复现、抽取落在本关范围、自由模式 = 现有默认值、命令行解析、解锁规则。

const VALID_PRESETS := ["RaisedCave", "BasicCave", "SnowTrench", "LeanTo"]
const WEATHERS := ["clear", "overcast", "storm"]
const SAMPLE_SEEDS := 300

var _passed := 0
var _failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_failures.append(msg)

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var tuning := load("res://resources/tuning.tres") as Tuning
	var defs: Array[LevelDef] = []
	for i in range(LevelState.LEVEL_COUNT + 1):
		var d := LevelState.load_level(i)
		_check(d != null, "关卡 %d 资源无法加载" % i)
		if d == null:
			return {"passed": _passed, "failures": _failures}
		_check(d.index == i, "关卡 %d 的 index 字段为 %d" % [i, d.index])
		_check(not d.lesson.strip_edges().is_empty(), "关卡 %d 缺课题文案" % i)
		_check(not d.snow_depth_scale_choices.is_empty() and not d.wind_rotation_choices_deg.is_empty(), "关卡 %d 候选为空" % i)
		for p in d.target_presets:
			_check(p in VALID_PRESETS, "关卡 %d 目标路线未知：%s" % [i, p])
		_check((d.target_presets.size() > 0) == (i > 0), "关卡 %d 目标路线（只有自由模式可为空）" % i)
		defs.append(d)
	_check(LevelState.load_level(-1) == null and LevelState.load_level(6) == null, "越界关卡应返回 null")

	# 自由模式 = 现有默认值（L2 接入后默认行为不变的前提）
	var free := defs[0]
	_check(free.is_free(), "level_free.is_free()")
	_check(free.start_minutes == tuning.start_minutes, "自由模式开局时间应等于 Tuning.start_minutes")
	_check(is_equal_approx(free.weather_weight_clear, tuning.weather_weight_clear)
		and is_equal_approx(free.weather_weight_overcast, tuning.weather_weight_overcast)
		and is_equal_approx(free.weather_weight_storm, tuning.weather_weight_storm), "自由模式天气权重应等于 Tuning")
	_check(free.snow_depth_scale_choices == PackedFloat32Array([1.0]) and is_equal_approx(free.snow_patchiness, 0.0)
		and is_equal_approx(free.snag_density_scale, 1.0) and is_equal_approx(free.wind_speed_offset_kmh, 0.0), "自由模式环境倍率应全部为 1 / 0")

	# 课题固定条件（CORE_GAMEPLAY §8.1 / §8.2）
	# 章节固定条件（CORE_GAMEPLAY §9.5）
	_check(defs[1].theme == "deep_drift" and defs[2].theme == "hidden_pockets" and defs[3].theme == "blowdown"
		and defs[4].theme == "open_flat" and defs[5].theme == "storm_mix", "五章主题按 §9.5 排列")
	_check(defs[1].start_minutes == tuning.full_day_start_minutes and defs[1].start_minutes_hard > defs[1].start_minutes, "第 1 章第 1 阶 10:00 开局，第 10 阶更晚")
	_check(defs[1].wind_speed_offset_kmh < 0.0 and defs[1].snow_depth_scale_choices[0] > 1.0, "第 1 章风偏弱、深雪")
	# R4：第 1 阶是宽裕的教程（10:00），第 2 阶起时间压力立刻回来（13:00 → 第 10 阶 15:00）
	var ch1_starts: Array[int] = []
	for st in range(1, 11):
		ch1_starts.append(LevelState.start_minutes_for(defs[1], LevelState.difficulty_of(st)))
	_check(ch1_starts[0] == 600 and ch1_starts[1] == 780 and ch1_starts[9] == 900, "第 1 章开局：第 1 阶 10:00、第 2 阶 13:00、第 10 阶 15:00（%s）" % str(ch1_starts))
	var mono := true
	for i in range(1, 10):
		mono = mono and ch1_starts[i] >= ch1_starts[i - 1]
	_check(mono, "第 1 章开局时刻逐阶不提前")
	_check(LevelState.start_minutes_for(defs[2], 0.5) == int(round(lerpf(float(defs[2].start_minutes), float(defs[2].start_minutes_hard), 0.5))), "没设第 2 阶开局的章节仍线性")
	_check(defs[2].snow_patchiness > 0.0 and defs[2].snow_patchiness_hard >= defs[2].snow_patchiness, "第 2 章雪深斑驳，越往后越斑驳")
	_check(defs[3].start_minutes > tuning.start_minutes and defs[3].rootball_bonus > 0 and defs[3].target_presets == PackedStringArray(["LeanTo"]), "第 3 章：开工晚、树根盘多、目标倒棚")
	_check(not ("ridge_valley" in defs[4].shape_choices) and defs[4].target_presets == PackedStringArray(["SnowTrench"]), "第 4 章：盆地 / 湖岸，目标雪沟")
	_check(defs[5].weather_weight_storm > 0.0 and defs[5].weather_weight_clear == 0.0 and not defs[5].has_extra_layer and "cliff_band" in defs[5].shape_choices, "第 5 章：暴风雪、无保暖层、可能有悬崖")
	for i in range(1, 6):
		_check(defs[i].start_minutes_hard >= defs[i].start_minutes and defs[i].night_temp_offset_c_hard <= defs[i].night_temp_offset_c
			and defs[i].wind_speed_offset_kmh_hard >= defs[i].wind_speed_offset_kmh and defs[i].snag_density_scale_hard <= defs[i].snag_density_scale,
			"第 %d 章第 10 阶不比第 1 阶容易（开工、气温、风、柴）" % i)
	for i in range(1, 5):
		_check(defs[i].weather_weight_storm == 0.0, "第 %d 章不应出现暴风雪" % i)

	# 抽取：可复现 + 落在范围内 + 有多样性
	for d in defs:
		var seen_valley := {}
		var seen_rot := {}
		var seen_weather := {}
		var seen_scale := {}
		var in_range := true
		for s in range(1, SAMPLE_SEEDS + 1):
			var a := LevelState.roll_for(d, s)
			var b := LevelState.roll_for(d, s)
			if _sig(a) != _sig(b):
				_failures.append("关卡 %d 种子 %d 两次抽取不同" % [d.index, s])
				in_range = false
				break
			var valleys: Array = Array(d.valley_seeds) if not d.valley_seeds.is_empty() else TerrainHeight.VALLEY_SEEDS
			var rot := float(a["wind_rotation_deg"])
			var rot_ok := false
			for c in d.wind_rotation_choices_deg:
				var diff := absf(wrapf(rot - c, -180.0, 180.0))
				rot_ok = rot_ok or diff <= d.wind_jitter_deg + 0.001
			var w := String(a["weather"])
			var w_weight := {"clear": d.weather_weight_clear, "overcast": d.weather_weight_overcast, "storm": d.weather_weight_storm}
			if not (int(a["valley_seed"]) in valleys) or not rot_ok or not (w in WEATHERS) or float(w_weight[w]) <= 0.0 \
					or not (float(a["snow_depth_scale"]) in Array(d.snow_depth_scale_choices)) \
					or int(a["start_minutes"]) != d.start_minutes:
				_failures.append("关卡 %d 种子 %d 抽取越界：%s" % [d.index, s, str(a)])
				in_range = false
				break
			seen_valley[a["valley_seed"]] = true
			seen_rot[snappedf(rot, 1.0)] = true
			seen_weather[w] = true
			seen_scale[a["snow_depth_scale"]] = true
		_check(in_range, "关卡 %d 抽取全部在范围内且可复现" % d.index)
		var n_weathers := int(d.weather_weight_clear > 0) + int(d.weather_weight_overcast > 0) + int(d.weather_weight_storm > 0)
		_check(seen_valley.size() == (d.valley_seeds.size() if not d.valley_seeds.is_empty() else TerrainHeight.VALLEY_SEEDS.size()), "关卡 %d 应抽到全部山谷" % d.index)
		_check(seen_rot.size() >= mini(d.wind_rotation_choices_deg.size(), 4), "关卡 %d 应抽到全部风向" % d.index)
		_check(seen_weather.size() == n_weathers, "关卡 %d 应抽到天气池里的每种天气" % d.index)
		_check(seen_scale.size() == d.snow_depth_scale_choices.size(), "关卡 %d 应抽到每个雪深档位" % d.index)
	# 不同关卡同一种子不应是同一局（种子与关卡一起哈希）
	var same := 0
	for s in range(1, 51):
		if LevelState.roll_for(defs[2], s)["valley_seed"] == LevelState.roll_for(defs[3], s)["valley_seed"] \
				and LevelState.roll_for(defs[2], s)["wind_rotation_deg"] == LevelState.roll_for(defs[3], s)["wind_rotation_deg"]:
			same += 1
	_check(same < 25, "不同关卡同种子的抽取应基本独立（重合 %d/50）" % same)

	_check_snow_bands(defs, tuning)
	_check_rotation()
	_check_texts(defs, tuning)
	_check_gear(defs, tuning)

	# begin()：章 / 阶 / 第 k 张图
	var r := LevelState.begin(3, 4242)
	_check(LevelState.level != null and LevelState.level.index == 3 and LevelState.game_seed == 4242 and LevelState.stage == 1, "begin(3, 4242) 设置章、种子，默认第 1 阶")
	_check(_sig(r) == _sig(LevelState.roll_for(defs[3], 4242, 0.0)) and _sig(r) == _sig(LevelState.roll), "begin 的结果 = roll_for")
	LevelState.begin(2, -1, 7, 0)
	var s70 := LevelState.game_seed
	LevelState.begin(2, -1, 7, 0)
	_check(LevelState.game_seed == s70 and LevelState.stage == 7, "同一阶同一张图 = 同一个种子（固定图）")
	LevelState.begin(2, -1, 7, 1)
	_check(LevelState.game_seed != s70, "[N] 第 2 张图换种子")
	_check(LevelState.global_stage(2, 7) == 17 and LevelState.global_stage(5, 10) == 50 and LevelState.global_stage(0, 1) == 0, "全局阶号 1–50")
	_check(is_equal_approx(LevelState.difficulty_of(1), 0.0) and is_equal_approx(LevelState.difficulty_of(10), 1.0), "难度：第 1 阶 0，第 10 阶 1")
	var easy := LevelState.roll_for(defs[1], 99, 0.0)
	var hard := LevelState.roll_for(defs[1], 99, 1.0)
	_check(int(hard["start_minutes"]) > int(easy["start_minutes"]) and float(hard["night_temp_offset_c"]) < float(easy["night_temp_offset_c"])
		and int(hard["rootball_bonus"]) == int(easy["rootball_bonus"]), "同种子第 10 阶开工更晚、夜更冷")
	LevelState.begin(1, 5, 10)
	LevelState.apply_world()
	_check(MapLayout.DIFFICULTY == 1.0 and MapLayout.rootball_count() == 2, "第 10 阶布局难度 1：树根盘 2 个")
	LevelState.begin(3, 5, 1)
	LevelState.apply_world()
	_check(MapLayout.rootball_count() == 7, "第 3 章第 1 阶风倒区：树根盘 4 + 3 = 7 个")
	LevelState.begin(99, 7)
	_check(LevelState.level.index == 0, "非法章回退到自由模式")
	LevelState.reset()
	_check(TerrainHeight.SNOW_SCALE == 1.0 and TerrainHeight.SNOW_PATCHINESS == 0.0 and TerrainHeight.RECIPE.is_default() and MapLayout.DIFFICULTY == 0.0, "reset() 复位所有旋钮")

	# 命令行
	_check(LevelState.parse_args(PackedStringArray(["--level=3", "--seed=77", "--stage=4"])) == {"level": 3, "seed": 77, "stage": 4}, "--level=3 --seed=77 --stage=4")
	_check(LevelState.parse_args(PackedStringArray(["--level=free"]))["level"] == 0, "--level=free")
	_check(LevelState.parse_args(PackedStringArray(["--level=9", "--seed=x", "--stage=11", "--weather=storm"])) == {"level": -1, "seed": -1, "stage": -1}, "非法参数忽略")

	# 解锁规则（D13：COLD / SAFE 开下一阶；第 5 阶开下一章；第 5 章第 5 阶开自由模式）
	_check(LevelState.unlocks_after(1, 1, "COLD") == {"stage": 2, "chapter": 0, "free": false}, "第 1 阶 COLD → 第 2 阶")
	_check(LevelState.unlocks_after(1, 1, "DANGEROUS") == {"stage": 0, "chapter": 0, "free": false}, "DANGEROUS 不开放")
	_check(LevelState.unlocks_after(2, 5, "SAFE") == {"stage": 6, "chapter": 3, "free": false}, "第 5 阶 → 第 6 阶 + 下一章")
	_check(LevelState.unlocks_after(4, 10, "SAFE") == {"stage": 0, "chapter": 5, "free": false}, "第 10 阶之后没有第 11 阶")
	_check(LevelState.unlocks_after(5, 5, "COLD")["free"] == true and LevelState.unlocks_after(5, 4, "COLD")["free"] == false, "第 5 章第 5 阶开自由模式")
	_check(LevelState.unlocks_after(0, 1, "SAFE") == {"stage": 0, "chapter": 0, "free": false}, "自由模式不开放任何东西")
	return {"passed": _passed, "failures": _failures}


## L2：每关雪深分布符合 CORE_GAMEPLAY §8.2（D5 区间面积，4 个山谷都要满足）。
func _band_fractions(step: float, tuning: Tuning) -> Dictionary:
	var n := 0
	var ge_trench := 0
	var ge_cave := 0
	var ge_raised := 0
	var x := -48.0
	while x <= 48.0:
		var z := -48.0
		while z <= 48.0:
			var s := TerrainHeight.snow_depth_at(x, z)
			n += 1
			if s >= tuning.snow_depth_trench_wall_min_m: ge_trench += 1
			if s >= tuning.snow_depth_cave_min_m: ge_cave += 1
			if s >= tuning.snow_depth_raised_cave_min_m: ge_raised += 1
			z += step
		x += step
	return {"trench": float(ge_trench) / n, "cave": float(ge_cave) / n, "raised": float(ge_raised) / n}

func _check_snow_bands(defs: Array[LevelDef], tuning: Tuning) -> void:
	# D13：每章在真实抽到的图上（第 1 / 10 阶各 4 张）满足本章意图；所有章节都有积雪覆盖
	for ch in range(1, 6):
		var theme := defs[ch].theme
		for st in [1, 10]:
			for k in range(4):
				LevelState.begin(ch, -1, st, k)
				LevelState.apply_world()
				var f := _band_fractions(2.0, tuning)
				var thin := _thin_land_fraction(tuning)
				var tag := "第 %d 章第 %d 阶第 %d 张图（%s ×%.2f）" % [ch, st, k + 1, TerrainHeight.RECIPE.shape, TerrainHeight.SNOW_SCALE]
				_check(thin <= 0.25, tag + "：有积雪覆盖（< 0.3 m 的陆地 %.0f%%）" % (thin * 100.0))
				match theme:
					"deep_drift":
						_check(f["cave"] >= 0.3, tag + "：深雪多（雪洞深度 %.0f%%）" % (f["cave"] * 100.0))
					"hidden_pockets":
						_check(f["cave"] <= 0.3 and f["raised"] >= 0.02, tag + "：深雪少但高床雪洞仍可建（洞 %.0f%% / 高床 %.0f%%）" % [f["cave"] * 100.0, f["raised"] * 100.0])
					"blowdown":
						_check(f["trench"] >= 0.7, tag + "：雪能挖（雪沟深度 %.0f%%）" % (f["trench"] * 100.0))
					"open_flat":
						_check(f["cave"] <= 0.01 and thin <= 0.2, tag + "：没有雪洞深度、陆地上雪沟处处可挖（洞 %.1f%% / 陆地薄雪 %.0f%%）" % [f["cave"] * 100.0, thin * 100.0])
					"storm_mix":
						_check(f["trench"] >= 0.6, tag + "：至少雪沟可挖（%.0f%%）" % (f["trench"] * 100.0))
	LevelState.reset()

func _thin_land_fraction(tuning: Tuning) -> float:
	var n := 0
	var thin := 0
	var x := -48.0
	while x <= 48.0:
		var z := -48.0
		while z <= 48.0:
			if not TerrainHeight.is_lake_at(x, z):
				n += 1
				if TerrainHeight.snow_depth_at(x, z) < tuning.snow_depth_trench_wall_min_m:
					thin += 1
			z += 4.0
		x += 4.0
	return float(thin) / maxf(n, 1)

## L3：风向 = 整图旋转。旋转后在"同一个地图点"上的高度 / 雪深 / 背风度不变；风向随之转；
## 地形结构相对风不变（迎风坡在上风侧、背风深雪在下风侧）。
func _check_rotation() -> void:
	var r0 := TerrainHeight.ROTATION_DEG
	var wind := load("res://resources/default_wind.tres") as WindData
	var samples: Array[Vector2] = []
	for k in range(40):
		samples.append(Vector2((TerrainHeight.hash2(k, 1, 991) - 0.5) * 92.0, (TerrainHeight.hash2(k, 2, 991) - 0.5) * 92.0))
	TerrainHeight.ROTATION_DEG = 0.0
	var base_h: Array[float] = []
	var base_s: Array[float] = []
	var base_l: Array[float] = []
	for p in samples:
		base_h.append(TerrainHeight.height_at(p.x, p.y))
		base_s.append(TerrainHeight.snow_depth_at(p.x, p.y))
		base_l.append(TerrainHeight.lee_factor_at(p.x, p.y))
	_check(wind.from_octant() == 6, "不旋转时风来自西（W）")
	var expected_octant := {0.0: 6, 90.0: 4, 180.0: 2, 270.0: 0}
	for rot in [90.0, 180.0, 270.0]:
		TerrainHeight.ROTATION_DEG = rot
		var ok := true
		for k in range(samples.size()):
			var w := TerrainHeight.to_world(samples[k])
			var back := TerrainHeight.to_map(w.x, w.y)
			if not back.is_equal_approx(samples[k]) \
					or absf(TerrainHeight.height_at(w.x, w.y) - base_h[k]) > 1e-3 \
					or absf(TerrainHeight.snow_depth_at(w.x, w.y) - base_s[k]) > 1e-3 \
					or absf(TerrainHeight.lee_factor_at(w.x, w.y) - base_l[k]) > 1e-3:
				ok = false
				break
		_check(ok, "旋转 %d°：同一地图点的高度 / 雪深 / 背风度不变，坐标可往返" % int(rot))
		_check(wind.from_octant() == int(expected_octant[rot]), "旋转 %d°：风向罗盘方位 = %s（实际 %s）" % [int(rot), GameRules.wind_abbr(int(expected_octant[rot])), GameRules.wind_abbr(wind.from_octant())])
		# 结构相对风不变：从出生点往上风走 20 m 更高（迎风坡 / 脊线），出生点处背风度 > 0
		var spawn := TerrainHeight.to_world(Vector2(18.0, 8.0))
		var up := wind.get_wind_direction_3d()
		var upwind := spawn + Vector2(up.x, up.z) * 20.0
		_check(TerrainHeight.height_at(upwind.x, upwind.y) > TerrainHeight.height_at(spawn.x, spawn.y), "旋转 %d°：出生点上风方向是更高的迎风脊" % int(rot))
	TerrainHeight.ROTATION_DEG = 0.0
	_check(TerrainHeight.to_world(Vector2(3.0, 4.0)) == Vector2(3.0, 4.0), "不旋转时 to_world 是恒等")
	TerrainHeight.ROTATION_DEG = r0


## L5：文案如实——课题有中文；目标行只依据探测结果与 D5 门槛；报告要点引用本图实测值。
func _check_texts(defs: Array[LevelDef], t: Tuning) -> void:
	for d in defs:
		_check(Loc.ZH.has(d.lesson), "关卡 %d 课题缺中文：%s" % [d.index, d.lesson])
	# 第 5 章（自己判断）：目标 = 本图实测雪深允许的、玩家能用的庇护所
	for k in range(6):
		LevelState.begin(5, -1, 1, k)
		LevelState.apply_world()
		var f := SnowField.map_facts(t)
		var tp := LevelState.target_presets()
		var ok := tp.size() == 1
		if ok and tp[0] == "RaisedCave":
			ok = float(f["frac_raised"]) >= LevelState.TARGET_MIN_FRACTION
		elif ok and tp[0] == "BasicCave":
			ok = float(f["frac_cave"]) >= LevelState.TARGET_MIN_FRACTION and float(f["frac_raised"]) < LevelState.TARGET_MIN_FRACTION or not ("RaisedCave" in LevelState.available_presets(Records.learned_shelters()))
		elif ok and tp[0] == "SnowTrench":
			ok = float(f["frac_cave"]) < LevelState.TARGET_MIN_FRACTION or not ("BasicCave" in LevelState.available_presets(Records.learned_shelters()))
		_check(ok, "第 5 章第 %d 张图（%s，雪洞 %.0f%% / 高床 %.0f%%）的目标 %s 与实测一致" % [k + 1, TerrainHeight.RECIPE.shape, float(f["frac_cave"]) * 100.0, float(f["frac_raised"]) * 100.0, str(tp)])
	LevelState.begin(4, 1)
	_check(LevelState.target_presets() == PackedStringArray(["SnowTrench"]), "第 4 章目标 = 雪沟")
	LevelState.reset()
	_check(LevelState.target_presets().is_empty(), "非关卡模式没有目标路线")

	# 目标行：每个 D5 区间一句，且都不写死方位 / 不预设雪洞
	var o0 := GameRules.next_objective({}, t)
	var o1 := GameRules.next_objective({"probed": true, "best_depth": 0.2}, t)
	var o2 := GameRules.next_objective({"probed": true, "best_depth": 0.8}, t)
	var o3 := GameRules.next_objective({"probed": true, "best_depth": 1.7}, t)
	var o4 := GameRules.next_objective({"probed": true, "best_depth": 2.3}, t)
	_check(o0.contains("probe") and not o0.contains("1.5"), "开局目标行：去探，不预设雪洞深度")
	_check(o1.contains("too thin") and o1.contains("lean-to"), "< 0.3 m：太薄，建议倒棚（%s）" % o1)
	_check(o2.contains("trench") and o2.contains("1.5"), "0.3–1.5 m：够雪沟，雪洞要 1.5 m（%s）" % o2)
	_check(o3.contains("snow cave fits") and o3.contains("2.0"), "1.5–2.0 m：能挖雪洞（%s）" % o3)
	_check(o4.contains("raised cave"), "≥ 2.0 m：能挖高床雪洞（%s）" % o4)
	for o in [o0, o1, o2, o3, o4]:
		_check(not (o.contains("east") or o.contains("west")), "目标行不得写死方位（地图会旋转）：%s" % o)

	# 倒棚教训：本图没有雪洞深度时不建议"去找深雪挖洞"
	var lean := {"shelter_type": "LeanTo", "snow_depth_meters": 0.2, "terrain_shelter": 0.8, "completion_ratio": 1.0, "map_max_snow_m": 0.3}
	var rep := NightSimulator.evaluate(lean, t)
	rep["details"]["min_axis"] = "isolation"
	_check(not NightReportText.build(rep, lean, t)["lesson"].contains("cave"), "第 4 关这种图上，倒棚教训不提雪洞")
	lean["map_max_snow_m"] = 2.5
	_check(NightReportText.build(rep, lean, t)["lesson"].contains("cave"), "有深雪的图上，倒棚教训可以建议雪洞")

	# 报告"本关要点"：章节主题 + 实测值 + 判断
	var ctx := {"chapter": 4, "stage": 3, "wind_kmh": 32.0, "night_temp_c": -24.0, "start_minutes": 860, "sunset_minutes": 978.0, "probed_site": true, "entrance_deg": 160.0}
	var facts := {"max_depth": 1.37, "frac_cave": 0.0}
	var ok4 := NightReportText.level_takeaway("open_flat", PackedStringArray(["SnowTrench"]), "SnowTrench", "COLD", facts, ctx, t)
	_check(ok4.contains("1.4") and ok4.contains("read the land right") and ok4.contains("Chapter 4") and ok4.contains("stage 3"), "开阔平地雪沟 COLD：引用最深 1.4 m、章 / 阶并肯定（%s）" % ok4)
	# R2：结果对 ≠ 过程对
	var ctx2 := ctx.duplicate()
	ctx2["probed_site"] = false
	var lucky := NightReportText.level_takeaway("open_flat", PackedStringArray(["SnowTrench"]), "SnowTrench", "COLD", facts, ctx2, t)
	_check(lucky.contains("never probed") and not lucky.contains("read the land right"), "选对但没在挖的地方探过：不表扬，指出深度是碰巧的（%s）" % lucky)
	ctx2["probed_site"] = true
	ctx2["entrance_deg"] = 95.0
	var side := NightReportText.level_takeaway("open_flat", PackedStringArray(["SnowTrench"]), "SnowTrench", "COLD", facts, ctx2, t)
	_check(side.contains("95°") and not side.contains("read the land right"), "入口侧风：指出角度（%s）" % side)
	var lean_ok := NightReportText.level_takeaway("blowdown", PackedStringArray(["LeanTo"]), "LeanTo", "COLD", facts, {"chapter": 3, "stage": 1, "probed_site": false, "entrance_deg": 180.0, "start_minutes": 900, "sunset_minutes": 978.0}, t)
	_check(lean_ok.contains("read the land right"), "倒棚不靠雪深：没探雪也不扣（%s）" % lean_ok)
	var pts: Array[Vector3] = [Vector3(10, 0, 10), Vector3(30, 0, 0)]
	_check(GameRules.probed_near(pts, Vector3(14, 2, 13), 6.0) and not GameRules.probed_near(pts, Vector3(0, 0, -20), 6.0), "选址 6 m 内探过的判定")
	var wrong4 := NightReportText.level_takeaway("open_flat", PackedStringArray(["SnowTrench"]), "BasicCave", "DANGEROUS", facts, ctx, t)
	_check(wrong4.contains("Snow cave") and wrong4.contains("Trench"), "开阔平地硬挖雪洞：指出雪沟更合适（%s）" % wrong4)
	ctx["start_minutes"] = 905
	var blow := NightReportText.level_takeaway("blowdown", PackedStringArray(["LeanTo"]), "None", "DANGEROUS", {"max_depth": 2.0}, ctx, t)
	_check(blow.contains("15:05") and blow.contains("73 min") and blow.contains("no shelter"), "风倒区：引用开工时刻与剩余天光（%s）" % blow)
	var l2 := NightReportText.level_takeaway("hidden_pockets", PackedStringArray(["RaisedCave"]), "RaisedCave", "DANGEROUS", {"max_depth": 2.6, "frac_cave": 0.14}, ctx, t)
	_check(l2.contains("14%") and l2.contains("Right choice"), "隐藏深雪：引用深雪面积 14%%（%s）" % l2)
	ctx["wind_kmh"] = 52.0
	ctx["night_temp_c"] = -29.0
	var l5 := NightReportText.level_takeaway("storm_mix", PackedStringArray(["LeanTo"]), "LeanTo", "SAFE", {"max_depth": 0.3}, ctx, t)
	_check(l5.contains("52") and l5.contains("-29") and l5.contains("Lean-to"), "暴风雪：引用风速 / 气温 / 目标（%s）" % l5)
	_check(NightReportText.level_takeaway("free", PackedStringArray(), "None", "SAFE", facts, ctx, t) == "", "自由模式没有本关要点")
	# 真实地图实测：第 4 章（开阔平地）的图上最深雪 < 雪洞门槛（与文案一致）
	LevelState.begin(4, 7)
	LevelState.apply_world()
	var f3 := SnowField.map_facts(t)
	_check(float(f3["max_depth"]) < t.snow_depth_cave_min_m and float(f3["frac_cave"]) == 0.0, "第 4 章实测：没有能挖雪洞的地方（最深 %.2f m）" % float(f3["max_depth"]))
	LevelState.reset()
	_check(SnowField.map_facts(t)["max_depth"] > t.snow_depth_raised_cave_min_m, "复位后缓存失效：基础地图有高床雪洞深度")


## S6：装备是关卡的固定条件；没有雪铲挖雪更慢；防潮垫加地面隔热；非关卡模式 = 旧默认。
func _check_gear(defs: Array[LevelDef], t: Tuning) -> void:
	LevelState.reset()
	_check(LevelState.gear() == {"shovel": true, "layer": true, "pad": false, "wood": 0, "bark": 0, "bedding": 0}, "非关卡模式装备 = 旧默认")
	LevelState.begin(1, 1)
	var g1 := LevelState.gear()
	_check(bool(g1["shovel"]) and bool(g1["layer"]) and bool(g1["pad"]) and int(g1["bark"]) == 2, "第 1 关全套装备 + 2 份桦皮")
	LevelState.begin(5, 1)
	_check(not bool(LevelState.gear()["layer"]) and bool(LevelState.gear()["shovel"]), "第 5 关减配：没有额外保暖层")
	LevelState.reset()
	_check(is_equal_approx(GameRules.dig_minutes(30.0, true, false, t), 30.0 * t.no_shovel_dig_factor) and t.no_shovel_dig_factor > 1.5, "没有雪铲：挖雪庇护所工时 × %.1f" % t.no_shovel_dig_factor)
	_check(is_equal_approx(GameRules.dig_minutes(30.0, true, true, t), 30.0), "有雪铲：工时不变")
	_check(is_equal_approx(GameRules.dig_minutes(30.0, false, false, t), 30.0), "倒棚不靠雪铲：工时不变")
	_check(GameRules.bedding_with_pad(0.2, true, t) > 0.2 and GameRules.bedding_with_pad(0.9, true, t) <= 1.0 and is_equal_approx(GameRules.bedding_with_pad(0.2, false, t), 0.2), "防潮垫加地面隔热，封顶 1")
	# 机制如实：防潮垫让隔热分更高（NightSimulator 同一套规则）
	var base := {"shelter_type": "SnowTrench", "snow_depth_meters": 1.0, "terrain_shelter": 0.6, "completion_ratio": 1.0, "bedding_quality": 0.2}
	var with_pad := base.duplicate()
	with_pad["bedding_quality"] = GameRules.bedding_with_pad(0.2, true, t)
	_check(float(NightSimulator.evaluate(with_pad, t)["scores"]["insulation"]) > float(NightSimulator.evaluate(base, t)["scores"]["insulation"]), "带防潮垫的一夜隔热分更高")


## 抽取结果的可比较签名（配方是对象，按描述比较）。
func _sig(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out["recipe"] = (r["recipe"] as TerrainRecipe).describe() if r.has("recipe") else ""
	return out
