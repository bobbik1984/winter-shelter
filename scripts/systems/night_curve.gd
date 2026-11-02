class_name NightCurve
extends RefCounted

## D14 / N1 可玩的夜晚：整夜体温曲线的纯逻辑模型（CORE_GAMEPLAY §10）。
## 用法：var n := NightCurve.new(input, tuning) → 反复 step() 推进；返回事件时游戏暂停，调用方（界面 / 机器人 / 测试）
## 用 available_actions() + act() 处理，再继续 step()；整夜结束后 result()。
## input = 现有 GameDirector.night_input()（与 NightSimulator 同一份事实），另读 night_snowfall（夜间降雪 0..1）。
##
## 关键规则：
##   失温 / 小时 = 基础 × 温度系数 × (1 − 保护度)^γ + 湿衣额外失温；保护度 = 原 6 维（不含空气）的加权平均。
##   火在燃烧期间让失温 × (1 − 火的作用)并回一点体温；入睡时只架了 night_fire_initial_hours 的柴，其余备柴要醒来添。
##   火灭不会自动叫醒人：只有已经冷了或者没火时掉得很快才醒（暖和就接着睡，用户定调 2026-11-02）。
##   A2 红线：W ≤ 极危阈值时一定醒；所以 W 归零之前玩家至少醒过一次、有机会行动。
##   N5：活动回温同一次醒来递减、整夜越累越少（不能靠连按代替庇护所）；行动耗时照算失温与烧火；冻醒不受次数上限限制。

const ACT_ADD_WOOD := "add_wood"
const ACT_EXERCISE := "exercise"
const ACT_CLEAR_VENT := "clear_vent"
const ACT_KNOCK_SNOW := "knock_snow"
const ACT_DRY_SOCKS := "dry_socks"
const ACT_SLEEP := "sleep"

const EV_COLD := "cold"
const EV_CRITICAL := "critical"
const EV_FIRE_DYING := "fire_dying"
const EV_FIRE_OUT := "fire_out"
const EV_WET_FEET := "wet_feet"
const EV_NO_VENT := "no_vent"
const EV_VENT_CLOGGED := "vent_clogged"
const EV_SNOW_LOAD := "snow_load"

var t: Tuning
var input: Dictionary

## 状态
var minute := 0.0                 ## 入睡后经过的游戏分钟
var duration := 0.0               ## 整夜分钟数
var warmth := 100.0               ## 体温 W 0..100
var min_warmth := 100.0
var dampness := 0.0
var fire_minutes := 0.0           ## 火里剩余燃烧分钟
var stock_logs := 0               ## 备柴（根）
var has_fire_place := false       ## 有能整夜烧的火（倒棚反射火 / 露天火），且不会被吹灭
var sleep_quality := 0            ## 每次醒来 / 活动 −1
var wakes := 0                    ## 非极危醒来次数（计入上限）
var critical_wakes := 0
var protection := 0.0             ## 0..1
var base_loss := 0.0              ## W/小时（未计火、湿衣）
var curve: PackedVector2Array = PackedVector2Array()   ## (分钟, W)，每 30 分钟一点
var timeline: Array = []          ## [{minute, kind: "event"/"action", id}]

## 夜间隐患（处理前一直存在）
var vent_none := false
var vent_clogged_pending := false
var vent_clog_due := INF
var vent_none_due := INF
var snow_load_due := INF
var snow_load_active := false
var wet_feet_due := INF
var suffocated := false
var clog_unresolved := false

## 火最后一次熄灭的时刻（入睡后分钟；-1 = 一直烧到天亮）。
var fire_out_at := -1.0
## 一根柴能烧多少分钟（风、雪越大越短）。
var log_minutes := 120.0
## 没有火可添时的原因（给玩家看）："" / "no_fire" / "no_logs" / "wind"。
var fire_blocked := "no_fire"
var _fire_out_reported := false
var _last_wake := -INF
## N5：活动不是无限的热源——同一次醒来连续活动效果递减（_ex_this_wake），整夜活动越多越累（_ex_total）。
var _ex_this_wake := 0
var _ex_total := 0
var _pending_event := ""
var _fire_dying_reported := false
var _is_snow := false
var _shelter := "None"

