extends RefCounted

## 本地化覆盖：代码里每个 Loc.t("…") 字面量都必须在中文表里有译文；译文的 % 占位符数量与英文一致。

var _passed := 0
var _failures: Array[String] = []

func run() -> Dictionary:
	_passed = 0
	_failures = []
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
			if not Loc.ZH.has(key):
				_failures.append("缺中文：%s  (%s)" % [key, path.get_file()])
				continue
			var n_en := ph.search_all(key).size()
			var n_zh := ph.search_all(String(Loc.ZH[key])).size()
			if n_en != n_zh:
				_failures.append("占位符数量不一致：%s" % key)
				continue
			_passed += 1
	if checked < 100:
		_failures.append("只扫到 %d 个 Loc.t 调用，扫描可能失效" % checked)
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
