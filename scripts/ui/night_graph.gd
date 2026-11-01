class_name NightGraph
extends Control

## D14 夜间体温曲线（夜里播放时的 HUD、报告缩略图共用）。x = 入睡后分钟（0..duration），y = 体温 0..100。
## 画 SAFE 线（50）、冷醒线（40）、极危线（15），以及醒来事件的小竖线。

var points: PackedVector2Array = PackedVector2Array()
var duration := 828.0
var events: Array = []          ## [{minute}]
var now_minute := -1.0
var safe_w := 50.0
var cold_w := 40.0
var critical_w := 15.0

const BG := Color(0.03, 0.05, 0.09, 0.82)
const LINE := Color(1.0, 0.72, 0.38)
const GRID := Color(1, 1, 1, 0.12)

func set_data(p_points: PackedVector2Array, p_duration: float, p_events: Array, p_now: float = -1.0) -> void:
	points = p_points
	duration = maxf(p_duration, 1.0)
	events = p_events
	now_minute = p_now
	queue_redraw()

func _xy(m: float, w: float) -> Vector2:
	return Vector2(size.x * clampf(m / duration, 0.0, 1.0), size.y * (1.0 - clampf(w / 100.0, 0.0, 1.0)))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for pair in [[safe_w, Color(0.55, 0.9, 0.6, 0.35)], [cold_w, Color(1.0, 0.75, 0.35, 0.3)], [critical_w, Color(1.0, 0.4, 0.35, 0.4)]]:
		var y := _xy(0.0, float(pair[0])).y
		draw_line(Vector2(0, y), Vector2(size.x, y), pair[1], 1.0)
	for e in events:
		var x := _xy(float(e["minute"]), 0.0).x
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 1.0)
	if points.size() >= 2:
		var pts := PackedVector2Array()
		for p in points:
			pts.append(_xy(p.x, p.y))
		draw_polyline(pts, LINE, 2.0, true)
	if now_minute >= 0.0:
		var x2 := _xy(now_minute, 0.0).x
		draw_line(Vector2(x2, 0), Vector2(x2, size.y), Color(1, 1, 1, 0.5), 1.0)
