class_name NightReportText
extends RefCounted

## 把 NightSimulator 的结算（分数 + details + 输入事实）写成玩家可读的英文报告（T2.8 / T3.7）。
## NightSimulator 的 notes 是中文开发者归因（测试依赖），这里是展示层，只用同一批事实，不改规则。

const AXES := [
	["site", "Site & wind"], ["structure", "Structure"], ["insulation", "Insulation"],
	["isolation", "Cold-air isolation"], ["air", "Air"], ["heat", "Heat"],
]

const LESSONS := {
	"site": "Face the entrance away from the wind — the trees lean downwind and the compass needle shows where the wind goes.",
	"structure": "Start digging earlier. When the shadows grow long, you have less than an hour of light.",
	"insulation": "Gather bedding: dry grass and low spruce boughs keep the snow from stealing your heat.",
	"isolation": "Cold air sinks. In a snow cave, dig a cold-air pit and sleep on a raised platform.",
	"air": "Always pierce a vent in a snow shelter. Stale air kills quietly.",
	"heat": "Probe several spots — deeper snow means thicker walls. Warm up by a fire and drink something hot before you crawl in.",
}

static func build(report: Dictionary, input: Dictionary, t: Tuning) -> Dictionary:
	var scores: Dictionary = report.get("scores", {})
	var d: Dictionary = report.get("details", {})
	var zh_notes: Array = report.get("notes", [])
	var preset := String(input.get("shelter_type", "None"))
	var rows: Array = []
	var idx := 0
	for a in AXES:
		var key: String = a[0]
		# 中文模式：直接使用 NightSimulator 自带的中文归因（同一批事实）
		var note := String(zh_notes[idx]) if Loc.is_zh() and idx < zh_notes.size() else _note(key, preset, input, d, t, scores)
		rows.append({"key": key, "label": Loc.t(a[1]), "score": int(round(float(scores.get(key, 0.0)))), "note": note})
		idx += 1
	var outcome := String(report.get("outcome", "DANGEROUS"))
	var raw_title := String(report.get("outcome_title", outcome))
	var title := raw_title.split(" (")[0]
	if Loc.is_zh() and raw_title.contains("(") :
		title = raw_title.get_slice("(", 1).trim_suffix(")")
	var min_axis := String(d.get("min_axis", "heat"))
	var conclusion := ""
	match outcome:
		"SAFE": conclusion = Loc.t("You slept through the night and walked out at dawn. Weakest point: %s.") % _label(min_axis)
		"COLD": conclusion = Loc.t("You made it to dawn, shivering. Weakest point: %s.") % _label(min_axis)
		_: conclusion = Loc.t("You would not have survived this night. Main cause: %s.") % _label(min_axis)
	var lesson: String = Loc.t(LESSONS.get(min_axis, ""))
	if preset == "LeanTo":
		if min_axis == "isolation":
			lesson = Loc.t("An open lean-to can't trap cold air. Pile bedding thick and keep the reflector fire fed — or find deeper snow for a cave.")
		elif min_axis == "heat":
			lesson = Loc.t("The night is %.0f hours long. At %.0f h per log, a lean-to fire needs about %d logs of dry wood stockpiled.") % [
				t.night_duration_hours, t.fire_fuel_hours_per_log, int(ceil(t.night_duration_hours / t.fire_fuel_hours_per_log))]
	elif min_axis == "air" and bool(input.get("vent_snow_clogged", false)):
		lesson = Loc.t("When snow is falling, leave a stick in the vent and poke it clear — or dig a second vent.")
	elif preset == "None":
		lesson = Loc.t("Without any shelter the wind takes your heat all night. Even a half-finished trench is better than nothing.")
	return {"title": title, "outcome": outcome, "rows": rows, "conclusion": conclusion, "lesson": lesson}

static func _label(key: String) -> String:
	for a in AXES:
		if a[0] == key:
			return Loc.t(String(a[1]))
	return key

