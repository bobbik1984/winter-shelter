extends SceneTree
func _initialize() -> void:
	Loc.lang = "en"
	var result: Dictionary = load("res://tests/test_loc.gd").new().run()
	print("CATALOG ", Loc.catalog().size(), " entries; checks ", result.passed)
	for failure in result.failures: printerr(failure)
	quit(0 if result.failures.is_empty() else 1)
