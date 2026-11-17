extends SceneTree
## Visible input/UI review of the three core stages and optional legacy challenges.
var d
var scene
var failures: Array[String] = []
func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Records.path = "user://compact_chapter_review.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	LevelState.begin(1, -1, 1, 0)
	Loc.lang = "en"
	_run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
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
	root.get_texture().get_image().save_png("res://snapshots/compact_chapter_" + label + ".png")
func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(45)
	d = scene.get_node("GameDirector")
	var identity: int = scene.get_instance_id()
	check(scene.find_child("StageChip_3", true, false) != null and scene.find_child("StageChip_4", true, false) == null, "fresh first chapter has only three main chips")
	check(LevelState.lesson().begins_with("1.") and LevelState.target_presets() == PackedStringArray(["BasicCave"]), "first lesson focuses on basic snow caves")
	await shot("stage1_en")
	Records.record_stage_result(1, 1, "SAFE")
	await key(KEY_UP)
	check(LevelState.stage == 2 and d.weather.day_start_minutes == 600 and LevelState.target_presets() == PackedStringArray(["RaisedCave"]), "stage two introduces raised caves in the same gentle conditions")
	Loc.lang = "zh"
	d._preview_selection()
	await frames(3)
	var lesson: Label = scene.find_child("LevelLesson", true, false)
	check(lesson != null and lesson.text.contains("把床抬高"), "second lesson is localized")
	await shot("stage2_zh")
	Records.record_stage_result(1, 2, "SAFE")
	await key(KEY_UP)
	check(LevelState.stage == 3 and d.weather.day_start_minutes == 780 and not Records.stage_unlocked(2, 1), "stage three is the afternoon overnight-preparation lesson")
	await shot("stage3_zh")
	Records.record_stage_result(1, 3, "COLD")
	check(Records.stage_unlocked(2, 1) and d._next_stage() == Vector2i(2, 1), "third core stage opens chapter two and Next skips optional challenges")
	await key(KEY_UP)
	check(LevelState.stage == 4 and LevelState.is_optional() and String(d._level_info().title).contains("可选挑战"), "up from completed main stages enters explicitly optional challenges")
	check(scene.find_child("StageChip_7", true, false) != null and LevelState.global_stage() == 0, "seven legacy challenge IDs remain separate from main progress")
	await shot("optional_zh")
	await key(KEY_DOWN)
	check(LevelState.stage == 3 and not LevelState.is_optional() and scene.find_child("StageChip_4", true, false) == null, "down returns to the three-stage main row")
	await key(KEY_RIGHT)
	check(LevelState.level.index == 2 and LevelState.main_stage_count(2) == 10 and current_scene.get_instance_id() == identity, "chapter two remains available and selection still does not regenerate the world")
	print("FPS ", Engine.get_frames_per_second(), " GPU ms ", RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	print("RESULT ", "PASS" if failures.is_empty() else "FAIL %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
