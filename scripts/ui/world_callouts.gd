class_name WorldCallouts
extends Control

## 世界空间引线标签（参考图 4 / 5 / 6 号元素），统一一个组件（T3.5）。
## 内容是**动态**的（D4：Deeper snow 只在玩家探测过的位置出现）：
## GameDirector 通过 set_callout / set_marker / remove_callout 增删；距离过远或在相机背后时隐藏。
##
## 第三次评审（UI）：世界标签只做"发现级"提示，按屏幕空间规则排版，而不是固定 offset：
## * 每个标签有优先级；高优先级先放，放不下的只留一个小点（不画卡片）。
## * 候选位置依次尝试；不得压在 HUD 卡片（rect_provider 提供）、其它标签、或"标记"保护区上。
## * 标记（set_marker，用于玩家的庇护所入口）只画环和箭头、不放文字卡，并在入口周围留出保护区。
## * 小窗口（≤ 800 px 高，如 720p）同时最多 2 张卡，大窗口 3 张。

const MAX_DISTANCE := 45.0
## 以下为纯屏幕几何（画布单位，基准 1920×1080）
const CARD_MIN_WIDTH := 170.0
const CARD_MAX_WIDTH := 230.0
const MARKER_GUARD := Vector2(220.0, 170.0)   # 庇护所入口周围不让卡片盖住的区域
const PLAYER_GUARD := Vector2(90.0, 150.0)    # 玩家身体
const EDGE := 18.0
const GAP := 6.0

var _entries: Dictionary = {}   # id -> {world, title, sub, accent, offset, priority, card, marker, screen, active, shown}
## 返回 Array[Rect2]（画布坐标）：HUD 上卡片不得覆盖的区域。由 GameDirector 设置。
var rect_provider: Callable
## 玩家位置（世界坐标），用于保护区；由 GameDirector 每帧更新。
var player_world := Vector3.INF
## D16：建造特写时隐藏所有探索级文字卡和小点，只留工地的环与箭头。
var cards_hidden := false
## 非空时只画这个前缀的标签（庇护所剖面用）。
var only_prefix := ""
## > 0 时覆盖同时显示的卡片数上限。
var card_limit := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("world_callouts")

func set_callout(id: String, world: Vector3, title: String, sub: String, accent: Color,
		offset: Vector2 = Vector2(18.0, -58.0), priority: int = 1) -> void:
	if _entries.has(id):
		var e: Dictionary = _entries[id]
		if e["card"] == null or e["title"] != title or e["sub"] != sub:
			if e["card"] != null:
				(e["card"] as PanelContainer).queue_free()
			e["card"] = _make_card(title, sub, accent)
			add_child(e["card"])
		e["world"] = world
		e["title"] = title
		e["sub"] = sub
		e["accent"] = accent
		e["offset"] = offset
		e["priority"] = priority
		e["marker"] = false
		return
	var card := _make_card(title, sub, accent)
	add_child(card)
	_entries[id] = {"world": world, "title": title, "sub": sub, "accent": accent, "offset": offset, "priority": priority,
		"card": card, "marker": false, "screen": Vector2.ZERO, "active": false, "shown": false}

## 只画环 + 向下箭头的标记（没有文字卡）：文字信息放在固定 HUD 卡片里。
func set_marker(id: String, world: Vector3, accent: Color) -> void:
	if _entries.has(id) and _entries[id]["card"] != null:
		remove_callout(id)
	if _entries.has(id):
		_entries[id]["world"] = world
		_entries[id]["accent"] = accent
		return
	_entries[id] = {"world": world, "title": "", "sub": "", "accent": accent, "offset": Vector2.ZERO, "priority": 99,
		"card": null, "marker": true, "screen": Vector2.ZERO, "active": false, "shown": false}

func remove_callout(id: String) -> void:
	if _entries.has(id):
		if _entries[id]["card"] != null:
			(_entries[id]["card"] as PanelContainer).queue_free()
		_entries.erase(id)

## 删除所有 id 以 prefix 开头的标签（如 "deeper_"）。
func remove_prefix(prefix: String) -> void:
	for id in _entries.keys():
		if String(id).begins_with(prefix):
			remove_callout(id)

func has_callout(id: String) -> bool:
	return _entries.has(id)

## 当前真正画出了文字卡的标签 id（测试与截图检查用）。
func shown_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _entries:
		if bool(_entries[id]["shown"]):
			out.append(String(id))
	return out

