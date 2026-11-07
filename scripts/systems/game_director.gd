class_name GameDirector
extends Node

## 一局游戏的总导演（M2 循环）：简报 → 自由行动（探测 / 采集 / 建造 / 生火）→ 入夜 → 6 维报告 → 重开。
## 只做编排：规则在 GameRules / NightSimulator / ShelterBuilder，数值在 Tuning，外观在各自节点。
## 由 MainLevel 在 _ready 中创建并注入引用。

enum State { BRIEFING, PLAYING, NIGHT_FADE, REPORT, PAUSED, NIGHT }

var main: Node3D
var player: PlayerController
var weather: WeatherController
var warmth: WarmthController
var hud: HUDController
var tuning: Tuning
var wind: WindData

var inventory: Inventory
var interaction: InteractionController
var build: BuildMode
var spawner: ResourceSpawner
var ui: GameUI
var callouts: WorldCallouts
## D16 建造特写（CORE_GAMEPLAY §12）。
var session := BuildSession.new()
var rig: IsometricCameraRig
var _hiker_ghost := 0.0
## 特写时角色的模型画在工地旁边（只改外观，玩家真实位置不动）。
var _figure_spot := Vector3.INF
var _figure_home := Vector3.ZERO
var _focus_complete_ms := 0
var site: ShelterSite
var graphics: GraphicsSettings
var audio: AmbientAudio
var snowfall: Snowfall
var prints: Footprints
var spindrift: Spindrift
var headlamp: SpotLight3D
var state: State = State.BRIEFING

var prewarmed := false
## 全天模式（简报页按 2）：10:00 开局。记录与标准模式分开保存。
var full_day := false
## 本局装备（S6，来自 LevelState.gear()）。
var _in_shelter := false
var _shelter_tween: Tween
var gear: Dictionary = {"shovel": true, "pot": true, "layer": true, "pad": false, "hides": false, "wood": 0, "bark": 0, "bedding": 0}
## 一天的时间线（报告里回顾时间花在哪）：事件 -> 时刻字符串。
var _timeline: Array = []

func _mark(event: String) -> void:
	for e in _timeline:
		if e[0] == event:
			return
	_timeline.append([event, weather.clock_string()])
var _saved_time_scale := 12.0
var _sleep_confirm_t := 0.0
var _fade_t := 0.0
var _fade_start_ms := 0
## 教程里标出的"可生火位置"（缓存，2 s 刷新）。
var _fire_spot := Vector3.INF
## D14 可玩的夜晚
var night: NightCurve
var _night_input: Dictionary = {}
var _bed_minutes := 0.0
## 测试工具用：夜晚播放倍速（smoke test 设大，避免等 75 秒）。
static var night_speed_scale := 1.0
## 手机网页版的触屏层（TouchMode.enabled 时才有）。
var _touch: TouchControls
var _fire_spot_ms := -100000
var _last_minutes := 0.0
var _markers: Array[Node3D] = []
var _deeper_count := 0
var _deeper_points: Array[Vector3] = []
var _cutaway_panel: Control
var _compass: Control
var _forced := false
var _probe_count := 0
var _best_depth := 0.0
## R2（第一次评审）：探测点位置；选址时附近是否探过（报告据此区分"选对了"和"真的观察过"）。
var _probe_points: Array[Vector3] = []
var _site_probed := false
## [GAME] "在选址处探过"的距离（m）：探测点离工地中心不超过这个距离。
const PROBE_NEAR_SITE_M := 6.0
var _zero_t := 0.0
var _startup_frames := 0
var _debug_depth := false
## 保暖层受潮 0..1（CORE_GAMEPLAY §4）。
var dampness := 0.0
var _cloth_label: Label
## 生火仪式：按住 F（Tuning.fire_hold_seconds）——打火棒擦火星、引燃桦树皮；松手取消。
var _fire_hold := -1.0

const MAX_MARKERS := 24
const MAX_DEEPER_LABELS := 3

func setup(p_main: Node3D, p_player: PlayerController, p_weather: WeatherController,
		p_warmth: WarmthController, p_hud: HUDController) -> void:
	main = p_main
	player = p_player
	weather = p_weather
	warmth = p_warmth
	hud = p_hud

func _ready() -> void:
	TouchMode.detect()
	Loc.ensure_cjk_font()
	HoldAssist.load_setting()
	HoldAssist.latched = ""
	tuning = load("res://resources/tuning.tres") as Tuning
	wind = load("res://resources/default_wind.tres") as WindData

	inventory = Inventory.new()
	inventory.max_wood = tuning.max_wood
	inventory.max_bedding = tuning.max_bedding
	gear = LevelState.gear()
	inventory.has_extra_clothing = bool(gear["layer"])
	inventory.wood = int(gear["wood"])
	inventory.bark = int(gear["bark"])
	inventory.bedding = int(gear["bedding"])
	add_child(inventory)
	inventory.changed.connect(_on_inventory_changed)
	_on_inventory_changed.call_deferred()   # 开局自带的材料（S6）也要显示在托盘里

	interaction = InteractionController.new()
	interaction.player = player
	interaction.tuning = tuning
	add_child(interaction)
	interaction.completed.connect(_on_interaction_completed)
	interaction.blocked.connect(func(_it: Interactable, reason: String) -> void: ui.toast(reason))

	spawner = ResourceSpawner.new()
	spawner.name = "Resources"
	spawner.tuning = tuning
	spawner.on_harvest = _on_harvest
	spawner.harvest_blocked = _harvest_blocked
	main.add_child(spawner)

	build = BuildMode.new()
	build.name = "BuildMode"
	build.player = player
	build.visual = player.visual_node
	build.tuning = tuning
	build.wind_from = wind.get_wind_direction_3d()
	main.add_child(build)

	graphics = GraphicsSettings.new()
	add_child(graphics)
	graphics.cycled.connect(func(l: int) -> void: if ui: ui.toast(Loc.t("Graphics: %s  [F10]") % graphics.level_name(), 2.5))

	prints = Footprints.new()
	prints.name = "Footprints"
	prints.player = player
	main.add_child(prints)

	# 头灯：日落后自动点亮（真实登山者的标配；保证暮色赶工仍可玩）
	headlamp = SpotLight3D.new()
	headlamp.name = "Headlamp"
	headlamp.light_color = Color(0.95, 0.97, 1.0)
	headlamp.light_energy = 0.0
	headlamp.spot_range = 16.0
	headlamp.spot_angle = 38.0
	headlamp.spot_attenuation = 0.8
	headlamp.shadow_enabled = false
	headlamp.position = Vector3(0, 1.6, 0.2)
	headlamp.rotation = Vector3(deg_to_rad(-28.0), PI, 0)
	player.visual_node.add_child(headlamp)

	spindrift = Spindrift.new()
	spindrift.name = "Spindrift"
	spindrift.follow = player
	main.add_child(spindrift)

	snowfall = Snowfall.new()
	snowfall.name = "Snowfall"
	snowfall.follow = player
	main.add_child(snowfall)

	audio = AmbientAudio.new()
	audio.name = "AmbientAudio"
	audio.gust_frequency = wind.gust_frequency
	audio.wind_strength = clampf(wind.speed_kmh / 40.0, 0.2, 1.2)
	add_child(audio)

	ui = GameUI.new()
	add_child(ui)
	_on_inventory_changed()

	callouts = get_tree().get_first_node_in_group("world_callouts") as WorldCallouts
	if callouts:
		callouts.rect_provider = _hud_rects
	rig = get_tree().get_first_node_in_group("camera_rig") as IsometricCameraRig
	_figure_home = player.visual_node.position
	_cutaway_panel = hud.get_parent().get_node_or_null("ShelterCutawayPanel") as Control
	_compass = hud.get_node_or_null("Compass") as Control
	if _cutaway_panel:
		_cutaway_panel.visible = false
	var instr := hud.get_node_or_null("Instructions") as Label
	if instr:
		instr.text = Loc.t("[WASD] Move   [Space] Probe   [E] Gather / Build   [B] Build   [F] Fire   [N] Sleep   [I] Intel   [H] Field guide")

	_apply_static_labels()
	GameInput.ensure_joypad()
	if TouchMode.enabled:
		_touch = TouchControls.new()
		_touch.director = self
		add_child(_touch)
	warmth.auto_update = false
	warmth.has_extra_clothing = bool(gear["layer"])
	warmth.set_body_warmth(tuning.warmth_max * 0.92)
	player.probe_activated.connect(_on_probe)
	_last_minutes = weather.current_time_minutes
	_enter_briefing()

# ------------------------------------------------------------------ 状态

func _enter_briefing() -> void:
	state = State.BRIEFING
	player.controls_enabled = false
	interaction.enabled = false
	_saved_time_scale = weather.time_scale
	weather.time_scale = 0.0
	ui.show_briefing(true, weather.forecast_text(), _briefing_intro(), _level_info())
	ui.set_intel(_intel_tabs())
	_set_world_hud(false)
	_update_hint()

## 简报时只留一个视觉焦点：隐藏体温卡 / 环境卡 / 罗盘 / 世界标签 / 背包托盘（第三次评审 UI）。
func _set_world_hud(on: bool) -> void:
	var hud_layer := hud.get_parent()
	if hud_layer:
		hud_layer.set("visible", on)
	ui.set_day_hud(on)

func start_game() -> void:
	SessionLog.start({"valley": TerrainHeight.SEED, "weather": weather.weather_kind, "full_day": full_day, "lang": Loc.lang,
		"level": LevelState.level.index if LevelState.active() else -1, "stage": LevelState.stage, "map": LevelState.map_index,
		"seed": LevelState.game_seed, "terrain": TerrainHeight.RECIPE.describe()})
	state = State.PLAYING
	ui.show_briefing(false)
	if ui.intel_open():
		ui.toggle_intel()
	_set_world_hud(true)
	player.controls_enabled = true
	interaction.enabled = true
	weather.time_scale = _saved_time_scale
	if LevelState.active() and not LevelState.level.is_free():
		ui.toast(Loc.t(LevelState.level.lesson), 7.0)
	else:
		ui.toast(Loc.t("Probe the snow [Space]: its depth decides which shelter you can build."), 6.0)

func _sleep(forced: bool) -> void:
	if state != State.PLAYING:
		return
	_forced = forced
	if build.active:
		build.exit()
	_release_focus()
	session.reset()
	_mark("sleep")
	state = State.NIGHT_FADE
	_fade_t = 0.0
	_fade_start_ms = Time.get_ticks_msec()
	player.controls_enabled = false
	interaction.enabled = false
	weather.time_scale = 0.0
	ui.set_prompt("", 0.0)
	ui.toast(Loc.t("Night falls...") if forced else Loc.t("You crawl in and try to sleep..."), tuning.night_fade_seconds)

## 完工雪洞的剖面贴图（独立 SubViewport），其余情况返回 null。
func _vignette_texture() -> Texture2D:
	if site == null or not site.is_complete() or not (site.preset_id in ["RaisedCave", "BasicCave"]):
		return null
	if _cutaway_panel == null:
		return null
	var vp := _cutaway_panel.get_node_or_null("Margin/VBox/ViewportContainer/SubViewport") as SubViewport
	if vp == null:
		return null
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return vp.get_texture()

func _timeline_text() -> String:
	var names := {"probe": Loc.t("first probe"), "site": Loc.t("site marked"), "done": Loc.t("shelter done"),
		"fire": Loc.t("fire lit"), "sleep": Loc.t("bed"), "up": Loc.t("got up")}
	var sm := int(weather.day_start_minutes)
	var start := "%02d:%02d" % [sm / 60, sm % 60]
	var events: Array = [[start, Loc.t("start")], [weather.sunset_clock(), Loc.t("sunset")]]
	for e in _timeline:
		events.append([e[1], names.get(e[0], e[0])])
	# 时刻 "HH:MM" 按字典序即时间序；日落按真实先后插入，玩家能看出自己是日落前还是后完工
	events.sort_custom(func(x, y) -> bool: return String(x[0]) < String(y[0]))
	var parts: Array[String] = []
	for e in events:
		parts.append("%s %s" % [e[1], e[0]])
	return Loc.t("Your day: ") + "  →  ".join(parts)

# ------------------------------------------------------------------ D14 可玩的夜晚

## 黑屏渐变之后进入夜晚：用入睡那一刻的事实建 NightCurve，世界变暗，时钟继续走过午夜。
func _begin_night() -> void:
	_night_input = night_input()
	_night_input["night_snowfall"] = weather.atmosphere.snowfall
	night = NightCurve.new(_night_input, tuning)
	_bed_minutes = weather.current_time_minutes
	SessionLog.log_event("bed", weather.clock_string(), {"warmth": int(night.warmth), "fire": night.has_fire_place, "dampness": snappedf(float(_night_input.get("dampness", 0.0)), 0.01)})
	state = State.NIGHT
	ui.show_vignette(null, "", 0.0)
	ui.set_fade(0.0)
	ui.set_prompt("", 0.0)
	headlamp.light_energy = 0.0
	ui.show_night_hud(true)
	ui.set_day_hud(false)
	var hud_layer := hud.get_parent()
	if hud_layer:
		hud_layer.set("visible", false)   # 白天的体温卡 / 环境卡 / 罗盘：夜里由夜间面板取代

func _tick_night(delta: float) -> void:
	if night == null:
		return
	if _touch != null and _touch.portrait:
		return   # 手机竖着时夜晚也停住，转回来再继续
	if not night.waiting():
		var rate := night.duration / maxf(tuning.night_real_seconds, 1.0) * night_speed_scale
		if Input.is_action_pressed("probe"):
			rate *= tuning.night_fast_multiplier
		var ev := night.play(rate * delta)
		weather.current_time_minutes = _bed_minutes + minf(night.playhead, night.duration)
		weather.advance_minutes(0.0)
		_sync_night_fire()
		if ev != "":
			_show_night_event(ev)
		elif night.is_over():
			_end_night()
			return
	ui.update_night_hud(weather.minutes_to_sunset() > 0.0, weather.clock_string(), int(night.warmth), night.curve + PackedVector2Array([Vector2(night.minute, night.warmth)]),
		night.duration, night.timeline.filter(func(e): return e["kind"] == "event"), night.minute)

