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
	_check(defs[1].start_minutes == tuning.full_day_start_minutes, "第 1 关 10:00 开局（= Tuning.full_day_start_minutes）")
	_check(defs[1].wind_speed_offset_kmh < 0.0, "第 1 关风偏弱")
	_check(defs[1].snow_depth_scale_choices[0] > 1.0, "第 1 关深雪")
	_check(defs[2].snow_patchiness > 0.0, "第 2 关雪深更斑驳")
	_check(defs[3].snow_depth_scale_choices[0] < 1.0 and defs[4].snow_depth_scale_choices[0] < defs[3].snow_depth_scale_choices[0], "第 3 / 4 关雪逐级变浅")
	_check(defs[4].snag_density_scale > 1.0, "第 4 关立枯木更多")
	_check(defs[5].weather_weight_storm > 0.0 and defs[5].weather_weight_clear == 0.0 and defs[5].weather_weight_overcast == 0.0, "第 5 关只有暴风雪将至")
	_check(defs[5].snow_depth_scale_choices.size() >= 3, "第 5 关雪深三选一")
	for i in range(1, 5):
		_check(defs[i].weather_weight_storm == 0.0, "第 %d 关不应出现暴风雪" % i)

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
			if a != b:
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

	# begin()
	var r := LevelState.begin(3, 4242)
	_check(LevelState.level != null and LevelState.level.index == 3 and LevelState.game_seed == 4242, "begin(3, 4242) 设置关卡与种子")
	_check(r == LevelState.roll_for(defs[3], 4242) and r == LevelState.roll, "begin 的结果 = roll_for")
	LevelState.begin(2)
	_check(LevelState.game_seed >= 1 and LevelState.game_seed <= LevelState.SEED_MAX, "未给种子时随机生成 1..SEED_MAX")
	LevelState.begin(99, 7)
	_check(LevelState.level.index == 0, "非法关卡回退到自由模式")
	LevelState.reset()
	_check(TerrainHeight.SNOW_SCALE == 1.0 and TerrainHeight.SNOW_PATCHINESS == 0.0, "reset() 复位雪深旋钮")

	# 命令行
	_check(LevelState.parse_args(PackedStringArray(["--level=3", "--seed=77"])) == {"level": 3, "seed": 77}, "--level=3 --seed=77")
	_check(LevelState.parse_args(PackedStringArray(["--level=free"]))["level"] == 0, "--level=free")
	_check(LevelState.parse_args(PackedStringArray(["--level=9", "--seed=x", "--weather=storm"])) == {"level": -1, "seed": -1}, "非法参数忽略")
	_check(LevelState.parse_args(PackedStringArray()) == {"level": -1, "seed": -1}, "无参数")

	# 解锁规则（§8.4）
	_check(LevelState.unlocks_next("SAFE") and LevelState.unlocks_next("COLD") and not LevelState.unlocks_next("DANGEROUS"), "COLD / SAFE 解锁，DANGEROUS 不解锁")
	_check(LevelState.unlocked_after(1, 1, "COLD") == 2, "第 1 关 COLD → 解锁第 2 关")
	_check(LevelState.unlocked_after(1, 1, "DANGEROUS") == 1, "第 1 关 DANGEROUS → 不变")
	_check(LevelState.unlocked_after(4, 2, "SAFE") == 4, "重玩旧关不降低进度")
	_check(LevelState.unlocked_after(3, 0, "SAFE") == 3, "自由模式不影响解锁")
	_check(LevelState.unlocked_after(5, 5, "COLD") == 6, "通过第 5 关 → 开放自由模式")
	_check(LevelState.is_unlocked(1, 0) and not LevelState.is_unlocked(2, 1), "新存档只开第 1 关")
	_check(not LevelState.is_unlocked(0, 5) and LevelState.is_unlocked(0, 6), "自由模式在通过第 5 关后开放")
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
	var seed0 := TerrainHeight.SEED
	var base := {}
	for v in TerrainHeight.VALLEY_SEEDS:
		TerrainHeight.SEED = v
		TerrainHeight.SNOW_SCALE = 1.0
		TerrainHeight.SNOW_PATCHINESS = 0.0
		base[v] = _band_fractions(2.0, tuning)
		for li in range(defs.size()):
			var d := defs[li]
			for sc in d.snow_depth_scale_choices:
				TerrainHeight.SNOW_SCALE = sc
				TerrainHeight.SNOW_PATCHINESS = d.snow_patchiness
				var f := _band_fractions(2.0, tuning)
				var tag := "关卡 %d 山谷 %d 倍率 %.2f" % [li, v, sc]
				if sc == 1.0 and d.snow_patchiness == 0.0:
					_check(f == base[v], tag + "：倍率 1 时雪深应与基础地图完全一致")
				elif li == 1:
					_check(f["cave"] > base[v]["cave"] and f["cave"] >= 0.4, tag + "：深雪（可挖雪洞）面积应更大且 ≥ 40%%（%.1f%%）" % (f["cave"] * 100.0))
				elif li == 2:
					_check(f["cave"] < base[v]["cave"] * 0.65 and f["raised"] >= 0.03, tag + "：深雪应明显变少但高床雪洞仍可建（洞 %.1f%% / 高床 %.1f%%）" % [f["cave"] * 100.0, f["raised"] * 100.0])
				elif sc < 0.2:
					_check(f["trench"] <= 0.03, tag + "：几乎没有能挖雪沟的地方（%.1f%%）" % (f["trench"] * 100.0))
				elif sc < 1.0:
					_check(f["cave"] == 0.0 and f["trench"] >= 0.7, tag + "：雪洞不可建、雪沟大部分可建（沟 %.1f%%）" % (f["trench"] * 100.0))
	TerrainHeight.SEED = seed0
	TerrainHeight.SNOW_SCALE = 1.0
	TerrainHeight.SNOW_PATCHINESS = 0.0


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
	# 第 5 关目标路线随抽到的雪深档位
	for s in range(1, 40):
		LevelState.begin(5, s)
		var sc := float(LevelState.roll["snow_depth_scale"])
		var tp := LevelState.target_presets()
		var want := "RaisedCave" if sc >= 1.0 else ("SnowTrench" if sc >= 0.5 else "LeanTo")
		if tp.size() != 1 or tp[0] != want:
			_failures.append("第 5 关种子 %d 雪深 %.2f 的目标路线应为 %s，实际 %s" % [s, sc, want, str(tp)])
			break
	_passed += 1
	LevelState.begin(3, 1)
	_check(LevelState.target_presets() == PackedStringArray(["SnowTrench"]), "第 3 关目标 = 雪沟")
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

	# 报告"本关要点"：条件句引用实测值 + 判断
	var facts := {"max_depth": 1.37, "frac_cave": 0.0}
	var ok3 := NightReportText.level_takeaway(3, PackedStringArray(["SnowTrench"]), "SnowTrench", "COLD", facts, 32.0, -24.0, t)
	_check(ok3.contains("1.4") and ok3.contains("read the land right"), "第 3 关雪沟 COLD：引用最深 1.4 m 并肯定（%s）" % ok3)
	var wrong3 := NightReportText.level_takeaway(3, PackedStringArray(["SnowTrench"]), "BasicCave", "DANGEROUS", facts, 32.0, -24.0, t)
	_check(wrong3.contains("Snow cave") and wrong3.contains("Trench"), "第 3 关硬挖雪洞：指出雪沟更合适（%s）" % wrong3)
	var none4 := NightReportText.level_takeaway(4, PackedStringArray(["LeanTo"]), "None", "DANGEROUS", {"max_depth": 0.31}, 32.0, -24.0, t)
	_check(none4.contains("0.31") and none4.contains("no shelter"), "第 4 关露天：引用 0.31 m（%s）" % none4)
	var l2 := NightReportText.level_takeaway(2, PackedStringArray(["RaisedCave"]), "RaisedCave", "DANGEROUS", {"max_depth": 2.6, "frac_cave": 0.14}, 32.0, -24.0, t)
	_check(l2.contains("14%") and l2.contains("Right choice"), "第 2 关：引用深雪面积 14%%（%s）" % l2)
	var l5 := NightReportText.level_takeaway(5, PackedStringArray(["LeanTo"]), "LeanTo", "SAFE", {"max_depth": 0.3}, 52.0, -29.0, t)
	_check(l5.contains("52") and l5.contains("-29") and l5.contains("Lean-to"), "第 5 关：引用风速 / 气温 / 目标（%s）" % l5)
	_check(NightReportText.level_takeaway(0, PackedStringArray(), "None", "SAFE", facts, 0.0, 0.0, t) == "", "自由模式没有本关要点")
	# 真实地图实测：第 3 关的图上最深雪 < 雪洞门槛（与文案一致）
	LevelState.begin(3, 7)
	LevelState.apply_world()
	var f3 := SnowField.map_facts(t)
	_check(float(f3["max_depth"]) < t.snow_depth_cave_min_m and float(f3["frac_cave"]) == 0.0, "第 3 关实测：没有能挖雪洞的地方（最深 %.2f m）" % float(f3["max_depth"]))
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
