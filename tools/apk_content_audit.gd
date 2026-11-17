extends SceneTree
## Runs against a ZIP/PCK made from the APK's exported assets, from an empty directory.
func _initialize() -> void:
	var failures: Array[String] = []
	var tuning = load("res://resources/tuning.tres")
	if tuning == null or tuning.mobile_play_fps != 30 or tuning.mobile_menu_fps != 15 or tuning.mobile_shadow_size != 1024:
		failures.append("mobile tuning missing/stale")
	for locale in ["en", "zh"]:
		var translation = load("res://localization/messages.%s.translation" % locale)
		if translation == null or translation.get_message_list().size() < 690:
			failures.append("translation missing: " + locale)
		elif locale == "zh" and translation.get_message("BODY WARMTH") != "保暖值":
			failures.append("Chinese translation stale")
	for path in ["res://assets/fonts/DroidSansFallbackFull.ttf", "res://assets/fonts/DejaVuSans.ttf", "res://scripts/systems/graphics_settings.gd", "res://scripts/systems/game_director.gd"]:
		if load(path) == null: failures.append("missing resource: " + path)
	if int(ProjectSettings.get_setting("application/run/max_fps.mobile", 0)) != 30:
		failures.append("startup frame cap missing")
	var chapter = load("res://resources/levels/level_01.tres")
	if chapter == null or chapter.main_stages.size() != 3:
		failures.append("three-stage chapter missing/stale")
	elif chapter.main_stages[1].target_presets != PackedStringArray(["RaisedCave"]) or chapter.main_stages[2].start_minutes != 780:
		failures.append("tutorial stage resources stale")
	print("APK build marker: ", FileAccess.get_file_as_string("res://build_info.txt").strip_edges())
	for failure in failures: printerr(failure)
	print("APK CONTENT ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