## 夜里的火：模型说烧着就烧着、说灭了就灭（倒棚反射火 / 睡前篝火）。
func _sync_night_fire() -> void:
	for f in get_tree().get_nodes_in_group("campfires"):
		var c := f as Campfire
		if night.has_fire_place:
			c.fuel_minutes = night.fire_minutes
			c.lit = night.fire_minutes > 0.0
		else:
			c.fuel_minutes = 0.0
			c.lit = false
		c._apply_lit()

func _show_night_event(ev: String) -> void:
	headlamp.light_energy = 2.5   # 醒了：打开头灯
	SessionLog.log_event("wake", weather.clock_string(), {"why": ev, "warmth": int(night.warmth)})
	var labels: Array = []
	for a in night.available_actions():
		labels.append(NightText.action_label(a, night, tuning))
	var body := NightText.event_body(ev, night.warmth)
	var note := NightText.fire_note(night)
	if note != "" and ev != NightCurve.EV_FIRE_DYING and ev != NightCurve.EV_FIRE_OUT:
		body += "\n" + note
	ui.show_night_event(Loc.t("%s — %s") % [weather.clock_string(), NightText.event_title(ev)], body, labels)
	audio.play_sfx("probe")

func _night_act(a: String) -> void:
	if night == null or not night.act(a):
		return
	SessionLog.log_event("night_act", weather.clock_string(), {"act": a, "warmth": int(night.warmth)})
	if a == NightCurve.ACT_SLEEP:
		ui.hide_night_event()
		headlamp.light_energy = 0.0
		return
	if a == NightCurve.ACT_GET_UP:
		_get_up()
		return
	ui.toast(NightText.action_done(a), 2.0)
	weather.current_time_minutes = _bed_minutes + night.minute
	weather.advance_minutes(0.0)
	_sync_night_fire()
	_show_night_event(night.pending_event())

## 白天醒来、起床（2026-11-07 试玩报告 P1）：这一觉到此为止，回到白天。体温、受潮、时钟、火都接着夜里模型走到的状态；
## 夜里烧掉的柴从工地堆 / 背包里扣掉。之后可以烘干衣服、添柴，再按 N 重新睡（新的一夜从那一刻算起）。
func _get_up() -> void:
	var up_at := _bed_minutes + night.minute
	var burned := int(round(float(_night_input.get("firewood_logs", 0.0)))) - night.stock_logs
	if night.has_fire_place and burned > 0:
		if site != null:
			site.pile.spend({"wood": mini(burned, site.pile.total("wood", inventory))}, inventory)
		else:
			inventory.add("wood", -mini(burned, inventory.wood))
	warmth.body_warmth = night.warmth
	dampness = night.dampness
	SessionLog.log_event("get_up", weather.clock_string(), {"warmth": int(night.warmth), "dampness": snappedf(dampness, 0.01),
		"light_left": int(night.light_left()), "logs_burned": maxi(burned, 0)})
	night = null
	_night_input = {}
	_forced = false
	_zero_t = 0.0
	ui.hide_night_event()
	ui.show_night_hud(false)
	ui.set_fade(0.0)
	_set_world_hud(true)
	weather.current_time_minutes = up_at
	weather.advance_minutes(0.0)
	_last_minutes = weather.current_time_minutes
	_timeline = _timeline.filter(func(e): return e[0] != "sleep")
	_mark("up")
	state = State.PLAYING
	player.controls_enabled = true
	interaction.enabled = true
	weather.time_scale = _saved_time_scale
	var msg := Loc.t("You get up. About %d minutes of light left.") % int(weather.minutes_to_sunset())
	if GameRules.clothing_state(dampness, tuning) != "dry":
		msg += " " + Loc.t("Dry your clothes by a fire, then [N] sleep again.")
	ui.toast(msg, 6.0)

func _end_night() -> void:
	ui.hide_night_event()
	ui.show_night_hud(false)
	ui.set_fade(1.0)
	_show_report(night.result())

func _show_report(night_res: Dictionary = {}) -> void:
	state = State.REPORT
	var input := _night_input if not _night_input.is_empty() else night_input()
	if night_res.is_empty():
		night_res = NightCurve.run(input, tuning, "sleep")
	# 本图实测最深雪（报告教训只在真的挖得了雪洞时才建议"去找深雪挖洞"）
	input["map_max_snow_m"] = float(SnowField.map_facts(tuning)["max_depth"])
	var report := NightSimulator.evaluate(input, tuning)
	var data := NightReportText.build(report, input, tuning)
	# D14：结局由整夜体温曲线决定；6 维留作"热量从哪里漏掉"
	var wet := NightSimulator.wet_fraction(float(input.get("dampness", 0.0)), tuning) > 0.5
	data["outcome"] = String(night_res["outcome"])
	data["title"] = NightText.title(night_res, wet)
	data["conclusion"] = NightText.conclusion(night_res, NightText.heat_leak(input, night_res, String(report["details"].get("min_axis", "heat")), tuning))
	data["night_curve"] = night_res["curve"]
	data["night_duration"] = night.duration if night != null else tuning.night_duration_hours * 60.0
	data["night_events"] = (night_res["timeline"] as Array).filter(func(e): return e["kind"] == "event")
	var extra: Array[String] = [NightText.timeline(night_res, _bed_minutes if _bed_minutes > 0.0 else weather.current_time_minutes)]
	for line in [NightText.three_comforts(input, night_res, tuning), NightText.boots_line(night_res)]:
		if line != "":
			extra.append(line)
	data["night_timeline"] = "\n".join(extra)
	# Heat 一行按整夜实际发生的写（旧模型假设"有柴就烧到天亮"；现在火要醒来添才烧得下去）
	if bool(night_res.get("had_fire", false)) and data["rows"].size() >= 6:
		var out_at := float(night_res["fire_out_at"])
		data["rows"][5]["note"] = Loc.t("You kept the fire going until dawn.") if out_at < 0.0 \
			else Loc.t("The fire went out at %s and nobody fed it; the rest of the night was cold.") % NightText.clock(_bed_minutes, out_at)
	if LevelState.active() and not LevelState.level.is_free():
		data["level_takeaway"] = NightReportText.level_takeaway(LevelState.level.theme, LevelState.target_presets(),
			String(input.get("shelter_type", "None")), String(data["outcome"]), SnowField.map_facts(tuning),
			{"chapter": LevelState.level.index, "stage": LevelState.stage, "wind_kmh": float(input.get("wind_speed_kmh", tuning.wind_speed_kmh)),
			"probed_site": _site_probed, "probe_count": _probe_count, "entrance_deg": float(input.get("wind_angle_diff", 180.0)),
			"night_temp_c": weather.night_temp_c(), "start_minutes": int(weather.day_start_minutes), "sunset_minutes": weather.sunset_minutes}, tuning)
	var name_ := Loc.t("None — slept in the open")
	if site:
		name_ = Loc.t("%s (%d/5 stages)") % [Loc.t(site.builder.active_preset().display_name), site.stage()]
	data["timeline"] = _timeline_text()
	ui.show_report(data, name_)
	SessionLog.log_event("report", weather.clock_string(), {"outcome": String(data["outcome"]), "preset": String(input.get("shelter_type", "None")), "scores": report["scores"], "min_axis": String(report["details"].get("min_axis", "")), "forced": _forced, "bed_warmth": int(warmth.body_warmth), "min_warmth": int(round(float(night_res.get("min_warmth", -1.0)))), "end_warmth": int(round(float(night_res.get("end_warmth", -1.0)))), "wakes": int(night_res.get("wakes", 0)), "cause": String(night_res.get("cause", ""))})
	SessionLog.close()
	var lvl := LevelState.level.index if LevelState.active() else 0
	Records.save(Records.key_for(String(input.get("shelter_type", "None")), lvl, full_day, LevelState.stage), String(data["outcome"]), int(round(float(report["details"].get("weighted_average", 0.0)))))
	_unlock_after_report(lvl, String(data["outcome"]))
	_learn_after_report(String(input.get("shelter_type", "None")), String(data["outcome"]))


# ------------------------------------------------------------------ 输入

func _joy_to_key(btn: JoyButton) -> Key:
	return GameInput.joy_to_key(btn, state, build.active or session.focused())

func _unhandled_input(event: InputEvent) -> void:
	# 按住辅助：轻点探针 / 交互即锁存（建造模式里 E 是放置，不锁存）
	if HoldAssist.enabled and state == State.PLAYING and not build.active:
		if event.is_action_pressed("probe"):
			HoldAssist.on_pressed("probe")
		elif event.is_action_pressed("interact"):
			HoldAssist.on_pressed("interact")
	var k: Key = KEY_NONE
	if event is InputEventJoypadButton and event.pressed:
		k = _joy_to_key((event as InputEventJoypadButton).button_index)
		if k == KEY_NONE:
			return
	elif event is InputEventKey and event.pressed and not event.echo:
		k = (event as InputEventKey).keycode
	else:
		return
	if k == KEY_F10:
		graphics.cycle()
		return
	if k == KEY_F3:
		_debug_depth = not _debug_depth
		var tb := get_tree().get_first_node_in_group("terrain")
		if tb:
			tb.set_debug_depth(_debug_depth)
		ui.toast("Snow depth heatmap: grey <0.3 · blue <0.9 · green <1.5 · yellow <2.0 · orange ≥2.0 m  [F3]" if _debug_depth else "Heatmap off  [F3]", 4.0)
		return
	if k == KEY_F9:
		ui.toast(Loc.t("Hold assist ON — tap once to probe / work / light fire  [F9]") if HoldAssist.toggle() else Loc.t("Hold assist OFF  [F9]"), 2.5)
		return
	if k == KEY_F11:
		graphics.toggle_fullscreen()
		return
	if k == KEY_MINUS or k == KEY_EQUAL:
		var sc := graphics.step_ui_scale(-1 if k == KEY_MINUS else 1)
		ui.toast(Loc.t("UI size %d%%  [-] [=]") % int(round(sc * 100.0)), 1.5)
		return
	if k == KEY_M:
		ui.toast(Loc.t("Sound off  [M]") if graphics.toggle_mute() else Loc.t("Sound on  [M]"), 1.5)
		return
	match state:
		State.BRIEFING:
			if k == KEY_I or k == KEY_H:
				ui.toggle_intel("brief" if k == KEY_I else "guide")
			elif ui.intel_open() and k in [KEY_LEFT, KEY_RIGHT, KEY_TAB]:
				ui.intel_step(-1 if k == KEY_LEFT or Input.is_key_pressed(KEY_SHIFT) else 1)
			elif ui.intel_open() and k == KEY_ESCAPE:
				ui.toggle_intel()
			elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_1:
				start_game()
			elif k == KEY_2 and (not LevelState.active() or LevelState.level.is_free()):
				full_day = true
				weather.current_time_minutes = float(tuning.full_day_start_minutes)
				weather.day_start_minutes = weather.current_time_minutes
				weather.advance_minutes(0.0)
				_last_minutes = weather.current_time_minutes
				start_game()
			elif k == KEY_LEFT or k == KEY_RIGHT:
				_switch_chapter(-1 if k == KEY_LEFT else 1)
			elif k == KEY_UP or k == KEY_DOWN:
				_switch_stage(-1 if k == KEY_DOWN else 1)
			elif k == KEY_N:
				_new_map()
			elif k == KEY_L:
				_toggle_lang()
				ui.show_briefing(true, weather.forecast_text(), _briefing_intro(), _level_info())
		State.NIGHT:
			if night != null and night.waiting():
				var acts := night.available_actions()
				if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_N:
					_night_act(NightCurve.ACT_SLEEP)
				elif k >= KEY_1 and k <= KEY_9 and int(k - KEY_1) < acts.size():
					_night_act(acts[int(k - KEY_1)])
		State.REPORT:
			if k == KEY_R:
				_restart()
			elif (k == KEY_ENTER or k == KEY_KP_ENTER) and _next_stage().x >= 0:
				_go_to(_next_stage().x, _next_stage().y)
		State.PAUSED:
			match k:
				KEY_ESCAPE, KEY_P: _set_paused(false)
				KEY_R: _restart()
				KEY_Q: get_tree().quit()
				KEY_C: ui.toggle_credits()
		State.PLAYING:
			if ui.intel_open() and (k == KEY_ESCAPE or (k == KEY_TAB and not build.active)):
				if k == KEY_ESCAPE:
					ui.toggle_intel()
				else:
					ui.intel_step(-1 if Input.is_key_pressed(KEY_SHIFT) else 1)
				return
			if session.focused():
				match k:
					KEY_B, KEY_ESCAPE: _step_back()
					KEY_R: _replace_site()
					KEY_H: ui.toggle_intel("guide")
					KEY_I: ui.toggle_intel("brief")
					KEY_L: _toggle_lang()
				return
			if k == KEY_ESCAPE and not build.active:
				_set_paused(true)
				return
			if build.active:
				match k:
					KEY_T: build.toggle_roof()
					KEY_2: build.toggle_vents()
					KEY_TAB: build.cycle_preset()
					KEY_R: build.rotate_entrance()
					KEY_B, KEY_ESCAPE: _exit_build()
				return
			match k:
				KEY_L: _toggle_lang()
				KEY_H: ui.toggle_intel("guide")
				KEY_I: ui.toggle_intel("brief")
				KEY_B:
					if _in_shelter:
						_leave_shelter()
					else:
						_enter_build()
				KEY_F:
					if _in_shelter:
						ui.toast(Loc.t("Step outside to light or feed a fire."))
					else:
						_begin_fire()
				KEY_N: _request_sleep()

