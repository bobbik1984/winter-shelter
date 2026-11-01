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
## R2：选址前是否在离工地 radius 米内探过雪（水平距离）。
static func probed_near(points: Array[Vector3], site_pos: Vector3, radius: float) -> bool:
	for p in points:
		if Vector2(p.x - site_pos.x, p.z - site_pos.z).length() <= radius:
			return true
	return false

static func entrance_wind_angle(entrance_dir: Vector3, wind_from: Vector3) -> float:
	var e := Vector2(entrance_dir.x, entrance_dir.z)
	var w := Vector2(wind_from.x, wind_from.z)
	if e.length() < 0.001 or w.length() < 0.001:
		return 90.0
	return rad_to_deg(acos(clampf(e.normalized().dot(w.normalized()), -1.0, 1.0)))


## 火位 / 人的迎风暴露 0（背风 / 有挡风物）..1（完全迎风）。
## tree_cover 0..1：附近林木挡风（Read the Land：林子里风小）。
## 暴露度 0..1。windbreak = 树根盘的挡风度 0..1（有方向：只有下风一侧被挡住，见 windbreak_shelter）。
static func fire_exposure(lee_factor: float, windbreak: float, tree_cover: float = 0.0) -> float:
	return clampf(1.0 - lee_factor - 0.75 * clampf(windbreak, 0.0, 1.0) - 0.5 * clampf(tree_cover, 0.0, 1.0), 0.0, 1.0)

## 树根盘对 p 点的挡风度 0..1（第二次评审：以前 3.5 m 内一律算挡风，正对风的一侧也算——火照样被吹灭，规则和"去树根背风处"的提示对不上）。
## 只挡下风一侧：p 在树根盘的正下风方 = 1，侧面逐渐减弱，迎风面 = 0；越靠近越挡得住。
static func windbreak_shelter(windbreak_points: Array, p: Vector2, blow: Vector2, radius: float) -> float:
	var best := 0.0
	var b := blow.normalized()
	for w in windbreak_points:
		var off: Vector2 = p - (w as Vector2)
		var d := off.length()
		if d >= radius:
			continue
		var side := 1.0 if d < 0.3 else off.normalized().dot(b)
		var s := smoothstep(-0.1, 0.6, side) * (1.0 - pow(d / radius, 2.0))
		best = maxf(best, s)
	return clampf(best, 0.0, 1.0)


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
		return {"ok": false, "reason": Loc.t("The wind blew the flame out. Go right behind a root plate on its downwind side, or into a leeward hollow.")}
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
## 装备（S6）：没有雪铲时，挖雪庇护所的工时 × no_shovel_dig_factor；倒棚不受影响。
static func dig_minutes(base_minutes: float, is_snow_shelter: bool, has_shovel: bool, t: Tuning) -> float:
	return base_minutes * (t.no_shovel_dig_factor if is_snow_shelter and not has_shovel else 1.0)

## 装备（S6）：防潮垫加到地面隔热上（封顶 1）。
static func bedding_with_pad(bedding_quality: float, has_pad: bool, t: Tuning) -> float:
	return clampf(bedding_quality + (t.sleeping_pad_bedding_bonus if has_pad else 0.0), 0.0, 1.0)

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
		return Loc.t("Your layers are wet and no longer warm — dry them by a fire [F]: right behind a root plate on its downwind side, away from spruce branches.")
	if bool(ctx.get("complete", false)):
		if bool(ctx.get("needs_vent_stick", false)):
			return Loc.t("Snow is falling — hold [E] at your shelter: stick in the vent (1 wood).")
		if String(ctx.get("preset", "")) == "LeanTo":
			return Loc.t("Shelter done. Stockpile dry wood for the fire, then rest [N].")
		return Loc.t("Shelter done. Warm up by a fire [F] + hot drink, then rest [N].")
	if not bool(ctx.get("has_site", false)):
		# 只依据玩家自己的探测结果 + D5 门槛说话（不泄露关卡设定，也不预设"一定要挖雪洞"）
		if not bool(ctx.get("probed", false)):
			return Loc.t("Hold [Space] to probe the snow on leeward slopes. Its depth decides which shelter you can build.")
		var best := float(ctx.get("best_depth", 0.0))
		if best < t.snow_depth_trench_wall_min_m:
			return Loc.t("Deepest so far %.2f m — too thin to dig. Probe elsewhere, or build a lean-to by a root plate [B].") % best
		if best < t.snow_depth_cave_min_m:
			return Loc.t("Deepest so far %.1f m — enough for a trench [B]. A snow cave needs %.1f m.") % [best, t.snow_depth_cave_min_m]
		if best < t.snow_depth_raised_cave_min_m:
			return Loc.t("Deepest so far %.1f m — a snow cave fits [B]. A raised cave needs %.1f m.") % [best, t.snow_depth_raised_cave_min_m]
		return Loc.t("Deep snow found (%.1f m) — room for a raised cave. Stand next to it and press [B].") % best
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
