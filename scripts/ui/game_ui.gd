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
## 「第一步」清单：每个里程碑一行，做完打勾，当前这一步高亮（参考图里的 First Steps）。
var _steps_box: VBoxContainer
var _step_labels: Array[Label] = []
var _steps_text := ""
## 背包格子：小色块 + 数量，满了变琥珀色（参考图里的格子背包，不画物品图）。
var _slot_box: HBoxContainer
var _slot_labels: Array[Label] = []
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
## 卡片页（情报 · 庇护所）：正文下面一张张图文卡片；和正文一起在滚动区里。
var _intel_cards: VBoxContainer
var _intel_scroll: ScrollContainer
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
var _night_hint: Label
var _night_graph: NightGraph
var _night_event: PanelContainer
var _night_event_box: VBoxContainer
## 触屏按钮占的区域（TouchControls 写入），世界标签不能压上去。
var touch_rects: Array[Rect2] = []

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 交互提示（底部居中）
	_prompt_card = _card(AMBER)
	_prompt_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_card.position = Vector2(-190, -92) if TouchMode.enabled else Vector2(-220, -150)
	_prompt_card.custom_minimum_size = Vector2(240, 0)
	root.add_child(_prompt_card)
	var pv := VBoxContainer.new()
	_prompt_card.add_child(pv)
	_prompt_label = _label("", 17, CREAM)
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
	if TouchMode.enabled:
		tray_card.position = Vector2(10, 134)   # 左下留给摇杆：放到体温卡下面
	else:
		tray_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		tray_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
		tray_card.offset_left = 32.0
		tray_card.offset_bottom = -64.0
		tray_card.offset_top = -64.0
	root.add_child(tray_card)
	var tv := VBoxContainer.new()
	tray_card.add_child(tv)
	_objective = _label("", 14, AMBER)
	if TouchMode.enabled:
		_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objective.custom_minimum_size = Vector2(380, 0)
	# 清单在提示句上面：先看"我在哪一步"，下面才是这一步具体怎么做
	_steps_box = VBoxContainer.new()
	_steps_box.name = "FirstSteps"
	_steps_box.add_theme_constant_override("separation", 1)
	tv.add_child(_steps_box)
	tv.add_child(_objective)
	_tray = _label("", 13, CREAM)
	_tray.visible = false   # 旧的文字托盘，由下面的格子取代（留着给测试 / 兼容）
	tv.add_child(_tray)
	_slot_box = HBoxContainer.new()
	_slot_box.name = "PackSlots"
	_slot_box.add_theme_constant_override("separation", 14)
	tv.add_child(_slot_box)
	for c in [Color(0.55, 0.36, 0.2), Color(0.93, 0.92, 0.88), Color(0.78, 0.66, 0.36)]:
		var slot_panel := PanelContainer.new()
		slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sps := StyleBoxFlat.new()
		sps.bg_color = Color(1, 1, 1, 0.04)
		sps.border_color = Color(1, 1, 1, 0.14)
		sps.set_border_width_all(1)
		sps.set_corner_radius_all(4)
		sps.content_margin_left = 8
		sps.content_margin_right = 8
		sps.content_margin_top = 3
		sps.content_margin_bottom = 3
		slot_panel.add_theme_stylebox_override("panel", sps)
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 6)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw := ColorRect.new()
		sw.color = c
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(sw)
		var lb := _label("", 13, CREAM)
		chip.add_child(lb)
		_slot_labels.append(lb)
		slot_panel.add_child(chip)
		_slot_box.add_child(slot_panel)

	# 消息（顶部居中）
	_toast = _label("", 17, CREAM)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-160, 76) if TouchMode.enabled else Vector2(-330, 250)
	_toast.custom_minimum_size = Vector2(520 if TouchMode.enabled else 660, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.95))
	_toast.add_theme_constant_override("outline_size", 6)
	root.add_child(_toast)

	# 建造面板
	_build_card = _card(Color(0.45, 1.0, 0.55))
	_build_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_card.position = Vector2(-300, -170) if TouchMode.enabled else Vector2(-330, -205)
	_build_card.custom_minimum_size = Vector2(520 if TouchMode.enabled else 660, 0)
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
	_build_keys.visible = not TouchMode.enabled
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
	s.bg_color = Color(0.032, 0.048, 0.075, 0.91)
	s.border_width_left = 3
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(accent.r, accent.g, accent.b, 0.78)
	s.corner_radius_top_left = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.shadow_color = Color(0, 0, 0, 0.36)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 15
	s.content_margin_right = 15
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)
	return p

