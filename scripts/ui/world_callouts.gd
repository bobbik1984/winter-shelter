extends Control

## 主场景大地图的 3 个探索级世界引线标注（保持主画面清爽，不与右上角独立剖面特写窗重叠）：
## Deeper snow / Good depth / Deadwood。

const CALLOUTS := [
	{
		"world": Vector3(20.0, 0.0, 10.0),
		"title": "DEEPER SNOW",
		"sub": "Ideal for shelter",
		"offset": Vector2(28.0, -54.0),
		"accent": Color(0.52, 0.72, 1.0),
	},
	{
		"world": Vector3(18.47, 0.0, 8.04),
		"title": "GOOD DEPTH",
		"sub": "~ 2.1 m",
		"offset": Vector2(-238.0, -34.0),
		"accent": Color(0.95, 0.78, 0.40),
	},
	{
		"world": Vector3(5.5, 0.0, 3.5),
		"title": "DEADWOOD",
		"sub": "Harvest for fuel",
		"offset": Vector2(28.0, 18.0),
		"accent": Color(1.0, 0.55, 0.12),
	},
]

var _cards: Array[PanelContainer] = []
var _active: Array[bool] = []
var _screen_points: Array[Vector2] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for entry in CALLOUTS:
		var card := _make_card(entry["title"], entry["sub"], entry["accent"])
		add_child(card)
		_cards.append(card)
		_active.append(false)
		_screen_points.append(Vector2.ZERO)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view_size := get_viewport_rect().size
	for i in range(CALLOUTS.size()):
		var entry: Dictionary = CALLOUTS[i]
		var world: Vector3 = entry["world"]
		world.y = TerrainHeight.height_at(world.x, world.z) + float(entry.get("y_offset", 0.65))
		if camera.is_position_behind(world):
			_cards[i].visible = false
			_active[i] = false
			continue
		var screen := camera.unproject_position(world)
		var card := _cards[i]
		card.visible = true
		_active[i] = true
		_screen_points[i] = screen
		var target: Vector2 = screen + entry["offset"]
		target.x = clampf(target.x, 18.0, view_size.x - card.size.x - 18.0)
		target.y = clampf(target.y, 18.0, view_size.y - card.size.y - 18.0)
		card.position = target
	queue_redraw()

func _draw() -> void:
	for i in range(CALLOUTS.size()):
		if not _active[i]:
			continue
		var card := _cards[i]
		var screen := _screen_points[i]
		var anchor := Vector2(
			clampf(screen.x, card.position.x, card.position.x + card.size.x),
			clampf(screen.y, card.position.y, card.position.y + card.size.y)
		)
		var color: Color = CALLOUTS[i]["accent"]
		draw_line(screen, anchor, Color(color.r, color.g, color.b, 0.80), 1.5, true)
		draw_circle(screen, 3.0, Color(color.r, color.g, color.b, 0.95))

func _make_card(title: String, subtitle: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(190.0, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.84)
	style.border_width_left = 2
	style.border_color = accent
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 10.0
	style.content_margin_top = 7.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 7.0
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
