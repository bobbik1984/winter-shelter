extends SceneTree
## 真实输入冒烟测试：用 Input 动作 / 按键事件驱动（而不是直接调内部函数），覆盖
## 开始、移动、按住探针、按住采集、B 建造 + Tab + E 放置、按住施工、H 手册、手柄 Start / Esc 暂停、N 睡觉 → 报告、手柄映射。
## 运行：godot --path . -s res://tools/input_smoke_test.gd   （需要窗口 / 显示；退出码非 0 = 失败）

var fails: Array[String] = []

func _initialize() -> void:
	# 第一部分用旧基准（不进关卡模式）；第二部分单独测关卡选择与解锁。记录写到测试文件。
	LevelState.auto_begin = false
	Loc.lang = "en"   # 断言按英文写；只改内存，不改玩家保存的语言设置
	Records.path = "user://test_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	GameDirector.night_speed_scale = 20.0   # D14：夜晚 75 秒 → 约 4 秒
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
	check(not d.hud.get_parent().visible, "briefing hides the world HUD (warmth / weather / compass / world labels)")
	await key(KEY_ENTER)
	check(d.state == d.State.PLAYING, "Enter starts the game")
	check(d.hud.get_parent().visible, "the world HUD comes back when the game starts")
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
	# 第二次评审：在这里探一次雪，再在这里放样——报告必须承认"在挖的地方探过"
	await hold("probe", 1.2)
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
	check(d._site_probed, "probing right before placing the site counts as 'probed where you dug' (report fact consistency)")
	# 施工：站在工地按住 E
	if d.site:
		p.global_position = d.site.interactable.global_position + Vector3(0.3, 0.5, 0.3)
		for i in 5: await physics_frame
		await hold("interact", d.tuning.stage_hold_seconds + 0.6)
		check(d.site.stage() >= 1, "holding E at the site advances a stage")
		for i in 3: await process_frame
		var card: Control = m.find_child("ShelterCard", true, false)
		var card_title: Label = m.find_child("ShelterTitle", true, false)
		check(card != null and card_title.text.contains("/5"), "shelter status is ready for the fixed HUD card (%s)" % (card_title.text if card_title else "none"))
		check(d.callouts.has_callout("my_shelter") and not ("my_shelter" in d.callouts.shown_ids()), "in the world the shelter is only a ring at the entrance, no text card")
		check(d.callouts.shown_ids().size() <= d.callouts.max_cards(), "no more world label cards than the screen allows (%d)" % d.callouts.shown_ids().size())
		await _build_focus_part(m, d, p)
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
	check(d.ui.intel_open() and d.ui.intel_tab_key() == "guide", "H opens the field guide page of the intel panel")
	await key(KEY_TAB)
	check(d.ui.intel_tab_key() == "controls", "Tab turns the page")
	await key(KEY_ESCAPE)
	check(not d.ui.intel_open() and d.state == d.State.PLAYING, "Esc closes the intel panel without pausing")
	await key(KEY_I)
	check(d.ui.intel_open() and d.ui.intel_tab_key() == "brief", "I opens the intel panel on the brief")
	await key(KEY_I)
	check(not d.ui.intel_open(), "I closes it again")
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
	# D14：黑屏后进入可玩的夜晚；第一次醒来按 [1] 做第一个行动，之后都按 Enter 接着睡
	var t0 := Time.get_ticks_msec()
	while d.state != d.State.NIGHT and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	check(d.state == d.State.NIGHT and d.night != null, "after the fade the night plays (state NIGHT)")
	check(m.find_child("NightHud", true, false) != null and m.find_child("NightHud", true, false).visible, "night HUD (clock, warmth curve) is shown")
	var first_event := true
	var acted := false
	t0 = Time.get_ticks_msec()
	while d.state == d.State.NIGHT and Time.get_ticks_msec() - t0 < 40000:
		if d.night.waiting():
			check(m.find_child("NightEvent", true, false) != null, "a wake-up pauses the night and shows the actions panel")
			if first_event:
				first_event = false
				var n_actions: int = d.night.timeline.size()
				await key(KEY_1)
				acted = d.night.timeline.size() > n_actions
			else:
				await key(KEY_ENTER)
		await process_frame
	check(acted, "pressing [1] at a wake-up performs the first action")
	check(d.state == d.State.REPORT, "night ends in the report")
	check(m.find_child("ReportNightGraph", true, false) != null and m.find_child("ReportNightTimeline", true, false) != null, "the report shows the night curve and timeline")
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