func _pill(text: String, font_size: int, fg: Color, bg: Color, border: Color, pad_x: int = 8, pad_y: int = 3) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	p.add_theme_stylebox_override("panel", s)
	var l := _label(text, font_size, fg)
	p.add_child(l)
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

## 把操作提示放在 anchor（画布坐标）上方，不出屏。
func place_prompt(anchor: Vector2) -> void:
	if not _prompt_card.visible:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var sz := _prompt_card.size
	_prompt_card.global_position = Vector2(
		clampf(anchor.x - sz.x * 0.5, 12.0, view.x - sz.x - 12.0),
		clampf(anchor.y - sz.y - 10.0, 12.0, view.y - sz.y - 12.0))

func set_inventory(wood: int, bark: int, bedding: int, max_wood: int = 4, max_bedding: int = 4) -> void:
	_tray.text = Loc.t("Dry wood  %d/%d     Birch bark  %d     Bedding  %d/%d") % [wood, max_wood, bark, bedding, max_bedding]
	if _slot_labels.size() < 3:
		return
	var vals := [[Loc.t("Wood"), wood, max_wood], [Loc.t("Bark"), bark, -1], [Loc.t("Bedding"), bedding, max_bedding]]
	for i in 3:
		var v: Array = vals[i]
		var full: bool = int(v[2]) > 0 and int(v[1]) >= int(v[2])
		_slot_labels[i].text = ("%s %d/%d" % [v[0], v[1], v[2]]) if int(v[2]) > 0 else ("%s %d" % [v[0], v[1]])
		_slot_labels[i].add_theme_color_override("font_color", AMBER if full else CREAM)
		if full:
			_slot_labels[i].text += " " + Loc.t("full")
		if _slot_box and i < _slot_box.get_child_count() and _slot_box.get_child(i) is PanelContainer:
			var sp := _slot_box.get_child(i) as PanelContainer
			var sps := sp.get_theme_stylebox("panel") as StyleBoxFlat
			if sps:
				sps.border_color = AMBER if full else Color(1, 1, 1, 0.14)
				sps.bg_color = Color(1.0, 0.62, 0.20, 0.14) if full else Color(1, 1, 1, 0.04)

