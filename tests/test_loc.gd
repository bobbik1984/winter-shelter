extends RefCounted

## 本地化覆盖：代码里每个 Loc.t("…") 字面量都必须在中文表里有译文；译文的 % 占位符数量与英文一致。

var _passed := 0
var _failures: Array[String] = []

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var catalog := Loc.catalog()
	var re := RegEx.new()
	re.compile("Loc\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"\\)")
	var ph := RegEx.new()
	ph.compile("%[-0-9.]*[dsf]")
	var files := _scan("res://scripts")
	var checked := 0
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var key := m.get_string(1).c_unescape()
			checked += 1
			if not catalog.has(key):
				_failures.append("缺中文：%s  (%s)" % [key, path.get_file()])
				continue
			var n_en := ph.search_all(key).size()
			var n_zh := ph.search_all(String(catalog[key])).size()
			if n_en != n_zh:
				_failures.append("占位符数量不一致：%s" % key)
				continue
			_passed += 1
	if checked < 100:
		_failures.append("只扫到 %d 个 Loc.t 调用，扫描可能失效" % checked)
	# 全表检查，而不仅是静态 Loc.t 调用；%% 为字面百分号，类型与顺序都须一致。
	for key in catalog:
		var translated := String(catalog[key])
		if translated.strip_edges() == "":
			_failures.append("空译文：%s" % key)
		elif _formats(String(key)) != _formats(translated):
			_failures.append("全表占位符类型或顺序不一致：%s" % key)
		else:
			_passed += 1
	# 中英文报告使用同一个条件分支，覆盖所有庇护所的六维说明。
	var old_lang := Loc.lang
	# CSV 是唯一编辑源：导入后必须逐条等价，拒绝重复键/空译文/丢行。
	var csv := FileAccess.open("res://localization/messages.csv", FileAccess.READ)
	var seen := {}
	if csv.get_csv_line() != PackedStringArray(["keys", "en", "zh"]):
		_failures.append("翻译表表头应为 keys,en,zh")
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row == PackedStringArray([""]): continue
		if row.size() != 3 or row[0].is_empty() or seen.has(row[0]):
			_failures.append("翻译行列数错误、空键或重复键：%s" % str(row))
			continue
		seen[row[0]] = true
		for index in [1, 2]:
			Loc.lang = Loc.SUPPORTED_LOCALES[index - 1]
			if row[index].is_empty() or Loc.t(row[0]) != row[index]:
				_failures.append("翻译资源与 CSV 不一致：%s/%s" % [Loc.lang, row[0]])
			else:
				_passed += 1
	if seen.size() != catalog.size():
		_failures.append("翻译源与引擎资源条目数不一致")
	for pair in [["zh-CN", "zh"], ["zh_TW", "zh"], ["en_US", "en"], ["fr", "en"]]:
		if Loc.normalize_locale(pair[0]) == pair[1]: _passed += 1
		else: _failures.append("语言区域回退错误：%s" % pair[0])
	Loc.lang = "zh"
	if Loc.t("unknown.message.key") == "unknown.message.key": _passed += 1
	else: _failures.append("未知消息未回退原文")
	var tuning := load("res://resources/tuning.tres") as Tuning
	for preset in ["None", "BasicCave", "RaisedCave", "SnowTrench", "TreeWell", "Quinzhee", "LeanTo", "RockOverhang", "FallenLog", "Tent"]:
		var input := {"shelter_type": preset, "completion_ratio": 1.0, "snow_depth_meters": 2.4, "roof_thickness_meters": 0.45, "vent_count": 1, "bedding_quality": 1.0, "has_cold_pit": preset == "RaisedCave", "has_raised_bed": preset == "RaisedCave"}
		for axis in NightReportText.AXES:
			Loc.lang = "en"
			var en := NightReportText._note(axis[0], preset, input, {}, tuning)
			Loc.lang = "zh"
			var zh := NightReportText._note(axis[0], preset, input, {}, tuning)
			if en == zh or zh.is_empty():
				_failures.append("报告未翻译：%s/%s" % [preset, axis[0]])
			else:
				_passed += 1
	Loc.lang = old_lang
	# 资源数据驱动的名称与施工阶段也会显示给玩家。
	for preset in ShelterPreset.create_all_presets().values():
		for text in [preset.display_name] + Array(preset.stage_titles):
			if not catalog.has(text):
				_failures.append("资源缺中文：%s" % text)
			else:
				_passed += 1
	return {"passed": _passed, "failures": _failures}

func _scan(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") and f != "loc.gd":
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scan(dir.path_join(sub)))
	return out

func _formats(text: String) -> PackedStringArray:
	var regex := RegEx.new()
	regex.compile("%[-+0-9.]*([dsf])")
	var out := PackedStringArray()
	for item in regex.search_all(text.replace("%%", "")):
		out.append(item.get_string(1))
	return out
