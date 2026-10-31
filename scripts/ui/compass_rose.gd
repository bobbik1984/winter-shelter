extends Control

## 右下角风向罗盘：半透明圆盘 + N/E/S/W + 指向东侧（西风吹向东）的橙金指针。

const RING_BG := Color(0.04, 0.07, 0.11, 0.72)
const RING_LINE := Color(0.78, 0.72, 0.58, 0.70)
const LABEL := Color(0.94, 0.90, 0.80, 0.95)
const NEEDLE := Color(1.0, 0.55, 0.12, 1.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(center, radius, RING_BG)
	draw_arc(center, radius, 0.0, TAU, 64, RING_LINE, 1.4, true)
	draw_arc(center, radius - 8.0, 0.0, TAU, 64, Color(0.78, 0.72, 0.58, 0.28), 1.0, true)

	for tick in range(8):
		var angle := float(tick) * TAU / 8.0 - PI * 0.5
		var dir := Vector2(cos(angle), sin(angle))
		var inner := center + dir * (radius - (14.0 if tick % 2 == 0 else 9.0))
		var outer := center + dir * (radius - 3.0)
		draw_line(inner, outer, RING_LINE, 1.2, true)

	var font := ThemeDB.fallback_font
	var label_offset := radius - 20.0
	draw_string(font, center + Vector2(-10.0, -label_offset), "N", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 15, LABEL)
	draw_string(font, center + Vector2(-10.0, label_offset + 6.0), "S", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 15, LABEL)
	draw_string(font, center + Vector2(label_offset - 6.0, 5.0), "E", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 15, LABEL)
	draw_string(font, center + Vector2(-label_offset - 14.0, 5.0), "W", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 15, LABEL)

	# 西风自西向东：指针指向右侧 E。
	var tail := center + Vector2(-radius * 0.44, 0.0)
	var tip := center + Vector2(radius * 0.62, 0.0)
	draw_line(tail, tip, NEEDLE, 3.0, true)
	var head := PackedVector2Array([
		tip,
		tip + Vector2(-12.0, -7.0),
		tip + Vector2(-12.0, 7.0),
	])
	draw_colored_polygon(head, NEEDLE)
	draw_circle(center, 4.0, Color(0.95, 0.86, 0.64, 1.0))