func _init(p_input: Dictionary, p_t: Tuning) -> void:
	input = p_input
	t = p_t
	duration = t.night_duration_hours * 60.0
	warmth = clampf(float(input.get("starting_warmth", t.warmth_max)), 0.0, t.warmth_max)
	min_warmth = warmth
	dampness = clampf(float(input.get("dampness", 0.0)), 0.0, 1.0)
	_shelter = String(input.get("shelter_type", "None"))
	_is_snow = _shelter in ["RaisedCave", "BasicCave", "SnowTrench", "TreeWell"]
	protection = protection_of(input, t)
	var night_temp := float(input.get("night_temp_c", t.temp_at_night_c))
	var temp_k := maxf(0.2, 1.0 + (t.night_temp_ref_c - night_temp) * t.night_temp_sensitivity)
	base_loss = t.night_base_loss_per_h * temp_k * pow(1.0 - protection, t.night_protection_gamma)
	# 火（所有庇护所同一条规则）：有火堆就留到夜里，柴烧完会灭，有柴就能再点；风和雪决定烧多快、留不留得住。
	# 雪洞内仍不能生火（D3）——火在外面，睡着时对洞里没有作用（_fire_factor = 0）。
	var wind_ratio := float(input.get("wind_speed_kmh", t.night_fire_wind_ref_kmh)) / maxf(t.night_fire_wind_ref_kmh, 0.1)
	var snow_now := clampf(float(input.get("night_snowfall", 0.0)), 0.0, 1.0)
	log_minutes = t.fire_fuel_hours_per_log * 60.0 / (1.0 + t.night_fire_wind_burn * maxf(wind_ratio - 1.0, 0.0) + t.night_fire_snow_burn * snow_now)
	if bool(input.get("fire_lit", false)) or bool(input.get("campfire_near", false)):
		if float(input.get("fire_exposure", 1.0)) * maxf(wind_ratio, 1.0) > t.fire_blowout_dot:
			fire_blocked = "wind"
		else:
			has_fire_place = true
			var logs := int(round(float(input.get("firewood_logs", 0.0))))
			var initial_logs := maxi(1, int(round(t.night_fire_initial_hours / maxf(t.fire_fuel_hours_per_log, 0.1))))
			var burn_now := mini(logs, initial_logs)
			fire_minutes = float(burn_now) * log_minutes + maxf(float(input.get("fire_minutes_left", 0.0)), 0.0)
			stock_logs = logs - burn_now
			fire_blocked = ""
	# 夜间隐患
	var vents := int(input.get("vent_count", 1 if bool(input.get("has_vent", false)) else 0))
	if _is_snow and _shelter != "TreeWell":
		if vents <= 0:
			vent_none = true
			vent_none_due = t.night_no_vent_wake_min
		elif bool(input.get("vent_snow_clogged", false)):
			vent_clogged_pending = true
			vent_clog_due = t.night_clog_wake_min
	var snowfall := float(input.get("night_snowfall", 0.0))
	if snowfall >= t.night_snow_load_snowfall and _shelter in ["SnowTrench", "TreeWell", "LeanTo"]:
		snow_load_due = t.night_snow_load_wake_min
	if NightSimulator.wet_fraction(dampness, t) >= 0.99:
		wet_feet_due = t.night_wet_feet_wake_min
	curve.append(Vector2(0.0, warmth))

## 庇护所保护度 0..1：原 6 维（不含空气）在"没有火、没有暖身、干衣、满体温"下的加权平均——只看庇护所本身。
static func protection_of(p_input: Dictionary, p_t: Tuning) -> float:
	var clean := p_input.duplicate()
	clean["fire_lit"] = false
	clean["fire_held"] = false
	clean["prewarmed"] = false
	clean["dampness"] = 0.0
	clean["starting_warmth"] = p_t.warmth_max
	var rep := NightSimulator.evaluate(clean, p_t)
	var s: Dictionary = rep["scores"]
	var w := {"site": p_t.weight_site, "structure": p_t.weight_structure, "insulation": p_t.weight_insulation,
		"isolation": p_t.weight_isolation, "heat": p_t.weight_heat}
	var sum := 0.0
	var wsum := 0.0
	for k in w:
		sum += float(s.get(k, 0.0)) / 100.0 * float(w[k])
		wsum += float(w[k])
	return clampf(sum / maxf(wsum, 0.001), 0.0, 1.0)

func is_over() -> bool:
	return minute >= duration or (warmth <= 0.0 and minute > 0.0) or suffocated

## 当前每小时净失温（正 = 在掉）。
func loss_per_hour() -> float:
	var loss := base_loss
	if snow_load_active:
		loss *= t.night_snow_load_penalty
	if minute < t.night_prewarm_hours * 60.0 and bool(input.get("prewarmed", false)):
		loss *= t.night_prewarm_factor
	if fire_minutes > 0.0:
		var ff := _fire_factor()
		loss = loss * (1.0 - ff) - ff * t.night_fire_heat_per_h
	loss += NightSimulator.wet_fraction(dampness, t) * t.night_wet_loss_per_h
	return loss

## 火对这个庇护所起多大作用 0..1。
func _fire_factor() -> float:
	match _shelter:
		"RaisedCave", "BasicCave": return 0.0
		"SnowTrench", "TreeWell": return t.night_fire_factor_snow_open
	return t.night_fire_factor_reflector if bool(input.get("has_reflector_wall", false)) else t.night_fire_factor_open

