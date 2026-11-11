extends SceneTree

## T0.6 统一测试入口。
## 运行：godot --headless --path . -s res://tests/run_all.gd
## 退出码：0 = 全部通过；1 = 有失败。
##
## 约定：
##   * tests/test_*.gd 若 extends RefCounted，需提供 run() -> Dictionary，
##     返回 {"passed": int, "failures": Array}（也兼容 bool / Array 返回值）。
##   * tests/test_*.gd 若 extends SceneTree（独立脚本风格），run_all 会用
##     `godot --headless -s <path>` 子进程运行，以其退出码判定成败。
##   * tests/test_terrain.gd / tests/test_snow_field.gd 由 Track B 负责；
##     文件不存在时跳过，不阻塞 T0.6。

const TUNING_PATH := "res://resources/tuning.tres"

const SUITES := [
	{"name": "night_sim", "path": "res://tests/test_night_sim.gd", "required": true},
	{"name": "terrain", "path": "res://tests/test_terrain.gd", "required": false},
	{"name": "snow_field", "path": "res://tests/test_snow_field.gd", "required": false},
	{"name": "warmth", "path": "res://tests/test_warmth.gd", "required": true},
	{"name": "shelter_builder", "path": "res://tests/test_shelter_builder.gd", "required": true},
	{"name": "sun_model", "path": "res://tests/test_sun_model.gd", "required": true},
	{"name": "game_rules", "path": "res://tests/test_game_rules.gd", "required": true},
	{"name": "loc", "path": "res://tests/test_loc.gd", "required": true},
	{"name": "loop_systems", "path": "res://tests/test_loop_systems.gd", "required": true},
	{"name": "levels", "path": "res://tests/test_levels.gd", "required": true},
	{"name": "terrain_recipe", "path": "res://tests/test_terrain_recipe.gd", "required": true},
	{"name": "map_layout", "path": "res://tests/test_map_layout.gd", "required": true},
	{"name": "night_curve", "path": "res://tests/test_night_curve.gd", "required": true},
	{"name": "build_session", "path": "res://tests/test_build_session.gd", "required": true},
	{"name": "tent", "path": "res://tests/test_tent.gd", "required": true},
]


func _initialize() -> void:
	Loc.lang = "en"   # 断言按英文写；只改内存，不改玩家保存的语言设置
	var assertions_passed := 0
	var suites_passed := 0
	var suites_skipped := 0
	var failures: Array[String] = []

	print("")
	print("=== run_all: T0.6 logic tests ===")
	if not ResourceLoader.exists(TUNING_PATH):
		failures.append("缺少 Tuning 资源：%s" % TUNING_PATH)

	for suite in SUITES:
		var suite_name := str(suite["name"])
		var suite_path := str(suite["path"])
		var required := bool(suite["required"])
		var result := _run_suite(suite_name, suite_path, required)
		assertions_passed += int(result.get("passed", 0))

		if bool(result.get("ok", false)):
			suites_passed += 1
			print(
				"[PASS] " + suite_name + " — "
				+ str(int(result.get("passed", 0))) + " assertion(s)"
			)
			continue

		if bool(result.get("skipped", false)):
			suites_skipped += 1
			print("[SKIP] " + suite_name + " — " + str(result.get("reason", "")))
			continue

		print("[FAIL] " + suite_name)
		var suite_failures: Array = []
		var raw_suite_failures: Variant = result.get("failures", [])
		if raw_suite_failures is Array:
			for failure in raw_suite_failures:
				suite_failures.append(failure)
		if suite_failures.is_empty():
			suite_failures.append("%s: %s" % [suite_name, str(result.get("reason", "未知失败"))])
		for failure in suite_failures:
			var message := str(failure)
			failures.append(message)
			print("  - " + message)

	print("")
	print("=== summary ===")
	print("suites: %d passed, %d skipped, %d failed" % [
		suites_passed, suites_skipped, SUITES.size() - suites_passed - suites_skipped
	])
	print("assertions passed: %d" % assertions_passed)
	print("failures: %d" % failures.size())

	if failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return

	print("RESULT: FAIL")
	for failure in failures:
		print("FAIL: " + failure)
	quit(1)


