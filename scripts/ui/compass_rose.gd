extends Control

## 右下角风向罗盘：随相机偏航旋转的 N/E/S/W，指针指向风的去向（下风）。
## 世界约定：-Z = 北，+X = 东。

const RING_BG := Color(0.04, 0.07, 0.11, 0.72)
const RING_LINE := Color(0.78, 0.72, 0.58, 0.70)
const LABEL := Color(0.94, 0.90, 0.80, 0.95)
const NEEDLE := Color(1.0, 0.55, 0.12, 1.0)

var _yaw := INF
var _blow := Vector3.RIGHT
## 太阳方位（°，自北顺时针）与高度角：罗盘上画一个太阳标记，越低越靠外圈、越红（影子就是时钟）。
var sun_azimuth_deg: float = 215.0
var sun_elevation_deg: float = 14.0

func set_sun(az: float, el: float) -> void:
	if absf(az - sun_azimuth_deg) > 0.2 or absf(el - sun_elevation_deg) > 0.2:
		sun_azimuth_deg = az
		sun_elevation_deg = el
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wind := load("res://resources/default_wind.tres") as WindData
	if wind:
		_blow = wind.get_blow_direction_3d()

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	var yaw := atan2(-fwd.x, -fwd.z)
	if not is_equal_approx(yaw, _yaw):
		_yaw = yaw
		queue_redraw()

## 世界水平方向 → 罗盘屏幕方向（屏幕上 = 相机前方）。
func _screen_dir(world: Vector3) -> Vector2:
	var local := world.rotated(Vector3.UP, -(_yaw if _yaw != INF else 0.0))
	return Vector2(local.x, local.z).normalized()

func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(center, radius, RING_BG)
	draw_arc(center, radius, 0.0, TAU, 64, RING_LINE, 1.4, true)
	draw_arc(center, radius - 8.0, 0.0, TAU, 64, Color(0.78, 0.72, 0.58, 0.28), 1.0, true)

	var north := _screen_dir(Vector3.FORWARD)
	var base_angle := north.angle()
	for tick in range(8):
		var angle := base_angle + float(tick) * TAU / 8.0
		var dir := Vector2(cos(angle), sin(angle))
		var inner := center + dir * (radius - (14.0 if tick % 2 == 0 else 9.0))
		var outer := center + dir * (radius - 3.0)
		draw_line(inner, outer, RING_LINE, 1.2, true)

	var font := ThemeDB.fallback_font
	var label_offset := radius - 22.0
	var labels := {"N": Vector3.FORWARD, "E": Vector3.RIGHT, "S": Vector3.BACK, "W": Vector3.LEFT}
	for key in labels:
		var p := center + _screen_dir(labels[key]) * label_offset
		draw_string(font, p + Vector2(-10.0, 5.0), key, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 15, LABEL)

	var d := _screen_dir(_blow)
	var tail := center - d * radius * 0.44
	var tip := center + d * radius * 0.58
	draw_line(tail, tip, NEEDLE, 3.0, true)
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([tip + d * 4.0, tip - d * 12.0 + side * 7.0, tip - d * 12.0 - side * 7.0]), NEEDLE)
	draw_circle(center, 4.0, Color(0.95, 0.86, 0.64, 1.0))

	# 太阳标记：方位 = 真实太阳方位；离中心的距离 = 越低越靠外（地平线 = 外圈）
	if sun_elevation_deg > -2.0:
		var az := deg_to_rad(sun_azimuth_deg)
		var sun_world := Vector3(sin(az), 0, -cos(az))
		var k := clampf(1.0 - sun_elevation_deg / 30.0, 0.25, 1.0)
		var sp := center + _screen_dir(sun_world) * (radius - 8.0) * k
		var warm := clampf(1.0 - sun_elevation_deg / 20.0, 0.0, 1.0)
		var sc := Color(1.0, lerpf(0.92, 0.55, warm), lerpf(0.55, 0.2, warm))
		draw_circle(sp, 7.0, sc)
		for r in range(8):
			var a := TAU * r / 8.0
			draw_line(sp + Vector2(cos(a), sin(a)) * 9.0, sp + Vector2(cos(a), sin(a)) * 12.0, sc, 1.5, true)
