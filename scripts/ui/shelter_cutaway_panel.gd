extends PanelContainer

## 右上角独立 45° 剖面特写面板：SubViewport + 正交相机 + 5 个结构引线标注。
## 严格对标参考图右上角 SHELTER DESIGN (SNOW CAVE) — CUTAWAY VIEW (45° ISOMETRIC) 布局。

const LABELS := [
	{
		"local": Vector3(0.25, 2.95, 0.0),
		"title": "Vent / Chimney",
		"sub": "Reduce CO2, expel moisture",
		"pos": Vector2(342.0, 6.0),
		"accent": Color(0.68, 0.86, 1.0),
	},
	{
		"local": Vector3.ZERO,  # 运行时取 rig.roof_outer_point()
		"title": "Roof thickness",
		"sub": "",                # 运行时由 Tuning 生成
		"pos": Vector2(352.0, 62.0),
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
		"local": Vector3(-2.55, 0.10, 0.0),
		"title": "Entrance tunnel",
		"sub": "Slopes slightly down",
		"pos": Vector2(12.0, 206.0),
		"accent": Color(0.62, 0.82, 1.0),
	},
	{
		"local": Vector3(-0.75, -0.42, 0.0),
		"title": "Cold-air pit",
		"sub": "Traps cold air (lower)",
		"pos": Vector2(342.0, 220.0),
		"accent": Color(0.46, 0.72, 1.0),
	},
]
const ROOF_LABEL_INDEX := 1

## 气流示意线（rig 局部坐标，z = 0 剖切面内），与 shader 共用同一相机投影。
const VENT_ARROW := [Vector3(0.25, 2.12, 0.0), Vector3(0.25, 2.86, 0.0)]
const COLD_AIR_PATH := [
	Vector3(-3.0, 0.16, 0.0), Vector3(-2.2, 0.10, 0.0), Vector3(-1.55, -0.02, 0.0),
	Vector3(-1.15, -0.30, 0.0), Vector3(-0.70, -0.40, 0.0), Vector3(-0.32, -0.30, 0.0),
	Vector3(-0.20, -0.08, 0.0), Vector3(-0.36, 0.06, 0.0),
]
const COOL_COLOR := Color(0.66, 0.86, 1.0, 0.95)
const DIM_COLOR := Color(0.12, 0.20, 0.34, 0.95)

@onready var viewport_container: SubViewportContainer = $Margin/VBox/ViewportContainer
@onready var sub_viewport: SubViewport = $Margin/VBox/ViewportContainer/SubViewport
@onready var camera: Camera3D = $Margin/VBox/ViewportContainer/SubViewport/CutawayCamera
@onready var rig: ShelterCutawayRig = $Margin/VBox/ViewportContainer/SubViewport/ShelterRig
@onready var overlay: Control = $Margin/VBox/ViewportContainer/LabelOverlay

var _cards: Array[PanelContainer] = []
var _lines: Array[Line2D] = []
var _roof_sub: Label
var _frame := 0
## 剖面是光线步进 SDF，较贵：每 N 帧重绘一次（烛光闪烁仍足够流畅）。
const REDRAW_EVERY := 4

func _ready() -> void:
	# 正前偏右 15°、俯角 18° 的 45° 等距剖面机位：预留顶部排湿箭头与后景冷杉空间。
	camera.position = Vector3(1.85, 2.45, 6.80)
	camera.look_at(Vector3(-0.15, 0.96, -0.55), Vector3.UP)
	_build_overlay()
	overlay.draw.connect(_draw_overlay)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

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
	# 顶厚副标题：从 Tuning 读，不再写死
	_roof_sub = _cards[ROOF_LABEL_INDEX].get_child(0).get_child(1) as Label
	_roof_sub.text = "≥ %.2f m · built %.2f m" % [rig.roof_min_m, rig.roof_built_m]

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

## rig 局部坐标 → 面板屏幕坐标（与 shader 同一相机）。
func _proj(local: Vector3) -> Vector2:
	return camera.unproject_position(rig.to_global(local))

func _process(_delta: float) -> void:
	if camera == null or rig == null:
		return

	overlay.position = Vector2.ZERO
	overlay.size = viewport_container.size
	overlay.clip_contents = true

	for i in range(LABELS.size()):
		var local: Vector3 = LABELS[i]["local"]
		if i == ROOF_LABEL_INDEX:
			local = rig.roof_outer_point()
		var screen := _proj(local)
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
	overlay.queue_redraw()
	_frame += 1
	if _frame % REDRAW_EVERY == 0:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_overlay() -> void:
	# 顶厚双向尺寸线（两端点来自 rig：穹顶内侧 → 内侧 + built 顶厚）
	var lo := _proj(rig.roof_inner_point())
	var hi := _proj(rig.roof_outer_point())
	overlay.draw_line(lo, hi, DIM_COLOR, 1.4, true)
	for end in [[lo, 1.0], [hi, -1.0]]:
		var pt: Vector2 = end[0]
		var sgn: float = end[1]
		overlay.draw_polyline(PackedVector2Array([
			pt + Vector2(-4.0, 5.0 * sgn), pt, pt + Vector2(4.0, 5.0 * sgn)
		]), DIM_COLOR, 1.4, true)
		overlay.draw_line(pt + Vector2(-6.0, 0.0), pt + Vector2(6.0, 0.0), DIM_COLOR, 1.2, true)

	# 排湿箭头（穿过通风井向上）
	_draw_arrow([_proj(VENT_ARROW[0]), _proj(VENT_ARROW[1])], COOL_COLOR, 2.2)

	# 冷气下沉弧线：从隧道口沿地面滑进冷气坑再打旋
	var pts := PackedVector2Array()
	for v in COLD_AIR_PATH:
		pts.append(_proj(v))
	_draw_arrow(_smooth(pts), COOL_COLOR, 2.0)

## Catmull-Rom 平滑，保证弧线不出折角。
func _smooth(pts: PackedVector2Array, per_seg: int = 8) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for k in range(per_seg):
			var t := float(k) / float(per_seg)
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 1])
	return out

func _draw_arrow(points: Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var packed := PackedVector2Array()
	for p in points:
		packed.append(p)
	# 先画一层深色描边保证在亮雪上也可读
	overlay.draw_polyline(packed, Color(0.04, 0.09, 0.18, 0.55), width + 2.2, true)
	overlay.draw_polyline(packed, color, width, true)
	var tip: Vector2 = points[points.size() - 1]
	var back: Vector2 = points[maxi(points.size() - 4, 0)]
	var dir := (tip - back).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([tip + dir * 6.0, tip - dir * 5.0 + side * 5.0, tip - dir * 5.0 - side * 5.0])
	overlay.draw_colored_polygon(head, color)