## 环境卡提示行（V3）。简报时也刷新一次，否则显示的是 hud.tscn 的空默认值。
func _update_hint() -> void:
	if hud and hud.has_node("TopRightCard/VBox/HintLabel"):
		var hint := hud.get_node("TopRightCard/VBox/HintLabel") as Label
		hint.text = GameRules.tip_for(weather.minutes_to_sunset(), weather.sun_elevation_deg,
			warmth.body_warmth, site != null and site.stage() > 0, site != null and site.is_complete(), tuning,
			GameRules.wind_word(wind.from_octant()))

# ------------------------------------------------------------------ 关卡（D12 / L4）

## 简报页装备一行（S6）。
func _gear_text() -> String:
	var items: Array[String] = []
	match GameRules.dig_tool(gear):
		"shovel": items.append(Loc.t("snow shovel"))
		"pot": items.append(Loc.t("NO shovel — dig with your pot, %dx slower") % int(round(tuning.no_shovel_dig_factor)))
		_: items.append(Loc.t("NO shovel or pot — dig by hand, %dx slower and wetter") % int(round(tuning.bare_hands_dig_factor)))
	items.append(Loc.t("extra warm layer") if bool(gear["layer"]) else Loc.t("NO extra layer"))
	if bool(gear["pad"]):
		items.append(Loc.t("sleeping pad"))
	if bool(gear.get("hides", false)):
		items.append(Loc.t("caribou hides"))
	var carried: Array[String] = []
	if int(gear["bark"]) > 0: carried.append(Loc.t("%d birch bark") % int(gear["bark"]))
	if int(gear["wood"]) > 0: carried.append(Loc.t("%d dry wood") % int(gear["wood"]))
	if int(gear["bedding"]) > 0: carried.append(Loc.t("%d bedding") % int(gear["bedding"]))
	if not carried.is_empty():
		items.append(", ".join(carried))
	return Loc.t("Gear: %s") % " · ".join(items)

## D13 §9.2：用某种庇护所熬过一夜 = 学会它（只在关卡模式里记；测试 / 机器人基准不写）。
func _learn_after_report(preset: String, outcome: String) -> void:
	if not LevelState.active():
		return
	if Records.learn_shelter(preset, outcome):
		var name_ := String(Records.preset_names().get(preset, preset))
		ui.toast(Loc.t("You've learned the %s — you can use it on any level now.") % name_, 7.0)
		ui.add_report_line(Loc.t("Learned: %s") % name_)

# ------------------------------------------------------------------ 章节 × 阶（D13 / S3）

## 重开：章节模式 = 同一阶、同一张图再来一次（换图用简报页 [N]）；否则换到下一个山谷。再重载场景。
func _restart() -> void:
	if LevelState.active():
		LevelState.begin(LevelState.level.index, LevelState.game_seed, LevelState.stage, LevelState.map_index)
		get_tree().reload_current_scene()
		return
	var seeds: Array = TerrainHeight.VALLEY_SEEDS
	TerrainHeight.SEED = seeds[(seeds.find(TerrainHeight.SEED) + 1) % seeds.size()]
	get_tree().reload_current_scene()

## 简报页的章节 / 阶信息（GameUI 渲染）；不在关卡模式时为空。
func _level_info() -> Dictionary:
	if not LevelState.active():
		return {}
	var ch := LevelState.level.index
	var chips: Array = []
	for idx in LevelState.ORDER:
		chips.append({"label": Loc.t("Free") if idx == 0 else str(idx), "current": idx == ch,
			"unlocked": Records.stage_unlocked(idx, 1)})
	var stage_chips: Array = []
	if ch >= 1:
		for st in range(1, LevelState.STAGES + 1):
			stage_chips.append({"label": str(st), "current": st == LevelState.stage, "unlocked": Records.stage_unlocked(ch, st)})
	var locked_hint := ""
	if ch >= 1:
		var hi := Records.chapter_highest(ch)
		if hi < LevelState.STAGES:
			locked_hint = Loc.t("COLD or SAFE on stage %d opens stage %d.") % [hi, hi + 1]
		if ch < LevelState.LEVEL_COUNT and not Records.stage_unlocked(ch + 1, 1):
			locked_hint += ("   ·   " if locked_hint != "" else "") + Loc.t("Pass stage %d to open chapter %d.") % [LevelState.CHAPTER_GATE_STAGE, ch + 1]
	var names := Records.preset_names()
	var learned := Records.learned_shelters()
	var known: Array[String] = []
	var new_here: Array[String] = []
	for p in LevelState.available_presets(learned):
		if p in learned:
			known.append(String(names.get(p, p)))
		else:
			new_here.append(String(names.get(p, p)))
	var shelters := Loc.t("Shelters you know: %s") % ", ".join(known)
	if not new_here.is_empty():
		shelters += "\n" + Loc.t("New here: %s") % ", ".join(new_here)
	shelters += "\n\n" + Loc.t("Survive a night in a shelter and you've learned it — use it on any level after that.")
	var title := Loc.t("Free play") if ch == 0 else Loc.t("Chapter %d · Stage %d  (%d of 50)") % [ch, LevelState.stage, LevelState.global_stage()]
	return {"index": ch, "title": title, "lesson": Loc.t(LevelState.level.lesson), "seed": LevelState.game_seed, "conditions": _conditions_line(),
		"map": LevelState.map_index + 1, "shelters_only": shelters, "chips": chips, "stage_chips": stage_chips,
		"best": Records.stage_best(ch, LevelState.stage) if ch >= 1 else Records.text(),
		"locked_hint": locked_hint, "full_day_option": ch == 0}

## 简报页 ←/→：换章（到该章已开放的最高阶），↑/↓：本章内换阶，[N]：本阶换一张新图。都会重载场景。
func _switch_chapter(step: int) -> void:
	if not LevelState.active():
		return
	var pos := LevelState.ORDER.find(LevelState.level.index)
	for k in range(1, LevelState.ORDER.size()):
		var idx: int = LevelState.ORDER[posmod(pos + step * k, LevelState.ORDER.size())]
		if Records.stage_unlocked(idx, 1):
			_go_to(idx, maxi(Records.chapter_highest(idx), 1) if idx >= 1 else 1)
			return

func _switch_stage(step: int) -> void:
	if not LevelState.active() or LevelState.level.is_free():
		return
	var ch := LevelState.level.index
	var st := LevelState.stage + step
	if st >= 1 and st <= LevelState.STAGES and Records.stage_unlocked(ch, st):
		_go_to(ch, st)

func _new_map() -> void:
	if not LevelState.active():
		return
	var ch := LevelState.level.index
	var k := Records.next_map(ch, LevelState.stage)
	LevelState.begin(ch, -1, LevelState.stage, k)
	get_tree().reload_current_scene()

func _go_to(ch: int, st: int) -> void:
	Records.set_last_selection(ch, st)
	LevelState.begin(ch, -1, st, Records.map_index(ch, st))
	get_tree().reload_current_scene()

## 报告页 [Enter]：本章下一阶；第 10 阶之后 = 下一章第 1 阶（第 5 章之后 = 自由模式）。Vector2i(-1, -1) = 没有。
func _next_stage() -> Vector2i:
	if not LevelState.active() or LevelState.level.is_free():
		return Vector2i(-1, -1)
	var ch := LevelState.level.index
	var st := LevelState.stage
	if st < LevelState.STAGES and Records.stage_unlocked(ch, st + 1):
		return Vector2i(ch, st + 1)
	var nch := ch + 1 if ch < LevelState.LEVEL_COUNT else 0
	if Records.stage_unlocked(nch, 1):
		return Vector2i(nch, 1)
	return Vector2i(-1, -1)

func _unlock_after_report(ch: int, outcome: String) -> void:
	if ch < 1:
		return
	var news := Records.record_stage_result(ch, LevelState.stage, outcome)
	var msgs: Array[String] = []
	if int(news["stage"]) > 0:
		msgs.append(Loc.t("Stage %d unlocked!") % int(news["stage"]))
	if int(news["chapter"]) > 0:
		msgs.append(Loc.t("Chapter %d unlocked!") % int(news["chapter"]))
	if bool(news["free"]):
		msgs.append(Loc.t("Free play unlocked!"))
	if not msgs.is_empty():
		ui.toast("  ".join(msgs), 6.0)
	if _next_stage().x >= 0 and LevelState.unlocks_next(outcome):
		ui.add_report_line(Loc.t("[Enter] next stage   ·   [R] same place again"))
	elif not LevelState.unlocks_next(outcome):
		ui.add_report_line(Loc.t("Reach COLD or SAFE to unlock the next stage.  [R] try the same place again"))

## 简报第一句：本局真实的开局时刻、气温、风向风速、日落与剩余天光（关卡会改这些）。
func _briefing_intro() -> String:
	var sm := int(weather.day_start_minutes)
	var hours := maxi(int(round(weather.minutes_to_sunset() / 60.0)), 1)
	return (Loc.t("January 14, %s. %d °C, wind from the %s at %d km/h; the sun sets at %s.\n") % [
		"%02d:%02d" % [sm / 60, sm % 60], int(round(weather.current_temp_c())),
		GameRules.wind_word(wind.from_octant()), int(round(weather.current_wind_kmh())), weather.sunset_clock()]) \
		+ (Loc.t("You have about an hour of light to read the land, gather what you need and build a shelter for the night.\n\n") if hours == 1
			else Loc.t("You have about %d hours of light to read the land, gather what you need and build a shelter for the night.\n\n") % hours)

## 首屏的一行条件："10:00 · −17 °C · 北风 20 km/h · 日落 16:18（约 6 小时天光）"。
func _conditions_line() -> String:
	var sm := int(weather.day_start_minutes)
	var hours := maxi(int(round(weather.minutes_to_sunset() / 60.0)), 1)
	return Loc.t("%s  ·  %d °C  ·  wind from the %s, %d km/h  ·  sunset %s, ~%d h of light") % [
		"%02d:%02d" % [sm / 60, sm % 60], int(round(weather.current_temp_c())), GameRules.wind_word(wind.from_octant()),
		int(round(weather.current_wind_kmh())), weather.sunset_clock(), hours]

## [I] 情报面板各页（第三次评审 UI：首屏之外的全部细节都在这里）。
func _intel_tabs() -> Array:
	var info := _level_info()
	var lesson := String(info.get("lesson", ""))
	var brief := (lesson + "\n\n" if lesson != "" else "") + _briefing_intro() + \
		Loc.t("Read the land: trees lean away from the wind, snow piles up on leeward slopes, standing dead trees are dry fuel — ") + \
		Loc.t("and the shadows tell you how much daylight is left.")
	var conditions := valley_name() + "\n" + _conditions_line() + "\n\n" + weather.forecast_text()
	var kit := _gear_text()
	match GameRules.dig_tool(gear):
		"shovel": kit += "\n\n" + Loc.t("A shovel digs at full speed. Digging still makes you sweat — dry off by a fire before bed.")
		_: kit += "\n\n" + Loc.t("Without a shovel every snow shelter takes much longer — a trench or a tree well may be all the day allows.")
	var shelters := String(info.get("shelters_only", Loc.t("All shelters are open in free play.")))
	var map := Loc.t("Map %d  ·  Seed %d") % [int(info.get("map", 1)), int(info.get("seed", LevelState.game_seed))] + "\n" + \
		Loc.t("Terrain: %s") % TerrainHeight.RECIPE.describe() + "\n\n" + Loc.t("[N] on this screen gives the same stage a new map.")
	if String(info.get("locked_hint", "")) != "":
		map += "\n" + String(info["locked_hint"])
	var controls := Loc.t("[WASD] move    [Space] hold to probe snow depth    [E] hold to gather / build    [F10] graphics\n") + \
		Loc.t("[B] build mode    [F] light fire / add wood    [N] sleep    [V] camera    [Wheel] zoom") + "\n" + \
		Loc.t("[I] intel    [H] field guide    [L] language    [M] sound    [-] [=] UI size    [Esc] pause") + "\n\n" + \
		Loc.t("Night: [Enter] sleep on    [1]–[5] act when you wake    hold [Space] to speed up")
	var records := String(info.get("best", Records.text()))
	if records == "":
		records = Loc.t("No record on this stage yet.")
	return [
		{"key": "brief", "title": Loc.t("Brief"), "body": brief},
		{"key": "conditions", "title": Loc.t("Conditions"), "body": conditions},
		{"key": "kit", "title": Loc.t("Kit"), "body": kit},
		{"key": "shelters", "title": Loc.t("Shelters"), "body": shelters},
		{"key": "map", "title": Loc.t("Map"), "body": map},
		{"key": "guide", "title": Loc.t("Field guide"), "body": GameUI.field_guide_text()},
		{"key": "controls", "title": Loc.t("Controls"), "body": controls},
		{"key": "records", "title": Loc.t("Records"), "body": records},
	]

func valley_name() -> String:
	return Loc.t("Valley %d of %d") % [TerrainHeight.VALLEY_SEEDS.find(TerrainHeight.SEED) + 1, TerrainHeight.VALLEY_SEEDS.size()]

func _set_paused(on: bool) -> void:
	state = State.PAUSED if on else State.PLAYING
	player.controls_enabled = not on and not session.focused()
	interaction.enabled = not on
	weather.time_scale = 0.0 if on else _saved_time_scale
	ui.show_pause(on)

## [L]：English ⇄ 中文（保存到 user://settings.cfg），重建缓存的面板与静态标签。
func _toggle_lang() -> void:
	Loc.set_lang("en" if Loc.is_zh() else "zh")
	ui.relocalize()
	ui.set_intel(_intel_tabs())
	_apply_static_labels()
	_on_inventory_changed()
	ui.toast("中文" if Loc.is_zh() else "English", 1.5)