## 「第一步」清单：steps = [{label, done}]，第一个没做完的是当前步。触屏只画一行进度（✓✓○○○ 2/5），省地方。
func set_steps(steps: Array) -> void:
	var key := str(steps)
	if key == _steps_text:
		return
	_steps_text = key
	var cur := -1
	var done_n := 0
	for i in steps.size():
		if bool(steps[i]["done"]):
			done_n += 1
		elif cur < 0:
			cur = i
	if TouchMode.enabled:
		for c in _step_labels:
			c.queue_free()
		_step_labels.clear()
		var marks := ""
		for st in steps:
			marks += "✓" if bool(st["done"]) else "○"
		var l := _label("%s  %d/%d  %s" % [marks, done_n, steps.size(), String(steps[cur]["label"]) if cur >= 0 else ""], 13, MUTED)
		_steps_box.add_child(l)
		_step_labels.append(l)
		return
	while _step_labels.size() < steps.size():
		var l := _label("", 13, MUTED)
		_steps_box.add_child(l)
		_step_labels.append(l)
	for i in steps.size():
		var done := bool(steps[i]["done"])
		var l := _step_labels[i]
		l.text = ("✓ " if done else ("▸ " if i == cur else "○ ")) + String(steps[i]["label"])
		l.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6) if done else (AMBER if i == cur else MUTED))

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
	shade.color = Color(0.018, 0.030, 0.052, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	if TouchMode.enabled:
		center.offset_bottom = -76.0   # 底部是按钮
	shade.add_child(center)
	var board := _card(AMBER)
	var bs := board.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	bs.bg_color = Color(0.025, 0.038, 0.062, 0.92)
	bs.border_width_left = 4
	bs.border_color = Color(1.0, 0.65, 0.24, 0.85)
	bs.set_corner_radius_all(8)
	bs.content_margin_left = 28 if TouchMode.enabled else 42
	bs.content_margin_right = 28 if TouchMode.enabled else 42
	bs.content_margin_top = 22 if TouchMode.enabled else 32
	bs.content_margin_bottom = 22 if TouchMode.enabled else 30
	bs.shadow_color = Color(0, 0, 0, 0.48)
	bs.shadow_size = 16
	board.add_theme_stylebox_override("panel", bs)
	center.add_child(board)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 22)
	board.add_child(outer)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24 if TouchMode.enabled else 44)
	outer.add_child(cols)
	# 左栏：标题 + 章 / 阶选择
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430 if TouchMode.enabled else 500, 0)
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	left.add_child(_label(Loc.t("SNOW SHELTER"), 38 if TouchMode.enabled else 48, CREAM))
	left.add_child(_label(Loc.t("C H A L L E N G E"), 16, MUTED))
	left.add_child(_label(Loc.t("FIND  ·  GATHER  ·  BUILD  ·  SURVIVE"), 13, AMBER))
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
	cols.add_child(VSeparator.new())
	# 右栏：这一阶是什么、条件、开始
	var right_card := PanelContainer.new()
	var rcs := StyleBoxFlat.new()
	rcs.bg_color = Color(0.055, 0.080, 0.125, 0.55)
	rcs.border_color = Color(0.62, 0.78, 0.95, 0.25)
	rcs.set_border_width_all(1)
	rcs.set_corner_radius_all(6)
	rcs.set_content_margin_all(18)
	right_card.add_theme_stylebox_override("panel", rcs)
	right_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(right_card)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(500 if TouchMode.enabled else 580, 0)
	right.add_theme_constant_override("separation", 12)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right_card.add_child(right)
	var title := _label(String(level.get("title", Loc.t("Free play"))), 15, Color(0.68, 0.82, 0.98))
	title.name = "LevelTitle"
	right.add_child(title)
	var lesson_text := String(level.get("lesson", "")) if not level.is_empty() else Loc.t("Read the land, find deep snow on the sheltered side, and build a shelter before dark.")
	var lesson := _label(lesson_text, 22, CREAM)
	lesson.name = "LevelLesson"
	lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(lesson)
	var cond_box := PanelContainer.new()
	var cbs := StyleBoxFlat.new()
	cbs.bg_color = Color(1.0, 0.62, 0.20, 0.12)
	cbs.border_color = Color(1.0, 0.62, 0.20, 0.42)
	cbs.border_width_left = 3
	cbs.set_corner_radius_all(4)
	cbs.content_margin_left = 10
	cbs.content_margin_right = 10
	cbs.content_margin_top = 6
	cbs.content_margin_bottom = 6
	cond_box.add_theme_stylebox_override("panel", cbs)
	cond_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cond := _label(String(level.get("conditions", intro.split("\n")[0])), 15, AMBER)
	cond.name = "LevelConditions"
	cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cond_box.add_child(cond)
	right.add_child(cond_box)
	if forecast != "":
		var fl := _label(forecast, 13, MUTED)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(fl)
	# 唯一主行动
	var go := _label(Loc.t("ENTER  Begin          [I]  Intel: gear, shelters, map, controls"), 18, AMBER)
	go.name = "BriefingGo"
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not TouchMode.enabled:
		outer.add_child(HSeparator.new())
		outer.add_child(go)
	if not TouchMode.enabled and (level.is_empty() or bool(level.get("full_day_option", false))):
		var alt := _label(Loc.t("[2]  Full day — start at 10:00 (more time, watch the shadows shorten and grow)"), 13, MUTED)
		alt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(alt)
	return shade

