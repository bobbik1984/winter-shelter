class_name GameDirector
extends Node

## 一局游戏的总导演（M2 循环）：简报 → 自由行动（探测 / 采集 / 建造 / 生火）→ 入夜 → 6 维报告 → 重开。
## 只做编排：规则在 GameRules / NightSimulator / ShelterBuilder，数值在 Tuning，外观在各自节点。
## 由 MainLevel 在 _ready 中创建并注入引用。

enum State { BRIEFING, PLAYING, NIGHT_FADE, REPORT, PAUSED }

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
var site: ShelterSite
var graphics: GraphicsSettings
var audio: AmbientAudio
var snowfall: Snowfall
var spindrift: Spindrift
var headlamp: SpotLight3D
var state: State = State.BRIEFING

var prewarmed := false
## 全天模式（简报页按 2）：10:00 开局。记录与标准模式分开保存。
var full_day := false
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
var _last_minutes := 0.0
var _markers: Array[Node3D] = []
var _deeper_count := 0
var _deeper_points: Array[Vector3] = []
var _cutaway_panel: Control
var _compass: Control
var _forced := false
var _probe_count := 0
var _best_depth := 0.0
var _zero_t := 0.0
var _startup_frames := 0
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
	Loc.ensure_cjk_font()
	HoldAssist.load_setting()
	HoldAssist.latched = ""
	tuning = load("res://resources/tuning.tres") as Tuning
	wind = load("res://resources/default_wind.tres") as WindData

	inventory = Inventory.new()
	inventory.max_wood = tuning.max_wood
	inventory.has_extra_clothing = true
	add_child(inventory)
	inventory.changed.connect(_on_inventory_changed)

	interaction = InteractionController.new()
	interaction.player = player
	interaction.tuning = tuning
	add_child(interaction)
	interaction.completed.connect(_on_interaction_completed)

	spawner = ResourceSpawner.new()
	spawner.name = "Resources"
	spawner.tuning = tuning
	spawner.on_harvest = _on_harvest
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

	var prints := Footprints.new()
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
	_cutaway_panel = hud.get_parent().get_node_or_null("ShelterCutawayPanel") as Control
	_compass = hud.get_node_or_null("Compass") as Control
	if _cutaway_panel:
		_cutaway_panel.visible = false
	var instr := hud.get_node_or_null("Instructions") as Label
	if instr:
		instr.text = Loc.t("[WASD] Move   [Space] Probe   [E] Gather / Build   [B] Build   [F] Fire   [N] Sleep   [H] Field guide")

	_apply_static_labels()
	GameInput.ensure_joypad()
	warmth.auto_update = false
	warmth.has_extra_clothing = true
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
	ui.show_briefing(true, valley_name() + "  ·  " + weather.forecast_text())

func start_game() -> void:
	state = State.PLAYING
	ui.show_briefing(false)
	player.controls_enabled = true
	interaction.enabled = true
	weather.time_scale = _saved_time_scale
	ui.toast(Loc.t("Probe the snow [Space]. Deep, leeward snow is where a snow cave works."), 6.0)

func _sleep(forced: bool) -> void:
	if state != State.PLAYING:
		return
	_forced = forced
	if build.active:
		build.exit()
	_mark("sleep")
	state = State.NIGHT_FADE
	_fade_t = 0.0
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
		"fire": Loc.t("fire lit"), "sleep": Loc.t("bed")}
	var start := "%02d:%02d" % [tuning.full_day_start_minutes / 60, tuning.full_day_start_minutes % 60] if full_day \
		else "%02d:%02d" % [tuning.start_minutes / 60, tuning.start_minutes % 60]
	var events: Array = [[start, Loc.t("start")], [weather.sunset_clock(), Loc.t("sunset")]]
	for e in _timeline:
		events.append([e[1], names.get(e[0], e[0])])
	# 时刻 "HH:MM" 按字典序即时间序；日落按真实先后插入，玩家能看出自己是日落前还是后完工
	events.sort_custom(func(x, y) -> bool: return String(x[0]) < String(y[0]))
	var parts: Array[String] = []
	for e in events:
		parts.append("%s %s" % [e[1], e[0]])
	return Loc.t("Your day: ") + "  →  ".join(parts)

