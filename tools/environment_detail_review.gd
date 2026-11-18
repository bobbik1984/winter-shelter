extends SceneTree
## Fixed world/camera comparison. Isolates player records; does not save graphics settings.
var d
var out := OS.get_cache_dir().path_join("winter-environment-review")
var results: Array = []
var started := 0
func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Records.path = "user://test_environment_review.cfg"
	Loc.lang = "zh"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	_run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	started = Time.get_ticks_msec()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	d = scene.get_node("GameDirector")
	print("DETAIL load_to_ready_ms=", Time.get_ticks_msec() - started)
	await frames(45)
	d.graphics.level = 0 if "--low" in OS.get_cmdline_user_args() else 1
	d.graphics.apply()
	d.start_game()
	d.weather.time_scale = 0.0
	d.weather.current_time_minutes = 860.0
	await frames(30)
	await sample("world")
	var forest = get_first_node_in_group("forest")
	var facts := {"trees": Array(forest.spruce_points), "snags": Array(forest.snag_points), "rocks": forest.rock_spheres}
	var detail_preview := Node3D.new()
	var detail_started := Time.get_ticks_msec()
	EnvironmentDetails.build(detail_preview, forest.rock_spheres, forest.spruce_points)
	print("DETAIL ground_generation_ms=", Time.get_ticks_msec() - detail_started)
	for child in detail_preview.get_children():
		child.material_override = null
		child.mesh = null
	detail_preview.free()
	var r: Vector3 = forest.rock_spheres[0]
	d.rig.set_focus(Vector3(r.x, TerrainHeight.height_at(r.x, r.y), r.y), 0.65)
	await sample("rocks")
	var site := ShelterSite.new()
	site.position = d.player.global_position + Vector3(3, 0, -3)
	site.setup("RaisedCave", Vector3(1, 0, 1).normalized(), 2.5, 22.0, true)
	scene.add_child(site)
	site.builder.current_stage = 5
	site._refresh()
	d.rig.set_focus(site.global_position, 0.65)
	await sample("shelter")
	for proxy in site._visual.find_children("*glow*", "MeshInstance3D", true, false):
		assert(not proxy.visible, "emissive door proxy must stay hidden")
	assert(site._entrance_light != null and site._entrance_light.light_energy <= EnvironmentDetails.settings().entrance_night_energy)

	# Additional detail shots, excluded from the same-camera before/after measurements.
	var toward: Vector3 = d.rig.camera_offset(0.5)
	toward.y = 0
	site.entrance_dir = toward.normalized()
	site.rotation.y = atan2(toward.x, toward.z)
	site._refresh()
	d.rig.set_focus(site.global_position, 0.5)
	await create_timer(2.0).timeout
	await shot("entrance")
	d.weather.weather_kind = "overcast"
	d.weather._apply_sun()
	d.rig.clear_focus()
	await create_timer(2.0).timeout
	await shot("overcast")
	d.weather.current_time_minutes = 1380.0
	d.weather._apply_sun()
	d.rig.set_focus(site.global_position, 0.65)
	await create_timer(2.0).timeout
	await shot("night")
	var f := FileAccess.open(out.path_join("review.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"measurements": results, "gameplay_positions": facts}, "\t"))
	f.close()
	print("RESULT PASS")
	scene.queue_free()
	await frames(3)
	quit()
func sample(label: String) -> void:
	await create_timer(1.5).timeout
	var start := Time.get_ticks_usec()
	var before := Engine.get_process_frames()
	await create_timer(4.0).timeout
	var seconds := (Time.get_ticks_usec() - start) / 1000000.0
	var m := {"view": label, "fps": (Engine.get_process_frames() - before) / seconds,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"render_scale": root.scaling_3d_scale}
	results.append(m)
	print("DETAIL ", JSON.stringify(m))
	await shot(label)
func shot(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(label + ".png"))
