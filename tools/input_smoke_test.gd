extends SceneTree
## 真实输入冒烟测试：用 Input 动作 / 按键事件驱动（而不是直接调内部函数），覆盖
## 开始、移动、按住探针、按住采集、B 建造 + Tab + E 放置、按住施工、H 手册、手柄 Start / Esc 暂停、N 睡觉 → 报告、手柄映射。
## 运行：godot --path . -s res://tools/input_smoke_test.gd   （需要窗口 / 显示；退出码非 0 = 失败）

var fails: Array[String] = []

func _initialize() -> void:
	# 第一部分用旧基准（不进关卡模式）；第二部分单独测关卡选择与解锁。记录写到测试文件。
	LevelState.auto_begin = false
	Records.path = "user://test_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	_run()

func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)
	await process_frame

func hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame
	Input.action_release(action)
	await process_frame

func _joy_btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e

func check(c: bool, msg: String) -> void:
	if not c:
		fails.append(msg)
	printerr(("PASS " if c else "FAIL ") + msg)

func _run() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m   # 让 reload_current_scene() 与真实运行一致
	for i in 20: await process_frame
	var d = m.get_node("GameDirector")
	var p = m.player
	check(d.state == d.State.BRIEFING, "starts on briefing")
	await key(KEY_ENTER)
	check(d.state == d.State.PLAYING, "Enter starts the game")
	check(int(d.weather.current_time_minutes) == d.tuning.start_minutes, "standard mode starts at 14:20")
	# 移动
	var p0: Vector3 = p.global_position
	await hold("move_up", 1.0)
	check(p.global_position.distance_to(p0) > 1.0, "W moves the player (%.2f m)" % p.global_position.distance_to(p0))
	# 按住探针
	var probes_before: int = d._probe_count
	await hold("probe", 1.2)
	check(d._probe_count == probes_before + 1, "holding Space probes once")
	# 采集：站到最近的干草 / 立枯木旁按住 E
	var target: Interactable = null
	for n in get_nodes_in_group("interactables"):
		if n.kind == "deadwood" and n.uses_left != 0:
			target = n
			break
	p.global_position = target.global_position + Vector3(0.8, 0.5, 0.0)
	for i in 10: await physics_frame
	check(d.interaction.current == target, "nearest interactable is selected")
	var wood0: int = d.inventory.wood
	await hold("interact", 1.8)
	check(d.inventory.wood > wood0, "holding E harvests deadwood")
	# 建造：B → Tab → E
	d.inventory.add("bedding", 4); d.inventory.add("wood", 4); d.inventory.add("bark", 2)
	p.global_position = Vector3(19.0, TerrainHeight.height_at(19, 8) + 0.5, 8.0)
	p.visual_node.rotation.y = atan2(1.0, 0.0)
	for i in 5: await physics_frame
	await key(KEY_B)
	check(d.build.active, "B enters build mode")
	var pre: String = d.build.preset_id
	await key(KEY_TAB)
	check(d.build.preset_id != pre, "Tab cycles shelter type")
	d.build.preset_id = "SnowTrench"
	await process_frame
	Input.action_press("interact")
	await process_frame
	await process_frame
	Input.action_release("interact")
	await process_frame
	check(d.site != null, "E places the site (%s)" % d.build.reason)
	# 施工：站在工地按住 E
	if d.site:
		p.global_position = d.site.interactable.global_position + Vector3(0.3, 0.5, 0.3)
		for i in 5: await physics_frame
		await hold("interact", d.tuning.stage_hold_seconds + 0.6)
		check(d.site.stage() >= 1, "holding E at the site advances a stage")
	# 生火：轻点 F 不生火；按住 F 才尝试（成功或因风 / 树冠消耗桦树皮）
	p.global_position = Vector3(10.0, TerrainHeight.height_at(10, 2) + 0.5, 2.0)
	for i in 5: await physics_frame
	d.inventory.add("wood", 4); d.inventory.add("bark", 2)
	var bark0: int = d.inventory.bark
	var fires0 := get_nodes_in_group("campfires").size()
	await key(KEY_F)
	for i in 5: await process_frame
	check(d.inventory.bark == bark0 and get_nodes_in_group("campfires").size() == fires0, "tapping F does not light a fire")
	var fe := InputEventKey.new()
	fe.keycode = KEY_F
	fe.physical_keycode = KEY_F
	fe.pressed = true
	Input.parse_input_event(fe)   # 走 Input 单例（与真实按键一致），is_key_pressed 才能读到
	var ft := Time.get_ticks_msec()
	while Time.get_ticks_msec() - ft < int((d.tuning.fire_hold_seconds + 0.6) * 1000.0):
		await process_frame
	var fu := fe.duplicate()
	fu.pressed = false
	Input.parse_input_event(fu)
	await process_frame
	check(d.inventory.bark < bark0 or get_nodes_in_group("campfires").size() > fires0, "holding F attempts a fire (lit or bark spent)")
	# 按住辅助：F9 打开后，轻点 Space 一次即完成探针
	await key(KEY_F9)
	check(HoldAssist.enabled, "F9 turns hold assist on")
	var pc0: int = d._probe_count
	var sp := InputEventAction.new()
	sp.action = "probe"
	sp.pressed = true
	Input.parse_input_event(sp)
	await process_frame
	var spu := sp.duplicate()
	spu.pressed = false
	Input.parse_input_event(spu)
	var pt := Time.get_ticks_msec()
	while Time.get_ticks_msec() - pt < int((d.tuning.probe_seconds + 0.5) * 1000.0):
		await process_frame
	check(d._probe_count == pc0 + 1, "with hold assist a single tap completes a probe")
	await key(KEY_F9)
	check(not HoldAssist.enabled, "F9 turns hold assist off")
	# 手册 / 暂停
	await key(KEY_H)
	check(d.ui._guide != null and d.ui._guide.visible, "H opens the field guide")
	await key(KEY_H)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_START
	jb.pressed = true
	root.push_input(jb)
	await process_frame
	check(d.state == d.State.PAUSED, "gamepad Start pauses")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(d.state == d.State.PAUSED, "Esc pauses")
	await key(KEY_ESCAPE)
	check(d.state == d.State.PLAYING, "Esc resumes")
	# 睡觉：N 两次
	await key(KEY_N)
	await key(KEY_N)
	check(d.state == d.State.NIGHT_FADE, "N twice goes to night")
	var t0 := Time.get_ticks_msec()
	while d.state != d.State.REPORT and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
	check(d.state == d.State.REPORT, "night ends in the report")
	# 手柄：报告页按 Start = 重开（这里只验证映射，不真的重开）
	check(d._joy_to_key(JOY_BUTTON_START) == KEY_R, "gamepad Start maps to retry on the report")
	check(InputMap.action_has_event("interact", _joy_btn(JOY_BUTTON_A)), "gamepad A is bound to interact")
	# R 重开：应回到新一局的简报页
	await key(KEY_R)
	for i in 30: await process_frame
	var m2 = current_scene
	var d2 = m2.get_node_or_null("GameDirector") if m2 else null
	check(m2 != m and d2 != null and d2.state == d2.State.BRIEFING, "R on the report restarts at a fresh briefing")
	await _levels_part()
	check(levels_done, "level selection section ran to the end (a script error would stop it early)")
	printerr("RESULT ", "PASS" if fails.is_empty() else "FAIL %d" % fails.size())
	quit(0 if fails.is_empty() else 1)