## 章节行 + 阶行（D12 / D13）：当前高亮、未开放变暗。
func _chip_row(v: VBoxContainer, head_text: String, chips: Array, prefix: String, row_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := _label(head_text, 13, MUTED)
	head.custom_minimum_size = Vector2(142, 0)
	row.add_child(head)
	for chip in chips:
		var cur := bool(chip["current"])
		var open := bool(chip["unlocked"])
		var text := String(chip["label"])
		var col := AMBER if cur else (CREAM if open else Color(MUTED, 0.35))
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(1.0, 0.62, 0.20, 0.22) if cur else (Color(1, 1, 1, 0.06) if open else Color(1, 1, 1, 0.02))
		bs.border_color = AMBER if cur else (Color(1, 1, 1, 0.18) if open else Color(1, 1, 1, 0.06))
		bs.set_border_width_all(2 if cur else 1)
		bs.set_corner_radius_all(4)
		bs.content_margin_left = 7
		bs.content_margin_right = 7
		bs.content_margin_top = 2
		bs.content_margin_bottom = 2
		badge.add_theme_stylebox_override("panel", bs)
		var l := _label(text, 15 if cur else 13, col)
		l.name = "%s%s" % [prefix, chip["label"]]
		badge.add_child(l)
		row.add_child(badge)
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
		card.custom_minimum_size = Vector2(960, 410) if TouchMode.enabled else Vector2(1060, 620)
		var cs := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		cs.bg_color = Color(0.024, 0.036, 0.060, 0.95)
		cs.border_width_left = 4
		cs.set_corner_radius_all(8)
		cs.content_margin_left = 20
		cs.content_margin_right = 20
		cs.content_margin_top = 16
		cs.content_margin_bottom = 16
		card.add_theme_stylebox_override("panel", cs)
		if TouchMode.enabled:
			center.offset_bottom = -76.0
			center.mouse_filter = Control.MOUSE_FILTER_PASS
			shade.mouse_filter = Control.MOUSE_FILTER_PASS
			card.mouse_filter = Control.MOUSE_FILTER_PASS
		center.add_child(card)
		_intel = shade
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		card.add_child(v)
		_intel_tabs_row = HBoxContainer.new()
		_intel_tabs_row.add_theme_constant_override("separation", 8)
		v.add_child(_intel_tabs_row)
		v.add_child(HSeparator.new())
		_intel_body = _label("", 15, CREAM)
		_intel_body.name = "IntelBody"
		_intel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_intel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# 正文 + 卡片放在滚动区里：手机上用手指拖，桌面上用滚轮（庇护所卡片一页放不下）
		var sc := ScrollContainer.new()
		sc.name = "IntelScroll"
		sc.custom_minimum_size = Vector2(920, 330) if TouchMode.enabled else Vector2(1010, 505)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_intel_scroll = sc
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 14)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.mouse_filter = Control.MOUSE_FILTER_PASS
		_intel_body.custom_minimum_size = Vector2(900 if TouchMode.enabled else 980, 0)
		_intel_body.mouse_filter = Control.MOUSE_FILTER_PASS
		_intel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(_intel_body)
		_intel_cards = VBoxContainer.new()
		_intel_cards.name = "IntelCards"
		_intel_cards.add_theme_constant_override("separation", 12)
		_intel_cards.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_child(_intel_cards)
		sc.add_child(content)
		v.add_child(sc)
		if not TouchMode.enabled:
			v.add_child(HSeparator.new())
			v.add_child(_label(Loc.t("[←] [→] or [Tab]  switch page      [I] / [H]  close") + "      " + Loc.t("[Wheel] scroll"), 13, AMBER))
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
		var tab_pill := _pill(
			t,
			15 if cur else 14,
			AMBER if cur else MUTED,
			Color(1.0, 0.62, 0.20, 0.18) if cur else Color(1, 1, 1, 0.04),
			AMBER if cur else Color(1, 1, 1, 0.12),
			12, 5
		)
		_intel_tabs_row.add_child(tab_pill)
	_intel_body.text = String(_intel_tabs[_intel_idx]["body"]) if _intel_idx < _intel_tabs.size() else ""
	for c in _intel_cards.get_children():
		_intel_cards.remove_child(c)
		c.queue_free()
	if _intel_idx < _intel_tabs.size():
		for cd in _intel_tabs[_intel_idx].get("cards", []):
			_intel_cards.add_child(_shelter_card_ui(cd))
	_intel_scroll.scroll_vertical = 0