func _show_report() -> void:
	state = State.REPORT
	var input := night_input()
	var report := NightSimulator.evaluate(input, tuning)
	var data := NightReportText.build(report, input, tuning)
	var name_ := Loc.t("None — slept in the open")
	if site:
		name_ = Loc.t("%s (%d/5 stages)") % [Loc.t(site.builder.active_preset().display_name), site.stage()]
	data["timeline"] = _timeline_text()
	ui.show_report(data, name_)
	Records.save(String(input.get("shelter_type", "None")) + ("@day" if full_day else ""), String(data["outcome"]), int(round(float(report["details"].get("weighted_average", 0.0)))))


# ------------------------------------------------------------------ 输入

func _joy_to_key(btn: JoyButton) -> Key:
	return GameInput.joy_to_key(btn, state, build.active)

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
			if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_1:
				start_game()
			elif k == KEY_2:
				full_day = true
				weather.current_time_minutes = float(tuning.full_day_start_minutes)
				weather.advance_minutes(0.0)
				_last_minutes = weather.current_time_minutes
				start_game()
			elif k == KEY_L:
				_toggle_lang()
				ui.show_briefing(true, valley_name() + "  ·  " + weather.forecast_text())
		State.REPORT:
			if k == KEY_R:
				_restart()
		State.PAUSED:
			match k:
				KEY_ESCAPE, KEY_P: _set_paused(false)
				KEY_R: _restart()
				KEY_Q: get_tree().quit()
				KEY_C: ui.toggle_credits()
		State.PLAYING:
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
				KEY_H: ui.toggle_guide()
				KEY_B: _enter_build()
				KEY_F: _begin_fire()
				KEY_N: _request_sleep()

## 重开：换到下一个山谷（同一结构、不同的起伏与雪深分布），再重载场景。
func _restart() -> void:
	var seeds: Array = TerrainHeight.VALLEY_SEEDS
	TerrainHeight.SEED = seeds[(seeds.find(TerrainHeight.SEED) + 1) % seeds.size()]
	get_tree().reload_current_scene()

func valley_name() -> String:
	return Loc.t("Valley %d of %d") % [TerrainHeight.VALLEY_SEEDS.find(TerrainHeight.SEED) + 1, TerrainHeight.VALLEY_SEEDS.size()]

func _set_paused(on: bool) -> void:
	state = State.PAUSED if on else State.PLAYING
	player.controls_enabled = not on
	interaction.enabled = not on
	weather.time_scale = 0.0 if on else _saved_time_scale
	ui.show_pause(on)

## [L]：English ⇄ 中文（保存到 user://settings.cfg），重建缓存的面板与静态标签。
func _toggle_lang() -> void:
	Loc.set_lang("en" if Loc.is_zh() else "zh")
	ui.relocalize()
	_apply_static_labels()
	_on_inventory_changed()
	ui.toast("中文" if Loc.is_zh() else "English", 1.5)

func _apply_static_labels() -> void:
	var instr := hud.get_node_or_null("Instructions") as Label
	if instr:
		instr.text = Loc.t("[WASD] Move   [Space] Probe   [E] Gather / Build   [B] Build   [F] Fire   [N] Sleep   [H] Field guide")
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
	if done or _sleep_confirm_t > 0.0:
		_sleep(false)
		return
	_sleep_confirm_t = 4.0
	var have := Loc.t("no shelter") if site == null else Loc.t("a shelter only %d/5 done") % site.stage()
	ui.toast(Loc.t("Sleep now, with %s? Press N again to confirm.") % have, 4.0)

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
			_fade_t += delta
			ui.set_fade(clampf(_fade_t / 1.2, 0.0, 1.0))
			var vignette := _vignette_texture()
			var total := tuning.night_fade_seconds + (3.5 if vignette else 0.0)
			if vignette:
				var a := clampf((_fade_t - 1.4) / 0.8, 0.0, 1.0) * clampf((total - _fade_t) / 0.6, 0.0, 1.0)
				ui.show_vignette(vignette, Loc.t("Outside, the wind howls. Inside, the candle glows and the air stays still."), a)
				audio.shelter_level = 2
			if _fade_t >= total:
				_show_report()
		State.REPORT:
			ui.set_fade(1.0)

