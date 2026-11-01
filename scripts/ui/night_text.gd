class_name NightText
extends RefCounted

## D14 夜晚的文案：醒来原因、可选行动、整夜时间线、报告结局（CORE_GAMEPLAY §10）。只陈述 NightCurve 算出来的事实。

static func clock(bed_minutes: float, minute: float) -> String:
	var m := int(round(bed_minutes + minute)) % 1440
	return "%02d:%02d" % [m / 60, m % 60]

static func event_title(ev: String) -> String:
	match ev:
		NightCurve.EV_COLD: return Loc.t("You wake up cold")
		NightCurve.EV_CRITICAL: return Loc.t("You wake up shivering violently")
		NightCurve.EV_FIRE_DYING: return Loc.t("The fire is burning down")
		NightCurve.EV_WET_FEET: return Loc.t("Your feet are freezing")
		NightCurve.EV_NO_VENT: return Loc.t("A pounding headache")
		NightCurve.EV_VENT_CLOGGED: return Loc.t("Headache: the vent is blocked")
		NightCurve.EV_SNOW_LOAD: return Loc.t("The roof sags under new snow")
	return ev

static func event_body(ev: String, warmth: float) -> String:
	match ev:
		NightCurve.EV_COLD: return Loc.t("Body warmth %d. The cold woke you — do something, or try to sleep on.") % int(warmth)
		NightCurve.EV_CRITICAL: return Loc.t("Body warmth %d. You will not survive the night lying still. Get up and move, now.") % int(warmth)
		NightCurve.EV_FIRE_DYING: return Loc.t("Only embers left. Without more wood the cold comes back within the hour.")
		NightCurve.EV_WET_FEET: return Loc.t("You went to bed in wet socks. Wet layers hold almost no heat.")
		NightCurve.EV_NO_VENT: return Loc.t("The air is stale — there is no vent. Make one, or don't wake up again.")
		NightCurve.EV_VENT_CLOGGED: return Loc.t("New snow has buried the vent. The air is getting thick.")
		NightCurve.EV_SNOW_LOAD: return Loc.t("Snow is piling on the boughs above you. If it caves in, the cold gets in.")
	return ""

static func action_label(a: String, n: NightCurve, t: Tuning) -> String:
	match a:
		NightCurve.ACT_ADD_WOOD: return Loc.t("Add wood to the fire (%d logs left)") % n.stock_logs
		NightCurve.ACT_EXERCISE: return Loc.t("Get up and move (+%d warmth, costs sleep)") % int(t.night_exercise_warmth)
		NightCurve.ACT_CLEAR_VENT: return Loc.t("Poke the vent clear")
		NightCurve.ACT_KNOCK_SNOW: return Loc.t("Knock the snow off the roof")
		NightCurve.ACT_DRY_SOCKS: return Loc.t("Dry your socks and boots by the fire")
		NightCurve.ACT_SLEEP: return Loc.t("Go back to sleep  [Enter]")
	return a

static func action_done(a: String) -> String:
	match a:
		NightCurve.ACT_ADD_WOOD: return Loc.t("added wood")
		NightCurve.ACT_EXERCISE: return Loc.t("got up and moved")
		NightCurve.ACT_CLEAR_VENT: return Loc.t("cleared the vent")
		NightCurve.ACT_KNOCK_SNOW: return Loc.t("knocked the snow off")
		NightCurve.ACT_DRY_SOCKS: return Loc.t("dried socks and boots")
	return ""

static func event_short(ev: String) -> String:
	match ev:
		NightCurve.EV_COLD: return Loc.t("woke cold")
		NightCurve.EV_CRITICAL: return Loc.t("woke shivering")
		NightCurve.EV_FIRE_DYING: return Loc.t("fire burning down")
		NightCurve.EV_WET_FEET: return Loc.t("cold wet feet")
		NightCurve.EV_NO_VENT: return Loc.t("stale air, no vent")
		NightCurve.EV_VENT_CLOGGED: return Loc.t("vent blocked")
		NightCurve.EV_SNOW_LOAD: return Loc.t("snow on the roof")
	return ev

## "21:40 火要灭了 → 添柴 · 02:10 冻醒（38）→ 起来活动"
static func timeline(res: Dictionary, bed_minutes: float) -> String:
	var parts: Array[String] = []
	var cur := ""
	for e in res["timeline"]:
		if e["kind"] == "event":
			if cur != "":
				parts.append(cur)
			cur = "%s %s (%d)" % [clock(bed_minutes, float(e["minute"])), event_short(String(e["id"])), int(e["warmth"])]
		elif e["kind"] == "action" and action_done(String(e["id"])) != "":
			cur += " → " + action_done(String(e["id"]))
	if cur != "":
		parts.append(cur)
	if parts.is_empty():
		return Loc.t("Your night: you slept through until dawn.")
	return Loc.t("Your night: ") + "  ·  ".join(parts)

static func title(res: Dictionary, wet: bool) -> String:
	match String(res["outcome"]):
		"SAFE": return Loc.t("SURVIVED COZY")
		"COLD": return Loc.t("SURVIVED, COLD")
	if String(res["cause"]) == "suffocated":
		return Loc.t("SUFFOCATED")
	return Loc.t("SOAKED THROUGH") if wet else Loc.t("SEVERE HYPOTHERMIA")

static func conclusion(res: Dictionary, weakest: String) -> String:
	var lo := int(res["min_warmth"])
	var w := int(res["wakes"])
	match String(res["outcome"]):
		"SAFE": return Loc.t("You slept through and walked out at dawn. Lowest body warmth %d.") % lo
		"COLD": return Loc.t("You made it to dawn, but it was a hard night: lowest body warmth %d, woke %d times. Biggest heat leak: %s.") % [lo, w, weakest]
	if String(res["cause"]) == "suffocated":
		return Loc.t("The air ran out in a shelter with no vent. You woke with the warning and went back to sleep.")
	return Loc.t("Your body warmth fell to %d — severe hypothermia. Biggest heat leak: %s.") % [lo, weakest]

## "三样只受一样"（[OB]）：同时承受了冷 / 睡地面 / 湿中的两样以上。
static func three_comforts(input: Dictionary, res: Dictionary, t: Tuning) -> String:
	var bad: Array[String] = []
	if float(res["protection"]) < 0.6:
		bad.append(Loc.t("the cold"))
	if float(input.get("bedding_quality", 0.0)) < 0.5:
		bad.append(Loc.t("the bare ground"))
	if NightSimulator.wet_fraction(float(input.get("dampness", 0.0)), t) > 0.5:
		bad.append(Loc.t("wet clothes"))
	if bad.size() < 2:
		return ""
	return Loc.t("You took on %s at the same time. \"Cold, the ground, or hunger — only one of those at a time.\"") % " + ".join(bad)

static func boots_line(res: Dictionary) -> String:
	return Loc.t("You went to bed with wet boots and no fire to dry them — by morning they were frozen solid.") if bool(res.get("boots_frozen", false)) else ""
