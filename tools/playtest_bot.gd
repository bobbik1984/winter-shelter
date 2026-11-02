extends SceneTree
## 策略机器人（QA）：godot --path . -s res://tools/playtest_bot.gd -- --s=<good|deep|deep_stick|quick|twovent|wind|late|trench|treewell|leanto_short|leanto_full|none>
## 直接调用 GameDirector API 走完一局，打印结局与 6 维分数；用于平衡回归（见 PRODUCTION_PLAN §4.V / T3.9）。
## 策略机器人：直接调用 GameDirector API 走完一局，打印结局与 6 维分数。
func _initialize() -> void:
	# 固定基准：不进关卡模式（山谷 7 / 不旋转 / 天气按 Tuning），记录写到测试文件，不碰玩家存档
	LevelState.auto_begin = false
	Records.path = "user://test_records.cfg"
	_run()
func _run() -> void:
	var strat := "good"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--s="): strat = a.substr(4)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--valley="): TerrainHeight.SEED = int(a.substr(9))
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	for i in 15: await process_frame
	var d = m.get_node("GameDirector")
	d.start_game()
	var p = m.player
	# 寻找合法高床雪洞点（出生点附近）
	var spot := Vector3(22, 0, 8)
	var want := 2.05
	if strat in ["deep", "quick", "twovent", "deep_stick"]: want = 2.4
	for r in range(2, 40):
		var hit := false
		for k in range(16):
			var q := Vector2(18, 8) + Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0)) * r
			if SnowField.snow_at(q.x, q.y) >= want and SnowField.slope_at(q.x, q.y) >= 9.0:
				spot = Vector3(q.x, 0, q.y); hit = true; break
		if hit: break
	d._skip(3.0)   # 走路 + 探测
	p._finish_probe()
	var preset := "RaisedCave"
	var wood_need := 3
	var bedding_need := 4
	match strat:
		"late": d._skip(120.0); preset = "BasicCave"; wood_need = 1; bedding_need = 4
		"leanto_short": preset = "LeanTo"; wood_need = 9; bedding_need = 4; spot = Vector3(-1.2, 0, 10.5)   # 7 根施工 + 2 根过夜
		"leanto_full": preset = "LeanTo"; wood_need = 15; bedding_need = 4; spot = Vector3(-1.2, 0, 10.5)   # 7 根施工 + 8 根过夜
		"trench": preset = "SnowTrench"; wood_need = 3; bedding_need = 3
		"treewell":
			# S5：离出生点最近、周围积雪够厚的老云杉；树井不花木头，3 根留着睡前烤干
			preset = "TreeWell"; wood_need = 0; bedding_need = 6
			var best := INF
			for q in OldSpruces.points:
				var dq: float = q.distance_to(MapLayout.spawn())
				if dq < best and TerrainHeight.snow_depth_at(q.x, q.y) >= d.tuning.tree_well_min_snow_m + 0.1 and TerrainHeight.slope_at(q.x, q.y) < 25.0:
					best = dq
					spot = Vector3(q.x, 0, q.y)
			printerr("  tree well spruce at %s (%.0f m from spawn, %d old spruces on the map)" % [str(spot), best, OldSpruces.points.size()])
	# 好的策略睡前多铺 3 捆枝条（地面隔热：没有防潮垫就靠多铺，CORE_GAMEPLAY §9.5b）
	if not strat in ["none", "late", "wind", "leanto_short"]:
		bedding_need += 3
	# 采集（每次 6 分钟 / 3 分钟，与真实交互一致）
	# D16 / B4：背包有上限。放样前先装满一包，放样后来回跑，堆到工地（每趟走路 2 分钟）
	var total_wood := wood_need + (1 if strat == "deep_stick" else 0)
	_haul(d, "grass", "bedding", bedding_need)
	_haul(d, "deadwood", "wood", total_wood)
	d.inventory.add("bark", 2)
	d._skip(2.0 * 12.0 / 12.0)
	if strat == "none":
		d._sleep(false)
	else:
		p.global_position = Vector3(spot.x - 3.0, TerrainHeight.height_at(spot.x - 3.0, spot.z) + 0.5, spot.z)
		p.visual_node.rotation.y = atan2(1.0, 0.0)
		await physics_frame
		d._enter_build()
		d.build.preset_id = preset
		if strat == "quick":
			d.build.quick_roof = true
		if strat == "twovent":
			d.build.vent_count = 2
		if strat == "wind":
			d.build.entrance_dir = d.wind.get_wind_direction_3d()
		await process_frame
		await process_frame
		d._place_site()
		if d.site == null:
			printerr("PLACE FAILED ", d.build.reason); quit(1); return
		_haul(d, "grass", "bedding", bedding_need)
		_haul(d, "deadwood", "wood", total_wood)
		d._unload_to_site()
		var stages := 5
		for s in stages:
			if strat == "late" and d.weather.current_time_minutes > 1060.0:
				break
			d._on_interaction_completed(d.site.interactable, d.site.interactable.trigger())
		if strat in ["good", "deep", "leanto_full", "quick", "twovent", "deep_stick", "trench", "treewell"]:
			# 去生火要带上柴（放在工地的柴离得远就用不上）
			while d.inventory.wood < 3 and strat != "leanto_full":
				d._on_interaction_completed(_fake("deadwood"), d._on_harvest(_fake("deadwood")))
			# 篝火 + 热饮：像玩家一样找最近的树根盘，站到它的背风侧生火（原先站的开阔处风太大，火一直点不着）
			var best_r := Vector2.ZERO
			var best_d := INF
			for r in MapLayout.get_layout()["rootballs"]:
				var dd: float = (r as Vector2).distance_to(Vector2(d.site.global_position.x, d.site.global_position.z))
				if dd < best_d:
					best_d = dd
					best_r = r
			# 在树根盘背风一侧找一个能点着的地方（不在树冠下、挡得住风），像玩家一样多走几步
			var blow: Vector3 = d.wind.get_blow_direction_3d()
			var fire_spot := Vector3.INF
			for dist in [1.4, 2.0, 2.8]:
				for ang in [0.0, 40.0, -40.0, 80.0, -80.0]:
					var c: Vector3 = Vector3(best_r.x, 0.0, best_r.y) + blow.rotated(Vector3.UP, deg_to_rad(ang)) * dist
					c.y = TerrainHeight.height_at(c.x, c.z)
					if fire_spot == Vector3.INF and bool(d.fire_check_at(c)["ok"]):
						fire_spot = c
			if fire_spot == Vector3.INF:
				printerr("  no lightable fire fire_spot near the root plate")
				fire_spot = Vector3(best_r.x, 0.0, best_r.y) + blow * 1.6
			var fp: Vector3 = fire_spot - p.facing() * 1.3
			p.global_position = Vector3(fp.x, TerrainHeight.height_at(fp.x, fp.z) + 0.5, fp.z)
			await physics_frame
			d._try_fire()
			for n in get_nodes_in_group("interactables"):
				if n.kind == "fire" and n.current_prompt() != "":
					d._on_interaction_completed(n, n.trigger())
					# 挖雪庇护所会湿透：第二杯热水 = 把衣服烤干再睡（R1；倒棚不挖雪、不湿）
					if strat != "leanto_full" and GameRules.clothing_state(d.dampness, d.tuning) != "dry":
						d._on_interaction_completed(n, n.trigger())
					break
		if strat == "deep_stick" and d._needs_vent_stick():
			d._on_interaction_completed(d.site.interactable, d.site.interactable.trigger())
		printerr("  dampness before bed=%.2f wood=%d prewarmed=%s" % [d.dampness, d.inventory.wood, str(d.prewarmed)])
		d._sleep(false)
	var inp = d.night_input()
	inp["night_snowfall"] = d.weather.atmosphere.snowfall
	var rep = NightSimulator.evaluate(inp, d.tuning)
	var sc = rep["scores"]
	# D14：结局 = 可玩夜晚的整夜体温曲线（机器人夜里按 "smart" 处理：添柴 / 清通风口 / 顶雪 / 烘袜子 / 冷了就活动）
	var nightres := NightCurve.run(inp, d.tuning, "sleep" if strat in ["none", "late", "wind"] else "smart")
	# N5：同一份准备，两种夜里的玩家各走一遍；再看基础失温 ±10% 会不会翻转结局（离分界线 6 分内的不算，见 §10.5）
	var smart := NightCurve.run(inp, d.tuning, "smart")
	var lazy := NightCurve.run(inp, d.tuning, "sleep")
	var tol := "ok"
	var near_edge: bool = absf(float(smart["min_warmth"]) - d.tuning.night_safe_min_w) <= 6.0 or absf(float(smart["min_warmth"]) - d.tuning.night_wake_critical_w) <= 6.0
	for f in [0.9, 1.1]:
		var t2: Tuning = d.tuning.duplicate()
		t2.night_base_loss_per_h = d.tuning.night_base_loss_per_h * f
		if String(NightCurve.run(inp, t2, "smart")["outcome"]) != String(smart["outcome"]) and not near_edge:
			tol = "FLIP"
	printerr("depth %.2f " % inp.get("snow_depth_meters", 0.0), "BOT %-12s %-9s t=%s warmth=%d  site=%d struct=%d ins=%d iso=%d air=%d heat=%d  min=%s  night: low=%d wakes=%d  smart=%s/%d/%d sleep=%s/%d tol=%s" % [strat, nightres["outcome"], d.weather.clock_string(), int(inp["starting_warmth"]), sc["site"], sc["structure"], sc["insulation"], sc["isolation"], sc["air"], sc["heat"], rep["details"]["min_axis"], int(nightres["min_warmth"]), int(nightres["wakes"]), smart["outcome"], int(smart["min_warmth"]), int(smart["wakes"]), lazy["outcome"], int(lazy["min_warmth"]), tol])
	printerr("  fire_lit=", inp.get("fire_lit"), " exposure=", inp.get("fire_exposure"), " fuel_h=", inp.get("fuel_hours"), " held=", rep["details"]["fire_reaches_dawn"], " prewarmed=", inp.get("prewarmed"), " clogged=", inp.get("vent_snow_clogged"), " site_fire=", d.site.fire.lit if d.site and d.site.fire else null)
	quit(0)
## 采到"堆 + 背包"够 total；背包满了就走回工地放下（没有工地时就停在满包）。
func _haul(d, kind: String, item: String, total: int) -> void:
	var guard := 0
	while guard < 60:
		guard += 1
		var have: int = d.inventory.count(item) + (d.site.pile.amount(item) if d.site != null else 0)
		if have >= total:
			return
		if d.inventory.count(item) >= (d.inventory.max_wood if item == "wood" else d.inventory.max_bedding):
			if d.site == null:
				return
			d._skip(2.0)
			d._unload_to_site()
			d._skip(2.0)
		d._on_interaction_completed(_fake(kind), d._on_harvest(_fake(kind)))

func _fake(kind: String) -> Interactable:
	var it := Interactable.new()
	it.kind = kind
	return it
