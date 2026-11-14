extends SceneTree
## Same fixed scene and camera; measures frame submission and process CPU, not phone thermals.
var d
func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Loc.lang = "zh"
	_run.call_deferred()
func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	d = scene.get_node("GameDirector")
	await create_timer(3.0).timeout
	d.graphics.level = 0
	d.graphics.apply()
	d.start_game()
	d.weather.time_scale = 0.0
	await sample("world")
	if GraphicsSettings.mobile_profile():
		var time_before: float = d.weather.current_time_minutes
		var mute_before := AudioServer.is_bus_mute(0)
		d.graphics.set_background(true)
		await create_timer(0.25, true).timeout
		assert(paused and Engine.max_fps == d.tuning.mobile_background_fps)
		assert(d.weather.current_time_minutes == time_before and AudioServer.is_bus_mute(0))
		d.graphics.set_background(false)
		assert(not paused and AudioServer.is_bus_mute(0) == mute_before)
		assert(Engine.max_fps == d.tuning.mobile_play_fps)
		assert(Engine.physics_ticks_per_second == 60)
		print("POWER lifecycle pause/resume PASS; physics stays 60 Hz")
	d._set_paused(true)
	await sample("pause")
	d._set_paused(false)
	# The report is opaque; verify that hidden world rendering is suspended.
	d._night_input = d.night_input()
	d._show_report()
	await sample("report")
	if GraphicsSettings.mobile_profile():
		assert(root.disable_3d and Engine.max_fps == d.tuning.mobile_menu_fps)
		d.graphics.set_scene_mode("playing")
		assert(not root.disable_3d and Engine.max_fps == d.tuning.mobile_play_fps)
	print("RESULT PASS")
	quit()
func sample(label: String) -> void:
	await create_timer(2.0).timeout
	var start := Time.get_ticks_usec()
	var before := Engine.get_process_frames()
	var cpu_before := cpu_ticks()
	await create_timer(8.0).timeout
	var seconds := float(Time.get_ticks_usec() - start) / 1000000.0
	var fps := float(Engine.get_process_frames() - before) / seconds
	print("PERF %s fps=%.1f cpu_ticks_per_s=%.1f cap=%d draw_calls=%d triangles=%d scale=%.3f disable_3d=%s" % [label, fps, float(cpu_ticks()-cpu_before)/seconds, Engine.max_fps, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), root.scaling_3d_scale, root.disable_3d])
	if label == "world":
		await RenderingServer.frame_post_draw
		var tag := "mobile" if "--mobile-profile" in OS.get_cmdline_user_args() else "baseline"
		root.get_texture().get_image().save_png("res://snapshots/power_20261115_"+tag+".png")
func cpu_ticks() -> int:
	if not FileAccess.file_exists("/proc/self/stat"): return 0
	var fields := FileAccess.open("/proc/self/stat", FileAccess.READ).get_line().split(") ", true, 1)[1].split(" ")
	return int(fields[11]) + int(fields[12])
