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
	_check(free.snow_depth_scale_choices == PackedFloat32Array([1.0]) and is_equal_approx(free.snow_contrast, 1.0)
		and is_equal_approx(free.snag_density_scale, 1.0) and is_equal_approx(free.wind_speed_offset_kmh, 0.0), "自由模式环境倍率应全部为 1 / 0")

	# 课题固定条件（CORE_GAMEPLAY §8.1 / §8.2）
	_check(defs[1].start_minutes == tuning.full_day_start_minutes, "第 1 关 10:00 开局（= Tuning.full_day_start_minutes）")
	_check(defs[1].wind_speed_offset_kmh < 0.0, "第 1 关风偏弱")
	_check(defs[1].snow_depth_scale_choices[0] > 1.0, "第 1 关深雪")
	_check(defs[2].snow_contrast > 1.0, "第 2 关雪深更斑驳")
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

	# begin()
	var r := LevelState.begin(3, 4242)
	_check(LevelState.level != null and LevelState.level.index == 3 and LevelState.game_seed == 4242, "begin(3, 4242) 设置关卡与种子")
	_check(r == LevelState.roll_for(defs[3], 4242) and r == LevelState.roll, "begin 的结果 = roll_for")
	LevelState.begin(2)
	_check(LevelState.game_seed >= 1 and LevelState.game_seed <= LevelState.SEED_MAX, "未给种子时随机生成 1..SEED_MAX")
	LevelState.begin(99, 7)
	_check(LevelState.level.index == 0, "非法关卡回退到自由模式")
	LevelState.begin(0, 0)

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
