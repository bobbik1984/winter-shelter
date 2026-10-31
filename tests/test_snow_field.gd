extends RefCounted

## T1.2 雪深场断言：背风区更厚、读数连续、坡度可用。

var _passed := 0

func run() -> Dictionary:
	_passed = 0
	var failures: Array[String] = []
	_test_lee_deeper(failures)
	_test_snow_bounds(failures)
	_test_slope_continuous(failures)
	return {"passed": _passed, "failures": failures}

func _test_lee_deeper(failures: Array[String]) -> void:
	var lee := SnowField.snow_at(20.0, 0.0)
	var windward := SnowField.snow_at(-20.0, 0.0)
	_check(lee > windward, "背风坡雪深 %.2f 应大于迎风坡 %.2f" % [lee, windward], failures)
	_check(lee >= 1.5, "背风坡应达到雪洞量级（>=1.5 m），实际 %.2f" % lee, failures)

func _test_snow_bounds(failures: Array[String]) -> void:
	var samples := [
		Vector2(-45.0, -45.0), Vector2(0.0, 0.0), Vector2(25.0, 20.0), Vector2(45.0, 45.0),
	]
	for s in samples:
		var depth := SnowField.snow_at(s.x, s.y)
		_check(depth >= 0.04 and depth <= 3.0, "雪深越界 %.2f @ %s" % [depth, s], failures)

func _test_slope_continuous(failures: Array[String]) -> void:
	var a := SnowField.snow_at(18.0, 5.0)
	var b := SnowField.snow_at(18.4, 5.0)
	_check(absf(a - b) < 0.5, "同一斜坡相邻采样应连续（%.2f vs %.2f）" % [a, b], failures)
	var lee_factor := SnowField.lee_factor_at(20.0, 0.0)
	_check(lee_factor >= 0.0 and lee_factor <= 1.0, "背风因子应在 0..1，实际 %.2f" % lee_factor, failures)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		_passed += 1
	else:
		failures.append(message)