var levels_done := false

## 等场景重载完成。用实例 id 比较：旧场景对象此时已被释放。
func _scene_after_reload(prev_id: int) -> Node:
	for i in 60:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != prev_id and current_scene.is_inside_tree():
			break
	for i in 20: await process_frame
	return current_scene

## D12 / D13：章节 × 阶选择、解锁、换图、重玩（真实按键）。存档是测试文件，开始时只有第 1 章第 1 阶。
func _levels_part() -> void:
	LevelState.begin(1, -1, 1, 0)
	var prev_id := current_scene.get_instance_id()
	reload_current_scene()
	var m = await _scene_after_reload(prev_id)
	var d = m.get_node("GameDirector")
	check(d.state == d.State.BRIEFING and LevelState.level.index == 1 and LevelState.stage == 1, "chapter mode boots on chapter 1, stage 1")
	var lesson: Label = m.find_child("LevelLesson", true, false)
	check(lesson != null and lesson.text == LevelState.level.lesson, "briefing shows the chapter lesson")
	check(m.find_child("LevelChip_1", true, false) != null and m.find_child("StageChip_10", true, false) != null, "briefing shows the chapter row and the stage row")
	var sh_label: Label = m.find_child("LevelShelters", true, false)
	check(sh_label != null and sh_label.text.contains("Trench") and sh_label.text.contains("New here"), "briefing lists known shelters and what is new here")
	check(int(d.weather.current_time_minutes) == 600, "chapter 1 stage 1 starts at 10:00")
	check(d.inventory.bark == 2 and d.gear["pad"] == true, "chapter 1 starts with its gear: 2 birch bark and a sleeping pad")
	await key(KEY_RIGHT)
	await key(KEY_UP)
	for i in 10: await process_frame
	check(current_scene == m and LevelState.level.index == 1 and LevelState.stage == 1, "→ and ↑ do nothing while only chapter 1 stage 1 is open")
	Records.record_stage_result(1, 1, "COLD")
	var id1 := m.get_instance_id()
	await key(KEY_UP)
	m = await _scene_after_reload(id1)
	d = m.get_node("GameDirector")
	check(LevelState.level.index == 1 and LevelState.stage == 2 and d.state == d.State.BRIEFING, "after stage 1, ↑ goes to stage 2 (fresh briefing)")
	check(Records.last_selection() == Vector2i(1, 2), "the chosen chapter / stage is remembered")
	var seed_a := LevelState.game_seed
	var id2 := m.get_instance_id()
	await key(KEY_N)
	m = await _scene_after_reload(id2)
	d = m.get_node("GameDirector")
	check(LevelState.stage == 2 and LevelState.map_index == 1 and LevelState.game_seed != seed_a, "[N] on the briefing gives a new map for the same stage")
	await key(KEY_2)
	check(d.state == d.State.BRIEFING and not d.full_day, "[2] full day is free-mode only")
	var id3 := m.get_instance_id()
	await key(KEY_DOWN)
	m = await _scene_after_reload(id3)
	d = m.get_node("GameDirector")
	check(LevelState.stage == 1, "↓ goes back to stage 1")
	Records.record_stage_result(1, 5, "COLD")   # 第 5 阶开下一章
	var id4 := m.get_instance_id()
	await key(KEY_RIGHT)
	m = await _scene_after_reload(id4)
	d = m.get_node("GameDirector")
	check(LevelState.level.index == 2 and LevelState.stage == 1, "passing stage 5 opens chapter 2; → goes there")
	await key(KEY_ENTER)
	check(d.state == d.State.PLAYING and int(d.weather.current_time_minutes) == d.tuning.start_minutes, "chapter 2 stage 1 starts at 14:20")
	await key(KEY_B)
	var seen := {}
	for i in 6:
		seen[d.build.preset_id] = true
		await key(KEY_TAB)
	check(not seen.has("LeanTo") and not seen.has("BasicCave") and seen.has("RaisedCave") and seen.has("SnowTrench"), "chapter 2 build mode only offers known + introduced shelters (%s)" % str(seen.keys()))
	await key(KEY_B)
	await key(KEY_N)
	await key(KEY_N)
	var t0 := Time.get_ticks_msec()
	while d.state != d.State.REPORT and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
	check(d.state == d.State.REPORT, "the night ends in the report")
	check(not Records.stage_unlocked(2, 2), "sleeping in the open (DANGEROUS) does not open stage 2")
	await key(KEY_ENTER)
	for i in 10: await process_frame
	check(current_scene == m and d.state == d.State.REPORT, "[Enter] on the report does nothing while the next stage is locked")
	var seed_b := LevelState.game_seed
	var id5 := m.get_instance_id()
	await key(KEY_R)
	m = await _scene_after_reload(id5)
	d = m.get_node("GameDirector")
	check(LevelState.game_seed == seed_b and LevelState.level.index == 2 and LevelState.stage == 1 and d.state == d.State.BRIEFING, "[R] retries the same place (same seed)")
	await key(KEY_ENTER)
	await key(KEY_N)
	await key(KEY_N)
	t0 = Time.get_ticks_msec()
	while d.state != d.State.REPORT and Time.get_ticks_msec() - t0 < 12000:
		await process_frame
	d._unlock_after_report(2, "COLD")   # 冒烟测试打不出 COLD：直接走解锁分支
	check(Records.stage_unlocked(2, 2), "COLD on chapter 2 stage 1 opens stage 2")
	var id6 := m.get_instance_id()
	await key(KEY_ENTER)
	m = await _scene_after_reload(id6)
	d = m.get_node("GameDirector")
	check(LevelState.level.index == 2 and LevelState.stage == 2 and d.state == d.State.BRIEFING, "[Enter] on the report goes to the next stage")
	check(d._joy_to_key(JOY_BUTTON_RIGHT_SHOULDER) == KEY_RIGHT and d._joy_to_key(JOY_BUTTON_LEFT_SHOULDER) == KEY_LEFT
		and d._joy_to_key(JOY_BUTTON_DPAD_UP) == KEY_UP and d._joy_to_key(JOY_BUTTON_Y) == KEY_N, "gamepad: LB/RB chapter, d-pad stage, Y new map on the briefing")
	levels_done = true
