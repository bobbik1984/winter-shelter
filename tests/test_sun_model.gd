extends RefCounted

## 太阳模型断言：日落时刻与 Tuning 一致、影子"长→短→长"、方位自东南经南到西南。

var _passed := 0

func run() -> Dictionary:
	_passed = 0
	var failures: Array[String] = []
	var t := load("res://resources/tuning.tres") as Tuning
	if t == null:
		t = Tuning.new()
	var lat := t.sun_latitude_deg
	var dec := t.sun_declination_deg
	var noon := t.solar_noon_minutes

	var sunset := SunModel.sunset_minutes(lat, dec, noon)
	_check(absf(sunset - float(t.dusk_minutes)) < 10.0,
		"天文日落 %.0f 分钟应与 Tuning.dusk_minutes %d 相差 < 10 分钟" % [sunset, t.dusk_minutes], failures)

	var morning := SunModel.position(9.0 * 60.0, lat, dec, noon)
	var midday := SunModel.position(noon, lat, dec, noon)
	var afternoon := SunModel.position(float(t.start_minutes), lat, dec, noon)
	var late := SunModel.position(sunset - 20.0, lat, dec, noon)
	_check(midday.x > afternoon.x and afternoon.x > late.x, "高度角应 正午 > 开局 > 日落前，实际 %.1f / %.1f / %.1f" % [midday.x, afternoon.x, late.x], failures)
	_check(midday.x > morning.x, "正午应高于上午 9 点", failures)
	_check(absf(midday.y - 180.0) < 0.5, "正午方位应为正南 180°，实际 %.1f" % midday.y, failures)
	_check(morning.y > 90.0 and morning.y < 180.0, "上午太阳应在东南，实际 %.1f" % morning.y, failures)
	_check(late.y > 180.0 and late.y < 270.0, "傍晚太阳应在西南，实际 %.1f" % late.y, failures)
	_check(late.x > 0.0 and late.x < 4.0, "日落前 20 分钟应接近地平线，实际 %.1f°" % late.x, failures)

	var s_noon := SunModel.shadow_length_per_meter(midday.x)
	var s_late := SunModel.shadow_length_per_meter(late.x)
	_check(s_late > s_noon * 4.0, "傍晚影长 %.1f 应远长于正午 %.1f" % [s_late, s_noon], failures)

	var d := SunModel.direction(noon, lat, dec, noon)
	_check(d.z > 0.9 * cos(deg_to_rad(midday.x)) and absf(d.x) < 0.01, "正午太阳方向应指向世界 +Z（南），实际 %s" % d, failures)
	return {"passed": _passed, "failures": failures}

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		_passed += 1
	else:
		failures.append(message)
