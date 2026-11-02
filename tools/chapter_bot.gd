extends SceneTree
## S7 章节机器人：godot --headless --path . -s res://tools/chapter_bot.gd -- --ch=1 --st=1 --map=0 --route=RaisedCave --care=full
## 和 playtest_bot 不同：读地图上的地物找工地（任意地形 / 旋转），走路花真实的游戏时间，从真实资源点采集，
## 受背包上限约束，到强制入睡时间就必须睡。输出一行 S7 ...（tools/s7_matrix.sh 汇总）。
## route：庇护所预设名 / none（不建）/ intowind:<预设>（入口迎风）。care：full（备足、烘干、暖身）/ basic（建完就睡）。

var d
var p
var site_pos_known := Vector3.INF
var trips := 0
var walked := 0.0
var short := ""

func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Records.path = "user://test_records_s7.cfg"
	Loc.lang = "en"
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return fallback

func _deadline() -> float:
	return float(d.tuning.night_minutes) + d.tuning.forced_sleep_grace_minutes

func _late(margin: float = 0.0) -> bool:
	return d.weather.current_time_minutes >= _deadline() - margin

## 走过去：花真实的游戏时间（实时秒 × 时间倍率）。
func _walk(to: Vector3) -> void:
	var from: Vector3 = p.global_position
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var mid := (from + to) * 0.5
	var speed: float = GameRules.move_speed(d.tuning.move_speed_mps, 0.0, SnowField.snow_at(mid.x, mid.z), d.tuning)
	p.global_position = Vector3(to.x, TerrainHeight.height_at(to.x, to.z) + 0.5, to.z)
	walked += dist
	d._skip(dist / maxf(speed, 0.1) * d._saved_time_scale / 60.0)

func _nearest(kinds: Array) -> Interactable:
	var best: Interactable = null
	var bd := INF
	for n in get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not it.is_inside_tree() or not (it.kind in kinds) or it.uses_left == 0 or it.current_prompt() == "":
			continue
		var dd: float = it.global_position.distance_to(p.global_position)
		if dd < bd:
			bd = dd
			best = it
	return best

func _have(item: String) -> int:
	return d.inventory.count(item) + (d.site.pile.amount(item) if d.site != null else 0)

func _cap(item: String) -> int:
	return d.inventory.max_wood if item == "wood" else d.inventory.max_bedding

## 采到"堆 + 背包"够 total。背包满了走回工地放下（算一趟）；没有工地时装满就停。到点就停。
func _gather(item: String, total: int) -> bool:
	var kinds: Array = ["deadwood"] if item == "wood" else ["grass", "bough"]
	var guard := 0
	while _have(item) < total and guard < 80:
		guard += 1
		if _late():
			return false
		if d.inventory.count(item) >= _cap(item):
			if d.site == null:
				return true
			_back_to_site()
			continue
		var it := _nearest(kinds)
		if it == null:
			short = item
			return false
		_walk(it.global_position + Vector3(0.6, 0, 0))
		var r: Dictionary = it.trigger()
		d._on_interaction_completed(it, r)
		await process_frame
	return _have(item) >= total

func _back_to_site() -> void:
	trips += 1
	_walk(d.site.global_position + d.site.entrance_dir * 2.5)
	d._unload_to_site()

func _candidates(preset: String) -> Array:
	var t: Tuning = d.tuning
	var out: Array = []
	var here := Vector2(p.global_position.x, p.global_position.z)
	var blow: Vector3 = d.wind.get_blow_direction_3d()
	match preset:
		"TreeWell":
			for q in OldSpruces.points:
				if TerrainHeight.snow_depth_at(q.x, q.y) >= t.tree_well_min_snow_m + 0.05 and TerrainHeight.slope_at(q.x, q.y) < 28.0:
					out.append(Vector3(q.x, 0, q.y))
		"LeanTo":
			for r in MapLayout.get_layout()["rootballs"]:
				out.append(Vector3(r.x, 0, r.y) + blow * 2.0)
			for x in range(-42, 43, 6):
				for z in range(-42, 43, 6):
					out.append(Vector3(x, 0, z))
		"RockOverhang":
			for q in LandFeatures.rocks:
				out.append(Vector3(q.x, 0, q.y))
		"FallenLog":
			for q in LandFeatures.logs:
				out.append(Vector3(q.x, 0, q.y))
		_:
			var need := 0.3
			match preset:
				"RaisedCave": need = t.snow_depth_raised_cave_min_m + 0.05
				"BasicCave": need = t.snow_depth_cave_min_m + 0.05
				"SnowTrench": need = t.snow_depth_trench_standard_m
				"Quinzhee": need = t.quinzhee_min_snow_m + 0.05
			for x in range(-42, 43, 3):
				for z in range(-42, 43, 3):
					var s: float = SnowField.snow_at(x, z)
					var sl: float = SnowField.slope_at(x, z)
					if s < need:
						continue
					if preset in ["RaisedCave", "BasicCave"] and (sl < 9.0 or sl > 40.0):
						continue
					if preset == "SnowTrench" and sl > 25.0:
						continue
					if preset == "Quinzhee" and sl > t.quinzhee_max_slope_deg - 2.0:
						continue
					out.append(Vector3(x, 0, z))
			# 雪沟太浅的图：退到砌墙雪沟的深度
			if out.is_empty() and preset == "SnowTrench":
				for x in range(-42, 43, 3):
					for z in range(-42, 43, 3):
						if SnowField.snow_at(x, z) >= t.snow_depth_trench_wall_min_m and SnowField.slope_at(x, z) < 25.0:
							out.append(Vector3(x, 0, z))
	out.sort_custom(func(a, b): return here.distance_squared_to(Vector2(a.x, a.z)) < here.distance_squared_to(Vector2(b.x, b.z)))
	return out

