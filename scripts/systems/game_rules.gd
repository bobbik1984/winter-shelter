class_name GameRules
extends RefCounted

## 游戏循环的纯规则函数（无节点依赖，可 headless 测试）。
## 所有阈值来自 Tuning；这里只放"把世界状态翻译成玩法结果"的公式。

## 移动速度：上坡与深雪两项独立衰减（T1.4）。uphill_slope_deg 为沿移动方向的上坡角（下坡传 0）。
static func move_speed(base: float, uphill_slope_deg: float, snow_depth: float, t: Tuning) -> float:
	var uphill := maxf(0.0, tan(deg_to_rad(clampf(uphill_slope_deg, 0.0, 60.0))))
	var slope_k := maxf(t.uphill_speed_min, 1.0 / (1.0 + t.slope_slowdown * uphill))
	var snow_k := lerpf(1.0, t.deep_snow_speed_min,
		smoothstep(t.deep_snow_start_m, t.deep_snow_full_m, snow_depth))
	return base * slope_k * snow_k


## 探针读数分类（D5 雪深区间）：返回 {key, title, sub, color}。
static func classify_depth(depth: float, t: Tuning) -> Dictionary:
	if depth < t.snow_depth_non_snow_max_m:
		return {"key": "shallow", "title": Loc.t("Shallow snow"), "sub": Loc.t("~ %.1f m · lean-to only") % depth, "color": Color(0.70, 0.72, 0.78)}
	if depth < t.snow_depth_trench_wall_max_m:
		return {"key": "trench_wall", "title": Loc.t("Thin snow"), "sub": Loc.t("~ %.1f m · walled trench") % depth, "color": Color(0.62, 0.78, 0.95)}
	if depth < t.snow_depth_cave_min_m:
		return {"key": "trench", "title": Loc.t("Trench depth"), "sub": Loc.t("~ %.1f m · snow trench") % depth, "color": Color(0.52, 0.72, 1.0)}
	if depth < t.snow_depth_raised_cave_min_m:
		return {"key": "cave", "title": Loc.t("Good depth"), "sub": Loc.t("~ %.1f m · snow cave") % depth, "color": Color(0.95, 0.78, 0.40)}
	return {"key": "raised_cave", "title": Loc.t("Deep snow"), "sub": Loc.t("~ %.1f m · raised cave") % depth, "color": Color(1.0, 0.66, 0.24)}


## 入口朝向与风的来向夹角（°）：0 = 入口正对上风（最糟），180 = 完全背风。
static func entrance_wind_angle(entrance_dir: Vector3, wind_from: Vector3) -> float:
	var e := Vector2(entrance_dir.x, entrance_dir.z)
	var w := Vector2(wind_from.x, wind_from.z)
	if e.length() < 0.001 or w.length() < 0.001:
		return 90.0
	return rad_to_deg(acos(clampf(e.normalized().dot(w.normalized()), -1.0, 1.0)))


## 火位 / 人的迎风暴露 0（背风 / 有挡风物）..1（完全迎风）。
## tree_cover 0..1：附近林木挡风（Read the Land：林子里风小）。
static func fire_exposure(lee_factor: float, near_windbreak: bool, tree_cover: float = 0.0) -> float:
	return clampf(1.0 - lee_factor - (0.45 if near_windbreak else 0.0) - 0.5 * clampf(tree_cover, 0.0, 1.0), 0.0, 1.0)


## 林木挡风度：半径 r 内的树数量折算 0..1（每棵约 0.15，封顶 1）。
static func tree_cover(points: PackedVector2Array, p: Vector2, r: float) -> float:
	var n := 0
	for q in points:
		if q.distance_squared_to(p) < r * r:
			n += 1
	return clampf(n * 0.15, 0.0, 1.0)


## 生火判定（D2/D3）：返回 {ok, reason}。顺序即"第一条原因"。
static func fire_check(wood: int, bark: int, exposure: float, under_canopy: bool,
		inside_snow_shelter: bool, t: Tuning) -> Dictionary:
	if inside_snow_shelter:
		return {"ok": false, "reason": Loc.t("No open fire inside a snow shelter — it melts the roof and fills it with CO.")}
	if bark < t.fire_tinder_cost:
		return {"ok": false, "reason": Loc.t("Need birch bark as tinder (%d).") % t.fire_tinder_cost}
	if wood < t.fire_wood_cost:
		return {"ok": false, "reason": Loc.t("Need %d dry wood. Standing dead trees burn; fallen logs are wet.") % t.fire_wood_cost}
	if under_canopy:
		return {"ok": false, "reason": Loc.t("Fire put out by snow falling from the branches above. Move out from under the tree.")}
	# 与 NightSimulator 同一条规则：暴露度超过 fire_blowout_dot 火就会被吹灭（白天 / 夜里一致）
	if exposure > t.fire_blowout_dot:
		return {"ok": false, "reason": Loc.t("The wind blew the flame out. Find a leeward spot or a rootball to shelter it.")}
	return {"ok": true, "reason": Loc.t("Fire lit.")}


