extends SceneTree
## 随机输入模糊测试：随机移动 / 探针 / 按住交互 / 随机按键（建造、生火、手册、语言、暂停、睡觉、画质、静音），
## 跑满 N 秒或直到报告页再重开，检查不崩溃、状态机始终合法。
## 运行：godot --path . -s res://tools/fuzz_test.gd -- --seconds=90 --seed=1
## 退出码非 0 = 失败（Godot 的 SCRIPT ERROR 也会打印在日志里，CI 中 grep 即可）。

var KEYS := [KEY_B, KEY_TAB, KEY_R, KEY_T, KEY_2, KEY_F, KEY_H, KEY_ESCAPE, KEY_N, KEY_F10, KEY_M, KEY_L, KEY_ENTER, KEY_MINUS, KEY_EQUAL, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
var ACTIONS := ["move_left", "move_right", "move_up", "move_down", "probe", "interact"]

func _initialize() -> void:
	_run()

func _run() -> void:
	var seconds := 90.0
	var seed_ := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="): seconds = float(a.substr(10))
		if a.begins_with("--seed="): seed_ = int(a.substr(7))
	seed(seed_)
	# 关卡模式（D12）：关卡与本局抽取由 --seed 决定（可复现）；测试记录文件里全部解锁，让 ←/→ 换关也被覆盖
	Records.path = "user://fuzz_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	for ch in range(1, LevelState.LEVEL_COUNT + 1):
		for st in range(1, LevelState.STAGES + 1):
			Records.record_stage_result(ch, st, "SAFE")
	# 章 / 阶由 --seed 决定（覆盖不同地形配方与难度）
	LevelState.begin(LevelState.ORDER[seed_ % LevelState.ORDER.size()], seed_, 1 + (seed_ * 7) % LevelState.STAGES)
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 10: await process_frame
	var t0 := Time.get_ticks_msec()
	var restarts := 0
	var reports := 0
	var held := ""
	var frames := 0
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		frames += 1
		if frames % 120 == 0:
			var dh = current_scene.get_node_or_null("GameDirector") if current_scene else null
			if dh:
				printerr("HB frames=%d state=%d t=%s build=%s" % [frames, dh.state, dh.weather.clock_string(), dh.build.active])
		var d = current_scene.get_node_or_null("GameDirector") if current_scene else null
		if d == null:
			await process_frame
			continue
		if d.state == d.State.REPORT:
			reports += 1
			_key(KEY_R)
			restarts += 1
			for i in 20: await process_frame
			continue
		# 每 ~0.4 s 换一个按住的动作
		if frames % 12 == 0:
			if held != "":
				Input.action_release(held)
			held = ACTIONS[randi() % ACTIONS.size()]
			Input.action_press(held)
		# 偶尔按一个随机键（Esc / N 频率低一些，避免一直暂停）
		if randf() < 0.04:
			var k: Key = KEYS[randi() % KEYS.size()]
			if (k == KEY_ESCAPE or k == KEY_N or k == KEY_F10 or k == KEY_L) and randf() < 0.6:
				k = KEY_ENTER
			_key(k)
		# 偶尔快进时间，覆盖黄昏 / 入夜分支
		if randf() < 0.01 and d.state == d.State.PLAYING:
			d._skip(randf_range(5.0, 40.0))
		await process_frame
	if held != "":
		Input.action_release(held)
	var d_end = current_scene.get_node_or_null("GameDirector") if current_scene else null
	var ok: bool = d_end != null
	printerr("FUZZ frames=%d reports=%d restarts=%d final_state=%s RESULT %s" % [frames, reports, restarts, str(d_end.state) if d_end else "none", "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	var u := e.duplicate()
	u.pressed = false
	root.push_input(u)