func _apply_static_labels() -> void:
	var instr := hud.get_node_or_null("Instructions") as Label
	if instr:
		instr.text = Loc.t("[WASD] Move   [Space] Probe   [E] Gather / Build   [B] Build   [F] Fire   [N] Sleep   [I] Intel   [H] Field guide")
	var warm := hud.get_parent().get_node_or_null("HUDWarmth")
	if warm:
		var title := warm.find_child("TitleLabel", true, false) as Label
		if title:
			title.text = Loc.t("BODY WARMTH")
		var cloth := warm.find_child("ClothingLabel", true, false) as Label
		if cloth:
			cloth.text = Loc.t("▣ CLOTHING · DRY LAYER")
	if callouts and callouts.has_callout("deadwood"):
		callouts.remove_callout("deadwood")

func _request_sleep() -> void:
	var done := site != null and site.is_complete()
	if _sleep_confirm_t > 0.0:
		_sleep(false)
		return
	var lines: Array[String] = []
	if not done:
		var have := Loc.t("no shelter") if site == null else Loc.t("a shelter only %d/5 done") % site.stage()
		lines.append(Loc.t("Sleep now, with %s?") % have)
	var wet := wet_sleep_forecast()
	if not wet.is_empty():
		lines.append(Loc.t("Your clothes are %s. Tonight your warmth would fall to about %d if you sleep through, about %d if you get up and move each time you wake. With dry clothes: about %d. Dry off by a fire first.") \
			% [Loc.t(String(wet["state"])), int(wet["wet_sleep"]), int(wet["wet_smart"]), int(wet["dry_min"])])
	if lines.is_empty():
		_sleep(false)
		return
	var secs := 4.0 if wet.is_empty() else 7.0
	_sleep_confirm_t = secs
	lines.append(Loc.t("Press [N] again to sleep anyway."))
	ui.toast(" ".join(lines), secs)
	SessionLog.log_event("sleep_warn", weather.clock_string(), {"done": done, "wet": wet})

## 睡前提醒（2026-11-07 试玩报告 P1）：按入睡这一刻的真实过夜模型，湿衣 / 干衣各算两种过法——一觉睡到天亮（"sleep"），
## 每次醒来都起来活动、处理（"smart"）。雪沟这类庇护所一觉睡到天亮干衣也会冻到 0，差别只在醒来活动时才看得出来，所以两种都比。
## 任一种过法里湿衣让最低体温低 sleep_wet_warn_drop_w 以上、且湿衣不是 SAFE 才提醒；否则返回 {}。
func wet_sleep_forecast() -> Dictionary:
	if GameRules.clothing_state(dampness, tuning) == "dry":
		return {}
	var inp := night_input()
	inp["night_snowfall"] = weather.atmosphere.snowfall
	var dry := inp.duplicate()
	dry["dampness"] = 0.0
	var r := {}
	for pol in ["sleep", "smart"]:
		r["wet_" + pol] = NightCurve.run(inp, tuning, pol)
		r["dry_" + pol] = NightCurve.run(dry, tuning, pol)
	var m := func(k: String) -> float: return roundf(float(r[k]["min_warmth"]))
	var drop := maxf(m.call("dry_sleep") - m.call("wet_sleep"), m.call("dry_smart") - m.call("wet_smart"))
	var wet_safe := String(r["wet_sleep"]["outcome"]) == "SAFE" and String(r["wet_smart"]["outcome"]) == "SAFE"
	if wet_safe or drop < tuning.sleep_wet_warn_drop_w:
		return {}
	return {"state": GameRules.clothing_state(dampness, tuning), "wet_sleep": m.call("wet_sleep"), "wet_smart": m.call("wet_smart"),
		"dry_min": maxf(m.call("dry_sleep"), m.call("dry_smart")), "drop": drop,
		"wet_outcome": String(r["wet_smart"]["outcome"]), "dry_outcome": String(r["dry_smart"]["outcome"])}

# ------------------------------------------------------------------ 每帧

func _process(delta: float) -> void:
	# 启动守卫：第 30 帧再打开粒子（与 GraphicsSettings 一致，避开 swapchain 重建）
	if _startup_frames < 30:
		_startup_frames += 1
		if _startup_frames == 30:
			for n in get_tree().get_nodes_in_group("deferred_particles"):
				(n as GPUParticles3D).emitting = true
	_sleep_confirm_t = maxf(0.0, _sleep_confirm_t - delta)
	match state:
		State.PLAYING:
			_tick_playing(delta)
		State.NIGHT_FADE:
			# 按真实时间推进（第二次评审：软件渲染下每帧很慢，按帧 delta 累计会让黑屏卡很久）
			_fade_t = float(Time.get_ticks_msec() - _fade_start_ms) / 1000.0
			ui.set_fade(clampf(_fade_t / 1.2, 0.0, 1.0))
			var vignette := _vignette_texture()
			var total := tuning.night_fade_seconds + (3.5 if vignette else 0.0)
			if vignette:
				var a := clampf((_fade_t - 1.4) / 0.8, 0.0, 1.0) * clampf((total - _fade_t) / 0.6, 0.0, 1.0)
				ui.show_vignette(vignette, Loc.t("Outside, the wind howls. Inside, the candle glows and the air stays still."), a)
				audio.shelter_level = 2
			if _fade_t >= total:
				_begin_night()
		State.NIGHT:
			_tick_night(delta)
		State.REPORT:
			ui.set_fade(1.0)

func _tick_playing(delta: float) -> void:
	# 选中的东西刚被释放（采完的草、枝）时，控制器要到它自己的 _process 才换目标：这一帧先清掉
	if not is_instance_valid(interaction.current):
		interaction.current = null
	# 游戏分钟推进 → 火堆燃烧
	var now := weather.current_time_minutes
	var dm := now - _last_minutes
	_last_minutes = now
	if dm > 0.0:
		for f in get_tree().get_nodes_in_group("campfires"):
			(f as Campfire).burn(dm)

	_update_warmth(delta, 1.0)
	_tick_focus(delta)
	# 未完工工地旁按 [E]：回到特写（按住的进度接着算）
	if not session.focused() and site != null and not site.is_complete() and not build.active \
			and interaction.current == site.interactable and Input.is_action_just_pressed("interact"):
		_enter_focus()
	player.working = interaction.progress > 0.0
	player.work_anim = "Chop" if interaction.current and interaction.current.kind in ["deadwood", "wet_log"] else "Dig"
	_tick_fire_hold(delta)
	if player.visual_node is HikerVisual:
		(player.visual_node as HikerVisual).set_body_state(warmth.body_warmth, player.current_speed > 0.3 or player.working)

	# 建造模式
	if build.active:
		var info := Loc.t("Snow %.1f m · slope %d° · %s\n%s") % [build.depth, int(build.slope), build.wind_text(), build.interior_text()]
		if build.near_windbreak:
			info += Loc.t(" · rootball windbreak nearby")
		ui.show_build(true, Loc.t("BUILD — ") + build.display_name(), build.reason, build.valid, info)
		if Input.is_action_just_pressed("interact"):
			_place_site()
	elif not session.focused():
		var p := interaction.prompt_text()
		if player.is_probing:
			ui.set_prompt(Loc.t("Probing snow depth…"), player._probe_t / tuning.probe_seconds if player._probe_t > 0.0 else 0.0)
		elif _fire_hold >= 0.0:
			ui.set_prompt(Loc.t("Striking the ferro rod… keep holding [F]"), _fire_hold / tuning.fire_hold_seconds)
		elif p != "" and interaction.current.blocked_reason() != "":
			ui.set_prompt(Loc.t("Pack full") + "  ·  " + p, 0.0)
		elif p != "":
			ui.set_prompt(Loc.t("Hold [E]  ") + p, interaction.progress)
		else:
			ui.set_prompt("", 0.0)
		_place_prompt()

	if _in_shelter:
		_tick_inside_shelter()
		ui.set_prompt(Loc.t("You're inside  ·  [E] Step outside  ·  [N] Sleep"), 0.0)
		ui.place_prompt(Vector2(get_viewport().get_visible_rect().size.x * 0.5, get_viewport().get_visible_rect().size.y - 40.0))

	# 世界内洞内视图（T4.4）
	if site:
		site.set_inside(site.preset_id in ["RaisedCave", "BasicCave"] and site.stage() >= 1 and _inside_site())

	# 剖面面板：建造雪洞时或身处雪洞内显示（T3.6 触发）
	if _cutaway_panel:
		var show := build.active and build.preset_id in ["RaisedCave", "BasicCave"]
		show = show or (site != null and site.preset_id in ["RaisedCave", "BasicCave"] and site.stage() >= 1 and _inside_site())
		show = show and not session.focused() and not _in_shelter
		_cutaway_panel.visible = show
		if show and _cutaway_panel.has_method("set_progress"):
			_cutaway_panel.set_progress(site.stage() if site != null and not build.active else -1)

	# 提示行：影子就是时钟（V3）
	_update_hint()

	_update_world_callouts()
	var atm := weather.atmosphere
	if _compass:
		_compass.set_sun(atm.sun_azimuth_deg, atm.sun_elevation_deg)
	audio.wind_strength = clampf(atm.wind_kmh / 40.0, 0.2, 1.4)
	ui.set_objective(GameRules.next_objective(_objective_ctx(), tuning))
	# 傍晚降雪：16:00 起渐密（氛围 + 能见度下降的暗示）
	snowfall.intensity = atm.snowfall
	headlamp.light_energy = lerpf(0.0, 3.0, clampf((2.0 - atm.sun_elevation_deg) / 4.0, 0.0, 1.0))

	# 体温归零持续 → 失温倒下（有后果，且报告能解释：Heat 轴 + 入夜体温 0）
	_zero_t = _zero_t + delta if warmth.body_warmth <= 0.01 else 0.0
	if _zero_t >= tuning.collapse_seconds_at_zero:
		ui.toast(Loc.t("Too cold to go on — you curl up where you are."), 4.0)
		_sleep(true)
		return

	# 天黑后宽限期结束 → 强制入夜
	if now >= float(tuning.night_minutes) + tuning.forced_sleep_grace_minutes:
		_sleep(true)

func _objective_ctx() -> Dictionary:
	var ctx := {"probed": _probe_count > 0, "best_depth": _best_depth, "has_site": site != null,
		"minutes_to_sunset": weather.minutes_to_sunset()}
	if site:
		ctx["stage"] = site.stage()
		ctx["complete"] = site.is_complete()
		ctx["preset"] = site.preset_id
		ctx["next_stage"] = site.next_stage_title()
		ctx["missing"] = site.pile.missing_text(site.next_stage_cost(), inventory)
		ctx["needs_vent_stick"] = _needs_vent_stick()
	ctx["clothes_wet"] = GameRules.clothing_state(dampness, tuning) == "wet"
	return ctx

func _inside_site() -> bool:
	if site == null:
		return false
	var a := player.global_position
	var b := site.global_position
	return Vector2(a.x - b.x, a.z - b.z).length() < tuning.shelter_inside_radius_m

func _warmth_inputs() -> Dictionary:
	var pos := player.global_position
	# 挡风统一规则，按人的高度算：风声、风雪、体温流失都用这一个数
	var windbreak := wind_shelter_at(pos, tuning.wind_body_height_m)
	var level := site.shelter_level() if _inside_site() else 0
	var fire := 0.0
	for f in get_tree().get_nodes_in_group("campfires"):
		fire = maxf(fire, (f as Campfire).warmth_at(pos, tuning.fire_warm_radius_m))
	var after_sunset := -weather.minutes_to_sunset()
	var env := 1.0 + 0.6 * clampf(after_sunset / 60.0, 0.0, 1.0)
	return {"windbreak": windbreak, "level": level, "fire": fire, "env": env}

func _update_cloth_label() -> void:
	if _cloth_label == null:
		var warm := hud.get_parent().get_node_or_null("HUDWarmth")
		if warm:
			_cloth_label = warm.find_child("ClothingLabel", true, false) as Label
	if _cloth_label == null:
		return
	_cloth_label.visible = true
	match GameRules.clothing_state(dampness, tuning):
		"dry":
			_cloth_label.text = Loc.t("▣ CLOTHING · DRY LAYER")
			_cloth_label.add_theme_color_override("font_color", Color(0.72, 0.52, 0.24))
		"damp":
			_cloth_label.text = Loc.t("▣ CLOTHING · DAMP — dry it by a fire")
			_cloth_label.add_theme_color_override("font_color", Color(0.45, 0.55, 0.75))
		_:
			_cloth_label.text = Loc.t("▣ CLOTHING · WET — no longer warm")
			_cloth_label.add_theme_color_override("font_color", Color(0.75, 0.25, 0.2))

func _tree_cover(p: Vector3) -> float:
	var forest := get_tree().get_first_node_in_group("forest")
	if forest == null:
		return 0.0
	return GameRules.tree_cover(forest.spruce_points, Vector2(p.x, p.z), 6.0)

func _update_warmth(real_seconds: float, factor: float, min_level: int = 0) -> void:
	var w := _warmth_inputs()
	w["level"] = maxi(int(w["level"]), min_level)
	if audio and min_level == 0:
		var pp := player.global_position
		audio.exposure = 1.0 - float(w["windbreak"])
		if spindrift:
			spindrift.intensity = audio.exposure * clampf(weather.atmosphere.wind_kmh / 32.0, 0.5, 1.6)
		audio.shelter_level = int(w["level"])
		audio.fire = float(w["fire"])
		audio.speed = player.current_speed
		audio.snow_depth = SnowField.snow_at(pp.x, pp.z)
		audio.master = 0.0 if state == State.REPORT else (0.4 if state == State.NIGHT_FADE else 1.0)
	warmth.windbreak_factor = w["windbreak"]
	warmth.in_shelter_level = w["level"]
	warmth.near_fire_intensity = w["fire"]
	warmth.update_warmth(real_seconds * factor, w["windbreak"], warmth.has_extra_clothing,
		w["level"], w["fire"], w["env"])
	if float(w["fire"]) > 0.3 and weather.minutes_to_sunset() < 60.0:
		prewarmed = true
	# 受潮 / 烘干（劳作跳时也按等效现实秒结算）
	var secs := real_seconds * factor if min_level == 0 else 0.0
	if float(w["fire"]) > 0.05:
		dampness = maxf(0.0, dampness - tuning.dry_rate_fire * float(w["fire"]) * real_seconds)
	elif weather.atmosphere.snowfall > 0.5 and int(w["level"]) == 0:
		dampness = minf(1.0, dampness + tuning.damp_snowfall_rate * secs)
	warmth.has_extra_clothing = GameRules.clothing_effective(bool(gear["layer"]), dampness, tuning)
	_update_cloth_label()

