extends SceneTree
## Controlled scene setup, real input for selection, waking, movement, refuelling and harvesting.
var failures: Array[String] = []
var d
var scene
func _initialize() -> void:
	LevelState.auto_begin = false
	Records.path = "user://night_recovery_review.cfg"
	SessionLog.disabled = true
	Loc.lang = "zh"
	LevelState.begin(1, -1, 1, 0)
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int) -> void:
	for i in count: await process_frame
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://snapshots/night_recovery_20261116_" + label + ".png")
func leave_bed() -> void:
	var was_inside: bool = d._in_shelter
	if not d.night.waiting(): await key(KEY_W)
	var actions: PackedStringArray = d.night.available_actions()
	check(NightCurve.ACT_GET_UP in actions, "get out of bed is available at night")
	await key(int(KEY_1) + actions.find(NightCurve.ACT_GET_UP))
	if was_inside:
		await create_timer(0.7).timeout
	check(d.state == d.State.PLAYING and d.player.controls_enabled, "wake action restores world control")
	check(not d._in_shelter, "getting up leaves the interior view and restores world movement")
func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(40)
	d = scene.get_node("GameDirector")
	Records.record_stage_result(1, 1, "COLD")
	Records.record_stage_result(1, 5, "COLD")
	var identity: int = scene.get_instance_id()
	var start := Time.get_ticks_usec()
	await key(KEY_UP)
	await key(KEY_RIGHT)
	await key(KEY_N)
	check(current_scene.get_instance_id() == identity and d.state == d.State.BRIEFING, "stage/chapter/map arrows keep the same world instance")
	print("SELECTION total ms ", float(Time.get_ticks_usec() - start) / 1000.0)
	check(d._selection_pending and int(d.weather.day_start_minutes) == int(LevelState.roll.start_minutes), "preview shows selected level weather and defers the world rebuild")
	var title: Label = scene.find_child("LevelTitle", true, false)
	check(title != null and title.text == String(d._level_info().title), "visible briefing title immediately matches the selected chapter and stage")
	var meta: Label = scene.find_child("LevelMeta", true, false)
	check(meta != null and meta.text.begins_with(Loc.t("Map %d  ·  [N] new map") % (LevelState.map_index + 1)), "visible map number follows new-map selection")
	await shot("selection")
	await key(KEY_ENTER)
	check(d.state == d.State.LOADING and scene.find_child("MapLoading", true, false) != null, "Start displays loading feedback before rebuilding")
	for i in 120:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != identity: break
	await frames(35)
	scene = current_scene
	d = scene.get_node("GameDirector")
	check(scene.get_instance_id() != identity and d.state == d.State.PLAYING and not LevelState.start_on_load, "Start rebuilds once and starts selected chapter")
	d.weather.time_scale = 0.0
	d.weather.current_time_minutes = float(d.tuning.night_minutes) + d.tuning.forced_sleep_grace_minutes + 1.0
	d.weather.advance_minutes(0.0)
	d._last_minutes = d.weather.current_time_minutes
	d._tick_playing(0.0)
	check(d.state == d.State.PLAYING, "nightfall does not force sleep")
	var site := ShelterSite.new()
	site.setup("BasicCave", Vector3(0, 0, 1), 2.4, 0.0, false)
	site.position = d.player.global_position + Vector3(6, 0, 0)
	scene.add_child(site)
	d.site = site
	for i in 5: site.advance()
	check(d.night_input().shelter_type == "None", "a distant completed shelter does not protect an outdoor sleeper")
	d._sleep(false)
	d._begin_night()
	check(d._night_input.shelter_type == "None", "outdoor sleep uses the real sleeping position")
	await leave_bed()
	d.weather.time_scale = 0.0
	d._tick_playing(0.0)
	check(d.state == d.State.PLAYING, "getting up after darkness does not immediately force sleep again")
	var position_before: Vector3 = d.player.global_position
	Input.action_press("move_right")
	await create_timer(0.6).timeout
	Input.action_release("move_right")
	check(d.player.global_position.distance_to(position_before) > 0.2, "movement input works after getting up at night")
	d.player.global_position = site.global_position + Vector3(0, 1, 0.5)
	await frames(8)
	d.inventory.wood = 4
	d.dampness = 0.0
	d.warmth.set_body_warmth(90.0)
	site.entrance_dir = -d.wind.get_wind_direction_3d()
	var fire: Campfire = site.fire
	if fire == null:
		fire = Campfire.new()
		scene.add_child(fire)
	fire.global_position = site.global_position + site.entrance_dir * 3.0
	fire.ignite(80.0)
	var distant := Campfire.new()
	distant.position = site.global_position + Vector3(18, 0, 0)
	scene.add_child(distant)
	distant.ignite(140.0)
	d._enter_shelter()
	await create_timer(0.7).timeout
	check(d._in_shelter and not d.player.controls_enabled, "entered the real shelter interior before sleeping")
	d._sleep(false)
	d._begin_night()
	print("FUEL stock=", d.night.stock_logs, " minutes=", d.night.fire_minutes, " source=", d._night_fire, " blocked=", d.night.fire_blocked)
	check(d.night.stock_logs == 4 and is_equal_approx(d.night.fire_minutes, 80.0), "sleep does not consume spare wood or add free fuel")
	check(not (NightCurve.ACT_ADD_WOOD in d.night.available_actions()), "closed cave does not offer feeding the outside fire through the wall")
	d.night.play(30.0)
	d.weather.current_time_minutes = d._bed_minutes + d.night.minute
	d._sync_night_fire()
	check(is_equal_approx(fire.fuel_minutes, 50.0) and is_equal_approx(distant.fuel_minutes, 110.0), "near and distant fires burn their own fuel instead of mirroring each other")
	if not d.night.waiting(): d.night.wake_now()
	d._show_night_event(d.night.pending_event())
	await frames(3)
	await shot("cave_wake_zh")
	check(NightText.fire_note(d.night).contains("挡风墙"), "cave wake panel explains the fire is outside and not a wind barrier")
	var origin: float = d._bed_minutes
	var minimum: float = d.night.min_warmth
	var sleep_minutes: float = d.night.asleep_minutes
	await leave_bed()
	d.weather.time_scale = 0.0
	d.player.global_position = fire.global_position + Vector3(0, 1, 0.2)
	await frames(6)
	var stock: int = d.inventory.wood
	var fuel: float = fire.fuel_minutes
	await key(KEY_F)
	check(d.inventory.wood == stock - 1 and fire.fuel_minutes > fuel, "world Fire input spends a real log at the outdoor fire")
	var wood
	for item in get_nodes_in_group("interactables"):
		if item.kind == "deadwood":
			wood = item
			break
	if wood != null:
		d.player.global_position = wood.global_position + Vector3(0, 1, 0.8)
		await frames(8)
		stock = d.inventory.wood
		var clock: float = d.weather.current_time_minutes
		Input.action_press("interact")
		await create_timer(float(wood.hold_seconds) + 0.6).timeout
		Input.action_release("interact")
		await frames(3)
		check(d.inventory.wood > stock and d.weather.current_time_minutes > clock, "night gathering gains wood and spends world time")
	else:
		check(false, "map contains harvestable dry wood")
	check(d._awake_min <= minimum, "outside actions preserve or reduce the night's lowest warmth")
	d.player.global_position = site.global_position + Vector3(0, 1, 0.5)
	await frames(8)
	d._sleep(false)
	d._begin_night()
	check(d._bed_minutes == origin and d.night.minute > 30.0 and d.night.asleep_minutes == sleep_minutes, "returning to bed retains origin, elapsed time and sleep history")
	check(d.night.min_warmth <= minimum, "returning to bed does not erase the lowest warmth")
	await leave_bed()
	d.weather.time_scale = 0.0
	d.weather.current_time_minutes = d._dawn_minutes()
	d.weather.advance_minutes(0.0)
	d._tick_playing(0.0)
	check(d.state == d.State.REPORT and not d.player.controls_enabled, "being awake at dawn ends the same night with a report")
	check(d._night_input.shelter_type == "BasicCave", "dawn report retains the last actual sleeping shelter after getting up")
	await shot("report")
	print("FPS ", Engine.get_frames_per_second(), " GPU ms ", RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	print("RESULT ", "PASS" if failures.is_empty() else "FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