static func _note(key: String, preset: String, i: Dictionary, d: Dictionary, t: Tuning, report_scores: Dictionary = {}) -> String:
	var is_snow := preset in ["RaisedCave", "BasicCave", "SnowTrench"]
	var lean := preset == "LeanTo"
	var none := not (is_snow or lean)
	var angle := float(i.get("wind_angle_diff", 90.0))
	var completion := float(i.get("completion_ratio", 0.0))
	match key:
		"site":
			if none:
				return "No shelter — exposed to the %d km/h wind all night." % int(float(i.get("wind_speed_kmh", t.wind_speed_kmh)))
			if angle < 60.0:
				return "The entrance faced into the wind (%d°): drafts and drifting snow all night." % int(angle)
			if angle < 120.0:
				return "The entrance was side-on to the wind (%d°); gusts cut in now and then." % int(angle)
			return "The entrance was leeward (%d°); the wind passed over you." % int(angle)
		"structure":
			if none:
				return "Nothing was built."
			if bool(d.get("invalid_snow_depth", false)):
				return "The snow here (%.1f m) was too shallow for this shelter." % float(i.get("snow_depth_meters", 0.0))
			if completion < 0.999:
				return "Only %d%% finished — it wasn't closed up before night." % int(completion * 100.0)
			if is_snow:
				return "Roof %.2f m thick over %.1f m of snow — it held." % [float(i.get("roof_thickness_meters", 0.0)), float(i.get("snow_depth_meters", 0.0))]
			return "Frame, thatch and reflector wall all finished."
		"insulation":
			var b := float(i.get("bedding_quality", 0.0))
			if b < 0.2:
				return "No bedding: you lay on the snow and it drew the heat out of you."
			if b >= 0.8:
				return "Thick bough and grass bedding cut you off from the snow."
			return "Thin bedding — the cold crept up by morning."
		"isolation":
			if lean:
				return "An open shelter can't trap cold air; bedding and fire had to make up for it."
			if none:
				return "You slept in the coldest air, right on the ground."
			var pit := bool(i.get("has_cold_pit", false))
			var bed := bool(i.get("has_raised_bed", false))
			if pit and bed:
				return "The cold-air pit and raised platform kept you above the coldest air."
			if pit:
				return "A cold-air pit, but the bed wasn't raised — cold air still reached you."
			return "Your bed was level with the entrance, where the cold air pools."
		"air":
			if not is_snow:
				return "Open air — no stale-air risk, but no trapped heat either."
			if int(i.get("vent_count", 0)) <= 0:
				return "No vent: CO₂ and moisture built up inside. Dangerous."
			if bool(i.get("vent_snow_clogged", false)):
				return "New snow partly blocked the vent; you woke with a headache."
			return "The vent kept the air fresh."
		"heat":
			var s := ""
			if is_snow:
				var depth := float(i.get("snow_depth_meters", 0.0))
				var heat_score := float(report_scores.get("heat", 100.0))
				s = "Body heat and %.1f m of snow kept you warm; no fire inside — correct." % depth
				if heat_score < t.safe_min_axis and depth < t.snow_depth_raised_cave_min_m + 0.4:
					s = "Only %.1f m of snow: thin walls let the heat leak out. Deeper snow (2.4 m+) means a warmer night." % depth
				if bool(i.get("prewarmed", false)):
					s += " A fire and hot water before bed helped."
				elif heat_score < t.safe_min_axis:
					s += " A fire and a hot drink before bed would have helped."
			elif lean:
				if not bool(i.get("fire_lit", false)):
					s = "No fire in an open lean-to: a long, bitter night."
				elif bool(d.get("fire_reaches_dawn", false)):
					s = "The reflector fire burned until dawn (%.0f h of wood)." % float(d.get("fuel_hours", 0.0))
				else:
					s = "The wood ran out around %s; the rest of the night was bitter." % String(d.get("fire_out_clock", "midnight"))
			else:
				s = "Nothing kept your heat in."
			var w := float(i.get("starting_warmth", 100.0))
			if w < t.warmth_tier_warm:
				s += " You went to bed already chilled (%d/100)." % int(w)
			return s
	return ""