## 动作消耗游戏时间：时钟跳进；按"劳作中"的暴露率结算体温；火堆燃烧。
## min_level：劳作时所处的庇护等级（例如在雪洞里挖掘 = 1，避开风吹）。
func _skip(minutes: float, min_level: int = 0) -> void:
	if minutes <= 0.0:
		return
	_sync_fires()
	weather.advance_minutes(minutes)
	for f in get_tree().get_nodes_in_group("campfires"):
		(f as Campfire).burn(minutes)
	_last_minutes = weather.current_time_minutes
	var real_equiv := minutes * 60.0 / maxf(_saved_time_scale, 1.0)
	_update_warmth(real_equiv, tuning.work_exposure_factor, min_level)

## 把上次结算后的流逝时间先烧掉，再开始新的跳时（火堆燃烧只按实际经过的时间）。
func _sync_fires() -> void:
	var dm := weather.current_time_minutes - _last_minutes
	if dm > 0.0:
		for f in get_tree().get_nodes_in_group("campfires"):
			(f as Campfire).burn(dm)
	_last_minutes = weather.current_time_minutes

# ------------------------------------------------------------------ 探针（T1.6 / D4）

func _on_probe(pos: Vector3, depth: float) -> void:
	_probe_count += 1
	_probe_points.append(pos)
	SessionLog.log_event("probe", weather.clock_string(), {"depth": snappedf(depth, 0.01), "lee": snappedf(SnowField.lee_factor_at(pos.x, pos.z), 0.01), "x": snappedf(pos.x, 0.1), "z": snappedf(pos.z, 0.1)})
	_mark("probe")
	_best_depth = maxf(_best_depth, depth)
	audio.play_sfx("probe")
	var cls := GameRules.classify_depth(depth, tuning)
	_add_marker(pos, depth, cls["color"])
	if callouts:
		callouts.set_callout("probe", pos + Vector3(0, 0.6, 0), String(cls["title"]), String(cls["sub"]), cls["color"], Vector2(18.0, -58.0), 3)
		# D4：Deeper snow 只在玩家探测过、且达到雪洞深度的位置出现
		if depth >= tuning.snow_depth_cave_min_m and _deeper_count < MAX_DEEPER_LABELS:
			var far_enough := true
			for q in _deeper_points:
				if q.distance_to(pos) < 8.0:
					far_enough = false
			if far_enough:
				_deeper_points.append(pos)
				callouts.set_callout("deeper_%d" % _deeper_count, pos + Vector3(0, 0.4, 0), Loc.t("Deeper snow"),
					Loc.t("Ideal for shelter"), Color(0.52, 0.72, 1.0), Vector2(-200.0, 20.0), 2)
				_deeper_count += 1
	_skip(1.0)

func _add_marker(pos: Vector3, depth: float, color: Color) -> void:
	var m := Node3D.new()
	m.position = pos
	main.add_child(m)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.1
	cyl.radial_segments = 6
	pole.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	pole.material_override = mat
	pole.position = Vector3(0, 0.55, 0)
	m.add_child(pole)
	var flag := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.16, 0.02)
	flag.mesh = box
	var fm := StandardMaterial3D.new()
	fm.albedo_color = color
	fm.emission_enabled = true
	fm.emission = color
	fm.emission_energy_multiplier = 0.4
	flag.material_override = fm
	flag.position = Vector3(0.15, 1.0, 0)
	m.add_child(flag)
	var label := Label3D.new()
	label.text = "%.1f m" % depth
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 10
	label.modulate = color
	label.position = Vector3(0, 1.45, 0)
	label.no_depth_test = false
	m.add_child(label)
	_markers.append(m)
	if _markers.size() > MAX_MARKERS:
		_markers.pop_front().queue_free()

# ------------------------------------------------------------------ 采集（T2.2）

## 背包满了：不开始采（不播砍 / 拔的动作，不耗时间），提示里直接说明。
func _harvest_blocked(it: Interactable) -> String:
	match it.kind:
		"deadwood":
			if inventory.wood >= inventory.max_wood:
				return Loc.t("Your pack can't carry more wood. Stack it at your site.")
		"grass", "bough":
			if inventory.bedding >= inventory.max_bedding:
				return Loc.t("Your pack can't carry more bedding. Stack it at your site.")
	return ""

func _on_harvest(it: Interactable) -> Dictionary:
	match it.kind:
		"deadwood":
			var got := inventory.add("wood", tuning.wood_per_harvest)
			if got <= 0:
				return {"ok": false, "msg": Loc.t("Your pack can't carry more wood. Stack it at your site.")}
			return {"ok": true, "minutes": tuning.gather_minutes, "msg": Loc.t("+%d dry wood — standing dead trees burn well.") % got}
		"birch":
			inventory.add("bark", tuning.bark_per_harvest)
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5, "msg": Loc.t("+%d birch bark — the best tinder there is.") % tuning.bark_per_harvest}
		"grass":
			if inventory.add("bedding", tuning.bedding_per_harvest) <= 0:
				return {"ok": false, "msg": Loc.t("Your pack can't carry more bedding. Stack it at your site.")}
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5, "msg": Loc.t("+%d bedding (dry grass).") % tuning.bedding_per_harvest}
		"bough":
			if inventory.add("bedding", tuning.bedding_per_harvest) <= 0:
				return {"ok": false, "msg": Loc.t("Your pack can't carry more bedding. Stack it at your site.")}
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5, "msg": Loc.t("+%d bedding (spruce boughs).") % tuning.bedding_per_harvest}
		"wet_log":
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5,
				"msg": Loc.t("This fallen log is soaked through — it won't burn. Look for STANDING dead trees.")}
	return {"ok": false, "msg": ""}

func _on_interaction_completed(target: Interactable, result: Dictionary) -> void:
	if target.kind != "shelter" and target.kind != "fire":
		SessionLog.log_event("gather", weather.clock_string(), {"kind": target.kind})
	if bool(result.get("ok", true)):
		match target.kind:
			"deadwood", "wet_log": audio.play_sfx("chop")
			"birch", "grass", "bough": audio.play_sfx("gather")
			"shelter": audio.play_sfx("dig")
	var msg := String(result.get("msg", ""))
	if msg != "":
		ui.toast(msg)
	if bool(result.get("ok", true)):
		_skip(float(result.get("minutes", 0.0)))
	if target.uses_left == 0 and target.kind in ["grass", "bough"]:
		target.get_parent().queue_free()

func _on_inventory_changed() -> void:
	if ui:
		ui.set_inventory(inventory.wood, inventory.bark, inventory.bedding, inventory.max_wood, inventory.max_bedding)
	if player and player.visual_node is HikerVisual:
		(player.visual_node as HikerVisual).set_load(inventory.wood, inventory.bedding)
	if prints:
		prints.heavy = inventory.wood >= inventory.max_wood

# ------------------------------------------------------------------ 建造（T2.4–T2.6）

func _enter_build() -> void:
	# §12.3：同一时间只有一个未完工工地；再按 B 是"返回 / 继续"，不是新建
	var near := site != null and interaction.current == site.interactable
	match BuildSession.b_key_action(site != null, site != null and site.is_complete(), near):
		"resume":
			_enter_focus()
			return
		"far":
			ui.toast(Loc.t("You're already building a %s, %d m away. Walk back and press [E] to continue.") % [Loc.t(site.builder.active_preset().display_name), int(round(_site_distance()))])
			return
		"done":
			ui.toast(Loc.t("Your %s is finished. One shelter is all you get to build tonight.") % Loc.t(site.builder.active_preset().display_name))
			return
	interaction.enabled = false
	build.available = LevelState.available_presets(Records.learned_shelters())
	build.enter()

func _exit_build() -> void:
	build.exit()
	interaction.enabled = true
	ui.show_build(false)

func _place_site() -> void:
	if not build.valid:
		ui.toast(build.reason)
		return
	if site != null:
		site.queue_free()
	site = ShelterSite.new()
	site.name = "ShelterSite"
	site.setup(build.preset_id, build.entrance_dir, build.depth, build.slope, build.near_windbreak)
	if build.is_snow_preset():
		site.quick_roof = build.quick_roof
		site.vent_count = build.vent_count
		site.time_factor = tuning.quick_roof_time_factor if build.quick_roof else 1.0
	site.position = build.site_pos
	main.add_child(site)
	# R2 / 第二次评审：必须在工地就位之后再判断"附近探过没有"（之前在就位前判断，量的是原点 → 几乎总说没探过）
	_site_probed = GameRules.probed_near(_probe_points, build.site_pos, PROBE_NEAR_SITE_M)
	site.interactable.hold_seconds = tuning.stage_hold_seconds
	site.interactable.prompt_fn = _site_prompt
	site.interactable.handler = _on_build_stage
	_mark("site")
	SessionLog.log_event("site", weather.clock_string(), {"preset": site.preset_id, "depth": snappedf(site.snow_depth, 0.01), "wind_angle": int(GameRules.entrance_wind_angle(site.entrance_dir, wind.get_wind_direction_3d()))})
	_exit_build()
	_enter_focus()

# ------------------------------------------------------------------ D16 建造特写

func _site_distance() -> float:
	if site == null:
		return 0.0
	return Vector2(player.global_position.x - site.global_position.x, player.global_position.z - site.global_position.z).length()

func _enter_focus() -> void:
	if site == null or not session.begin(site.is_complete()):
		return
	player.controls_enabled = false
	interaction.enabled = true
	interaction.forced = site.interactable
	_unload_to_site()
	# §12.2：角色的模型画到工地旁边、面向工地干活；玩家真实位置、碰撞、控制都不变
	_figure_spot = _pick_figure_spot()
	var to := site.global_position - _figure_spot
	player.visual_node.rotation.y = atan2(to.x, to.z)
	if rig:
		var aim := _focus_aim()
		rig.set_focus(aim, _focus_zoom_for(aim))
	_set_focus_hud(true)
	_update_section()

## 退回远景（B / Esc）：工地和进度都保留。
func _step_back() -> void:
	if session.state == BuildSession.State.COMPLETE:
		session.reset()
	else:
		session.step_back()
	_release_focus()

## 只有还没动工（0 阶）的工地可以换个地方：这不算第二个工地。
func _replace_site() -> void:
	if site == null or site.stage() > 0:
		return
	session.reset()
	_release_focus()
	site.queue_free()
	site = null
	callouts.remove_callout("my_shelter")
	ui.set_shelter_card("", "", false)
	_enter_build()

## 角色画在哪里：工地在屏幕上的一侧，离入口近的那边（材料堆在另一边），略靠后；有树就换一边。
func _pick_figure_spot() -> Vector3:
	var c := site.global_position
	var right := rig.global_transform.basis.x if rig else Vector3.RIGHT
	var away := -rig.global_transform.basis.z if rig else Vector3.FORWARD
	away.y = 0.0
	away = away.normalized()
	var e_side := (site.entrance_point() - c).dot(right)
	var first := signf(e_side) if absf(e_side) > 0.01 else 1.0
	var dist := site.footprint_radius() + tuning.build_focus_figure_gap_m + absf(e_side) * 0.5
	var trees := build._tree_points()
	for g in ["forest", "scenery"]:
		for n in get_tree().get_nodes_in_group(g):
			for key in ["snag_points", "deadwood_points"]:
				if key in n:
					trees.append_array(n.get(key))
	# 依次试：两侧、再往外一点。站的地方和它朝镜头方向（树干会挡住人）都要没有树。
	var best := Vector3.INF
	for extra in [0.0, 1.0, 2.0]:
		for s in [first, -first]:
			var q: Vector3 = c + right * s * (dist + extra) + away * 0.6
			var clear := true
			for along in [0.0, 1.5, 3.0]:
				var a: Vector3 = q - away * along
				for t in trees:
					if t.distance_to(Vector2(a.x, a.z)) < 1.0:
						clear = false
						break
			if best == Vector3.INF:
				best = q
			if clear:
				return Vector3(q.x, SnowField.height_at(q.x, q.z), q.z)
	return Vector3(best.x, SnowField.height_at(best.x, best.z), best.z)

func _release_focus() -> void:
	_figure_spot = Vector3.INF
	player.visual_node.position = _figure_home
	player.controls_enabled = state == State.PLAYING
	interaction.forced = null
	interaction.enabled = state == State.PLAYING
	if rig:
		rig.clear_focus()
	ui.show_build_focus("", "", "", "", false, 0.0)
	_set_focus_hud(false)
	_update_section(false)

func _set_focus_hud(on: bool) -> void:
	if callouts:
		callouts.cards_hidden = on
	if _compass:
		_compass.visible = not on
	var instr := hud.get_node_or_null("Instructions") as Control
	if instr:
		instr.visible = not on
	ui.set_day_hud(not on)

## 取景点：工地和入口之间；向角色一侧略偏，让两者都在画面里。
func _focus_aim() -> Vector3:
	var p := site.global_position + site.entrance_dir * 0.6
	p.y = SnowField.height_at(p.x, p.z) + 0.4
	if rig and _figure_spot != Vector3.INF:
		var right := rig.global_transform.basis.x
		p += right * signf((_figure_spot - p).dot(right)) * tuning.build_focus_side_m
	return p

