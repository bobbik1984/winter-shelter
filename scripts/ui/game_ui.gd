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
var _report_box: VBoxContainer
var _pause: Control
## [I] 情报面板（= [H] 野外手册）与庇护所 HUD 卡片（第三次评审）。
var _intel: Control   # 全屏遮罩，内含情报卡片
var _intel_tabs: Array = []
var _intel_idx := 0
var _intel_tabs_row: HBoxContainer
var _intel_body: Label
var _shelter_card: PanelContainer
var _shelter_title: Label
var _shelter_line: Label
var _day_hud_on := true
## D16 建造特写面板。
var _focus_panel: PanelContainer
var _focus_title: Label
var _focus_needs: Label
var _focus_time: Label
var _focus_keys: Label
var _focus_progress: ProgressBar
var _credits: Control
var _build_keys: Label
var _vignette: Control
var _vignette_tex: TextureRect
## D14 夜晚：HUD（时钟 / 体温 / 曲线）与醒来面板。
var _night_hud: PanelContainer
var _night_clock: Label
var _night_graph: NightGraph
var _night_event: PanelContainer
var _night_event_box: VBoxContainer

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
	_build_keys = _label(Loc.t("[Tab] shelter type   [R] rotate entrance   [T] roof   [2] vents   [E] place   [B] cancel"), 12, MUTED)
	bv.add_child(_build_keys)
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

func set_inventory(wood: int, bark: int, bedding: int, max_wood: int = 4, max_bedding: int = 4) -> void:
	_tray.text = Loc.t("Dry wood  %d/%d     Birch bark  %d     Bedding  %d/%d") % [wood, max_wood, bark, bedding, max_bedding]

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

func show_briefing(on: bool, forecast: String = "", intro: String = "", level: Dictionary = {}) -> void:
	if on and _briefing == null:
		_briefing = _make_briefing(forecast, intro, level)
		get_child(0).add_child(_briefing)
	if _briefing:
		_briefing.visible = on

## 第三次评审（UI）：首屏只负责"选关和开始"——左栏选章 / 阶，右栏一句话目标 + 天气时间条件 + 唯一主行动。
## 装备、庇护所、地图种子、完整课题、操作、记录都在 [I] 情报面板里（与 [H] 野外手册是同一个面板）。
func _make_briefing(forecast: String = "", intro: String = "", level: Dictionary = {}) -> Control:
	var shade := ColorRect.new()
	shade.name = "Briefing"
	shade.color = Color(0.02, 0.035, 0.06, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 26)
	center.add_child(outer)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 56)
	outer.add_child(cols)
	# 左栏：标题 + 章 / 阶选择
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 12)
	cols.add_child(left)
	left.add_child(_label(Loc.t("SNOW SHELTER"), 52, CREAM))
	left.add_child(_label(Loc.t("C H A L L E N G E"), 18, CREAM))
	left.add_child(_label(Loc.t("FIND  ·  GATHER  ·  BUILD  ·  SURVIVE"), 14, AMBER))
	left.add_child(HSeparator.new())
	if not level.is_empty():
		_chip_row(left, Loc.t("[←] CHAPTER [→]"), level.get("chips", []), "LevelChip_", "LevelRow")
		if not (level.get("stage_chips", []) as Array).is_empty():
			_chip_row(left, Loc.t("[↓] STAGE [↑]"), level["stage_chips"], "StageChip_", "StageRow")
		var meta := Loc.t("Map %d  ·  [N] new map") % int(level.get("map", 1))
		var ml := _label(meta, 13, MUTED)
		ml.name = "LevelMeta"
		left.add_child(ml)
		if String(level.get("locked_hint", "")) != "":
			var lh := _label(String(level["locked_hint"]), 13, Color(MUTED, 0.75))
			lh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			left.add_child(lh)
	# 右栏：这一阶是什么、条件、开始
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(660, 0)
	right.add_theme_constant_override("separation", 14)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(right)
	var title := _label(String(level.get("title", Loc.t("Free play"))), 16, MUTED)
	title.name = "LevelTitle"
	right.add_child(title)
	var lesson_text := String(level.get("lesson", "")) if not level.is_empty() else Loc.t("Read the land, find deep snow on the sheltered side, and build a shelter before dark.")
	var lesson := _label(lesson_text, 24, CREAM)
	lesson.name = "LevelLesson"
	lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(lesson)
	var cond := _label(String(level.get("conditions", intro.split("\n")[0])), 16, AMBER)
	cond.name = "LevelConditions"
	cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(cond)
	if forecast != "":
		var fl := _label(forecast, 14, MUTED)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(fl)
	# 唯一主行动
	var go := _label(Loc.t("ENTER  Begin          [I]  Intel: gear, shelters, map, controls"), 20, AMBER)
	go.name = "BriefingGo"
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(go)
	if level.is_empty() or bool(level.get("full_day_option", false)):
		var alt := _label(Loc.t("[2]  Full day — start at 10:00 (more time, watch the shadows shorten and grow)"), 13, MUTED)
		alt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(alt)
	return shade

