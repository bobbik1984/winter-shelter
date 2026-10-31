class_name GameUI
extends CanvasLayer

## 游戏循环的屏幕 UI（代码构建）：交互提示 + 进度、背包托盘、消息、建造面板、
## 开场简报（T2.9）、入夜黑屏与 6 维报告（T2.8 / T3.7）。样式与现有 HUD 卡片一致。

const INK := Color(0.035, 0.05, 0.075, 0.88)
const CREAM := Color(0.96, 0.91, 0.80)
const MUTED := Color(0.75, 0.78, 0.84)
const AMBER := Color(1.0, 0.62, 0.20)

var _prompt_card: PanelContainer
var _prompt_label: Label
var _progress: ProgressBar
var _tray: Label
var _objective: Label
var _toast: Label
var _toast_t := 0.0
var _build_card: PanelContainer
var _build_title: Label
var _build_reason: Label
var _build_info: Label
var _briefing: Control
var _fade: ColorRect
var _report: Control
var _pause: Control
var _guide: Control
var _vignette: Control
var _vignette_tex: TextureRect

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 交互提示（底部居中）
	_prompt_card = _card(AMBER)
	_prompt_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_card.position = Vector2(-220, -150)
	_prompt_card.custom_minimum_size = Vector2(440, 0)
	root.add_child(_prompt_card)
	var pv := VBoxContainer.new()
	_prompt_card.add_child(pv)
	_prompt_label = _label("", 15, CREAM)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(_prompt_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	_progress.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	_progress.add_theme_stylebox_override("background", bg)
	pv.add_child(_progress)
	_prompt_card.visible = false

	# 背包托盘（左下，操作说明上方）
	var tray_card := _card(Color(0.62, 0.78, 0.95))
	tray_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tray_card.position = Vector2(32, -140)
	root.add_child(tray_card)
	var tv := VBoxContainer.new()
	tray_card.add_child(tv)
	_objective = _label("", 14, AMBER)
	tv.add_child(_objective)
	_tray = _label("", 13, CREAM)
	tv.add_child(_tray)

	# 消息（顶部居中）
	_toast = _label("", 17, CREAM)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-330, 250)
	_toast.custom_minimum_size = Vector2(660, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.95))
	_toast.add_theme_constant_override("outline_size", 6)
	root.add_child(_toast)

	# 建造面板
	_build_card = _card(Color(0.45, 1.0, 0.55))
	_build_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_card.position = Vector2(-330, -205)
	_build_card.custom_minimum_size = Vector2(660, 0)
	root.add_child(_build_card)
	var bv := VBoxContainer.new()
	_build_card.add_child(bv)
	_build_title = _label("", 16, CREAM)
	_build_reason = _label("", 13, CREAM)
	_build_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_info = _label("", 12, MUTED)
	_build_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(_build_title)
	bv.add_child(_build_reason)
	bv.add_child(_build_info)
	bv.add_child(_label("[Tab] shelter type   [R] rotate entrance   [T] roof   [2] vents   [E] place   [B] cancel", 12, MUTED))
	_build_card.visible = false

	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.02, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)

func _card(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = INK
	s.border_width_left = 3
	s.border_color = accent
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)
	return p

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------------------------------------------------------------- API

func set_prompt(text: String, progress: float) -> void:
	_prompt_card.visible = text != "" and not _build_card.visible
	_prompt_label.text = text
	_progress.value = progress
	_progress.visible = progress > 0.0

func set_inventory(wood: int, bark: int, bedding: int) -> void:
	_tray.text = "Dry wood  %d     Birch bark  %d     Bedding  %d" % [wood, bark, bedding]

func set_objective(text: String) -> void:
	_objective.text = "▸ " + text

func toast(text: String, seconds: float = 4.0) -> void:
	_toast.text = text
	_toast_t = seconds
	_toast.modulate.a = 1.0

func show_build(visible_: bool, title: String = "", reason: String = "", ok: bool = true, info: String = "") -> void:
	_build_card.visible = visible_
	if not visible_:
		return
	_build_title.text = title
	_build_reason.text = reason
	_build_reason.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if ok else Color(1.0, 0.5, 0.42))
	_build_info.text = info
	var s := _build_card.get_theme_stylebox("panel") as StyleBoxFlat
	s.border_color = Color(0.45, 1.0, 0.55) if ok else Color(1.0, 0.35, 0.25)

func set_fade(a: float) -> void:
	_fade.color.a = a

func show_briefing(on: bool, forecast: String = "") -> void:
	if on and _briefing == null:
		_briefing = _make_briefing(forecast)
		get_child(0).add_child(_briefing)
	if _briefing:
		_briefing.visible = on