## 按庇护所体量取特写距离（§12.2）。
func _focus_zoom_for(aim: Vector3) -> float:
	var want := tuning.build_focus_zoom_cave
	match site.preset_id:
		"SnowTrench": want = tuning.build_focus_zoom_trench
		"TreeWell": want = tuning.build_focus_zoom_treewell
		"LeanTo", "RockOverhang", "FallenLog": want = tuning.build_focus_zoom_leanto
	# 视线不穿地形：先试理想距离，再拉远 / 推近（偏航不能动，只能改距离）
	var height := func(x: float, z: float) -> float: return SnowField.height_at(x, z)
	for z in BuildSession.zoom_candidates(want, tuning.build_focus_min_ratio, tuning.build_focus_max_ratio):
		if BuildSession.view_clear(aim + rig.camera_offset(z), aim, height):
			return z
	return want

## 工地（含入口）的屏幕包围盒。
func site_screen_rect(camera: Camera3D) -> Rect2:
	var c := site.global_position
	var y := SnowField.height_at(c.x, c.z)
	var r := Rect2(camera.unproject_position(Vector3(c.x, y, c.z)), Vector2.ZERO)
	var e := site.entrance_point() - Vector3(c.x, y, c.z)
	var f := site.footprint_radius() * 0.75
	for q in [Vector3(f, 0, 0), Vector3(-f, 0, 0), Vector3(0, 0, f), Vector3(0, 0, -f), Vector3(0, 1.2, 0), e, e + Vector3(0, 1.0, 0)]:
		r = r.expand(camera.unproject_position(Vector3(c.x, y, c.z) + q))
	return r

## 角色（含背包）的屏幕包围盒。
func character_screen_rect(camera: Camera3D) -> Rect2:
	var p: Vector3 = player.visual_node.global_position
	var r := Rect2(camera.unproject_position(p), Vector2.ZERO)
	for q in [Vector3(0, 1.9, 0), Vector3(0.55, 1.0, 0), Vector3(-0.55, 1.0, 0), Vector3(0, 1.0, 0.55), Vector3(0, 1.0, -0.55)]:
		r = r.expand(camera.unproject_position(p + q))
	return r

## B2 硬规则：角色不挡工地。模型已经画在旁边（_pick_figure_spot），这里是兜底判定。
func character_blocks_site() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null or site == null:
		return false
	var cam := camera.global_position
	return BuildSession.blocks_site(character_screen_rect(camera), site_screen_rect(camera), cam.distance_to(player.visual_node.global_position), cam.distance_to(site.global_position))

func _tick_focus(delta: float) -> void:
	var hide := false
	if session.focused():
		if site == null:
			session.reset()
			_release_focus()
		else:
			if _figure_spot != Vector3.INF:
				var v: Node3D = player.visual_node
				v.global_position = v.global_position.lerp(_figure_spot, minf(delta * 5.0, 1.0))
			hide = character_blocks_site()
			if site.is_complete() and session.state == BuildSession.State.FOCUSED:
				session.complete()
				_focus_complete_ms = Time.get_ticks_msec()
				interaction.forced = null
				interaction.enabled = false
			if session.state == BuildSession.State.COMPLETE and Time.get_ticks_msec() - _focus_complete_ms >= int(tuning.build_focus_complete_seconds * 1000.0):
				session.reset()
				_release_focus()
				hide = false
			else:
				_update_focus_panel()
	var want := tuning.build_focus_ghost_amount if hide else 0.0
	if _hiker_ghost != want and player.visual_node is HikerVisual:
		_hiker_ghost = move_toward(_hiker_ghost, want, delta / maxf(tuning.build_focus_ghost_seconds, 0.01))
		(player.visual_node as HikerVisual).set_ghost(_hiker_ghost)

## 把背包里的柴和枝条放到工地的材料堆（B4）。
func _unload_to_site() -> bool:
	var moved := site.pile.deposit(inventory)
	if moved.is_empty():
		return false
	site.refresh_pile()
	var names := _material_names()
	var parts: Array[String] = []
	for k in moved:
		parts.append("%d %s" % [int(moved[k]), names.get(k, k)])
	ui.toast(Loc.t("Added to your site pile: %s") % ", ".join(parts), 3.0)
	return true

## 生火 / 添柴能用的柴：背包里的，加上就在工地旁边时堆里的。
func _fire_wood() -> int:
	var n := inventory.wood
	if site != null and _site_distance() <= tuning.night_fire_reach_m:
		n += site.pile.amount("wood")
	return n

func _spend_fire_wood(n: int) -> bool:
	if n > _fire_wood():
		return false
	var from_pack := mini(n, inventory.wood)
	inventory.spend({"wood": from_pack})
	if n > from_pack:
		site.pile.spend({"wood": n - from_pack}, inventory)
		site.refresh_pile()
	return true

## 走近可采集物时先告诉玩家这是什么、怎么采（走进圈里后由操作提示接手）。
func _update_near_item_callout(building: bool) -> void:
	var best: Interactable = null
	var best_d := tuning.near_item_label_m
	if not building:
		for n in get_tree().get_nodes_in_group("interactables"):
			var it := n as Interactable
			if not (it.kind in ["grass", "bough", "birch"]) or it.uses_left == 0 or it == interaction.current or it.is_queued_for_deletion():
				continue
			var d := it.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = it
	if best == null:
		callouts.remove_callout("near_item")
		return
	var titles := {"grass": Loc.t("Dry grass"), "bough": Loc.t("Spruce boughs"), "birch": Loc.t("Birch bark")}
	var sub_line := Loc.t("Tinder · walk up, hold [E]") if best.kind == "birch" else Loc.t("Bedding · walk up, hold [E]")
	callouts.set_callout("near_item", best.global_position + Vector3(0, 0.7, 0), titles[best.kind], sub_line, Color(0.95, 0.82, 0.45), Vector2(28.0, -58.0), 2)

## 火的状态卡：还能烧多久、怎么添柴。
func _update_fire_callout() -> void:
	var fire := _nearest_fire(tuning.fire_card_m)
	if fire == null or session.focused():
		callouts.remove_callout("fire_status")
		return
	var title := Loc.t("Fire: %d min left") % int(ceil(fire.fuel_minutes)) if fire.lit else Loc.t("Fire is out")
	var inside := _nearest_fire(tuning.fire_warm_radius_m) != null
	var lines: Array[String] = []
	if fire.lit:
		lines.append(Loc.t("You're warming up") if inside else Loc.t("Too far to feel the heat"))
	if not inside:
		lines.append(Loc.t("Step into the circle"))
	elif _fire_wood() <= 0:
		lines.append(Loc.t("No dry wood to add"))
	else:
		lines.append((Loc.t("[F] Add a log: +%d min (%d dry wood)") if fire.lit else Loc.t("[F] Relight with a log: +%d min (%d dry wood)")) % [int(tuning.campfire_minutes_per_wood), _fire_wood()])
	var line := "\n".join(lines)
	callouts.set_callout("fire_status", fire.global_position + Vector3(0, 1.1, 0), title, line, Color(1.0, 0.62, 0.2), Vector2(28.0, -70.0), 3)

## 火放在面朝方向，但玩家背对相机时那正好在人身后、被挡住：这时往屏幕右侧偏。
func _fire_place() -> Vector3:
	var f := player.facing()
	var cam := get_viewport().get_camera_3d()
	if cam:
		var away := -cam.global_transform.basis.z
		away.y = 0.0
		if f.dot(away.normalized()) > 0.6:
			f = (f + cam.global_transform.basis.x).normalized()
	return player.global_position + f * 1.3

## 工地到完工还缺多少垫层（堆里 + 背包都算）；没有工地或已完工 = 0。
func _bedding_short() -> int:
	if site == null or site.is_complete():
		return 0
	return int(site.remaining_cost().get("bedding", 0)) - site.pile.total("bedding", inventory)

func _nearest_bedding() -> Interactable:
	var best: Interactable = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if not (it.kind in ["grass", "bough"]) or it.uses_left == 0 or it.is_queued_for_deletion():
			continue
		var d := it.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best

## 告诉玩家垫层是什么、最近的在哪（真实距离与方位）。
func _bedding_hint() -> String:
	var it := _nearest_bedding()
	if it == null:
		return Loc.t("Bedding: dry grass or low spruce boughs. None left on this map.")
	return Loc.t("Bedding: dry grass (orange tufts) or low spruce boughs (green). Nearest: %d m %s") % _bearing_to(it)

func _bearing_to(it: Node3D) -> Array:
	var v := it.global_position - player.global_position
	return [int(round(Vector2(v.x, v.z).length())), _dir_word(v)]

func _material_names() -> Dictionary:
	return {"wood": Loc.t("dry wood"), "bark": Loc.t("birch bark"), "bedding": Loc.t("bedding")}

func _update_focus_panel() -> void:
	var p := site.builder.active_preset()
	if session.state == BuildSession.State.COMPLETE:
		ui.show_build_focus("%s  ·  %d/%d  ✓" % [Loc.t(p.display_name).to_upper(), site.stage(), ShelterBuilder.STAGES_MAX], Loc.t("Shelter complete."), "", "", false, 1.0)
		return
	var wait_left := site.ready_at - weather.current_time_minutes
	if wait_left > 0.0:
		interaction.enabled = true
		ui.show_build_focus("%s  ·  %d/%d  ·  %s" % [Loc.t(p.display_name).to_upper(), site.stage(), ShelterBuilder.STAGES_MAX, site.next_stage_title()],
			Loc.t("The snow is setting: %d min left.") % int(ceil(wait_left)), Loc.t("Hollow it too soon and it collapses."),
			Loc.t("[B] Step back & gather meanwhile   ·   Hold [E] to wait it out"), false, interaction.progress)
		return
	var cost := site.next_stage_cost()
	var short := not site.pile.has_all(cost, inventory)
	interaction.enabled = not short
	if short and Input.is_action_just_pressed("interact"):
		ui.toast(Loc.t("Not enough materials — still need %s.") % site.pile.missing_text(cost, inventory), 3.0)
	var names := _material_names()
	var parts: Array[String] = []
	for k in cost:
		parts.append(Loc.t("%d %s (you have %d)") % [int(cost[k]), names.get(k, k), site.pile.total(k, inventory)])
	var needs := Loc.t("Needs: %s") % ", ".join(parts) if not parts.is_empty() else Loc.t("No materials needed for this stage.")
	var left := weather.minutes_to_sunset()
	var light := Loc.t("after sunset") if left <= 0.0 else Loc.t("%d min of daylight left") % int(left)
	var time_line := Loc.t("~%d min of work  ·  %s") % [int(_stage_minutes() / _efficiency()), light]
	if short and site.pile.total("bedding", inventory) < int(cost.get("bedding", 0)):
		time_line = _bedding_hint()
	var keys := Loc.t("[B] Step back & gather — your site stays here") if short else Loc.t("Hold [E] to build   ·   [B] Step back")
	if site.stage() == 0:
		keys += "   ·   " + Loc.t("[R] Pick another spot")
	ui.show_build_focus("%s  ·  %d/%d  ·  %s" % [Loc.t(p.display_name).to_upper(), site.stage(), ShelterBuilder.STAGES_MAX, site.next_stage_title()],
		needs, time_line, keys, short, interaction.progress)

# ------------------------------------------------------------------ 进入庇护所（2026-11-04）

## 走进去：换成切开的剖面（对标 north star 的 SHELTER DESIGN），人躺在里面。规则不变，体温本来就按"人在不在里面"算；时间照走。
func _enter_shelter() -> void:
	if _in_shelter or site == null or not site.is_complete():
		return
	_in_shelter = true
	_shelter_transition(func() -> void:
		var cam := site.set_interior_view(true)
		player.global_position = Vector3(site.global_position.x, player.global_position.y, site.global_position.z)
		player.controls_enabled = false
		interaction.enabled = false
		var view := site.interior_view()
		var fig: Node3D = player.visual_node
		# 模型原点在脚底、身体绕中轴：躺平后要抬高半个身体厚度，不然半截埋进床里
		fig.global_position = site.to_global(view.figure_spot + Vector3.UP * tuning.interior_figure_lift_m)
		_set_figure_particles(false)   # 呼出的白气跟着站姿算位置，躺着时会飘在半空
		# 躺着：模型的"上"指向 -Z（头朝里），脸朝上
		fig.global_basis = site.global_basis * Basis(Vector3.RIGHT, -PI * 0.5)
		if rig:
			rig.lens_suspended = true
			# shader 只淡掉比焦点近 1.2 m 以上的东西：把焦点往后推 1.2 m，切面前面的树（树井的那棵）才全部消失
			rig.interior_focus = site.global_position - cam.global_transform.basis.z * 1.2
			get_tree().call_group("occlusion_fade", "set_focus_fade", 6.0, 1.0)
		cam.make_current()
		_update_section()
		callouts.only_prefix = "section_"
		callouts.card_limit = 4
		var i := 0
		for l: Array in view.labels():
			callouts.set_callout("section_%d" % i, site.to_global(l[0]), l[1], l[2], Color(0.72, 0.86, 1.0), Vector2(30.0, -50.0), 5)
			i += 1
		if _compass:
			_compass.visible = false)

## 剖面切开：进到庇护所里（剖面相机在工地本地 +X）或树井建造特写（工地就在那棵老云杉底下）时，
## 把切面朝镜头一侧的树切掉，像剖面图一样；其它时候关掉。
func _update_section(focus_on: bool = true) -> void:
	var normal := Vector3.ZERO
	var back := 0.0
	if site != null and _in_shelter:
		normal = site.global_basis.x
		back = tuning.section_cut_behind_m
	elif focus_on and site != null and rig and site.preset_id == "TreeWell" and session.focused():
		normal = rig.global_transform.basis.z
	normal.y = 0.0
	var on := normal.length() > 0.01
	normal = normal.normalized() if on else Vector3.RIGHT
	var point := site.global_position - normal * back if on else Vector3.ZERO
	var radius := tuning.section_cut_radius_m + back
	get_tree().call_group("occlusion_fade", "set_section", on, point, normal, radius)
	# 火堆用的是普通材质，切不掉：在剖面里挡在镜头前面时整个藏起来（火照样在烧，规则不变）
	for f in get_tree().get_nodes_in_group("campfires"):
		var c := f as Node3D
		var d := c.global_position - point
		c.visible = not (on and _in_shelter and d.dot(normal) > 0.0 and Vector2(d.x, d.z).length() < radius)

