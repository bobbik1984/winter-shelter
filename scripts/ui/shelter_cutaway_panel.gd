extends PanelContainer

## 右上角独立 45° 剖面特写面板：SubViewport + 正交相机 + 5 个结构引线标注。
## 严格对标参考图右上角 SHELTER DESIGN (SNOW CAVE) — CUTAWAY VIEW (45° ISOMETRIC) 布局。

const LABELS := [
	{
		"local": Vector3(0.25, 2.75, 0.03),
		"title": "Vent / Chimney",
		"sub": "Reduce CO2, expel moisture",
		"pos": Vector2(342.0, 6.0),
		"accent": Color(0.68, 0.86, 1.0),
	},
	{
		"local": Vector3(0.95, 1.88, 0.0),
		"title": "Roof thickness",
		"sub": ">= 1.5 m",
		"pos": Vector2(368.0, 62.0),
		"accent": Color(0.96, 0.86, 0.64),
	},
	{
		"local": Vector3(1.18, 0.54, -0.65),
		"title": "Raised sleeping platform",
		"sub": "Stay above cold air",
		"pos": Vector2(328.0, 140.0),
		"accent": Color(0.96, 0.78, 0.42),
	},
	{
		"local": Vector3(-2.15, 0.05, -0.25),
		"title": "Entrance tunnel",
		"sub": "Slopes slightly down",
		"pos": Vector2(12.0, 206.0),
		"accent": Color(0.62, 0.82, 1.0),
	},
	{
		"local": Vector3(-0.72, -0.38, -0.55),
		"title": "Cold-air pit",
		"sub": "Traps cold air (lower)",
		"pos": Vector2(342.0, 220.0),
		"accent": Color(0.46, 0.72, 1.0),
	},
]

@onready var viewport_container: SubViewportContainer = $Margin/VBox/ViewportContainer
@onready var sub_viewport: SubViewport = $Margin/VBox/ViewportContainer/SubViewport
@onready var camera: Camera3D = $Margin/VBox/ViewportContainer/SubViewport/CutawayCamera
@onready var rig: ShelterCutawayRig = $Margin/VBox/ViewportContainer/SubViewport/ShelterRig
@onready var overlay: Control = $Margin/VBox/ViewportContainer/LabelOverlay

var _cards: Array[PanelContainer] = []
var _lines: Array[Line2D] = []
var _roof_line: Line2D
var _roof_tick_top: Line2D
var _roof_tick_bottom: Line2D

func _ready() -> void:
	# 正前偏右 15°、俯角 18° 的 45° 等距剖面机位：预留顶部排湿箭头与后景冷杉空间。
	camera.position = Vector3(1.85, 2.45, 6.80)
	camera.look_at(Vector3(-0.15, 0.96, -0.55), Vector3.UP)
	_build_overlay()

func _build_overlay() -> void:
	for i in range(LABELS.size()):
		var line := Line2D.new()
		line.width = 1.15
		line.default_color = Color(LABELS[i]["accent"])
		line.z_index = -1
		overlay.add_child(line)
		_lines.append(line)

		var card := _make_card(
			String(LABELS[i]["title"]), String(LABELS[i]["sub"]),
			LABELS[i]["accent"]
		)
		overlay.add_child(card)
		_cards.append(card)

	_roof_line = Line2D.new()
	_roof_line.width = 1.35
	_roof_line.default_color = Color(0.16, 0.25, 0.38, 0.95)
	_roof_line.z_index = -1
	overlay.add_child(_roof_line)
	_roof_tick_top = _make_tick(Color(0.16, 0.25, 0.38, 0.95))
	_roof_tick_bottom = _make_tick(Color(0.16, 0.25, 0.38, 0.95))

func _make_tick(color: Color) -> Line2D:
	var tick := Line2D.new()
	tick.width = 1.35
	tick.default_color = color
	tick.z_index = -1
	overlay.add_child(tick)
	return tick

func _make_card(title: String, subtitle: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(142.0, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.085, 0.88)
	style.border_width_left = 2
	style.border_color = accent
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 7.0
	style.content_margin_top = 4.0
	style.content_margin_right = 7.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84, 1.0))
	title_label.add_theme_font_size_override("font_size", 10)
	box.add_child(title_label)

	var sub_label := Label.new()
	sub_label.text = subtitle
	sub_label.add_theme_color_override("font_color", Color(0.74, 0.80, 0.88, 1.0))
	sub_label.add_theme_font_size_override("font_size", 8)
	box.add_child(sub_label)
	return panel

func _process(_delta: float) -> void:
	if camera == null or rig == null:
		return

	overlay.position = Vector2.ZERO
	overlay.size = viewport_container.size
	overlay.clip_contents = true

	for i in range(LABELS.size()):
		var world: Vector3 = rig.to_global(LABELS[i]["local"])
		var screen := camera.unproject_position(world)
		var card := _cards[i]
		var card_pos: Vector2 = LABELS[i]["pos"]
		card_pos.x = clampf(card_pos.x, 4.0, overlay.size.x - card.size.x - 4.0)
		card_pos.y = clampf(card_pos.y, 4.0, overlay.size.y - card.size.y - 4.0)
		card.position = card_pos
		var anchor := Vector2(
			clampf(screen.x, card_pos.x, card_pos.x + card.size.x),
			clampf(screen.y, card_pos.y, card_pos.y + card.size.y)
		)
		_lines[i].points = PackedVector2Array([screen, anchor])

	# 拱顶 1.5m 厚度双向箭头指示线（对应参考图拱顶左侧上下双箭头）
	var roof_low := camera.unproject_position(rig.to_global(Vector3(-0.22, 1.52, 0.02)))
	var roof_high := camera.unproject_position(rig.to_global(Vector3(-0.22, 2.38, 0.02)))
	_roof_line.points = PackedVector2Array([roof_low, roof_high])
	_roof_tick_top.points = PackedVector2Array([
		roof_high + Vector2(-4.0, 5.0), roof_high, roof_high + Vector2(4.0, 5.0)
	])
	_roof_tick_bottom.points = PackedVector2Array([
		roof_low + Vector2(-4.0, -5.0), roof_low, roof_low + Vector2(4.0, -5.0)
	])
