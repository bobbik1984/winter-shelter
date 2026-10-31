class_name WorldCallouts
extends Control

## 世界空间引线标签（参考图 4 / 5 / 6 号元素），统一一个组件（T3.5）。
## 内容是**动态**的（D4：Deeper snow 只在玩家探测过的位置出现）：
## GameDirector 通过 set_callout / remove_callout 增删；距离过远或在相机背后时隐藏。

const MAX_DISTANCE := 45.0

var _entries: Dictionary = {}   # id -> {world, title, sub, accent, offset, card}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("world_callouts")

func set_callout(id: String, world: Vector3, title: String, sub: String, accent: Color,
		offset: Vector2 = Vector2(18.0, -58.0)) -> void:
	if _entries.has(id):
		var e: Dictionary = _entries[id]
		if e["title"] != title or e["sub"] != sub:
			(e["card"] as PanelContainer).queue_free()
			e["card"] = _make_card(title, sub, accent)
			add_child(e["card"])
		e["world"] = world
		e["title"] = title
		e["sub"] = sub
		e["accent"] = accent
		e["offset"] = offset
		return
	var card := _make_card(title, sub, accent)
	add_child(card)
	_entries[id] = {"world": world, "title": title, "sub": sub, "accent": accent,
		"offset": offset, "card": card, "screen": Vector2.ZERO, "active": false}

func remove_callout(id: String) -> void:
	if _entries.has(id):
		(_entries[id]["card"] as PanelContainer).queue_free()
		_entries.erase(id)

func has_callout(id: String) -> bool:
	return _entries.has(id)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view_size := get_viewport_rect().size
	for id in _entries:
		var e: Dictionary = _entries[id]
		var card := e["card"] as PanelContainer
		var world: Vector3 = e["world"]
		if camera.is_position_behind(world) or camera.global_position.distance_to(world) > MAX_DISTANCE + 40.0:
			card.visible = false
			e["active"] = false
			continue
		var screen := camera.unproject_position(world)
		card.visible = true
		e["active"] = true
		e["screen"] = screen
		var target: Vector2 = screen + e["offset"]
		target.x = clampf(target.x, 18.0, view_size.x - card.size.x - 18.0)
		target.y = clampf(target.y, 18.0, view_size.y - card.size.y - 18.0)
		card.position = target
	queue_redraw()

func _draw() -> void:
	for id in _entries:
		var e: Dictionary = _entries[id]
		if not e["active"]:
			continue
		var card := e["card"] as PanelContainer
		var screen: Vector2 = e["screen"]
		var anchor := Vector2(
			clampf(screen.x, card.position.x, card.position.x + card.size.x),
			clampf(screen.y, card.position.y, card.position.y + card.size.y)
		)
		var color: Color = e["accent"]
		draw_line(screen, anchor, Color(color.r, color.g, color.b, 0.82), 1.5, true)
		draw_circle(screen, 3.5, Color(color.r, color.g, color.b, 0.95))
		draw_arc(screen, 8.5, 0.0, TAU, 24, Color(color.r, color.g, color.b, 0.55), 1.2, true)

func _make_card(title: String, subtitle: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(170.0, 0.0)
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
	box.add_child(title_label)
	var sub_label := Label.new()
	sub_label.text = subtitle
	sub_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82, 1.0))
	sub_label.add_theme_font_size_override("font_size", 11)
	box.add_child(sub_label)
	return panel