func _tick_playing(delta: float) -> void:
	# 游戏分钟推进 → 火堆燃烧
	var now := weather.current_time_minutes
	var dm := now - _last_minutes
	_last_minutes = now
	if dm > 0.0:
		for f in get_tree().get_nodes_in_group("campfires"):
			(f as Campfire).burn(dm)

	_update_warmth(delta, 1.0)
	player.working = interaction.progress > 0.0
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
	else:
		var p := interaction.prompt_text()
		if player.is_probing:
			ui.set_prompt(Loc.t("Probing snow depth…"), player._probe_t / tuning.probe_seconds if player._probe_t > 0.0 else 0.0)
		elif _fire_hold >= 0.0:
			ui.set_prompt(Loc.t("Striking the ferro rod… keep holding [F]"), _fire_hold / tuning.fire_hold_seconds)
		elif p != "":
			ui.set_prompt("[E]  " + p, interaction.progress)
		else:
			ui.set_prompt("", 0.0)

	# 世界内洞内视图（T4.4）
	if site:
		site.set_inside(site.preset_id in ["RaisedCave", "BasicCave"] and site.stage() >= 1 and _inside_site())

	# 剖面面板：建造雪洞时或身处雪洞内显示（T3.6 触发）
	if _cutaway_panel:
		var show := build.active and build.preset_id in ["RaisedCave", "BasicCave"]
		show = show or (site != null and site.preset_id in ["RaisedCave", "BasicCave"] and site.stage() >= 1 and _inside_site())
		_cutaway_panel.visible = show
		if show and _cutaway_panel.has_method("set_progress"):
			_cutaway_panel.set_progress(site.stage() if site != null and not build.active else -1)

	# 提示行：影子就是时钟（V3）
	if hud and hud.has_node("TopRightCard/VBox/HintLabel"):
		var hint := hud.get_node("TopRightCard/VBox/HintLabel") as Label
		hint.text = GameRules.tip_for(weather.minutes_to_sunset(), weather.sun_elevation_deg,
			warmth.body_warmth, site != null and site.stage() > 0, site != null and site.is_complete(), tuning)

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
		ctx["missing"] = inventory.missing_text(site.next_stage_cost())
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
	var lee := SnowField.lee_factor_at(pos.x, pos.z)
	var wb_d := ResourceSpawner.nearest_windbreak_distance(get_tree(), pos)
	var cover := _tree_cover(pos)
	var windbreak := maxf(1.0 - GameRules.fire_exposure(lee, wb_d < 3.0, cover), 0.0)
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
	warmth.has_extra_clothing = GameRules.clothing_effective(true, dampness, tuning)
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
	_mark("probe")
	_best_depth = maxf(_best_depth, depth)
	audio.play_sfx("probe")
	var cls := GameRules.classify_depth(depth, tuning)
	_add_marker(pos, depth, cls["color"])
	if callouts:
		callouts.set_callout("probe", pos + Vector3(0, 0.6, 0), String(cls["title"]), String(cls["sub"]), cls["color"])
		# D4：Deeper snow 只在玩家探测过、且达到雪洞深度的位置出现
		if depth >= tuning.snow_depth_cave_min_m and _deeper_count < MAX_DEEPER_LABELS:
			var far_enough := true
			for q in _deeper_points:
				if q.distance_to(pos) < 8.0:
					far_enough = false
			if far_enough:
				_deeper_points.append(pos)
				callouts.set_callout("deeper_%d" % _deeper_count, pos + Vector3(0, 0.4, 0), Loc.t("Deeper snow"),
					Loc.t("Ideal for shelter"), Color(0.52, 0.72, 1.0), Vector2(-200.0, 20.0))
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