## 章节行 + 阶行（D12 / D13）：当前高亮、未开放变暗。
func _chip_row(v: VBoxContainer, head_text: String, chips: Array, prefix: String, row_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var head := _label(head_text, 13, MUTED)
	head.custom_minimum_size = Vector2(150, 0)
	row.add_child(head)
	for chip in chips:
		var cur := bool(chip["current"])
		var open := bool(chip["unlocked"])
		var text := ("[ %s ]" % chip["label"]) if cur else String(chip["label"])
		var col := AMBER if cur else (CREAM if open else Color(MUTED, 0.35))
		var l := _label(text, 19 if cur else 15, col)
		l.name = "%s%s" % [prefix, chip["label"]]
		row.add_child(l)
	row.name = row_name
	v.add_child(row)

# ---------------------------------------------------------------- [I] 情报面板（含 [H] 野外手册）

## tabs：[{key, title, body}]，由 GameDirector 生成；语言切换 / 换关时重新设置。
func set_intel(tabs: Array) -> void:
	_intel_tabs = tabs
	if _intel and _intel.visible:
		_render_intel()

func intel_open() -> bool:
	return _intel != null and _intel.visible

func intel_tab_key() -> String:
	return String(_intel_tabs[_intel_idx]["key"]) if _intel_idx < _intel_tabs.size() else ""

## 打开到指定页；已经开着且就在这一页 → 关上。tab_key 为空 = 保持当前页。
func toggle_intel(tab_key: String = "") -> void:
	var idx := _intel_idx
	for i in _intel_tabs.size():
		if String(_intel_tabs[i]["key"]) == tab_key:
			idx = i
	if intel_open() and (tab_key == "" or idx == _intel_idx):
		_intel.visible = false
		return
	_intel_idx = idx
	if _intel == null:
		var shade := ColorRect.new()
		shade.name = "IntelPanel"
		shade.color = Color(0.015, 0.025, 0.045, 0.9)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.add_child(center)
		var card := _card(Color(0.62, 0.78, 0.95))
		card.custom_minimum_size = Vector2(1000, 600)
		center.add_child(card)
		_intel = shade
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		card.add_child(v)
		_intel_tabs_row = HBoxContainer.new()
		_intel_tabs_row.add_theme_constant_override("separation", 18)
		v.add_child(_intel_tabs_row)
		v.add_child(HSeparator.new())
		_intel_body = _label("", 16, CREAM)
		_intel_body.name = "IntelBody"
		_intel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_intel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(_intel_body)
		v.add_child(_label(Loc.t("[←] [→] or [Tab]  switch page      [I] / [H]  close"), 13, AMBER))
		get_child(0).add_child(_intel)
	_intel.visible = true
	_render_intel()

func intel_step(dir: int) -> void:
	if not intel_open() or _intel_tabs.is_empty():
		return
	_intel_idx = posmod(_intel_idx + dir, _intel_tabs.size())
	_render_intel()

func _render_intel() -> void:
	for c in _intel_tabs_row.get_children():
		_intel_tabs_row.remove_child(c)
		c.queue_free()
	for i in _intel_tabs.size():
		var cur := i == _intel_idx
		var t := String(_intel_tabs[i]["title"])
		_intel_tabs_row.add_child(_label(("[ %s ]" % t) if cur else t, 17 if cur else 15, AMBER if cur else MUTED))
	_intel_body.text = String(_intel_tabs[_intel_idx]["body"]) if _intel_idx < _intel_tabs.size() else ""

## 野外手册内容（[H] 打开情报面板的这一页）。
static func field_guide_text() -> String:
	var lines: Array[String] = [Loc.t("READ THE LAND")]
	for line in [
			Loc.t("Trees show wind direction — branches are short on the windward side, crowns lean downwind."),
			Loc.t("Snow drifts reveal depth — leeward slopes collect the deepest snow. Probe to be sure."),
			Loc.t("Standing dead trees mean fuel — fallen logs are wet and won't burn."),
			Loc.t("Rootballs and thick forest break the wind — shelter there, and light fires there."),
			Loc.t("Shadows tell time — the longer they get, the less daylight you have left."),
		]:
		lines.append("•  " + line)
	lines.append("")
	lines.append(Loc.t("KEY RESOURCES"))
	for line in [Loc.t("Birch bark — tinder (white trunk, black bands)"), Loc.t("Dry grass / spruce boughs — bedding"),
			Loc.t("Dry wood — standing dead trees"), Loc.t("Snow — melt it over a fire for a hot drink")]:
		lines.append("•  " + line)
	return "\n".join(lines)

# ---------------------------------------------------------------- 庇护所 HUD 卡片

## 第三次评审（UI）：庇护所的状态是最高优先级的信息，放在固定的 HUD 卡片里（体温卡下方），
## 世界里只在入口画一个环和箭头。title 为空 = 隐藏。
func set_shelter_card(title: String, line: String, done: bool) -> void:
	if _shelter_card == null:
		_shelter_card = _card(Color(1.0, 0.7, 0.35))
		_shelter_card.name = "ShelterCard"
		_shelter_card.position = Vector2(32, 178)
		_shelter_card.custom_minimum_size = Vector2(398, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		_shelter_card.add_child(v)
		_shelter_title = _label("", 16, CREAM)
		_shelter_title.name = "ShelterTitle"
		v.add_child(_shelter_title)
		_shelter_line = _label("", 13, MUTED)
		_shelter_line.name = "ShelterLine"
		_shelter_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_shelter_line.custom_minimum_size = Vector2(370, 0)
		v.add_child(_shelter_line)
		get_child(0).add_child(_shelter_card)
	_shelter_card.visible = title != "" and _day_hud_on
	_shelter_title.text = title
	_shelter_line.text = line
	(_shelter_card.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(1.0, 0.7, 0.35) if done else Color(0.62, 0.78, 0.95)

# ---------------------------------------------------------------- D16 建造特写面板

## 特写时唯一的建造信息：阶段、材料（需要 / 已有）、工时、剩余天光、退出方式。title 为空 = 隐藏。
func show_build_focus(title: String, needs: String, time_line: String, keys: String, short: bool, progress: float) -> void:
	if _focus_panel == null:
		if title == "":
			return
		_focus_panel = _card(AMBER)
		_focus_panel.name = "BuildFocusPanel"
		_focus_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_focus_panel.position = Vector2(-330, -210)
		_focus_panel.custom_minimum_size = Vector2(660, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		_focus_panel.add_child(v)
		_focus_title = _label("", 17, CREAM)
		_focus_needs = _label("", 15, CREAM)
		_focus_needs.name = "BuildFocusNeeds"
		_focus_needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_focus_time = _label("", 13, MUTED)
		_focus_keys = _label("", 15, AMBER)
		_focus_keys.name = "BuildFocusKeys"
		_focus_progress = ProgressBar.new()
		_focus_progress.custom_minimum_size = Vector2(0, 6)
		_focus_progress.show_percentage = false
		_focus_progress.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = AMBER
		_focus_progress.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.12)
		_focus_progress.add_theme_stylebox_override("background", bg)
		for c in [_focus_title, _focus_needs, _focus_time, _focus_progress, _focus_keys]:
			v.add_child(c)
		get_child(0).add_child(_focus_panel)
	_focus_panel.visible = title != ""
	if title == "":
		return
	_focus_title.text = title
	_focus_needs.text = needs
	_focus_needs.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if short else CREAM)
	_focus_time.text = time_line
	_focus_keys.text = keys
	_focus_progress.value = progress

## 世界标签不能压住的屏幕区域（画布坐标）。
func occupied_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in [_prompt_card, _build_card, _objective.get_parent().get_parent(), _shelter_card, _intel, _night_event]:
		if c != null and (c as Control).is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	if _toast.text != "" and _toast.modulate.a > 0.05:
		out.append(_toast.get_global_rect())
	return out

## 切换语言后重建缓存的面板（简报 / 手册 / 暂停 / 建造面板操作行）。
func relocalize() -> void:
	for n in [_briefing, _intel, _pause]:
		if n:
			n.queue_free()
	_briefing = null
	_intel = null
	_pause = null
	if _build_keys:
		_build_keys.text = Loc.t("[Tab] shelter type   [R] rotate entrance   [T] roof   [2] vents   [E] place   [B] cancel")

## 致谢与许可（发布要求：Godot MIT 声明、随包字体 Apache-2.0）。暂停菜单里按 [C] 开关。
func toggle_credits() -> void:
	if _credits == null:
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.03, 0.05, 0.95)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.offset_left = 160
		scroll.offset_right = -160
		scroll.offset_top = 80
		scroll.offset_bottom = -80
		shade.add_child(scroll)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 10)
		scroll.add_child(v)
		v.add_child(_label(Loc.t("CREDITS & LICENSES"), 24, CREAM))
		for line in [
				Loc.t("Snow Shelter Challenge — design and development by the Winter Shelter project."),
				Loc.t("Built with the Godot Engine (godotengine.org). Character modelled procedurally in Blender."),
				Loc.t("Chinese text fallback font: Droid Sans Fallback © Google, Apache License 2.0 (assets/fonts/DroidSansFallback-LICENSE.txt)."),
				Loc.t("All other art, sound and shaders are generated procedurally by this project."),
				"", "Godot Engine — MIT License:"]:
			var l := _label(line, 13, MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(l)
		var lic := _label(Engine.get_license_text(), 11, MUTED)
		lic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(lic)
		v.add_child(_label(Loc.t("[C] close"), 13, AMBER))
		_credits = shade
		get_child(0).add_child(shade)
	else:
		_credits.visible = not _credits.visible

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
		var t := _label(Loc.t("PAUSED"), 40, CREAM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		for line in [Loc.t("[Esc] resume      [R] restart      [Q] quit      [C] credits"),
				"", Loc.t("[WASD] move    [Space] hold: probe snow    [E] hold: gather / build / drink"),
				Loc.t("[B] build mode — [Tab] type, [R] rotate entrance, [E] place"),
				Loc.t("[F] light fire / add wood    [N] sleep    [V] camera    [Wheel] zoom    [F10] graphics") + "    [M] " + ("声音" if Loc.is_zh() else "sound") + "    [F11] " + ("全屏" if Loc.is_zh() else "fullscreen")]:
			var l := _label(line, 15 if line.begins_with("[Esc]") else 13, AMBER if line.begins_with("[Esc]") else MUTED)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(l)
		_pause = shade
		get_child(0).add_child(shade)
	if _pause:
		_pause.visible = on
	if not on and _credits:
		_credits.visible = false

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

## 报告页底部追加一行（关卡解锁 / 下一关提示，D12 / L4）。
func add_report_line(text: String) -> void:
	if _report_box:
		var l := _label(text, 15, AMBER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_report_box.add_child(l)

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
	v.add_child(_label(Loc.t("NIGHT REPORT  ·  JAN 14 → 15"), 14, MUTED))
	v.add_child(_label(String(data["title"]), 36, oc))
	v.add_child(_label(Loc.t("Shelter: %s") % shelter_name, 14, MUTED))
	if data.has("timeline"):
		var tl := _label(String(data["timeline"]), 12, MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tl)
	if data.has("night_curve"):
		var g := NightGraph.new()
		g.name = "ReportNightGraph"
		g.custom_minimum_size = Vector2(880, 64)
		g.set_data(data["night_curve"], float(data.get("night_duration", 828.0)), data.get("night_events", []))
		v.add_child(g)
		var nt := _label(String(data.get("night_timeline", "")), 12, CREAM)
		nt.name = "ReportNightTimeline"
		nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(nt)
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
	if String(data.get("level_takeaway", "")) != "":
		var tk := _label(String(data["level_takeaway"]), 15, CREAM)
		tk.name = "LevelTakeaway"
		tk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tk)
	var lesson := _label(Loc.t("What to remember: ") + String(data["lesson"]), 14, AMBER)
	lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lesson)
	var foot := _label(Loc.t("Survival starts with understanding.          [R] try again"), 13, MUTED)
	v.add_child(foot)
	_report_box = v
	_report = shade
	get_child(0).add_child(shade)

# ------------------------------------------------------------------ D14 可玩的夜晚

## 夜里只留夜间面板：隐藏白天的目标行 / 背包托盘 / 交互提示。
func set_day_hud(on: bool) -> void:
	_day_hud_on = on
	_prompt_card.visible = on and _prompt_card.visible
	if _shelter_card:
		_shelter_card.visible = on and _shelter_title.text != ""
	var tray_card := _objective.get_parent().get_parent() as Control
	if tray_card:
		tray_card.visible = on

func show_night_hud(on: bool) -> void:
	if on and _night_hud == null:
		_night_hud = _card(Color(0.55, 0.65, 0.9))
		_night_hud.name = "NightHud"
		_night_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_night_hud.position = Vector2(-230, 18)
		_night_hud.custom_minimum_size = Vector2(460, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		_night_hud.add_child(v)
		_night_clock = _label("", 15, CREAM)
		_night_clock.name = "NightClock"
		v.add_child(_night_clock)
		_night_graph = NightGraph.new()
		_night_graph.custom_minimum_size = Vector2(440, 70)
		v.add_child(_night_graph)
		var hint := _label(Loc.t("Hold [Space] to fast-forward"), 12, MUTED)
		v.add_child(hint)
		get_child(0).add_child(_night_hud)
	if _night_hud:
		_night_hud.visible = on

func update_night_hud(clock: String, warmth: int, points: PackedVector2Array, duration: float, events: Array, now_minute: float) -> void:
	if _night_hud == null:
		return
	_night_clock.text = Loc.t("Night · %s · body warmth %d") % [clock, warmth]
	_night_graph.set_data(points, duration, events, now_minute)

## 醒来面板：标题（为什么醒）、一句说明、带编号的可选行动。
func show_night_event(title: String, body: String, actions: Array) -> void:
	hide_night_event()
	_night_event = _card(Color(1.0, 0.62, 0.3))
	_night_event.name = "NightEvent"
	_night_event.set_anchors_preset(Control.PRESET_CENTER)
	_night_event.position = Vector2(-260, -90)
	_night_event.custom_minimum_size = Vector2(520, 0)
	_night_event_box = VBoxContainer.new()
	_night_event_box.add_theme_constant_override("separation", 6)
	_night_event.add_child(_night_event_box)
	_night_event_box.add_child(_label(title, 20, AMBER))
	var b := _label(body, 14, CREAM)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_night_event_box.add_child(b)
	_night_event_box.add_child(HSeparator.new())
	for i in range(actions.size()):
		var l := _label("[%d]  %s" % [i + 1, String(actions[i])], 15, CREAM)
		l.name = "NightAction%d" % (i + 1)
		_night_event_box.add_child(l)
	get_child(0).add_child(_night_event)

func hide_night_event() -> void:
	if _night_event:
		# 先摘下再释放：同一帧里重建面板时不能和旧面板重名（否则新面板被改名、找不到）
		if _night_event.get_parent():
			_night_event.get_parent().remove_child(_night_event)
		_night_event.queue_free()
		_night_event = null
