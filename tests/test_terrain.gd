extends RefCounted

## T1.1a 高度函数断言。

var _passed := 0

func run() -> Dictionary:
	_passed = 0
	var failures: Array[String] = []
	_test_ridge_highest(failures)
	_test_lee_slope_gentler(failures)
	_test_normal_and_bounds(failures)
	return {"passed": _passed, "failures": failures}

func _test_ridge_highest(failures: Array[String]) -> void:
	var ridge := TerrainHeight.height_at(-14.7, 0.0)
	var lee := TerrainHeight.height_at(30.0, 0.0)
	_check(ridge > lee, "脊线高度 %.2f 应高于背风坡 %.2f" % [ridge, lee], failures)
	_check(ridge > 4.0, "脊线应形成可读高差（>4 m），实际 %.2f" % ridge, failures)

func _test_lee_slope_gentler(failures: Array[String]) -> void:
	var west := TerrainHeight.slope_at(-10.0, 0.0)
	var east := TerrainHeight.slope_at(20.0, 0.0)
	_check(west > east, "西侧迎风坡 %.1f° 应比东侧背风坡 %.1f° 陡" % [west, east], failures)

func _test_normal_and_bounds(failures: Array[String]) -> void:
	var n := TerrainHeight.normal_at(0.0, 0.0)
	_check(n.y > 0.5, "地形法线应朝上，实际 %.2f" % n.y, failures)
	_check(absf(n.length() - 1.0) < 0.001, "法线应为单位向量", failures)
	var h := TerrainHeight.height_at(0.0, 0.0)
	_check(h >= 0.2 and h < 12.0, "高度应在合理范围，实际 %.2f" % h, failures)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		_passed += 1
	else:
		failures.append(message)