## 没有火时每小时掉多少。
func _fireless_loss() -> float:
	return base_loss + NightSimulator.wet_fraction(dampness, t) * t.night_wet_loss_per_h

## 火灭会不会把人弄醒：已经冷了，或者没火时掉得很快。暖和的时候火灭了也接着睡。
func _fire_bites() -> bool:
	return _fire_factor() > 0.0 and (warmth <= t.night_fire_wake_w or _fireless_loss() >= t.night_fire_wake_loss_per_h)

## 体温变化（火能回温，但不会超过上限）。
func _apply_loss(dt: float) -> void:
	var loss := loss_per_hour()
	var next := warmth - loss * dt / 60.0
	if loss < 0.0:
		next = minf(next, maxf(warmth, t.night_fire_warm_cap))
	warmth = clampf(next, 0.0, t.warmth_max)
	min_warmth = minf(min_warmth, warmth)

## 推进到下一个事件或天亮。返回事件 id（"" = 天亮 / 结束）。
func step() -> String:
	return advance_to(INF)

## 推进到 target 分钟（游戏播放用：每帧推进一点）；途中遇到事件就停下并返回事件 id。
func advance_to(target: float) -> String:
	while not is_over() and minute < target:
		var ev := _advance_one()
		if ev != "":
			_pending_event = ev
			timeline.append({"minute": minute, "kind": "event", "id": ev, "warmth": warmth})
			return ev
	return ""

func pending_event() -> String:
	return _pending_event

## 本次醒来、当前还能不能操作（等玩家选择）。
func waiting() -> bool:
	return _pending_event != ""

func _advance_one() -> String:
	var dt := t.night_step_min
	_apply_loss(dt)
	minute += dt
	if fire_minutes > 0.0:
		fire_minutes = maxf(0.0, fire_minutes - dt)
		if fire_minutes <= 0.0:
			fire_out_at = minute
	if int(minute) % 30 == 0:
		curve.append(Vector2(minute, warmth))
	# 没通风管：到时没处理 → 窒息（之前一定已经闷醒过一次）
	if vent_none and minute >= t.night_no_vent_fatal_min and _woke_for(EV_NO_VENT):
		suffocated = true
		return ""
	if snow_load_due <= minute and not snow_load_active and _woke_for(EV_SNOW_LOAD):
		snow_load_active = true    # 醒过但没顶落 → 结构受损
	if vent_clogged_pending and minute > vent_clog_due + 1.0 and _woke_for(EV_VENT_CLOGGED):
		clog_unresolved = true
	# ---- 事件（A2：极危一定醒，不受间隔与上限限制）
	if warmth <= t.night_wake_critical_w:
		if minute - _last_wake >= 30.0:
			critical_wakes += 1
			_last_wake = minute
			return EV_CRITICAL
		return ""
	if minute - _last_wake < t.night_wake_spacing_min:
		return ""
	# N5：上限只管次要事件；冻醒不受上限限制——否则第 6 次起玩家要一路睡到极危，结局不是他选的
	var ev := ""
	if wakes >= t.night_max_wakes:
		pass
	elif vent_none and minute >= vent_none_due and not _woke_for(EV_NO_VENT):
		ev = EV_NO_VENT
	elif vent_clogged_pending and minute >= vent_clog_due and not _woke_for(EV_VENT_CLOGGED):
		ev = EV_VENT_CLOGGED
	elif snow_load_due <= minute and not _woke_for(EV_SNOW_LOAD):
		ev = EV_SNOW_LOAD
	elif has_fire_place and fire_minutes > 0.0 and fire_minutes <= 30.0 and stock_logs > 0 and not _fire_dying_reported and _fire_bites():
		_fire_dying_reported = true
		ev = EV_FIRE_DYING
	elif has_fire_place and fire_minutes <= 0.0 and stock_logs > 0 and not _fire_out_reported and _fire_bites():
		_fire_out_reported = true
		ev = EV_FIRE_OUT
	elif wet_feet_due <= minute and not _woke_for(EV_WET_FEET):
		ev = EV_WET_FEET
	if ev == "" and warmth <= t.night_wake_cold_w:
		ev = EV_COLD
	if ev != "":
		wakes += 1
		_last_wake = minute
		sleep_quality -= 1
	return ev

func _woke_for(ev: String) -> bool:
	for e in timeline:
		if e["kind"] == "event" and e["id"] == ev:
			return true
	return false