func _on_harvest(it: Interactable) -> Dictionary:
	match it.kind:
		"deadwood":
			var got := inventory.add("wood", tuning.wood_per_harvest)
			if got <= 0:
				return {"ok": false, "msg": Loc.t("Your pack can't carry more wood.")}
			return {"ok": true, "minutes": tuning.gather_minutes, "msg": Loc.t("+%d dry wood — standing dead trees burn well.") % got}
		"birch":
			inventory.add("bark", tuning.bark_per_harvest)
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5, "msg": Loc.t("+%d birch bark — the best tinder there is.") % tuning.bark_per_harvest}
		"grass":
			inventory.add("bedding", tuning.bedding_per_harvest)
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5, "msg": Loc.t("+%d bedding (dry grass).") % tuning.bedding_per_harvest}
		"bough":
			inventory.add("bedding", tuning.bedding_per_harvest)
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5, "msg": Loc.t("+%d bedding (spruce boughs).") % tuning.bedding_per_harvest}
		"wet_log":
			return {"ok": true, "minutes": tuning.gather_minutes * 0.5,
				"msg": Loc.t("This fallen log is soaked through — it won't burn. Look for STANDING dead trees.")}
	return {"ok": false, "msg": ""}

func _on_interaction_completed(target: Interactable, result: Dictionary) -> void:
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
		ui.set_inventory(inventory.wood, inventory.bark, inventory.bedding)
	if player and player.visual_node is HikerVisual:
		(player.visual_node as HikerVisual).set_load(inventory.wood, inventory.bedding)

# ------------------------------------------------------------------ 建造（T2.4–T2.6）

func _enter_build() -> void:
	if site != null and site.stage() > 0:
		ui.toast(Loc.t("You're already building a %s. Hold [E] at the site to continue.") % Loc.t(site.builder.active_preset().display_name))
		return
	interaction.enabled = false
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
	site.interactable.hold_seconds = tuning.stage_hold_seconds
	site.interactable.prompt_fn = _site_prompt
	site.interactable.handler = _on_build_stage
	_mark("site")
	_exit_build()
	ui.toast(Loc.t("Site marked. Hold [E] at the site to work: %s") % site.next_stage_title(), 6.0)

func _needs_vent_stick() -> bool:
	return site != null and site.is_complete() and site.is_snow_shelter() and site.vent_count == 1 \
		and not site.vent_stick and weather.atmosphere.snowfall > 0.05

func _site_prompt() -> String:
	if _needs_vent_stick():
		return Loc.t("Push a stick through the vent (1 wood) — keeps it clear in falling snow")
	if site == null or site.is_complete():
		return ""
	var cost := site.next_stage_cost()
	var need := ""
	if not cost.is_empty():
		var parts: Array[String] = []
		for k in cost:
			parts.append("%d %s" % [cost[k], k])
		need = Loc.t("  (needs ") + ", ".join(parts) + ")"
	return Loc.t("%s%s  ·  ~%d min") % [site.next_stage_title(), need, int(site.stage_minutes() / _efficiency())]

func _efficiency() -> float:
	return GameRules.work_efficiency(warmth.get_action_efficiency(), weather.minutes_to_sunset(), tuning)

func _on_build_stage() -> Dictionary:
	if _needs_vent_stick():
		if not inventory.spend({"wood": 1}):
			return {"ok": false, "msg": Loc.t("You need 1 dry wood for a vent stick.")}
		site.vent_stick = true
		return {"ok": true, "minutes": 3.0, "msg": Loc.t("Stick in the vent: you can poke it clear during the night.")}
	var cost := site.next_stage_cost()
	if not inventory.has_all(cost):
		return {"ok": false, "msg": Loc.t("Not enough materials — still need %s.") % inventory.missing_text(cost)}
	inventory.spend(cost)
	var minutes := site.stage_minutes() / _efficiency()
	# 在雪下挖掘时人已在风外：按庇护等级 1 结算体温（倒棚施工仍暴露）
	_skip(minutes, 1 if site.is_snow_shelter() else 0)
	if site.is_snow_shelter():
		dampness = minf(1.0, dampness + tuning.damp_per_dig_stage)
		_update_cloth_label()
	var r := site.advance()
	if site.preset_id == "LeanTo" and site.is_complete() and site.fire:
		# 阶段完成时才点燃（工时已流逝）；之后由玩家 [F] 添柴维持
		site.fire.ignite(tuning.campfire_minutes_per_wood * 2.0)
		_attach_fire_interactable(site.fire)
	minutes = 0.0
	var msg := Loc.t("Stage %d/5 done — %s") % [int(r["stage"]), Loc.t(String(r["stage_title"]))]
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
	if _nearest_fire(2.6):
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

