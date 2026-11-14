extends SceneTree
## 可见窗口试玩：移动、采集、探雪、建造与夜间均使用输入，不传送、不补料。
var d
var p
var rejected := {}
func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Records.path = "user://review_walkthrough.cfg"
	Loc.lang = "zh"
	_run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
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
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000: await process_frame
	Input.action_release(action)
	await frames(2)
func stop() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
func walk(to: Vector3) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 45000:
		var delta: Vector3 = to - p.global_position
		delta.y = 0
		if delta.length() < 1.3:
			stop()
			await frames(3)
			return true
		var direction := delta.normalized()
		# 操作器用碰撞射线选择绕树方向，只改变按键，不改变角色位置。
		var best_dir := direction
		var score := -INF
		for angle in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0]:
			var candidate := direction.rotated(Vector3.UP, deg_to_rad(angle))
			var clear := true
			for side in [-0.3, 0.0, 0.3]:
				var origin: Vector3 = p.global_position + Vector3.UP * 0.8 + candidate.cross(Vector3.UP) * side
				var query := PhysicsRayQueryParameters3D.create(origin, origin + candidate * 2.2)
				query.exclude = [p.get_rid()]
				if not p.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): clear = false
			var value := candidate.dot(direction) if clear else -10.0
			if value > score:
				score = value
				best_dir = candidate
		var local := best_dir.rotated(Vector3.UP, -p._camera_yaw())
		stop()
		Input.action_press("move_right" if local.x > 0 else "move_left", absf(local.x))
		Input.action_press("move_down" if local.z > 0 else "move_up", absf(local.z))
		await physics_frame
	stop()
	return false
func nearest(kinds: Array):
	var best = null
	var dist := INF
	for n in get_nodes_in_group("interactables"):
		if n.kind in kinds and n.uses_left != 0 and n.current_prompt() != "" and not rejected.has(n.get_instance_id()):
			var dd: float = n.global_position.distance_to(p.global_position)
			if dd < dist:
				dist = dd
				best = n
	return best
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://snapshots/walkthrough_20261114_" + label + ".png")
func fail(msg: String) -> void:
	printerr("PLAY BLOCKED ", msg)
	quit(1)
func _run() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await frames(45)
	d = m.get_node("GameDirector")
	p = m.player
	await key(KEY_2) # 自由模式全天开局，保证能观察完整过程。
	await key(KEY_ENTER)
	print("PLAY start ", d.weather.clock_string())
	await shot("start_zh")
	for item in ["wood", "bedding"]:
		var target := 1 if item == "wood" else 4
		for attempt in 12:
			if d.inventory.count(item) >= target: break
			var it = nearest(["deadwood"] if item == "wood" else ["grass", "bough"])
			if it == null:
				fail("没有可达的资源点 " + item)
				return
			if not await walk(it.global_position):
				rejected[it.get_instance_id()] = true
				print("PLAY detour to another ", item)
				continue
			await hold("interact", 2.0)
		print("PLAY gathered ",item,"=",d.inventory.count(item)," clock=",d.weather.clock_string())
	var spot: Vector3 = p.global_position
	var best := INF
	for x in range(-38,39,2):
		for z in range(-38,39,2):
			if SnowField.snow_at(x,z) >= 1.6 and SnowField.slope_at(x,z) >= 9.0 and SnowField.slope_at(x,z) < 25:
				var q := Vector3(x,TerrainHeight.height_at(x,z),z)
				var dd: float = q.distance_to(p.global_position)
				if dd < best:
					best = dd
					spot = q
	if not await walk(spot):
		fail("通往雪洞工地的路线被挡")
		return
	await hold("probe",1.3)
	await key(KEY_B)
	for i in 12:
		if d.build.preset_id == "BasicCave": break
		await key(KEY_TAB)
	await frames(3)
	# 预览点在角色前方，站位的坡度不等于预览点的坡度；根据屏幕校验逐步挪位。
	for adjust in 32:
		if d.build.valid: break
		await hold(["move_up", "move_right", "move_down", "move_left"][int(adjust / 8) % 4], 0.35)
		await frames(3)
	print("PLAY site valid=",d.build.valid," reason=",d.build.reason)
	await hold("interact",0.3)
	if d.site == null:
		await shot("site_blocked")
		fail("工地不适合：" + d.build.reason)
		return
	for i in 5: await hold("interact",3.0)
	print("PLAY build stage=", d.site.stage()," clock=",d.weather.clock_string())
	await shot("built_zh")
	await key(KEY_B)
	await key(KEY_N)
	await key(KEY_N)
	var start := Time.get_ticks_msec()
	while d.state != d.State.REPORT and Time.get_ticks_msec()-start < 180000:
		if d.state == d.State.NIGHT and d.night.waiting():
			if NightCurve.ACT_CLEAR_VENT in d.night.available_actions(): await key(KEY_1)
			await key(KEY_ENTER)
		await process_frame
	await shot("report_zh")
	await key(KEY_L)
	await frames(3)
	await shot("report_en")
	print("PLAY end state=",d.state," FPS=",Engine.get_frames_per_second())
	quit(0 if d.state == d.State.REPORT else 1)