func max_cards() -> int:
	if card_limit > 0:
		return card_limit
	return 2 if get_window().size.y <= 800 else 3

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view_size := get_viewport_rect().size
	var blocked: Array[Rect2] = []
	if rect_provider.is_valid():
		for r in rect_provider.call():
			blocked.append((r as Rect2).grow(GAP))
	if player_world != Vector3.INF and not camera.is_position_behind(player_world):
		var ps := camera.unproject_position(player_world)
		blocked.append(Rect2(ps - Vector2(PLAYER_GUARD.x * 0.5, PLAYER_GUARD.y * 0.8), PLAYER_GUARD))
	var order: Array = []
	for id in _entries:
		var e: Dictionary = _entries[id]
		var world: Vector3 = e["world"]
		e["shown"] = false
		var dist := camera.global_position.distance_to(world)
		e["active"] = not camera.is_position_behind(world) and dist <= MAX_DISTANCE + 40.0
		if e["active"]:
			e["screen"] = camera.unproject_position(world)
			e["dist"] = dist
		if e["card"] != null:
			(e["card"] as PanelContainer).visible = false
		if only_prefix != "" and not String(id).begins_with(only_prefix):
			e["active"] = false
		if not e["active"]:
			continue
		if cards_hidden and not e["marker"]:
			continue
		if e["marker"]:
			var s: Vector2 = e["screen"]
			blocked.append(Rect2(s - Vector2(MARKER_GUARD.x * 0.5, MARKER_GUARD.y * 0.7), MARKER_GUARD))
		else:
			order.append(id)
	order.sort_custom(func(a, b):
		var ea: Dictionary = _entries[a]
		var eb: Dictionary = _entries[b]
		if int(ea["priority"]) != int(eb["priority"]):
			return int(ea["priority"]) > int(eb["priority"])
		return float(ea["dist"]) < float(eb["dist"]))
	var shown := 0
	var limit := max_cards()
	for id in order:
		var e: Dictionary = _entries[id]
		if shown >= limit:
			continue
		var card := e["card"] as PanelContainer
		var size := card.get_combined_minimum_size()
		var screen: Vector2 = e["screen"]
		for off in _candidates(e["offset"], size):
			var p: Vector2 = screen + off
			p.x = clampf(p.x, EDGE, view_size.x - size.x - EDGE)
			p.y = clampf(p.y, EDGE, view_size.y - size.y - EDGE)
			var r := Rect2(p, size)
			var free := true
			for b in blocked:
				if r.intersects(b):
					free = false
					break
			if free:
				card.position = p
				card.size = size
				card.visible = true
				e["shown"] = true
				blocked.append(r.grow(GAP))
				shown += 1
				break
	queue_redraw()

## 候选偏移：先用调用方给的偏好，然后右上 / 右下 / 左上 / 左下，再远一点。
func _candidates(pref: Vector2, size: Vector2) -> Array[Vector2]:
	var r := 22.0
	return [pref, Vector2(r, -size.y - r), Vector2(r, r), Vector2(-size.x - r, -size.y - r), Vector2(-size.x - r, r),
		Vector2(r, -size.y - 3.0 * r), Vector2(-size.x - r, -size.y - 3.0 * r), Vector2(r, 3.0 * r), Vector2(-size.x - r, 3.0 * r)]

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	for id in _entries:
		var e: Dictionary = _entries[id]
		if not e["active"] or (cards_hidden and not e["marker"]):
			continue
		var screen: Vector2 = e["screen"]
		var color: Color = e["accent"]
		if e["marker"]:
			# 入口：脉动的环 + 上方向下的箭头（文字信息在 HUD 的庇护所卡片里）
			draw_arc(screen, 14.0 + 4.0 * pulse, 0.0, TAU, 32, Color(color, 0.55 + 0.3 * pulse), 2.5, true)
			draw_circle(screen, 4.5, Color(color, 0.95))
			var tip := screen + Vector2(0, -26.0)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-11, -16), tip + Vector2(11, -16)]), Color(color, 0.9))
			continue
		if not e["shown"]:
			# 放不下文字卡：只留一个淡淡的点，说明"这里有东西"
			draw_circle(screen, 3.0, Color(color, 0.6))
			continue
		var card := e["card"] as PanelContainer
		var anchor := Vector2(
			clampf(screen.x, card.position.x, card.position.x + card.size.x),
			clampf(screen.y, card.position.y, card.position.y + card.size.y)
		)
		draw_line(screen, anchor, Color(color.r, color.g, color.b, 0.82), 1.5, true)
		draw_circle(screen, 3.5, Color(color.r, color.g, color.b, 0.95))
		draw_arc(screen, 8.5, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.55), 1.2, true)

func _make_card(title: String, subtitle: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0.0)
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.86)
	style.border_width_left = 2
	style.border_color = accent
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 10.0
	style.content_margin_top = 6.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.80, 1.0))
	title_label.add_theme_font_size_override("font_size", 13)
	_wrap_if_long(title_label, 13)
	box.add_child(title_label)
	var sub_label := Label.new()
	sub_label.text = subtitle
	sub_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82, 1.0))
	sub_label.add_theme_font_size_override("font_size", 11)
	_wrap_if_long(sub_label, 11)
	box.add_child(sub_label)
	return panel

## 文字太长时换行，卡片宽度不超过 CARD_MAX_WIDTH。
func _wrap_if_long(l: Label, font_size: int) -> void:
	var font := l.get_theme_font("font")
	if font and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > CARD_MAX_WIDTH - 20.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = CARD_MAX_WIDTH - 20.0