## 当前事件下可选的行动（依赖白天的准备）。
func available_actions() -> PackedStringArray:
	var out := PackedStringArray()
	if has_fire_place and stock_logs > 0:
		out.append(ACT_ADD_WOOD)
	if vent_none or vent_clogged_pending:
		out.append(ACT_CLEAR_VENT)
	if snow_load_due <= minute and not snow_load_active and _shelter in ["SnowTrench", "TreeWell", "LeanTo"] and _pending_event == EV_SNOW_LOAD:
		out.append(ACT_KNOCK_SNOW)
	if has_fire_place and fire_minutes > 0.0 and NightSimulator.wet_fraction(dampness, t) > 0.0:
		out.append(ACT_DRY_SOCKS)
	out.append(ACT_EXERCISE)
	out.append(ACT_SLEEP)
	return out

## 现在起来活动一次能回多少体温（界面显示的就是这个数）。
func exercise_gain() -> float:
	var fatigue := maxf(t.night_exercise_fatigue_floor, 1.0 - t.night_exercise_fatigue * float(_ex_total))
	return t.night_exercise_warmth * pow(t.night_exercise_repeat_factor, float(_ex_this_wake)) * fatigue

## 醒着做事也要花时间：照样在失温，火照样在烧。
func _spend(dt: float) -> void:
	_apply_loss(dt)
	if fire_minutes > 0.0:
		fire_minutes = maxf(0.0, fire_minutes - dt)
		if fire_minutes <= 0.0:
			fire_out_at = minute + dt
	minute += dt

## 执行一个行动（每次事件可做多个，最后 ACT_SLEEP 继续）。返回是否生效。
func act(a: String) -> bool:
	if not (a in available_actions()):
		return false
	timeline.append({"minute": minute, "kind": "action", "id": a, "warmth": warmth})
	match a:
		ACT_ADD_WOOD:
			var n := mini(stock_logs, t.night_add_wood_logs)
			stock_logs -= n
			fire_minutes += float(n) * log_minutes
			_fire_dying_reported = false
			_fire_out_reported = false
			fire_out_at = -1.0
			_spend(5.0)
		ACT_EXERCISE:
			var gain := exercise_gain()
			_spend(10.0)
			warmth = minf(t.warmth_max, warmth + gain)
			dampness = minf(1.0, dampness + t.night_exercise_damp)
			sleep_quality -= 1
			_ex_this_wake += 1
			_ex_total += 1
		ACT_CLEAR_VENT:
			vent_none = false
			vent_clogged_pending = false
			_spend(5.0)
		ACT_KNOCK_SNOW:
			snow_load_due = INF
			_spend(5.0)
		ACT_DRY_SOCKS:
			dampness = maxf(0.0, dampness - 0.3)
			wet_feet_due = INF
			_spend(15.0)
		ACT_SLEEP:
			if _pending_event == EV_SNOW_LOAD and snow_load_due <= minute:
				snow_load_active = true   # 没顶落就继续睡 → 结构受损
			if _pending_event == EV_VENT_CLOGGED and vent_clogged_pending:
				clog_unresolved = true
			_ex_this_wake = 0
			_pending_event = ""
	return true

## 整夜结局（CORE_GAMEPLAY §10.5）。
func result() -> Dictionary:
	var outcome := "COLD"
	var cause := ""
	if suffocated:
		outcome = "DANGEROUS"
		cause = "suffocated"
	elif min_warmth < t.night_wake_critical_w:
		outcome = "DANGEROUS"
		cause = "hypothermia"
	elif min_warmth >= t.night_safe_min_w and (wakes + critical_wakes) <= t.night_safe_max_wakes and not clog_unresolved:
		outcome = "SAFE"
	return {"outcome": outcome, "cause": cause, "min_warmth": min_warmth, "end_warmth": warmth, "wakes": wakes + critical_wakes,
		"sleep_quality": sleep_quality, "protection": protection, "base_loss": base_loss, "curve": curve, "timeline": timeline,
		"boots_frozen": NightSimulator.wet_fraction(dampness, t) > 0.5 and not has_fire_place,
		"had_fire": has_fire_place, "fire_out_at": fire_out_at, "logs_left": stock_logs}

## 测试 / 机器人用：按策略跑完整夜。policy: "sleep"（醒了什么都不做）或 "smart"（能做的都做）。
static func run(p_input: Dictionary, p_t: Tuning, policy: String = "smart") -> Dictionary:
	var n := NightCurve.new(p_input, p_t)
	var guard := 0
	while not n.is_over() and guard < 500:
		guard += 1
		var ev := n.step()
		if ev == "":
			break
		if policy == "smart":
			for a in [ACT_CLEAR_VENT, ACT_KNOCK_SNOW, ACT_ADD_WOOD, ACT_DRY_SOCKS]:
				if a in n.available_actions():
					n.act(a)
			# 冷了就动；越冷动得越久（效果递减，不值得之后就回去睡）
			while n.warmth <= p_t.night_wake_cold_w and n.exercise_gain() >= 3.0:
				n.act(ACT_EXERCISE)
		n.act(ACT_SLEEP)
	return n.result()