func _try_fire() -> void:
	var near := _nearest_fire(2.6)
	if near:
		if inventory.wood <= 0:
			ui.toast(Loc.t("No dry wood left to add."))
			return
		inventory.spend({"wood": 1})
		near.add_fuel(tuning.campfire_minutes_per_wood)
		ui.toast(Loc.t("Added a log (+%d min of fire).") % int(tuning.campfire_minutes_per_wood))
		_skip(2.0)
		return
	var p := player.global_position + player.facing() * 1.3
	var lee := SnowField.lee_factor_at(p.x, p.z)
	var near_wb := ResourceSpawner.nearest_windbreak_distance(get_tree(), p) < 3.5
	var exposure := GameRules.fire_exposure(lee, near_wb, _tree_cover(p))
	var inside_snow := site != null and site.is_snow_shelter() and site.stage() >= 1 and _inside_site()
	var check := GameRules.fire_check(inventory.wood, inventory.bark, exposure, _under_canopy(p), inside_snow, tuning)
	if not bool(check["ok"]):
		var reason := String(check["reason"])
		# 被风吹灭 / 落雪压灭：引火物已经烧掉了（代价让教训可记住）
		if reason.contains("wind") or reason.contains("branches"):
			inventory.spend({"bark": tuning.fire_tinder_cost})
			_skip(4.0)
		ui.toast(reason, 5.0)
		return
	inventory.spend({"wood": tuning.fire_wood_cost, "bark": tuning.fire_tinder_cost})
	var fire := Campfire.new()
	fire.name = "Campfire"
	fire.position = p
	main.add_child(fire)
	fire.ignite(tuning.fire_wood_cost * tuning.campfire_minutes_per_wood)
	_attach_fire_interactable(fire)
	_skip(5.0)
	audio.play_sfx("fire")
	_mark("fire")
	ui.toast(Loc.t("Fire lit. Warm up, dry off, and melt snow for a hot drink [E]."), 5.0)

func _attach_fire_interactable(fire: Campfire) -> void:
	var it := Interactable.new()
	it.kind = "fire"
	it.hold_seconds = 1.8
	it.ring_radius = 0.9
	it.prompt_fn = func() -> String: return Loc.t("Melt snow & drink hot water") if fire.lit else ""
	it.handler = func() -> Dictionary:
		var gained := warmth.apply_hot_drink()
		prewarmed = true
		dampness = maxf(0.0, dampness - 0.5)   # 喝热水的同时烤干衣物（CORE_GAMEPLAY §4）
		return {"ok": true, "minutes": tuning.melt_snow_minutes, "msg": Loc.t("Hot water: +%d warmth.") % int(gained)}
	fire.add_child(it)

# ------------------------------------------------------------------ 世界标签

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
	if best:
		callouts.set_callout("deadwood", best.global_position + Vector3(0, 1.0, 0), Loc.t("Deadwood"), Loc.t("Harvest for fuel"),
			Color(1.0, 0.55, 0.12), Vector2(28.0, 18.0))
	elif callouts.has_callout("deadwood"):
		callouts.remove_callout("deadwood")

# ------------------------------------------------------------------ 入夜结算输入

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
			var lit := site.is_complete() and inventory.wood > 0
			input["fire_lit"] = lit
			input["fire_held"] = lit
			input["firewood_logs"] = float(inventory.wood)
			input["fuel_hours"] = float(inventory.wood) * tuning.fire_fuel_hours_per_log
			input["fire_exposure"] = GameRules.fire_exposure(lee, site.near_windbreak, _tree_cover(sp))
	input["starting_warmth"] = warmth.body_warmth
	input["prewarmed"] = prewarmed
	input["wind_speed_kmh"] = weather.current_wind_kmh()
	input["night_temp_c"] = weather.night_temp_c()
	return input
