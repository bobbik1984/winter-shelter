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
	# 缺垫层：标出最近一处，并说明是什么、在哪；够了就撤掉
	await wait(0.2)
	check(d._bedding_short() > 0 and d.callouts.has_callout("bedding"), "short of bedding: nearest one is labelled")
	check(d._bedding_hint().contains("spruce boughs"), "the hint says what bedding is")
	var near_it = d._nearest_bedding()
	var near_d: float = near_it.global_position.distance_to(p.global_position)
	var closer := 0
	for n in get_nodes_in_group("interactables"):
		if n.kind in ["grass", "bough"] and n.uses_left != 0 and n.global_position.distance_to(p.global_position) < near_d:
			closer += 1
	check(closer == 0, "label points at the nearest bedding")
	check(not Loc.t("Hold [E]  ").contains("[E]"), "the Use prompt has no keyboard letter on a phone")
	# 走近：先有名字和采法，走进圈里后提示贴在东西旁边
	var ng: Vector3 = near_it.global_position
	p.global_position = Vector3(ng.x + 6.0, TerrainHeight.height_at(ng.x + 6.0, ng.z) + 0.3, ng.z)
	await wait(0.2)
	check(d.callouts.has_callout("near_item"), "walking near a collectable names it")
	p.global_position = Vector3(ng.x + 1.5, TerrainHeight.height_at(ng.x + 1.5, ng.z) + 0.3, ng.z)
	await wait(0.2)
	if d.interaction.current != null:
		var item_px: Vector2 = root.get_camera_3d().unproject_position(d.interaction.current.global_position)
		var card: Rect2 = d.ui._prompt_card.get_global_rect()
		check(d.ui._prompt_card.visible and card.grow(220.0).has_point(item_px), "the prompt sits next to the thing it's about")
	# 火：放在人没挡住的地方，卡片说明怎么添柴，火有可见的光晕
	# 找一块附近没有别的可交互物的地方（否则离得更近的东西会被选中，这是正常规则）
	var clear := Vector3.INF
	for x in range(-36, 37, 3):
		for z in range(-36, 37, 3):
			var q := Vector3(x, TerrainHeight.height_at(x, z), z)
			var free_spot := true
			for n in get_nodes_in_group("interactables"):
				if n.global_position.distance_to(q) < 8.0:
					free_spot = false
					break
			if free_spot:
				clear = q
				break
		if clear != Vector3.INF:
			break
	check(clear != Vector3.INF, "found a clear spot for the fire test")
	p.global_position = clear + Vector3.UP * 0.3
	for i in 3: await physics_frame
	var cf := Campfire.new()
	cf.position = p.global_position + Vector3(3.0, 0, 0)   # 3 m：在取暖圈里，比旧的添柴距离 2.6 m 远
	cf.warm_radius = d.tuning.fire_warm_radius_m
	d.main.add_child(cf)
	cf.ignite(50.0)
	d._attach_fire_interactable(cf)
	d.inventory.add("wood", 2)
	await wait(0.2)
	check(cf._glow.visible and d.callouts.has_callout("fire_status"), "a lit fire glows and has a status card")
	check(cf._circle.visible and is_equal_approx(cf.warm_radius, d.tuning.fire_warm_radius_m), "the circle on the snow is the real warmth range")
	check(d.interaction.current != null and d.interaction.current.kind == "fire", "everything at the fire works from inside the circle")
	check(not d.interaction._ring.visible, "no small selection ring around the fire")
	var fire_label := ""
	for b in d._touch._buttons:
		if b["id"] == "fire": fire_label = b["label"]
	check(fire_label == Loc.t("Add log"), "Fire button becomes Add log")
	await tap("fire")
	await wait(0.2)
	check(cf.fuel_minutes > 50.0, "Fire button adds a log (%.0f min)" % cf.fuel_minutes)
	cf.queue_free()
	await wait(0.1)
	check(d.interaction.current == null or is_instance_valid(d.interaction.current), "a freed target is dropped cleanly")
	d.inventory.add("bedding", d._bedding_short())
	await wait(0.2)
	check(d._bedding_short() <= 0 and not d.callouts.has_callout("bedding"), "enough bedding: label goes away")
	# 进入庇护所：完工后走到门口，按住 Use 进去，里面只有走出去 / 睡觉，走出去一切恢复
	var guard := 0
	while not d.site.is_complete() and guard < 8:
		d.site.advance()
		guard += 1
	d.inventory.wood = 0
	d.inventory.bedding = 0
	var door: Vector3 = d.site.entrance_point() + d.site.entrance_dir * 1.0
	p.global_position = Vector3(door.x, TerrainHeight.height_at(door.x, door.z) + 0.3, door.z)
	await wait(0.3)
	check(d.interaction.prompt_text() == Loc.t("Enter the shelter"), "a finished shelter offers Enter the shelter (%s)" % d.interaction.prompt_text())
	await hold("use", d.site.interactable.hold_seconds + 0.5)
	await wait(0.7)
	check(d._in_shelter and root.get_camera_3d() != d.rig.camera_3d, "holding Use goes inside, with the section camera (hold %.1f s)" % d.site.interactable.hold_seconds)
	check(d._inside_site() and p.visual_node.visible and not p.controls_enabled, "the figure is in the shelter, visible in the section, and can't walk")
	check(d.callouts.has_callout("section_0"), "the section has labels")
	check(has_btn("out") and has_btn("sleep") and not has_btn("build") and not has_btn("fire"), "inside: Step outside and Sleep, no Build or Fire")
	await shot("07b_inside")
	await tap("out")
	await wait(0.7)
	check(not d._in_shelter and root.get_camera_3d() == d.rig.camera_3d, "Step outside returns to the normal camera")
	check(p.controls_enabled and d.interaction.enabled and is_zero_approx(p.visual_node.rotation.x) and not d.callouts.has_callout("section_0"), "and the figure stands and walks again, labels gone")
	check(not d._inside_site(), "standing outside the shelter again")
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
