extends SceneTree
func _initialize() -> void:
	var t := load("res://resources/tuning.tres") as Tuning
	for sh in ["BasicCave", "LeanTo", "Tent"]:
		var inp := {"shelter_type": sh, "completion_ratio": 1.0, "snow_depth_meters": 2.0, "roof_thickness_meters": 0.45, "bedding_quality": 1.0, "tent_bag": true, "vent_count": 1, "has_vent": true, "starting_warmth": 90.0, "wind_angle_diff": 180.0, "terrain_shelter": 0.6, "night_temp_c": -24.0, "night_hours": 14.0, "fire_lit": true, "fire_exposure": 0.0, "firewood_logs": 8.0, "has_reflector_wall": sh == "LeanTo", "wind_speed_kmh": 32.0}
		var n := NightCurve.new(inp,t)
		var res := NightCurve.run(inp,t,"smart")
		var adds := 0
		for e in res.timeline:
			if e.id == "add_wood": adds += 1
		print("AUDIT ", sh, " min/log=",n.log_minutes," add_actions=",adds," outcome=",res.outcome," min_warmth=",res.min_warmth)
	quit()
