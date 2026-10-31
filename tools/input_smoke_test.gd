extends SceneTree
## 真实输入冒烟测试：用 Input 动作 / 按键事件驱动（而不是直接调内部函数），覆盖
## 开始、移动、按住探针、按住采集、B 建造 + Tab + E 放置、按住施工、F 生火、H 手册、Esc 暂停、N 睡觉 → 报告。
## 运行：godot --path . -s res://tools/input_smoke_test.gd   （需要窗口 / 显示；退出码非 0 = 失败）

var fails: Array[String] = []

func _initialize() -> void:
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

func check(c: bool, msg: String) -> void:
	if not c:
		fails.append(msg)
	printerr(("PASS " if c else "FAIL ") + msg)

func _run() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	for i in 20: await process_frame
	var d = m.get_node("GameDirector")
	var p = m.player
	check(d.state == d.State.BRIEFING, "starts on briefing")
	await key(KEY_ENTER)
	check(d.state == d.State.PLAYING, "Enter starts the game")
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
	# 手册 / 暂停
	await key(KEY_H)
	check(d.ui._guide != null and d.ui._guide.visible, "H opens the field guide")
	await key(KEY_H)
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
	printerr("RESULT ", "PASS" if fails.is_empty() else "FAIL %d" % fails.size())
	quit(0 if fails.is_empty() else 1)
