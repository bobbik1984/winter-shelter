extends SceneTree
## 触屏冒烟测试：只用屏幕触摸事件走完一局（开始 → 走路 → 探针 → 放工地 → 施工 → 退后 → 睡觉 → 醒来点选 → 报告 → 再来）。
## 运行：godot --headless --path . -s res://tools/touch_smoke_test.gd -- --touch
## 加 --shots=<目录> 时每一步存截图（需要显示，不能 headless）。

var fails: Array[String] = []
var shots := ""
var d
var m

func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Loc.lang = "en"
	Records.path = "user://test_records_touch.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	GameDirector.night_speed_scale = 20.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	_run.call_deferred()

func check(c: bool, msg: String) -> void:
	if not c:
		fails.append(msg)
	printerr(("PASS " if c else "FAIL ") + msg)

func shot(n: String) -> void:
	if shots == "":
		return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/touch_%s.png" % [shots, n])

func wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame

func _pt(ev, idx: int, pos: Vector2) -> void:
	ev.index = idx
	ev.position = pos
	root.push_input(ev, true)   # 坐标已经是画布坐标

func down(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.pressed = true
	_pt(e, idx, pos)
	await process_frame

func up(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.pressed = false
	_pt(e, idx, pos)
	await process_frame

func drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	_pt(e, idx, pos)
	await process_frame

func rect_of(id: String) -> Rect2:
	var t: TouchControls = d._touch
	for i in t._buttons.size():
		if t._buttons[i]["id"] == id:
			return t._rects[i]
	return Rect2()

func has_btn(id: String) -> bool:
	return rect_of(id).size != Vector2.ZERO

## 点一下：等按钮出现（情境切换后一帧才更新），按下、抬起。
func tap(id: String) -> void:
	for i in 30:
		if has_btn(id): break
		await process_frame
	check(has_btn(id), "button '%s' is on screen" % id)
	var c := rect_of(id).get_center()
	await down(1, c)
	await process_frame
	await up(1, c)
	for i in 3: await process_frame

func hold(id: String, sec: float, idx: int = 1) -> void:
	for i in 30:
		if has_btn(id): break
		await process_frame
	check(has_btn(id), "button '%s' is on screen" % id)
	var c := rect_of(id).get_center()
	await down(idx, c)
	await wait(sec)
	await up(idx, c)
	for i in 3: await process_frame

func _run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 40: await process_frame
	d = m.get_node("GameDirector")
	var p = m.player
	check(TouchMode.enabled and d._touch != null, "touch layer is on with --touch")
	await wait(0.3)
	await shot("01_briefing")
	# 简报
	var ch0 = LevelState.stage
	await tap("intel")
	check(d.ui.intel_open(), "Intel opens by touch")
	await shot("02_intel")
	await tap("next")
	await tap("close")
	check(not d.ui.intel_open(), "Close shuts Intel")
	await tap("begin")
	check(d.state == d.State.PLAYING, "Begin starts the game by touch")
	await wait(1.0)
	await shot("03_playing")
	# 摇杆：多点触控，边走边按探针
	var size: Vector2 = d._touch._canvas.get_rect().size
	var p0: Vector3 = p.global_position
	var origin := Vector2(160, size.y - 150)
	await down(0, origin)
	await drag(0, origin + Vector2(0, -80))
	check(Input.get_action_strength("move_up") > 0.5, "stick pushes move_up")
	await wait(0.8)
	await shot("04_stick")
	check(p.global_position.distance_to(p0) > 0.5, "stick walks the player (%.2f m)" % p.global_position.distance_to(p0))
	await up(0, origin)
	check(Input.get_action_strength("move_up") == 0.0, "lifting the finger stops")
	var probes: int = d._probe_count
	await hold("probe", 1.3)
	check(d._probe_count == probes + 1, "holding Probe probes once")
	# 在深雪上放工地
	var best := Vector3.ZERO
	var bd := -1.0
	for x in range(-30, 31, 3):
		for z in range(-30, 31, 3):
			var s := SnowField.snow_at(x, z)
			if s > bd:
				bd = s
				best = Vector3(x, 0, z)
	p.global_position = Vector3(best.x, TerrainHeight.height_at(best.x, best.z) + 0.5, best.z)
	for i in 5: await physics_frame
	await tap("build")
	check(d.build.active, "Build enters placing")
	await shot("05_placing")
	var preset0 = d.build.preset_id
	await tap("type")
	check(d.build.preset_id != preset0 or d.build.available().size() <= 1 if d.build.has_method("available") else true, "Type cycles shelter")
	d.build.preset_id = "SnowTrench"
	await tap("rotate")
	for i in 3: await process_frame
	await tap("place")
	await wait(0.2)
	if d.site == null:
		printerr("note: placing refused: ", d.build.reason)
		d.build.preset_id = "BasicCave"
		await tap("place")
	check(d.site != null, "Place puts the site down")
	check(d.session.focused(), "close-up starts")
	await wait(1.0)
	await shot("06_focus")
	await tap("back")
	check(not d.session.focused() and d.site != null, "Step back keeps the site")
	await wait(0.5)
	await shot("07_far")
	# 夜：菜单、睡觉、醒来、加速
	await tap("menu")
	check(d.state == d.State.PAUSED, "Menu pauses")
	await shot("08_pause")
	await tap("resume")
	check(d.state == d.State.PLAYING, "Resume returns to play")
	await tap("sleep")
	for i in 5: await process_frame
	if d.state == d.State.PLAYING:
		await tap("sleep")
	check(d.state != d.State.PLAYING, "Sleep goes to bed")
	var t0 := Time.get_ticks_msec()
	while d.state != d.State.NIGHT and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	check(d.state == d.State.NIGHT, "night starts")
	GameDirector.night_speed_scale = 1.0
	await wait(0.3)
	await shot("09_night")
	await down(1, rect_of("speed").get_center())
	await wait(0.3)
	check(Input.is_action_pressed("probe"), "Speed up holds fast-forward")
	await up(1, rect_of("speed").get_center())
	GameDirector.night_speed_scale = 20.0
	var wakes := 0
	var shot_wake := false
	t0 = Time.get_ticks_msec()
	while d.state != d.State.REPORT and Time.get_ticks_msec() - t0 < 40000:
		if d.state == d.State.NIGHT and d.night.waiting():
			if not shot_wake:
				shot_wake = true
				await shot("10_wake")
			var rows := get_nodes_in_group("touch_tap").filter(func(n): return (n as Control).is_visible_in_tree())
			if rows.is_empty():
				check(false, "wake panel has tappable rows")
				break
			var row: Control = rows[rows.size() - 1]
			var c: Vector2 = row.get_global_rect().get_center()
			await down(1, c)
			await up(1, c)
			wakes += 1
			for i in 3: await process_frame
		else:
			await process_frame
	check(wakes > 0, "woke at least once and tapped a choice (%d)" % wakes)
	check(d.state == d.State.REPORT, "reaches the report by touch")
	await wait(0.3)
	await shot("11_report")
	await tap("retry")
	await wait(1.0)
	for i in 30: await process_frame
	var nd = current_scene.get_node("GameDirector")
	check(nd.state == nd.State.BRIEFING or nd.state == nd.State.PLAYING, "Try again restarts")
	if fails.is_empty():
		printerr("RESULT PASS")
		quit(0)
	else:
		printerr("RESULT FAIL: ", fails)
		quit(1)