func _make_briefing(forecast: String = "") -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.035, 0.06, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(760, 0)
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)
	var title := _label("SNOW SHELTER", 64, CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("C H A L L E N G E", 22, CREAM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var tag := _label("FIND  ·  GATHER  ·  BUILD  ·  SURVIVE", 15, AMBER)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	v.add_child(HSeparator.new())
	var body := _label("January 14, 14:20. −17 °C, a strong west wind, and the sun sets at 16:18.\n" +
		"You have about two hours of light to find deep snow, gather what you need and build a shelter for the night.\n\n" +
		"Read the land: trees lean away from the wind, snow piles up on leeward slopes, standing dead trees are dry fuel — " +
		"and the shadows tell you how much daylight is left.", 15, MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	if forecast != "":
		var fl := _label(forecast, 15, AMBER)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(fl)
	var keys := _label("[WASD] move    [Space] hold to probe snow depth    [E] hold to gather / build    [F10] graphics\n" +
		"[B] build mode    [F] light fire / add wood    [N] sleep    [V] camera    [Wheel] zoom", 13, CREAM)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(keys)
	var rec := GameDirector.records_text()
	if rec != "":
		var rl := _label(rec, 13, MUTED)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rl)
	var go := _label("Press  ENTER  to begin", 18, AMBER)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(go)
	return shade

## 野外手册（参考图右侧 KEY RESOURCES / READ THE LAND 两块）：[H] 开关。
func toggle_guide() -> void:
	if _guide == null:
		var card := _card(Color(0.62, 0.78, 0.95))
		card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		card.position = Vector2(-470, -230)
		card.custom_minimum_size = Vector2(440, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		v.add_child(_label("READ THE LAND", 16, CREAM))
		for line in [
				"Trees show wind direction — branches are short on the windward side, crowns lean downwind.",
				"Snow drifts reveal depth — leeward slopes collect the deepest snow. Probe to be sure.",
				"Standing dead trees mean fuel — fallen logs are wet and won't burn.",
				"Rootballs and thick forest break the wind — shelter there, and light fires there.",
				"Shadows tell time — the longer they get, the less daylight you have left.",
			]:
			var l := _label("•  " + line, 13, MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(l)
		v.add_child(HSeparator.new())
		v.add_child(_label("KEY RESOURCES", 16, CREAM))
		for line in ["Birch bark — tinder (white trunk, black bands)", "Dry grass / spruce boughs — bedding",
				"Dry wood — standing dead trees", "Snow — melt it over a fire for a hot drink"]:
			v.add_child(_label("•  " + line, 13, MUTED))
		v.add_child(_label("[H] close", 12, AMBER))
		_guide = card
		get_child(0).add_child(card)
	else:
		_guide.visible = not _guide.visible

func show_pause(on: bool) -> void:
	if on and _pause == null:
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.035, 0.06, 0.75)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.add_child(center)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		center.add_child(v)
		var t := _label("PAUSED", 40, CREAM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		for line in ["[Esc] resume      [R] restart      [Q] quit",
				"", "[WASD] move    [Space] hold: probe snow    [E] hold: gather / build / drink",
				"[B] build mode — [Tab] type, [R] rotate entrance, [E] place",
				"[F] light fire / add wood    [N] sleep    [V] camera    [Wheel] zoom    [F10] graphics"]:
			var l := _label(line, 15 if line.begins_with("[Esc]") else 13, AMBER if line.begins_with("[Esc]") else MUTED)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(l)
		_pause = shade
		get_child(0).add_child(shade)
	if _pause:
		_pause.visible = on

## 入夜小场景（Brutal Outside, Cozy Inside）：黑屏上显示自己雪洞的剖面与烛光。
func show_vignette(tex: Texture2D, caption: String, alpha: float) -> void:
	if _vignette == null:
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(center)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 14)
		center.add_child(v)
		_vignette_tex = TextureRect.new()
		_vignette_tex.custom_minimum_size = Vector2(1040, 550)
		_vignette_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_vignette_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(_vignette_tex)
		var l := _label("", 18, CREAM)
		l.name = "Caption"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		_vignette = root
		get_child(0).add_child(root)
	_vignette.visible = alpha > 0.0
	_vignette.modulate.a = alpha
	_vignette_tex.texture = tex
	(_vignette.find_child("Caption", true, false) as Label).text = caption

func show_report(data: Dictionary, shelter_name: String) -> void:
	if _vignette:
		_vignette.visible = false
	if _report:
		_report.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.045, 0.94)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(880, 0)
	v.add_theme_constant_override("separation", 8)
	center.add_child(v)
	var outcome := String(data["outcome"])
	var oc := {"SAFE": Color(0.55, 0.95, 0.6), "COLD": Color(1.0, 0.78, 0.4)}.get(outcome, Color(1.0, 0.45, 0.38)) as Color
	v.add_child(_label("NIGHT REPORT  ·  JAN 14 → 15", 14, MUTED))
	v.add_child(_label(String(data["title"]), 36, oc))
	v.add_child(_label("Shelter: %s" % shelter_name, 14, MUTED))
	v.add_child(HSeparator.new())
	for r in data["rows"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_l := _label(String(r["label"]), 14, CREAM)
		name_l.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(160, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 100
		bar.value = int(r["score"])
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		var sc := float(r["score"])
		fill.bg_color = Color(0.55, 0.9, 0.6) if sc >= 70 else (Color(1.0, 0.75, 0.35) if sc >= 40 else Color(1.0, 0.42, 0.35))
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.1)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)
		var sl := _label("%3d" % int(r["score"]), 14, CREAM)
		sl.custom_minimum_size = Vector2(36, 0)
		row.add_child(sl)
		var note := _label(String(r["note"]), 13, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(470, 0)
		row.add_child(note)
		v.add_child(row)
	v.add_child(HSeparator.new())
	var c := _label(String(data["conclusion"]), 16, CREAM)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(c)
	var lesson := _label("What to remember: " + String(data["lesson"]), 14, AMBER)
	lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lesson)
	var foot := _label("Survival starts with understanding.          [R] try again", 13, MUTED)
	v.add_child(foot)
	_report = shade
	get_child(0).add_child(shade)