func _set_figure_particles(on: bool) -> void:
	for n in player.find_children("*", "GPUParticles3D", true, false):
		(n as GPUParticles3D).visible = on

func _leave_shelter() -> void:
	if not _in_shelter:
		return
	_shelter_transition(func() -> void:
		_in_shelter = false
		if site != null:
			site.set_interior_view(false)
			# 一定要落在"算在里面"的半径之外，否则走出去了还在享受庇护所的体温（雪沟的入口离中心很近）
			var out_d := maxf(site.entrance_point().distance_to(site.global_position) + 1.4, tuning.shelter_inside_radius_m + 0.5)
			var out := site.global_position + site.entrance_dir * out_d
			player.global_position = Vector3(out.x, TerrainHeight.height_at(out.x, out.z) + 0.2, out.z)
			var to := site.entrance_dir
			player.visual_node.position = _figure_home
			player.visual_node.rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)
		_set_figure_particles(true)
		player.controls_enabled = state == State.PLAYING
		interaction.enabled = state == State.PLAYING
		if rig:
			rig.lens_suspended = false
			rig.interior_focus = Vector3.INF
			get_tree().call_group("occlusion_fade", "set_focus_fade", 0.26, 0.85)
			rig.global_position = player.global_position
			rig.camera_3d.make_current()
		_update_section()
		callouts.only_prefix = ""
		callouts.card_limit = 0
		callouts.remove_prefix("section_")
		if _compass:
			_compass.visible = true)

## 短暂黑一下再换视角，像是弯腰钻进去。中途不接受第二次操作。
func _shelter_transition(swap: Callable) -> void:
	if _shelter_tween != null and _shelter_tween.is_valid():
		_shelter_tween.kill()
	_shelter_tween = create_tween()
	_shelter_tween.tween_method(ui.set_fade, 0.0, 1.0, 0.18)
	_shelter_tween.tween_callback(swap)
	_shelter_tween.tween_method(ui.set_fade, 1.0, 0.0, 0.3)

func _shelter_busy() -> bool:
	return _shelter_tween != null and _shelter_tween.is_valid() and _shelter_tween.is_running()

func _tick_inside_shelter() -> void:
	if site == null:
		_leave_shelter()
		return
	var elev: float = weather.sun_elevation_deg
	site.interior_daylight((elev + 6.0) / 18.0)
	if player.visual_node.has_method("set_motion"):
		player.visual_node.set_motion(0.0, false, false, "")
	if not _shelter_busy() and Input.is_action_just_pressed("interact"):
		_leave_shelter()

func _needs_vent_stick() -> bool:
	# 树井没有通风管（枝条屋顶透气，见 ShelterBuilder.has_vent），不要它插木棍
	return site != null and site.is_complete() and site.is_snow_shelter() and site.preset_id != "TreeWell" and site.vent_count == 1 \
		and not site.vent_stick and weather.atmosphere.snowfall > 0.05

func _site_prompt() -> String:
	if _needs_vent_stick():
		return Loc.t("Push a stick through the vent (1 wood) — keeps it clear in falling snow")
	if site != null and site.is_complete() and (inventory.wood > 0 or inventory.bedding > 0):
		return Loc.t("Stack what you're carrying here (fire logs, extra bedding)")
	if site != null and site.is_complete():
		return Loc.t("Enter the shelter")
	if site == null:
		return ""
	var cost := site.next_stage_cost()
	var need := ""
	if not cost.is_empty():
		var parts: Array[String] = []
		for k in cost:
			parts.append("%d %s" % [cost[k], k])
		need = Loc.t("  (needs ") + ", ".join(parts) + ")"
	var line := Loc.t("%s%s  ·  ~%d min") % [site.next_stage_title(), need, int(_stage_minutes() / _efficiency())]
	var rest := site.remaining_cost()
	var short: Array[String] = []
	for k in rest:
		var have := site.pile.total(k, inventory)
		if have < int(rest[k]):
			short.append("%d %s" % [int(rest[k]) - have, k])
	if not short.is_empty():
		line += "\n" + Loc.t("To finish the shelter you still need: %s") % ", ".join(short)
	return line

## 本阶段工时（含装备：没有雪铲挖雪庇护所更慢，S6）。
func _stage_minutes() -> float:
	# 树井的坑大多是现成的、浮雪用手就能掏：不靠雪铲（S5）
	return GameRules.dig_minutes(site.stage_minutes(), site.is_snow_shelter() and site.preset_id != "TreeWell", GameRules.dig_tool(gear), tuning)

func _efficiency() -> float:
	return GameRules.work_efficiency(warmth.get_action_efficiency(), weather.minutes_to_sunset(), tuning)

func _on_build_stage() -> Dictionary:
	if _needs_vent_stick():
		if not site.pile.spend({"wood": 1}, inventory):
			return {"ok": false, "msg": Loc.t("You need 1 dry wood for a vent stick.")}
		site.refresh_pile()
		site.vent_stick = true
		return {"ok": true, "minutes": 3.0, "msg": Loc.t("Stick in the vent: you can poke it clear during the night.")}
	if site.is_complete():
		if inventory.wood > 0 or inventory.bedding > 0:
			_unload_to_site()
			return {"ok": true, "minutes": 1.0, "msg": ""}
		_enter_shelter()
		return {"ok": true, "minutes": 0.0, "msg": ""}
	# 雪堆屋：堆好的雪要凝结。可以去采集，也可以按住 [E] 干等
	var wait_left := site.ready_at - weather.current_time_minutes
	if wait_left > 0.0:
		_skip(wait_left)
		return {"ok": true, "minutes": 0.0, "msg": Loc.t("You wait for the snow to set.")}
	var cost := site.next_stage_cost()
	if not site.pile.has_all(cost, inventory):
		return {"ok": false, "msg": Loc.t("Not enough materials — still need %s.") % site.pile.missing_text(cost, inventory)}
	site.pile.spend(cost, inventory)
	site.refresh_pile()
	var minutes := _stage_minutes() / _efficiency()
	# 在雪下挖掘时人已在风外：按庇护等级 1 结算体温（倒棚施工仍暴露）
	_skip(minutes, 1 if site.is_snow_shelter() else 0)
	if site.is_snow_shelter():
		dampness = minf(1.0, dampness + GameRules.dig_dampness(GameRules.dig_tool(gear), tuning))
		_update_cloth_label()
	var r := site.advance()
	site.ready_at = weather.current_time_minutes + site.wait_before_next_stage()
	if site.preset_id == "LeanTo" and site.is_complete() and site.fire:
		# 阶段完成时才点燃（工时已流逝）；之后由玩家 [F] 添柴维持
		site.fire.ignite(tuning.campfire_minutes_per_wood * 2.0)
		_attach_fire_interactable(site.fire)
	minutes = 0.0
	var msg := Loc.t("Stage %d/5 done — %s") % [int(r["stage"]), Loc.t(String(r["stage_title"]))]
	SessionLog.log_event("stage", weather.clock_string(), {"stage": site.stage()})
	if site.is_complete():
		_mark("done")
		msg = Loc.t("Shelter complete. Bring in what you need — rest when ready [N].")
		if site.preset_id == "LeanTo":
			msg += Loc.t(" Stockpile dry wood: the reflector fire burns %.0f h per log.") % tuning.fire_fuel_hours_per_log
	return {"ok": true, "minutes": minutes, "msg": msg}

# ------------------------------------------------------------------ 生火（T2.7）

func _nearest_fire(max_d: float) -> Campfire:
	var best: Campfire = null
	var pos := player.global_position
	for f in get_tree().get_nodes_in_group("campfires"):
		var c := f as Campfire
		var d := Vector2(c.global_position.x - pos.x, c.global_position.z - pos.z).length()
		if d < max_d:
			max_d = d
			best = c
	return best

## 离 from 最近的"按火规则点得着"的地方：每个树根盘紧贴下风一侧找（不看材料，只看风与树冠）。没有返回 INF。
func _sheltered_fire_spot(from: Vector3) -> Vector3:
	var blow := wind.get_blow_direction_3d()
	var best := Vector3.INF
	var bd := INF
	for n in get_tree().get_nodes_in_group("windbreaks"):
		var c := (n as Node3D).global_position
		for dist in [1.0, 1.4, 1.9]:
			for ang in [0.0, 25.0, -25.0, 50.0, -50.0]:
				var p: Vector3 = c + blow.rotated(Vector3.UP, deg_to_rad(ang)) * float(dist)
				p.y = TerrainHeight.height_at(p.x, p.z)
				var exposure := fire_exposure_at(p)
				if exposure <= tuning.fire_blowout_dot and not _under_canopy(p):
					var d := p.distance_to(from)
					if d < bd:
						bd = d
						best = p
	return best

func _under_canopy(p: Vector3) -> bool:
	var forest := get_tree().get_first_node_in_group("forest")
	if forest == null:
		return false
	for q: Vector2 in forest.spruce_points:
		if q.distance_to(Vector2(p.x, p.z)) < tuning.canopy_radius_m:
			return true
	return false

## F 按下：附近有火 = 立即添柴；否则开始按住生火。
func _begin_fire() -> void:
	if _nearest_fire(tuning.fire_warm_radius_m):
		_try_fire()
		return
	_fire_hold = 0.0
	HoldAssist.on_pressed("fire")
	player.controls_enabled = false

func _tick_fire_hold(delta: float) -> void:
	if _fire_hold < 0.0:
		return
	var held := HoldAssist.held("fire")
	if not held or state != State.PLAYING:
		_fire_hold = -1.0
		player.controls_enabled = state == State.PLAYING
		return
	_fire_hold += delta
	player.working = true
	if _fire_hold >= tuning.fire_hold_seconds:
		_fire_hold = -1.0
		HoldAssist.release("fire")
		player.controls_enabled = true
		_try_fire()

## 挡风统一规则：p 点、离地 h 米处挡掉了多少风（0..1）。风声、风雪、体温流失按人的高度，生火按火的高度。
## 地形（洼地 / 背风坡 / 崖脚：上风方向高出越多越好）、实心挡风物（岩石、树根盘、自己的雪墙：只挡下风一侧，
## 风影长约 3 倍高，比 h 矮的只挡一部分）、树林（透风，最多挡一半不到），三层叠加。
func wind_shelter_at(p: Vector3, h: float) -> float:
	return GameRules.combine_shelter(wind_shelter_parts(p, h).values())

## 各层分开（调试 / 测试 / 提示用）：{"terrain", "solid", "trees"}。
func wind_shelter_parts(p: Vector3, h: float) -> Dictionary:
	var blow := wind.get_blow_direction_3d()
	var b2 := Vector2(blow.x, blow.z)
	var q := Vector2(p.x, p.z)
	var up := p + wind.get_wind_direction_3d().normalized() * tuning.rock_cliff_run_m
	var depth := maxf(TerrainHeight.lee_depth_at(p.x, p.z), TerrainHeight.height_at(up.x, up.z) - TerrainHeight.height_at(p.x, p.z))
	var solid := 0.0
	for b in _wind_barriers():
		solid = maxf(solid, GameRules.barrier_shelter(b, q, b2, h, tuning))
	return {"terrain": GameRules.terrain_shelter(depth, h, tuning), "solid": solid,
		"trees": GameRules.tree_shelter(_tree_cover(p), tuning)}

func _wind_barriers() -> Array:
	var out: Array = ResourceSpawner.windbreak_barriers(get_tree())
	out.append_array(LandFeatures.wind_rocks)
	# S7：你自己堆起来的雪丘 / 雪墙 / 棚子也挡风，随阶段长高（开阔平地上否则哪里都点不着火，挖雪湿透了就没法烘干）
	if site != null:
		var wh := GameRules.shelter_wall_height(site.preset_id, site.stage(), ShelterBuilder.STAGES_MAX)
		if wh > 0.0:
			var fr := site.footprint_radius()
			out.append({"pos": Vector2(site.global_position.x, site.global_position.z), "h": wh, "r": fr * 0.8, "w": fr})
	return out

## 火在 p 点的迎风暴露 0..1（= 1 − 火高度处的挡风度）；超过 fire_blowout_dot 火就被吹灭（白天 / 夜里一致）。
func fire_exposure_at(p: Vector3) -> float:
	return 1.0 - wind_shelter_at(p, tuning.wind_fire_height_m)

## 在 p 点生火能否成功（与 _try_fire 同一套规则：背风 / 树根挡风 / 林木、树冠落雪、雪庇护所内禁火、材料）。
func fire_check_at(p: Vector3) -> Dictionary:
	var exposure := fire_exposure_at(p)
	# 判定的是火的位置，不是人站在哪（站在雪沟旁边往外生火是可以的）
	var inside_snow := site != null and site.is_snow_shelter() and site.stage() >= 1 \
		and Vector2(p.x - site.global_position.x, p.z - site.global_position.z).length() < tuning.shelter_inside_radius_m
	return GameRules.fire_check(_fire_wood(), inventory.bark, exposure, _under_canopy(p), inside_snow, tuning)

