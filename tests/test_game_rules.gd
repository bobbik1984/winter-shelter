extends RefCounted

## 游戏循环纯规则：移动阻尼、探针分类、入口风向、生火判定、提示、效率、背包。

var _passed := 0
var _failures: Array[String] = []

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var t := load("res://resources/tuning.tres") as Tuning

	# 移动阻尼（T1.4）
	var flat := GameRules.move_speed(3.6, 0.0, 0.2, t)
	var deep := GameRules.move_speed(3.6, 0.0, 2.5, t)
	var uphill := GameRules.move_speed(3.6, 20.0, 0.2, t)
	_check(is_equal_approx(flat, 3.6), "平地浅雪应为基础速度，实际 %.2f" % flat)
	_check(deep < flat * 0.6 and deep >= 3.6 * t.deep_snow_speed_min - 0.001, "深雪应明显变慢但不低于下限，实际 %.2f" % deep)
	_check(uphill < flat and uphill >= 3.6 * t.uphill_speed_min - 0.001, "上坡应变慢，实际 %.2f" % uphill)

	# 探针分类（D5）
	_check(GameRules.classify_depth(0.2, t)["key"] == "shallow", "0.2 m 应为浅雪")
	_check(GameRules.classify_depth(0.6, t)["key"] == "trench_wall", "0.6 m 应为砌墙雪沟")
	_check(GameRules.classify_depth(1.2, t)["key"] == "trench", "1.2 m 应为标准雪沟")
	_check(GameRules.classify_depth(1.7, t)["key"] == "cave", "1.7 m 应为雪洞")
	_check(GameRules.classify_depth(2.3, t)["key"] == "raised_cave", "2.3 m 应为高床雪洞")

	# 入口与风向（西风：来向 -X）
	var from_west := Vector3(-1, 0, 0)
	_check(GameRules.entrance_wind_angle(Vector3(-1, 0, 0), from_west) < 1.0, "入口朝西 = 正迎风 0°")
	_check(GameRules.entrance_wind_angle(Vector3(1, 0, 0), from_west) > 179.0, "入口朝东 = 背风 180°")
	_check(absf(GameRules.entrance_wind_angle(Vector3(0, 0, 1), from_west) - 90.0) < 1.0, "入口朝南 = 侧风 90°")

	# 生火（D2/D3）
	_check(not GameRules.fire_check(4, 2, 0.1, false, true, t)["ok"], "雪庇护所内禁止明火")
	_check(not GameRules.fire_check(4, 0, 0.1, false, false, t)["ok"], "没有引火物不能生火")
	_check(not GameRules.fire_check(1, 2, 0.1, false, false, t)["ok"], "木材不足不能生火")
	_check(not GameRules.fire_check(4, 2, 0.1, true, false, t)["ok"], "树冠下落雪压火")
	_check(not GameRules.fire_check(4, 2, 0.95, false, false, t)["ok"], "迎风被吹灭")
	_check(GameRules.fire_check(4, 2, 0.2, false, false, t)["ok"], "背风、材料齐全应能点燃")
	_check(GameRules.fire_exposure(0.2, true) < GameRules.fire_exposure(0.2, false), "挡风物降低暴露")

	# 提示（V3）
	_check(GameRules.tip_for(50.0, 6.0, 90.0, false, false, t).contains("lengthening"), "日落前 50 分钟应提示影子变长")
	_check(GameRules.tip_for(20.0, 2.0, 90.0, true, false, t).contains("Finish"), "日落前 20 分钟且未完工应催促")
	_check(GameRules.tip_for(120.0, 14.0, 20.0, false, false, t).contains("cold"), "低体温优先提示取暖")
	for m in [200.0, 60.0, 20.0, -5.0]:
		_check(GameRules.tip_for(m, 5.0, 90.0, false, false, t).length() <= 56, "提示须短到放进环境卡（<=56 字符）")

	# 效率
	_check(is_equal_approx(GameRules.work_efficiency(1.0, 30.0, t), 1.0), "日落前满效率")
	_check(GameRules.work_efficiency(1.0, -60.0, t) <= t.dusk_efficiency_floor + 0.001, "日落 1 小时后降到下限")

	# 背包
	var inv := Inventory.new()
	inv.max_wood = 3
	inv.add("wood", 5)
	_check(inv.wood == 3, "木材应受上限约束，实际 %d" % inv.wood)
	_check(inv.spend({"wood": 2, "bark": 1}) == false and inv.wood == 3, "材料不足时 spend 不扣任何东西")
	inv.add("bark", 1)
	_check(inv.spend({"wood": 2, "bark": 1}) and inv.wood == 1 and inv.bark == 0, "材料足够时扣除")
	inv.free()
	return {"passed": _passed, "failures": _failures}

func _check(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures.append(msg)