## 一张庇护所卡片：左边并排展示「内部剖面」+「地图外观」高清画框（带角标），右边展示名称、状态徽章、结构说明与四项关键规格表。
## 还没学会的整张卡略压暗。cd = GameDirector.shelter_cards() 的一项。
func _shelter_card_ui(cd: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "ShelterCard_%s" % String(cd["id"])
	var st := StyleBoxFlat.new()
	var state := String(cd["state"])
	var accent: Color = Color(0.52, 0.92, 0.62) if state == "known" else (AMBER if state == "new" else MUTED)
	st.bg_color = Color(0.052, 0.075, 0.118, 0.90) if state != "locked" else Color(0.038, 0.052, 0.082, 0.72)
	st.border_color = Color(accent.r, accent.g, accent.b, 0.75 if state != "locked" else 0.35)
	st.border_width_left = 4
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.set_corner_radius_all(7)
	st.content_margin_left = 14
	st.content_margin_right = 16
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	st.shadow_color = Color(0, 0, 0, 0.28)
	st.shadow_size = 6
	st.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", st)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(row)
	# 左栏：并排高清视图框（树井只画剖面图，则单张放大）
	var pics := HBoxContainer.new()
	pics.add_theme_constant_override("separation", 8)
	pics.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pics.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(pics)
	var has_out := ResourceLoader.exists("res://assets/ui/shelters/%s_out.webp" % String(cd["id"]))
	var pic_size := Vector2(216, 122) if has_out else Vector2(440, 188)
	if TouchMode.enabled:
		pic_size = Vector2(188, 106) if has_out else Vector2(384, 164)
	for pair in [["cut", Loc.t("CUTAWAY")], ["out", Loc.t("OUTSIDE")]]:
		var key: String = pair[0]
		var tag_txt: String = pair[1]
		var path := "res://assets/ui/shelters/%s_%s.webp" % [String(cd["id"]), key]
		if not ResourceLoader.exists(path):
			continue
		var frame := PanelContainer.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color(0.02, 0.03, 0.05, 1.0)
		fs.border_color = Color(0.70, 0.82, 0.96, 0.28)
		fs.set_border_width_all(1)
		fs.set_corner_radius_all(4)
		fs.set_content_margin_all(2)
		frame.add_theme_stylebox_override("panel", fs)
		frame.mouse_filter = Control.MOUSE_FILTER_PASS
		var holder := Control.new()
		holder.custom_minimum_size = pic_size
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		frame.add_child(holder)
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_PASS
		holder.add_child(tr)
		var badge := _pill(tag_txt, 10, CREAM, Color(0.02, 0.035, 0.06, 0.82), Color(1, 1, 1, 0.18), 6, 2)
		badge.position = Vector2(6, 6)
		holder.add_child(badge)
		pics.add_child(frame)
	# 右栏：标题 + 状态徽章 + 说明 + 规格小表
	var txt := VBoxContainer.new()
	txt.add_theme_constant_override("separation", 6)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	txt.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(txt)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title_lb := _label(String(cd["name"]), 19, CREAM)
	head.add_child(title_lb)
	var status_pill := _pill(
		String(cd["status"]).to_upper(),
		11,
		accent,
		Color(accent.r, accent.g, accent.b, 0.16),
		Color(accent.r, accent.g, accent.b, 0.55),
		8, 2
	)
	status_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status_pill)
	txt.add_child(head)
	var about_lb := _label(String(cd["about"]), 14, CREAM)
	about_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about_lb.custom_minimum_size = Vector2(460 if TouchMode.enabled else 510, 0)
	about_lb.mouse_filter = Control.MOUSE_FILTER_PASS
	txt.add_child(about_lb)
	# 规格栏：选址 / 工时 / 材料 / 篝火
	var specs := PanelContainer.new()
	var sps := StyleBoxFlat.new()
	sps.bg_color = Color(0.025, 0.038, 0.062, 0.65)
	sps.border_color = Color(1, 1, 1, 0.08)
	sps.set_border_width_all(1)
	sps.set_corner_radius_all(4)
	sps.content_margin_left = 10
	sps.content_margin_right = 10
	sps.content_margin_top = 6
	sps.content_margin_bottom = 6
	specs.add_theme_stylebox_override("panel", sps)
	specs.mouse_filter = Control.MOUSE_FILTER_PASS
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3)
	sv.mouse_filter = Control.MOUSE_FILTER_PASS
	specs.add_child(sv)
	var site_str := String(cd.get("site", ""))
	var time_str := String(cd.get("time", ""))
	var mats_str := String(cd.get("mats", ""))
	if site_str != "":
		var r1 := _label("%s: %s   ·   %s: %s   ·   %s: %s" % [
			Loc.t("SITE"), site_str, Loc.t("WORK TIME"), time_str, Loc.t("MATERIALS"), mats_str], 12, Color(0.82, 0.88, 0.96))
		r1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r1.custom_minimum_size = Vector2(440 if TouchMode.enabled else 490, 0)
		r1.mouse_filter = Control.MOUSE_FILTER_PASS
		sv.add_child(r1)
	else:
		var l_needs := _label(String(cd["needs"]), 12, Color(0.82, 0.88, 0.96))
		l_needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l_needs.custom_minimum_size = Vector2(440 if TouchMode.enabled else 490, 0)
		l_needs.mouse_filter = Control.MOUSE_FILTER_PASS
		sv.add_child(l_needs)
	var l_fire := _label("%s: %s" % [Loc.t("FIRE"), String(cd["fire"])], 12, Color(0.96, 0.78, 0.52))
	l_fire.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l_fire.custom_minimum_size = Vector2(440 if TouchMode.enabled else 490, 0)
	l_fire.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(l_fire)
	txt.add_child(specs)
	if state == "locked":
		panel.modulate = Color(0.82, 0.85, 0.90, 0.72)
	return panel

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
		_shelter_card.position = Vector2(10, 222) if TouchMode.enabled else Vector2(32, 178)
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
		_focus_panel.position = Vector2(-400, -150) if TouchMode.enabled else Vector2(-330, -210)
		_focus_panel.custom_minimum_size = Vector2(560 if TouchMode.enabled else 660, 0)
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
		_focus_keys.visible = not TouchMode.enabled
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
	out.append_array(touch_rects)
	return out