func _try_fire() -> void:
	var near := _nearest_fire(tuning.fire_warm_radius_m)
	if near:
		if not _spend_fire_wood(1):
			ui.toast(Loc.t("No dry wood left to add."))
			return
		near.add_fuel(tuning.campfire_minutes_per_wood)
		ui.toast(Loc.t("Added a log (+%d min of fire).") % int(tuning.campfire_minutes_per_wood))
		_skip(2.0)
		return
	var p := _fire_place()
	var check := fire_check_at(p)
	if not bool(check["ok"]):
		var reason := String(check["reason"])
		# 被风吹灭 / 落雪压灭：引火物已经烧掉了（代价让教训可记住）
		if reason.contains("wind") or reason.contains("branches"):
			inventory.spend({"bark": tuning.fire_tinder_cost})
			_skip(4.0)
		SessionLog.log_event("fire_fail", weather.clock_string(), {"reason": reason})
		ui.toast(reason, 5.0)
		return
	_spend_fire_wood(tuning.fire_wood_cost)
	inventory.spend({"bark": tuning.fire_tinder_cost})
	var fire := Campfire.new()
	fire.name = "Campfire"
	fire.position = p
	fire.warm_radius = tuning.fire_warm_radius_m
	main.add_child(fire)
	fire.ignite(tuning.fire_wood_cost * tuning.campfire_minutes_per_wood)
	_attach_fire_interactable(fire)
	_skip(5.0)
	audio.play_sfx("fire")
	SessionLog.log_event("fire", weather.clock_string())
	_mark("fire")
	ui.toast(Loc.t("Fire lit. Warm up, dry off, hold [E] for a hot drink. [F] adds a log."), 6.0)

func _attach_fire_interactable(fire: Campfire) -> void:
	var it := Interactable.new()
	it.kind = "fire"
	it.hold_seconds = 1.8
	it.reach_m = tuning.fire_warm_radius_m
	it.prompt_fn = func() -> String: return Loc.t("Melt snow & drink hot water") if fire.lit else ""
	it.handler = func() -> Dictionary:
		var gained := warmth.apply_hot_drink()
		prewarmed = true
		dampness = maxf(0.0, dampness - 0.5)   # 喝热水的同时烤干衣物（CORE_GAMEPLAY §4）
		return {"ok": true, "minutes": tuning.melt_snow_minutes, "msg": Loc.t("Hot water: +%d warmth.") % int(gained)}
	fire.add_child(it)

# ------------------------------------------------------------------ 世界标签

## 操作提示贴在目标上方（在屏幕底部时玩家根本注意不到）；探针、打火这类没有目标的贴在人头上方。
func _place_prompt() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head := player.global_position + Vector3.UP * 2.0
	if cam.is_position_behind(head):
		return
	var anchor := cam.unproject_position(head)
	if interaction.current != null and not player.is_probing and _fire_hold < 0.0:
		var item := interaction.current.global_position + Vector3.UP * 1.0
		if not cam.is_position_behind(item):
			var s := cam.unproject_position(item)
			anchor = Vector2(s.x, minf(s.y, anchor.y))
	ui.place_prompt(anchor)

func _update_world_callouts() -> void:
	if callouts == null:
		return
	# 最近的未采完立枯木（Read the Land 第 4 条）
	var pos := player.global_position
	var best: Interactable = null
	var best_d := 22.0
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it.kind != "deadwood" or it.uses_left == 0:
			continue
		var d := it.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = it
	# 第三次评审（UI）：建造模式只留选址需要的标签（探针 / 深雪）；庇护所完工后"深雪"不再有用
	var building := build.active
	if best and not building:
		callouts.set_callout("deadwood", best.global_position + Vector3(0, 1.0, 0), Loc.t("Deadwood"), Loc.t("Harvest for fuel"),
			Color(1.0, 0.55, 0.12), Vector2(28.0, 18.0), 1)
	elif callouts.has_callout("deadwood"):
		callouts.remove_callout("deadwood")
	_update_near_item_callout(building)
	_update_fire_callout()
	# 工地还缺垫层时标出最近的一处（不限距离：垫层点围绕出生点散布，工地可能离得很远）
	var bedding := _nearest_bedding() if _bedding_short() > 0 and not building else null
	if bedding:
		callouts.set_callout("bedding", bedding.global_position + Vector3(0, 0.7, 0), Loc.t("Bedding"),
			Loc.t("Dry grass") if bedding.kind == "grass" else Loc.t("Spruce boughs"),
			Color(0.55, 0.85, 0.45), Vector2(28.0, -58.0), 2)
	elif callouts.has_callout("bedding"):
		callouts.remove_callout("bedding")
	# 第二次评审：第 1 章（教程）里衣服湿了又没有火 → 标出最近的、按同一套火规则真的点得着的地方，教会"烘干"这一步
	var teach_fire := LevelState.active() and LevelState.level.index == 1 and GameRules.clothing_state(dampness, tuning) != "dry" \
		and get_tree().get_nodes_in_group("campfires").is_empty() and not building
	if teach_fire:
		if Time.get_ticks_msec() - _fire_spot_ms > 2000:
			_fire_spot = _sheltered_fire_spot(pos)
			_fire_spot_ms = Time.get_ticks_msec()
		if _fire_spot != Vector3.INF:
			callouts.set_callout("fire_spot", _fire_spot + Vector3(0, 0.6, 0), Loc.t("Sheltered fire spot"),
				Loc.t("Out of the wind · [F] here"), Color(1.0, 0.5, 0.2), Vector2(24.0, -30.0), 4)
	if not teach_fire or _fire_spot == Vector3.INF:
		if callouts.has_callout("fire_spot"):
			callouts.remove_callout("fire_spot")
	if site != null and site.is_complete():
		callouts.remove_prefix("deeper_")
		callouts.remove_callout("probe")
	callouts.player_world = player.global_position + Vector3(0, 0.9, 0)
	# R3 + 第三次评审：庇护所 = 固定 HUD 卡片（名字 · 阶段 · 入口朝向 · 下一步）；世界里只在入口画环和箭头
	if site != null:
		callouts.set_marker("my_shelter", site.entrance_point(), Color(1.0, 0.7, 0.35))
		var t := _shelter_card_text()
		ui.set_shelter_card(t[0], t[1], site.is_complete())
	else:
		if callouts.has_callout("my_shelter"):
			callouts.remove_callout("my_shelter")
		ui.set_shelter_card("", "", false)

## 庇护所卡片的两行：["SNOW CAVE (RAISED PLATFORM) · 3/5", "Next: … · needs … · 12 m away"]。
func _shelter_card_text() -> Array:
	var p := site.builder.active_preset()
	var title := "%s  ·  %d/%d" % [Loc.t(p.display_name).to_upper(), site.stage(), ShelterBuilder.STAGES_MAX]
	var parts: Array[String] = []
	var d := Vector2(player.global_position.x - site.global_position.x, player.global_position.z - site.global_position.z).length()
	if site.is_complete():
		title += "  ✓"
		var lee := GameRules.entrance_wind_angle(site.entrance_dir, wind.get_wind_direction_3d()) >= 90.0
		parts.append((Loc.t("Entrance faces %s, out of the wind") if lee else Loc.t("Entrance faces %s, INTO the wind")) % _dir_word(site.entrance_dir))
		parts.append(Loc.t("You're in it · [N] rest when ready") if _inside_site() else Loc.t("[N] rest when ready"))
	else:
		parts.append(Loc.t("Next: %s") % site.next_stage_title())
		var setting := site.ready_at - weather.current_time_minutes
		if setting > 0.0:
			parts.append(Loc.t("snow setting: %d min") % int(ceil(setting)))
		var rest := site.remaining_cost()
		var names := _material_names()
		var miss: Array[String] = []
		for k in rest:
			var have := site.pile.total(k, inventory)
			if have < int(rest[k]):
				miss.append("%d %s" % [int(rest[k]) - have, names.get(k, k)])
		if not miss.is_empty():
			parts.append(Loc.t("still to gather: %s") % ", ".join(miss))
		if _bedding_short() > 0:
			var near_bed := _nearest_bedding()
			if near_bed:
				parts.append(Loc.t("nearest bedding: %d m %s") % _bearing_to(near_bed))
		if interaction.current != site.interactable:
			parts.append(Loc.t("Return to site [E]"))
	if d > 8.0 and not _inside_site():
		parts.append(Loc.t("%d m away") % int(round(d)))
	if not site.pile.is_empty():
		parts.append(Loc.t("pile: %d wood, %d bedding") % [site.pile.amount("wood"), site.pile.amount("bedding")])
	return [title, "  ·  ".join(parts)]

## 水平方向向量 → "north" / "south-east" 等（世界约定：-Z = 北，+X = 东）。
func _dir_word(v: Vector3) -> String:
	var bearing := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	return GameRules.wind_word(int(round(bearing / 45.0)) % 8)

## 世界标签不能压住的 HUD 区域（画布坐标）。
func _hud_rects() -> Array[Rect2]:
	var out := ui.occupied_rects()
	for path in ["TopRightCard", "Compass", "Instructions", "ProbePopup"]:
		var c := hud.get_node_or_null(path) as Control
		if c and c.is_visible_in_tree():
			out.append(c.get_global_rect())
	for n in [hud.get_parent().get_node_or_null("HUDWarmth"), _cutaway_panel]:
		if n is Control and (n as Control).is_visible_in_tree():
			out.append((n as Control).get_global_rect())
	return out

# ------------------------------------------------------------------ 入夜结算输入

## 火（用户定调：所有庇护所同一条规则）：睡的地方附近有火堆，它就留到夜里，烧的是你的柴堆。
## 完工倒棚的反射火已经在 input 里；这里处理其它情况。雪洞里仍不能生火（D3），火在外面。
func _add_campfire_to_night(input: Dictionary) -> void:
	if bool(input.get("fire_lit", false)):
		for f in get_tree().get_nodes_in_group("campfires"):
			if site != null and f == site.fire and (f as Campfire).lit:
				input["fire_minutes_left"] = (f as Campfire).fuel_minutes
		return
	var bed := site.global_position if site != null and site.stage() > 0 else player.global_position
	var best: Campfire = null
	var best_d := tuning.night_fire_reach_m
	for f in get_tree().get_nodes_in_group("campfires"):
		var d := Vector2((f as Node3D).global_position.x - bed.x, (f as Node3D).global_position.z - bed.z).length()
		if d <= best_d and ((f as Campfire).lit or inventory.wood > 0 or (site != null and site.pile.amount("wood") > 0)):
			best_d = d
			best = f as Campfire
	if best == null:
		return
	var p := best.global_position
	input["campfire_near"] = true
	input["firewood_logs"] = float(inventory.wood + (site.pile.amount("wood") if site != null else 0))
	input["fire_minutes_left"] = best.fuel_minutes if best.lit else 0.0
	input["fire_exposure"] = fire_exposure_at(p)

func night_input() -> Dictionary:
	var input: Dictionary
	if site == null or site.stage() == 0:
		var p := player.global_position
		input = {
			"shelter_type": "None",
			"snow_depth_meters": SnowField.snow_at(p.x, p.z),
			"terrain_shelter": SnowField.lee_factor_at(p.x, p.z),
			"completion_ratio": 0.0,
		}
	else:
		input = site.builder.build_night_sim_input(warmth)
		var sp := site.global_position
		var lee := SnowField.lee_factor_at(sp.x, sp.z)
		input["wind_angle_diff"] = GameRules.entrance_wind_angle(site.entrance_dir, wind.get_wind_direction_3d())
		input["terrain_shelter"] = clampf(lee + (0.4 if site.near_windbreak else 0.0), -1.0, 1.0)
		if site.is_snow_shelter() and site.stage() >= 1:
			var roof := tuning.roof_thickness_min_m if site.quick_roof else tuning.roof_thickness_good_m
			input["roof_thickness_meters"] = minf(roof, float(input.get("snow_depth_meters", 0.0)) * 0.3)
		if bool(input.get("has_vent", false)):
			input["vent_count"] = site.vent_count
			# 夜雪堵通风（T3.1）：降雪够大 + 只有一根 + 没插木棍 → 部分堵塞（空气分封顶，报告解释）
			input["vent_snow_clogged"] = site.vent_count == 1 and not site.vent_stick \
				and weather.atmosphere.snowfall >= tuning.vent_clog_snowfall
		if site.preset_id == "LeanTo":
			# 倒棚反射火在入夜时用备柴重新点燃：只要火塘完工且有干柴即可（白天火是否还在烧不影响夜里）
			var logs := site.pile.total("wood", inventory)
			var lit := site.is_complete() and logs > 0
			input["fire_lit"] = lit
			input["fire_held"] = lit
			input["firewood_logs"] = float(logs)
			input["fuel_hours"] = float(logs) * tuning.fire_fuel_hours_per_log
			input["fire_exposure"] = GameRules.fire_exposure(lee, 1.0 if site.near_windbreak else 0.0, _tree_cover(sp))
	_add_campfire_to_night(input)
	input["starting_warmth"] = warmth.body_warmth
	input["prewarmed"] = prewarmed
	input["dampness"] = dampness   # R1：入睡时受潮进入过夜结算
	# 装备（S6）：防潮垫加到地面隔热
	# 地面隔热：枝条地板底子 + 睡前多铺的枝条捆（背包里剩下的垫层）+ 防潮垫 + 兽皮
	var spare_bedding := inventory.bedding + (site.pile.amount("bedding") if site != null else 0)
	input["bedding_quality"] = GameRules.ground_insulation(float(input.get("bedding_quality", 0.0)) > 0.5, spare_bedding,
		bool(gear["pad"]), bool(gear.get("hides", false)), tuning)
	input["wind_speed_kmh"] = weather.current_wind_kmh()
	input["night_temp_c"] = weather.night_temp_c()
	# 夜晚到明天日出为止（早睡要熬更久）；日落前那段还没到夜间气温
	var sunrise := SunModel.sunrise_minutes(tuning.sun_latitude_deg, tuning.sun_declination_deg, tuning.solar_noon_minutes) + 1440.0
	input["night_hours"] = maxf(sunrise - weather.current_time_minutes, 60.0) / 60.0
	input["daylight_minutes"] = maxf(weather.minutes_to_sunset(), 0.0)
	return input