func _place(preset: String, into_wind: bool) -> bool:
	var gd: float = d.tuning.ghost_distance_m
	var cands := _candidates(preset)
	var start: Vector3 = p.global_position
	var fails := 0
	for c in cands.slice(0, 25):
		p.global_position = Vector3(c.x - gd, TerrainHeight.height_at(c.x - gd, c.z) + 0.5, c.z)
		p.visual_node.rotation.y = atan2(1.0, 0.0)
		await physics_frame
		d._enter_build()
		d.build.preset_id = preset
		if into_wind:
			d.build.entrance_dir = d.wind.get_wind_direction_3d()
		else:
			d.build.entrance_dir = d.wind.get_blow_direction_3d()
		await process_frame
		await process_frame
		d._place_site()
		if d.site != null:
			var end: Vector3 = p.global_position
			p.global_position = start
			_walk(end)
			d._step_back()
			return true
		d._exit_build()
		fails += 1
	return false

func _stages(preset: String, stage_bedding: int, stage_wood: int) -> void:
	var stop := false
	var bark_need := 1 if preset == "LeanTo" else 0
	if bark_need > 0 and d.inventory.bark < bark_need:
		await _bark(bark_need)
	while not d.site.is_complete() and not stop:
		if _late():
			return
		if d.site.ready_at > d.weather.current_time_minutes:
			# 雪堆屋：趁雪凝结去备料；还没到点就干等
			await _gather("bedding", stage_bedding)
			await _gather("wood", stage_wood)
			if _late():
				return
			if d.site.ready_at > d.weather.current_time_minutes:
				_back_to_site()
				d._skip(maxf(d.site.ready_at - d.weather.current_time_minutes, 0.0))
		var cost: Dictionary = d.site.next_stage_cost()
		for k in cost:
			if k != "bark" and _have(k) < int(cost[k]):
				if not await _gather(k, int(cost[k])):
					stop = true
		if stop or _late():
			return
		if d.inventory.wood > 0 or d.inventory.bedding > 0 or Vector2(p.global_position.x - d.site.global_position.x, p.global_position.z - d.site.global_position.z).length() > 4.0:
			_back_to_site()
		var r: Dictionary = d.site.interactable.trigger()
		if not bool(r.get("ok", true)):
			return
		d._on_interaction_completed(d.site.interactable, r)
		await process_frame

func _bark(n: int) -> void:
	var g := 0
	while d.inventory.bark < n and g < 10 and not _late():
		g += 1
		var it := _nearest(["birch"])
		if it == null:
			short = "bark"
			return
		_walk(it.global_position + Vector3(0.6, 0, 0))
		var r: Dictionary = it.trigger()
		d._on_interaction_completed(it, r)
		await process_frame

## 生火、喝热水 / 烘干。near_site = 火要在工地旁边（给棚子供热）。
func _fire_and_dry(near_site: bool) -> void:
	await _bark(1)
	if d.inventory.bark < 1 or _late(10.0):
		printerr("  no fire: bark=%d late=%s short=%s" % [d.inventory.bark, str(_late(10.0)), short])
		return
	var c: Vector3 = d.site.global_position if d.site != null and near_site else p.global_position
	if not near_site and d.site != null and d.inventory.wood < d.tuning.fire_wood_cost:
		await _gather("wood", _have("wood") + d.tuning.fire_wood_cost)
	# 先看工地附近（自己的庇护所下风侧能挡风），再看站的地方周围
	if d.site != null:
		c = d.site.global_position
	var spot := Vector3.INF
	var max_r := 5.0 if near_site else 30.0
	var r := 2.5
	while r <= max_r and spot == Vector3.INF:
		for k in range(24):
			var q: Vector3 = c + Vector3(cos(TAU * k / 24.0), 0, sin(TAU * k / 24.0)) * r
			q.y = TerrainHeight.height_at(q.x, q.z)
			if absf(q.x) < 46.0 and absf(q.z) < 46.0 and bool(d.fire_check_at(q)["ok"]):
				spot = q
				break
		r += 1.5
	if spot == Vector3.INF:
		printerr("  no lightable spot")
		return
	var stand: Vector3 = spot - p.facing() * 1.3
	_walk(stand)
	var fires0 := get_nodes_in_group("campfires").size()
	var why_not: Dictionary = d.fire_check_at(p.global_position + p.facing() * 1.3)
	d._try_fire()
	await process_frame
	if get_nodes_in_group("campfires").size() <= fires0:
		printerr("  fire failed at %s: %s (spot was %s, wood=%d bark=%d)" % [str(p.global_position), str(why_not), str(spot), d._fire_wood(), d.inventory.bark])
		return
	for i in 2:
		var it := _nearest(["fire"])
		if it != null and not _late(5.0) and (i == 0 or GameRules.clothing_state(d.dampness, d.tuning) != "dry"):
			d._on_interaction_completed(it, it.trigger())
			await process_frame