func _run_suite(suite_name: String, suite_path: String, required: bool) -> Dictionary:
	if not ResourceLoader.exists(suite_path):
		if required:
			return _failure_result(suite_name, "必需的测试文件不存在：%s" % suite_path)
		return _skip_result("可选测试文件不存在（Track B 未完成）：%s" % suite_path)

	var resource: Resource = load(suite_path)
	if resource == null:
		return _failure_result(suite_name, "无法加载测试脚本：%s" % suite_path)
	var script := resource as GDScript
	if script == null:
		return _failure_result(suite_name, "测试文件不是 GDScript：%s" % suite_path)

	var base_type := str(script.get_instance_base_type())
	if base_type == "SceneTree" or base_type == "MainLoop":
		return _run_scenetree_suite(suite_name, suite_path)

	return _run_refcounted_suite(suite_name, script, required)


func _run_refcounted_suite(suite_name: String, script: GDScript, required: bool) -> Dictionary:
	var runner: Object = script.new()
	if runner == null:
		return _failure_result(suite_name, "实例化测试脚本失败")

	var method := ""
	for candidate in ["run", "run_all", "run_tests", "execute"]:
		if runner.has_method(candidate):
			method = candidate
			break
	if method.is_empty():
		if required:
			return _failure_result(suite_name, "测试脚本缺少 run() 入口")
		return _skip_result("测试脚本存在但没有 run() 入口（可选跳过）")

	var result: Variant = runner.call(method)
	return _normalize_result(suite_name, result)


func _normalize_result(suite_name: String, result: Variant) -> Dictionary:
	if result is Dictionary:
		var dict_failures: Array[String] = []
		var raw_failures: Variant = result.get("failures", [])
		if raw_failures is Array:
			for failure in raw_failures:
				dict_failures.append(str(failure))
		elif raw_failures is PackedStringArray:
			for failure in raw_failures:
				dict_failures.append(str(failure))
		elif raw_failures != null:
			dict_failures.append("failures 字段类型不支持：%s" % str(typeof(raw_failures)))

		var passed := int(result.get("passed", 0))
		return {
			"ok": dict_failures.is_empty(),
			"skipped": false,
			"passed": passed,
			"failures": dict_failures,
			"reason": "" if dict_failures.is_empty() else (
				"%d assertion(s) failed" % dict_failures.size()
			),
		}

	if result is bool:
		if bool(result):
			return {"ok": true, "skipped": false, "passed": 1, "failures": [], "reason": ""}
		return _failure_result(suite_name, "run() 返回 false")

	if result is Array:
		var array_failures: Array[String] = []
		for failure in result:
			array_failures.append(str(failure))
		if array_failures.is_empty():
			return {"ok": true, "skipped": false, "passed": 1, "failures": [], "reason": ""}
		return {
			"ok": false, "skipped": false, "passed": 0,
			"failures": array_failures, "reason": "%d failure(s)" % array_failures.size(),
		}

	if result is PackedStringArray:
		var packed_failures: Array[String] = []
		for failure in result:
			packed_failures.append(str(failure))
		if packed_failures.is_empty():
			return {"ok": true, "skipped": false, "passed": 1, "failures": [], "reason": ""}
		return {
			"ok": false, "skipped": false, "passed": 0,
			"failures": packed_failures, "reason": "%d failure(s)" % packed_failures.size(),
		}

	return _failure_result(
		suite_name,
		"run() 返回值不受支持（需要 Dictionary / bool / Array）"
	)


func _run_scenetree_suite(suite_name: String, suite_path: String) -> Dictionary:
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	if executable.is_empty() or project_path.is_empty():
		return _failure_result(suite_name, "无法定位 Godot 可执行文件或工程目录")

	var arguments := PackedStringArray([
		"--headless",
		"--path",
		project_path,
		"-s",
		suite_path,
	])
	var output: Array = []
	var exit_code := OS.execute(executable, arguments, output, true)
	for line in output:
		print("  [%s] %s" % [suite_name, str(line)])

	if exit_code == 0:
		return {"ok": true, "skipped": false, "passed": 1, "failures": [], "reason": ""}
	return _failure_result(suite_name, "子进程退出码 %d" % exit_code)


func _failure_result(suite_name: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"skipped": false,
		"passed": 0,
		"failures": ["%s: %s" % [suite_name, reason]],
		"reason": reason,
	}


func _skip_result(reason: String) -> Dictionary:
	return {
		"ok": false,
		"skipped": true,
		"passed": 0,
		"failures": [],
		"reason": reason,
	}
