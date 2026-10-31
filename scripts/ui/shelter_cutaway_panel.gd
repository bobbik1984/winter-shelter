extends PanelContainer

## 右上角独立 45° 剖面特写面板：SubViewport + 正交相机 + 5 个结构引线标注。
## 主场景只保留 3 个探索级 callout；本面板不污染大地图。

const LABELS := [
	{
		"local": Vector3(0.55, 2.85, -0.85),
		"title": "VENT / CHIMNEY",
		"sub": "Reduce CO2, expel moisture",
		"pos": Vector2(352.0, 8.0),
		"accent": Color(0.68, 0.86, 1.0),
	},
	{
		"local": Vector3(-0.35, 2.35, 0.0),
		"title": "ROOF THICKNESS",
		"sub": ">= 1.5 m",
		"pos": Vector2(8.0, 8.0),
		"accent": Color(0.96, 0.86, 0.64),
	},
	{
		"local": Vector3(1.25, 0.82, -0.55),
		"title": "RAISED PLATFORM",
		"sub": "Stay above cold air",
		"pos": Vector2(352.0, 146.0),
		"accent": Color(0.96, 0.78, 0.42),
	},
	{
		"local": Vector3(-2.35, 0.35, 0.0),
		"title": "ENTRANCE TUNNEL",
		"sub": "Slopes slightly down",
		"pos": Vector2(8.0, 206.0),
		"accent": Color(0.62, 0.82, 1.0),
	},
	{
		"local": Vector3(-0.70, -0.22, -0.25),
		"title": "COLD-AIR PIT",
		"sub": "Traps cold air lower",
		"pos": Vector2(352.0, 224.0),
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
	# 正前偏左 22° 的 45° 剖面特写机位。
	camera.position = Vector3(2.65, 4.05, 7.20)
	camera.look_at(Vector3(0.0, 1.35, -0.55), Vector3.UP)
	_build_overlay()

func _build_overlay() -> void:
	for i in range(LABELS.size()):
		var line := Line2D.new()
		line.width = 1.0
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
	_roof_line.width = 1.2
	_roof_line.default_color = Color(0.96, 0.86, 0.64, 0.95)
	_roof_line.z_index = -1
	overlay.add_child(_roof_line)
	_roof_tick_top = _make_tick(Color(0.96, 0.86, 0.64, 0.95))
	_roof_tick_bottom = _make_tick(Color(0.96, 0.86, 0.64, 0.95))

func _make_tick(color: Color) -> Line2D:
	var tick := Line2D.new()
	tick.width = 1.0
	tick.default_color = color
	tick.z_index = -1
	overlay.add_child(tick)
	return tick

func _make_card(title: String, subtitle: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(160.0, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.88)
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
	title_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.80, 1.0))
	title_label.add_theme_font_size_override("font_size", 10)
	box.add_child(title_label)

	var sub_label := Label.new()
	sub_label.text = subtitle
	sub_label.add_theme_color_override("font_color", Color(0.74, 0.79, 0.85, 1.0))
	sub_label.add_theme_font_size_override("font_size", 8)
	box.add_child(sub_label)
	return panel

func _process(_delta: float) -> void:
	if camera == null or rig == null:
		return

	# SubViewportContainer 不会自动给 Control 子节点一个尺寸；手动对齐到 520×275。
	overlay.position = Vector2.ZERO
	overlay.size = viewport_container.size
	overlay.clip_contents = true

	for i in range(LABELS.size()):
		var world: Vector3 = rig.to_global(LABELS[i]["local"])
		var screen := camera.unproject_position(world)
		var card := _cards[i]
		var card_pos: Vector2 = LABELS[i]["pos"]
		card_pos.x = clampf(card_pos.x, 2.0, overlay.size.x - card.size.x - 2.0)
		card_pos.y = clampf(card_pos.y, 2.0, overlay.size.y - card.size.y - 2.0)
		card.position = card_pos
		var anchor := Vector2(
			clampf(screen.x, card_pos.x, card_pos.x + card.size.x),
			clampf(screen.y, card_pos.y, card_pos.y + card.size.y)
		)
		_lines[i].points = PackedVector2Array([screen, anchor])

	# 拱顶厚度双向指示线：从内拱顶到外雪面。
	var roof_low := camera.unproject_position(rig.to_global(Vector3(-0.35, 0.98, 0.0)))
	var roof_high := camera.unproject_position(rig.to_global(Vector3(-0.35, 2.35, 0.0)))
	_roof_line.points = PackedVector2Array([roof_low, roof_high])
	_roof_tick_top.points = PackedVector2Array([
		roof_high + Vector2(-7.0, 4.0), roof_high + Vector2(7.0, -4.0)
	])
	_roof_tick_bottom.points = PackedVector2Array([
		roof_low + Vector2(-7.0, 4.0), roof_low + Vector2(7.0, -4.0)
	])