func credits_open() -> bool:
	return _credits != null and _credits.is_visible_in_tree()

## 触屏：内容比屏幕高时放进可以用手指拖动的滚动框，底部给按钮留位置。
func _scroll_wrap(content: Control, parent: Control, bottom: float = 84.0) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 12.0
	scroll.offset_right = -12.0
	scroll.offset_top = 10.0
	scroll.offset_bottom = -bottom
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(content)
	scroll.add_child(center)
	parent.add_child(scroll)

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
				Loc.t("DejaVu Sans symbols font © Bitstream and DejaVu authors, free license (assets/fonts/DejaVuSans-LICENSE.txt)."),
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
		shade.color = Color(0.018, 0.030, 0.052, 0.78)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.add_child(center)
		var card := _card(AMBER)
		var cs := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		cs.bg_color = Color(0.025, 0.038, 0.062, 0.94)
		cs.border_width_left = 4
		cs.set_corner_radius_all(8)
		cs.content_margin_left = 36
		cs.content_margin_right = 36
		cs.content_margin_top = 26
		cs.content_margin_bottom = 26
		card.add_theme_stylebox_override("panel", cs)
		center.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		card.add_child(v)
		var t := _label(Loc.t("PAUSED"), 36, CREAM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		v.add_child(HSeparator.new())
		var keys_lines := [] if TouchMode.enabled else [Loc.t("[Esc] resume      [R] restart      [Q] quit      [C] credits"),
				"", Loc.t("[WASD] move    [Space] hold: probe snow    [E] hold: gather / build / drink"),
				Loc.t("[B] build mode — [Tab] type, [R] rotate entrance, [E] place"),
				Loc.t("[F] light fire / add wood    [N] sleep    [V] camera    [Wheel] zoom    [F10] graphics") + "    [M] " + ("声音" if Loc.is_zh() else "sound") + "    [F11] " + ("全屏" if Loc.is_zh() else "fullscreen")]
		if TouchMode.enabled:
			var info := _label(BuildInfo.line(), 14, MUTED)
			info.name = "BuildInfo"
			info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(info)
		for line in keys_lines:
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
		_vignette_tex.custom_minimum_size = Vector2(700, 340) if TouchMode.enabled else Vector2(1040, 550)
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
	shade.color = Color(0.015, 0.025, 0.045, 0.90)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(880, 0)
	v.add_theme_constant_override("separation", 8)
	var outcome := String(data["outcome"])
	var oc := {"SAFE": Color(0.55, 0.95, 0.6), "COLD": Color(1.0, 0.78, 0.4)}.get(outcome, Color(1.0, 0.45, 0.38)) as Color
	var board := _card(oc)
	var bs := board.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	bs.bg_color = Color(0.024, 0.036, 0.060, 0.95)
	bs.border_width_left = 4
	bs.set_corner_radius_all(8)
	bs.content_margin_left = 26 if TouchMode.enabled else 34
	bs.content_margin_right = 26 if TouchMode.enabled else 34
	bs.content_margin_top = 20 if TouchMode.enabled else 26
	bs.content_margin_bottom = 20 if TouchMode.enabled else 24
	board.add_theme_stylebox_override("panel", bs)
	board.add_child(v)
	if TouchMode.enabled:
		_scroll_wrap(board, shade)
	else:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.add_child(center)
		center.add_child(board)
	v.add_child(_label(Loc.t("NIGHT REPORT  ·  JAN 14 → 15"), 13, MUTED))
	v.add_child(_label(String(data["title"]), 36, oc))
	v.add_child(_label(Loc.t("Shelter: %s") % shelter_name, 14, MUTED))
	if String(data.get("score_line", "")) != "":
		var sl0 := _label(String(data["score_line"]), 16, CREAM)
		sl0.name = "ReportScore"
		sl0.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl0)
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
	var foot := _label(Loc.t("Survival starts with understanding.          [R] try again") if not TouchMode.enabled else "", 13, MUTED)
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
		_night_hint = _label("", 12, MUTED)
		_night_hint.name = "NightHint"
		v.add_child(_night_hint)
		get_child(0).add_child(_night_hud)
	if _night_hud:
		_night_hud.visible = on