## D16 / B1–B3：建造特写、角色不遮工地、材料不足暂停、回来继续（真实按键）。进来时雪沟已完成 1 阶。
func _build_focus_part(m, d, p) -> void:
	check(d.session.focused() and d.rig.is_focusing(), "placing a site enters the build close-up")
	check(not p.controls_enabled, "the close-up locks movement")
	check(d.callouts.cards_hidden, "the close-up hides world labels")
	var panel: Control = m.find_child("BuildFocusPanel", true, false)
	check(panel != null and panel.visible, "the close-up shows the build panel")
	var card: Control = m.find_child("ShelterCard", true, false)
	check(card != null and not card.visible, "the close-up hides the far-view shelter card")
	var dist0: float = d.rig.camera_3d.position.length()
	for i in 90: await process_frame
	check(d.rig.camera_3d.position.length() < dist0 or d.rig._focus_blend >= 1.0, "the camera has pulled in")
	check(is_equal_approx(d.rig.camera_yaw_degrees, d.tuning.tilt_yaw_deg), "the close-up keeps the D8 yaw")
	var zoom0: float = d.rig._zoom
	await key(KEY_V)
	check(d.rig.camera_3d.size < d.rig.camera_size * 0.8, "the close-up also works in the orthographic view (%.1f)" % d.rig.camera_3d.size)
	await key(KEY_V)
	check(is_equal_approx(d.rig._zoom, zoom0), "the player's own zoom setting is left alone")
	# B2：角色站到工地和镜头之间 → 模型淡出，位置与碰撞不变
	var cam_dir: Vector3 = (d.rig.camera_3d.global_position - d.site.global_position)
	cam_dir.y = 0.0
	var stand: Vector3 = d.site.global_position + cam_dir.normalized() * 2.2
	p.global_position = Vector3(stand.x, TerrainHeight.height_at(stand.x, stand.z) + 0.5, stand.z)
	for i in 5: await physics_frame
	var held: Vector3 = p.global_position
	for i in 60: await process_frame
	var fig_d: float = Vector2(p.visual_node.global_position.x - d.site.global_position.x, p.visual_node.global_position.z - d.site.global_position.z).length()
	check(p.visual_node.visible and fig_d >= d.site.footprint_radius(), "the figure stays visible, drawn beside the site (%.1f m away)" % fig_d)
	check(not d.character_blocks_site(), "the figure does not cover the site, even if the player stood in front of it")
	check(Vector2(p.global_position.x - held.x, p.global_position.z - held.z).length() < 0.05 and not p.get_node("CollisionShape3D").disabled, "this changes looks only: real position and collision stay")
	var ep: Vector3 = d.site.entrance_point()
	check(d.callouts.has_callout("my_shelter") and is_equal_approx(d.callouts._entries["my_shelter"]["world"].y, ep.y), "the ring sits at the real opening, on the ground")
	# S7：自己的庇护所下风侧也挡风（开阔地上要能点火烘干）；迎风侧不算
	var bl: Vector3 = d.wind.get_blow_direction_3d()
	var lee_w: float = d.wind_shelter_at(d.site.global_position + bl * 2.6, d.tuning.wind_fire_height_m)
	# 材料不足：不扣料、不推进、面板写明
	d._on_interaction_completed(d.site.interactable, d.site.interactable.trigger())
	check(d.site.stage() == 2, "stage 2 done, the next stage needs bedding")
	var near_fire: Vector3 = d.site.global_position + bl * (d.tuning.shelter_inside_radius_m + 0.5)
	var saved_pos: Vector3 = p.global_position
	p.global_position = d.site.global_position
	var inside_msg := String(d.fire_check_at(near_fire)["reason"])
	var in_msg := String(d.fire_check_at(d.site.global_position)["reason"])
	p.global_position = saved_pos
	check(not inside_msg.contains("inside a snow shelter") and in_msg.contains("inside a snow shelter"), "the no-fire rule checks where the fire goes, not where you stand")
	check(d.wind_shelter_at(d.site.global_position + bl * 2.6, d.tuning.wind_fire_height_m) > lee_w and d.wind_shelter_at(d.site.global_position + bl * 2.6, d.tuning.wind_fire_height_m) > d.wind_shelter_at(d.site.global_position - bl * 2.6, d.tuning.wind_fire_height_m), "your own walls shelter a fire on the downwind side, not the upwind side")
	d.inventory.bedding = 0
	d.site.pile.stock["bedding"] = 0
	var wood0: int = d.site.pile.total("wood", d.inventory)
	await process_frame
	await process_frame
	await hold("interact", d.tuning.stage_hold_seconds + 0.4)
	check(d.site.stage() == 2 and d.site.pile.total("wood", d.inventory) == wood0, "short of materials: no progress and nothing spent")
	var keys: Label = m.find_child("BuildFocusKeys", true, false)
	var needs: Label = m.find_child("BuildFocusNeeds", true, false)
	check(keys.text.contains("Step back") and needs.text.contains("bedding"), "the panel says what is missing and how to step back")
	# 退回远景：工地保留、角色恢复、能走
	var site_ref = d.site
	await key(KEY_B)
	for i in 5: await process_frame
	check(not d.session.focused() and d.session.state == BuildSession.State.PAUSED, "B steps back to the far view")
	check(p.controls_enabled and not d.rig.is_focusing(), "stepping back restores movement and the camera")
	check(d.site == site_ref and d.site.stage() == 2, "the site and its progress stay")
	for i in 40: await process_frame
	check(p.visual_node.visible and p.visual_node.position.distance_to(d._figure_home) < 0.01, "the figure is back at the player")
	check(card.visible and m.find_child("ShelterLine", true, false).text.contains("gather"), "the far-view card shows what is still needed")
	# 同一时间一个工地：走远了按 B 不会新建
	p.global_position = Vector3(stand.x + 15.0, TerrainHeight.height_at(stand.x + 15.0, stand.z) + 0.5, stand.z)
	for i in 5: await physics_frame
	for i in 3: await process_frame
	await key(KEY_B)
	check(not d.build.active and d.site == site_ref and not d.session.focused(), "far from the site, B does not start a second site")
	# 回来按 E 继续：先有材料，再按住施工
	# 背包有上限（B4）：多的装不下，只能跑趟
	d.inventory.bedding = 0
	check(d.inventory.add("bedding", 99) == d.inventory.max_bedding, "the pack only holds so much bedding")
	var back: Vector3 = d.site.interactable.global_position + Vector3(0.3, 0.5, 0.3)
	p.global_position = back
	for i in 5: await physics_frame
	for i in 3: await process_frame
	await hold("interact", d.tuning.stage_hold_seconds + 0.6)
	check(d.session.focused(), "E at the site re-enters the close-up")
	check(d.site.stage() == 3, "and building continues with the gathered materials (%d)" % d.site.stage())
	check(d.inventory.bedding == 0 and d.site.pile.amount("bedding") == d.inventory.max_bedding - d.site.builder.active_preset().stage_costs[2]["bedding"], "what you carried went onto the pile, and the stage used it")
	# Esc 在特写里是退回，不是暂停
	await key(KEY_ESCAPE)
	check(not d.session.focused() and d.state == d.State.PLAYING, "Esc steps back instead of pausing")
	for i in 3: await process_frame
	# 第三次评审：正常逐阶施工——每次按住只进一阶，材料按预设扣，完工后回到远景
	d.site.pile.stock["wood"] = 8
	d.site.pile.stock["bedding"] = 8
	p.global_position = back
	for i in 5: await physics_frame
	for i in 3: await process_frame
	var costs: Array = d.site.builder.active_preset().stage_costs
	for st in [3, 4]:
		var w0: int = d.site.pile.amount("wood")
		var b0: int = d.site.pile.amount("bedding")
		await hold("interact", d.tuning.stage_hold_seconds + 0.3)
		for i in 3: await process_frame
		check(d.site.stage() == st + 1, "one hold = exactly one stage (%d -> %d)" % [st, d.site.stage()])
		check(d.site.pile.amount("wood") == w0 - int(costs[st].get("wood", 0)) and d.site.pile.amount("bedding") == b0 - int(costs[st].get("bedding", 0)), "stage %d spends exactly its cost from the pile" % (st + 1))
	check(d.site.is_complete() and d.session.state == BuildSession.State.COMPLETE, "the last stage finishes the shelter")
	var t0 := Time.get_ticks_msec()
	while d.session.focused() and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	check(not d.session.focused() and p.controls_enabled and not d.rig.is_focusing(), "after completion the camera returns to the player")

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
	var cond: Label = m.find_child("LevelConditions", true, false)
	check(cond != null and cond.text.contains("°C") and cond.text.contains("sunset"), "briefing first screen shows one line of conditions")
	check(m.find_child("LevelShelters", true, false) == null, "gear / shelters are not on the first screen")
	await key(KEY_I)
	check(d.ui.intel_open() and d.ui.intel_tab_key() == "brief", "[I] on the briefing opens the intel panel")
	for i in 3: await key(KEY_RIGHT)
	var body: Label = m.find_child("IntelBody", true, false)
	check(d.ui.intel_tab_key() == "shelters" and body.text.contains("Trench") and body.text.contains("New here"), "intel → Shelters lists known shelters and what is new here")
	check(LevelState.level.index == 1, "→ turns intel pages instead of switching chapter while the panel is open")
	await key(KEY_LEFT)
	check(body.text.contains("snow shovel"), "intel → Kit lists the gear")
	await key(KEY_ESCAPE)
	check(not d.ui.intel_open() and d.state == d.State.BRIEFING, "Esc closes intel, still on the briefing")
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
	check(not seen.has("LeanTo") and not seen.has("BasicCave") and not seen.has("RaisedCave") and seen.has("TreeWell") and seen.has("SnowTrench"), "chapter 2 build mode only offers known (trench) + introduced (tree well) shelters (%s)" % str(seen.keys()))
	await key(KEY_B)
	await key(KEY_N)
	await key(KEY_N)
	await _sleep_through_night(d)
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
	await _sleep_through_night(d)
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


## 夜里每次醒来都按 Enter 接着睡，直到报告页。
func _sleep_through_night(d) -> void:
	var t0 := Time.get_ticks_msec()
	while d.state != d.State.REPORT and Time.get_ticks_msec() - t0 < 40000:
		if d.state == d.State.NIGHT and d.night != null and d.night.waiting():
			await key(KEY_ENTER)
		await process_frame
