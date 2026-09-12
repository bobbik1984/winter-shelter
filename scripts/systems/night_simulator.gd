class_name NightSimulator
extends RefCounted

static func evaluate_shelter(
	shelter_type: String,
	wind_azimuth_difference: float, # 入口法线与风向夹角 (度)
	has_cold_pit: bool,
	has_vent: bool,
	has_spruce_bedding: bool
) -> Dictionary:
	var outside_temp = -24.0 # 夜间极端低温
	var outside_wind = 45.0 # 夜间强阵风 km/h
	var inside_temp = 0.0
	var is_survived = true
	var status_title = "SURVIVED COZY"
	var failure_reason = ""
	
	# 1. 基础保暖增益 (雪洞结构)
	if shelter_type == "RaisedCave":
		inside_temp = outside_temp + (24.0 if has_cold_pit else 18.0)
	elif shelter_type == "BasicCave":
		inside_temp = outside_temp + 14.0
	elif shelter_type == "SnowTrench":
		inside_temp = outside_temp + 9.0
	else:
		inside_temp = outside_temp + 2.0
	
	# 2. 入口迎风惩罚 (若迎风夹角小于 45 度，冷风直接灌入)
	if abs(wind_azimuth_difference) < 45.0:
		inside_temp -= 12.0
		
	# 3. 松针床垫层 (防止直接吸走体温)
	if has_spruce_bedding:
		inside_temp += 3.0
	else:
		inside_temp -= 8.0
		
	# 4. 氧气通气孔检查 (致命判定)
	var oxygen_status = "Good (Vent Clear)"
	if not has_vent:
		oxygen_status = "Depleted (Suffocated)"
		is_survived = false
		status_title = "SUFFOCATED"
		failure_reason = "Snow cave sealed airtight. Carbon dioxide buildup caused fatal asphyxiation."
	elif inside_temp < -12.0:
		is_survived = false
		status_title = "PERISHED IN FROST"
		failure_reason = "Severe hypothermia. Shelter entrance faced west wind or lacked floor insulation."
	elif inside_temp < -2.0:
		is_survived = true
		status_title = "SURVIVED HYPOTHERMIC"
		failure_reason = "Shivering through the night. Survived, but near edge of frostbite."
	else:
		is_survived = true
		status_title = "SURVIVED COZY"
		failure_reason = "Shelter provided effective insulation and wind barrier. Rested and safe."
		
	return {
		"survived": is_survived,
		"status_title": status_title,
		"outside_temp": outside_temp,
		"outside_wind": outside_wind,
		"inside_temp": inside_temp,
		"oxygen_status": oxygen_status,
		"reason": failure_reason
	}