## 上下文提示行（V3：影子就是时钟）。返回英文玩家文案。
## 风的来向：罗盘缩写（HUD）与本地化方位词（文案）。octant 见 WindData.from_octant()。
const WIND_ABBR := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

static func wind_abbr(octant: int) -> String:
	return WIND_ABBR[posmod(octant, 8)]

static func wind_word(octant: int) -> String:
	match posmod(octant, 8):
		0: return Loc.t("north")
		1: return Loc.t("north-east")
		2: return Loc.t("east")
		3: return Loc.t("south-east")
		4: return Loc.t("south")
		5: return Loc.t("south-west")
		6: return Loc.t("west")
	return Loc.t("north-west")

static func tip_for(minutes_to_sunset: float, sun_elevation_deg: float, body_warmth: float,
		has_shelter: bool, shelter_complete: bool, t: Tuning, wind_from_word: String = "") -> String:
	if body_warmth < t.tip_cold_warmth:
		return Loc.t("Getting cold — get out of the wind or light a fire.")
	if minutes_to_sunset <= 0.0:
		return Loc.t("Sun is down. Finish up, or sleep now [N].")
	if minutes_to_sunset < t.tip_hurry_minutes:
		if shelter_complete:
			return Loc.t("Long shadows — night is close. Rest when ready [N].")
		return Loc.t("Very long shadows: <%d min of light. Finish now!") % int(ceil(minutes_to_sunset))
	if minutes_to_sunset < t.tip_plenty_minutes:
		return Loc.t("Shadows lengthening — ~%d min of light left.") % int(round(minutes_to_sunset / 5.0) * 5.0)
	if not has_shelter:
		return Loc.t("Wind from the %s. Probe [Space] leeward slopes.") % (wind_from_word if wind_from_word != "" else wind_word(6))
	return Loc.t("Sun %d° — shadows grow toward evening.") % int(round(sun_elevation_deg))


## 作业效率：体温档 × 暮色衰减（非硬切换）。
static func work_efficiency(warmth_eff: float, minutes_to_sunset: float, t: Tuning) -> float:
	var dusk := 1.0
	if minutes_to_sunset < 0.0:
		dusk = lerpf(1.0, t.dusk_efficiency_floor, clampf(-minutes_to_sunset / 60.0, 0.0, 1.0))
	return clampf(warmth_eff * dusk, 0.1, 1.0)


## 当前目标行（M2 闸门"零口头帮助打完一局"）：根据进度给出下一步具体动作。
## ctx: {probed: bool, best_depth: float, has_site: bool, stage: int, complete: bool,
##       missing: String（下一阶段缺的材料，空 = 不缺）, next_stage: String, minutes_to_sunset: float, preset: String}
static func next_objective(ctx: Dictionary, t: Tuning) -> String:
	if bool(ctx.get("clothes_wet", false)):
		return "Your layers are wet and no longer warm — dry them by a fire [F]."
	if bool(ctx.get("complete", false)):
		if bool(ctx.get("needs_vent_stick", false)):
			return Loc.t("Snow is falling — hold [E] at your shelter: stick in the vent (1 wood).")
		if String(ctx.get("preset", "")) == "LeanTo":
			return Loc.t("Shelter done. Stockpile dry wood for the fire, then rest [N].")
		return Loc.t("Shelter done. Warm up by a fire [F] + hot drink, then rest [N].")
	if not bool(ctx.get("has_site", false)):
		if not bool(ctx.get("probed", false)):
			return Loc.t("Hold [Space] to probe the snow. Look for >= %.1f m on leeward slopes.") % t.snow_depth_cave_min_m
		if float(ctx.get("best_depth", 0.0)) < t.snow_depth_cave_min_m:
			return Loc.t("Keep probing — deeper snow collects east of the ridge, out of the wind.")
		return Loc.t("Deep snow found. Stand next to it and press [B] to plan a shelter.")
	var missing := String(ctx.get("missing", ""))
	if missing != "":
		return Loc.t("Gather %s — then hold [E] at your site.") % missing
	return Loc.t("Hold [E] at your site: %s") % String(ctx.get("next_stage", ""))


## 保暖层是否仍有效（CORE_GAMEPLAY §4）：带了保暖层且受潮未超过阈值。
static func clothing_effective(has_layer: bool, dampness: float, t: Tuning) -> bool:
	return has_layer and dampness < t.damp_threshold


## 保暖层状态文字键：dry / damp / wet。
static func clothing_state(dampness: float, t: Tuning) -> String:
	if dampness < t.damp_threshold * 0.5:
		return "dry"
	if dampness < t.damp_threshold:
		return "damp"
	return "wet"