func update_night_hud(before_sunset: bool, clock: String, warmth: int, points: PackedVector2Array, duration: float, events: Array, now_minute: float, slept_h: float = 0.0, hint: String = "") -> void:
	if _night_hud == null:
		return
	_night_clock.text = ((Loc.t("Before dark, trying to sleep · %s · body warmth %d") if before_sunset else Loc.t("Night · %s · body warmth %d")) % [clock, warmth]) \
		+ Loc.t(" · slept %.1f h") % slept_h
	_night_hint.text = hint
	_night_hint.visible = hint != ""
	_night_graph.set_data(points, duration, events, now_minute)

## 醒来面板：标题（为什么醒）、一句说明、带编号的可选行动。
func show_night_event(title: String, body: String, actions: Array) -> void:
	hide_night_event()
	_night_event = _card(Color(1.0, 0.62, 0.3))
	_night_event.name = "NightEvent"
	_night_event.set_anchors_preset(Control.PRESET_CENTER)
	_night_event.position = Vector2(-260, -130) if TouchMode.enabled else Vector2(-260, -90)
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
		var l := _label(("%s" if TouchMode.enabled else "[%d]  %s".replace("%d", str(i + 1))) % String(actions[i]), 15, CREAM)
		l.name = "NightAction%d" % (i + 1)
		if TouchMode.enabled:
			# 触屏：整行是一个能点的按钮
			var row := PanelContainer.new()
			var rs := StyleBoxFlat.new()
			rs.bg_color = Color(AMBER, 0.2)
			rs.border_color = Color(AMBER, 0.8)
			rs.set_border_width_all(2)
			rs.set_corner_radius_all(8)
			rs.set_content_margin_all(14)
			row.add_theme_stylebox_override("panel", rs)
			row.custom_minimum_size = Vector2(0, 56)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.set_meta("touch_key", KEY_1 + i)
			row.add_to_group("touch_tap")
			row.add_child(l)
			_night_event_box.add_child(row)
		else:
			_night_event_box.add_child(l)
	get_child(0).add_child(_night_event)

func hide_night_event() -> void:
	if _night_event:
		# 先摘下再释放：同一帧里重建面板时不能和旧面板重名（否则新面板被改名、找不到）
		if _night_event.get_parent():
			_night_event.get_parent().remove_child(_night_event)
		_night_event.queue_free()
		_night_event = null