func _run() -> void:
	var ch := int(_arg("ch", "1"))
	var st := int(_arg("st", "1"))
	var map := int(_arg("map", "0"))
	var route := _arg("route", "target")
	var care := _arg("care", "full")
	LevelState.begin(ch, -1, st, map)
	var m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	current_scene = m
	for i in 12: await process_frame
	d = m.get_node("GameDirector")
	p = m.player
	if route == "target":
		route = LevelState.target_presets()[0]
	d.start_game()
	await process_frame
	var into_wind := route.begins_with("intowind:")
	var preset := route.substr(9) if into_wind else route
	var start_clock: String = d.weather.clock_string()
	var placed := false
	var done_clock := "-"
	if preset != "none":
		var costs: Dictionary = {"wood": 0, "bedding": 0}
		var presets := ShelterPreset.create_all_presets()
		for c in (presets[preset] as ShelterPreset).stage_costs:
			for k in c:
				if costs.has(k):
					costs[k] += int(c[k])
		d._skip(3.0)   # 探雪、看地形
		# 先装满一包再去工地
		await _gather("wood", mini(costs["wood"], d.inventory.max_wood))
		await _gather("bedding", mini(costs["bedding"], d.inventory.max_bedding))
		placed = await _place(preset, into_wind)
		if placed:
			await _stages(preset, costs["bedding"], costs["wood"])
			if d.site.is_complete():
				done_clock = d.weather.clock_string()
			if care == "full" and d.site.is_complete():
				var snow: bool = preset in NightSimulator.SNOW_TYPES
				if snow:
					await _fire_and_dry(false)
				else:
					var logs: int = 8 if preset == "LeanTo" else 6
					await _gather("wood", logs)
					if preset != "LeanTo":
						await _fire_and_dry(true)
					else:
						# 倒棚完工时火已经点着：喝热水暖身，和玩家一样
						_back_to_site()
						var fi := _nearest(["fire"])
						if fi != null and not _late(5.0):
							d._on_interaction_completed(fi, fi.trigger())
							await process_frame
				await _gather("bedding", 3)
				if d.inventory.wood > 0 or d.inventory.bedding > 0:
					_back_to_site()
	var forced: bool = _late()
	var inp: Dictionary = d.night_input()
	inp["night_snowfall"] = d.weather.atmosphere.snowfall
	var smart := NightCurve.run(inp, d.tuning, "smart")
	var lazy := NightCurve.run(inp, d.tuning, "sleep")
	var rep := NightSimulator.evaluate(inp, d.tuning)
	var f := SnowField.map_facts(d.tuning)
	print("S7 ch=%d st=%d map=%d shape=%s weather=%s route=%s care=%s start=%s placed=%s stage=%d done=%s bed=%s forced=%s trips=%d walked=%d short=%s temp=%d wind=%d bedW=%d damp=%.2f prot=%.2f loss=%.1f hours=%.1f smart=%s/%d/%d sleep=%s/%d why=%s maxsnow=%.1f" % [
		ch, st, map, TerrainHeight.RECIPE.shape, d.weather.weather_kind, route, care, start_clock, str(placed), d.site.stage() if d.site != null else 0, done_clock, d.weather.clock_string(), str(forced),
		trips, int(walked), short if short != "" else "-", int(d.weather.night_temp_c()), int(d.weather.current_wind_kmh()), int(inp["starting_warmth"]), float(inp.get("dampness", 0.0)), float(smart["protection"]), float(smart["base_loss"]), float(inp.get("night_hours", 0.0)),
		smart["outcome"], int(smart["min_warmth"]), int(smart["wakes"]), lazy["outcome"], int(lazy["min_warmth"]), String(rep["details"].get("min_axis", "?")), float(f["max_depth"])])
	quit(0)
