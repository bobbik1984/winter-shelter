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
	_check(not GameRules.fire_check(4, 2, t.fire_blowout_dot + 0.05, false, false, t)["ok"], "白天吹灭阈值须与 NightSimulator 一致")
	_check(GameRules.fire_exposure(0.2, 1.0) < GameRules.fire_exposure(0.2, 0.0), "挡风物降低暴露")
	# 第二次评审：树根盘只挡下风一侧
	var wbp: Array = [Vector2(0, 0)]
	var blow := Vector2(1, 0)
	_check(GameRules.windbreak_shelter(wbp, Vector2(1.5, 0), blow, 3.5) > 0.5, "树根盘正下风 1.5 m：挡得住")
	_check(GameRules.windbreak_shelter(wbp, Vector2(-1.5, 0), blow, 3.5) == 0.0, "树根盘迎风一侧：挡不住")
	_check(GameRules.windbreak_shelter(wbp, Vector2(0, 1.5), blow, 3.5) < GameRules.windbreak_shelter(wbp, Vector2(1.5, 0), blow, 3.5), "侧面比正下风挡得少")
	_check(GameRules.windbreak_shelter(wbp, Vector2(5, 0), blow, 3.5) == 0.0, "离太远挡不住")
	_check(GameRules.fire_exposure(0.0, GameRules.windbreak_shelter(wbp, Vector2(1.2, 0), blow, 3.5)) <= t.fire_blowout_dot, "开阔地上，紧贴树根盘下风一侧能生火（不被吹灭）")
	_check(GameRules.fire_exposure(0.0, GameRules.windbreak_shelter(wbp, Vector2(-1.2, 0), blow, 3.5)) > t.fire_blowout_dot, "开阔地上，树根盘迎风一侧会被吹灭")

	# 提示（V3）
	_check(GameRules.tip_for(50.0, 6.0, 90.0, false, false, t).contains("lengthening"), "日落前 50 分钟应提示影子变长")
	_check(GameRules.tip_for(20.0, 2.0, 90.0, true, false, t).contains("Finish"), "日落前 20 分钟且未完工应催促")
	_check(GameRules.tip_for(120.0, 14.0, 20.0, false, false, t).contains("cold"), "低体温优先提示取暖")
	for m in [200.0, 60.0, 20.0, -5.0]:
		_check(GameRules.tip_for(m, 5.0, 90.0, false, false, t).length() <= 56, "提示须短到放进环境卡（<=56 字符）")

	# 目标行
	_check(GameRules.next_objective({}, t).contains("probe"), "开局应提示探测")
	_check(GameRules.next_objective({"probed": true, "best_depth": 2.0}, t).contains("[B]"), "找到深雪后提示建造")
	_check(GameRules.next_objective({"has_site": true, "missing": "2 bedding"}, t).contains("2 bedding"), "缺材料时提示采集")
	_check(GameRules.next_objective({"has_site": true, "next_stage": "Stage 4: Vent"}, t).contains("Vent"), "提示下一阶段")
	_check(GameRules.next_objective({"has_site": true, "complete": true}, t).contains("[N]"), "完工后提示休息")
	_check(GameRules.next_objective({"has_site": true, "complete": true, "needs_vent_stick": true}, t).contains("vent"), "降雪时提示插通风木棍")

	# 手柄映射与重复绑定
	_check(GameInput.joy_to_key(JOY_BUTTON_START, GameDirector.State.BRIEFING, false) == KEY_ENTER, "Start 在简报页 = 开始")
	_check(GameInput.joy_to_key(JOY_BUTTON_START, GameDirector.State.PLAYING, false) == KEY_ESCAPE, "Start 游戏中 = 暂停")
	_check(GameInput.joy_to_key(JOY_BUTTON_B, GameDirector.State.PLAYING, true) == KEY_B, "建造中 B = 取消")
	_check(GameInput.joy_to_key(JOY_BUTTON_B, GameDirector.State.PLAYING, false) == KEY_F, "平时 B = 生火")
	_check(GameInput.joy_to_key(JOY_BUTTON_RIGHT_SHOULDER, GameDirector.State.PLAYING, false) == KEY_TAB, "非建造时 RB = Tab（只在情报面板开着时翻页，否则无动作）")
	_check(GameInput.joy_to_key(JOY_BUTTON_BACK, GameDirector.State.BRIEFING, false) == KEY_I and GameInput.joy_to_key(JOY_BUTTON_BACK, GameDirector.State.PLAYING, false) == KEY_H, "Back：简报页开情报，游戏中开野外手册")
	if InputMap.has_action("interact"):
		GameInput.ensure_joypad()
		var n1 := InputMap.action_get_events("interact").size()
		GameInput.ensure_joypad()
		_check(InputMap.action_get_events("interact").size() == n1, "重复调用 ensure_joypad 不应叠加绑定")

	# 受潮
	_check(GameRules.clothing_effective(true, 0.2, t), "干燥保暖层有效")
	_check(not GameRules.clothing_effective(true, t.damp_threshold, t), "湿透的保暖层无效")
	_check(GameRules.clothing_state(0.0, t) == "dry" and GameRules.clothing_state(t.damp_threshold * 0.7, t) == "damp" and GameRules.clothing_state(0.9, t) == "wet", "受潮三档")
	_check(GameRules.next_objective({"clothes_wet": true, "has_site": true}, t).contains("dry"), "湿透时目标行提示烘干")

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
	# S7：自己的庇护所下风侧挡风
	var os := Vector2.ZERO
	var ob := Vector2(1, 0)
	_check(GameRules.own_shelter_lee(os, Vector2(3, 0), ob, 4.5) == 1.0, "正下风侧：挡风")
	_check(GameRules.own_shelter_lee(os, Vector2(-3, 0), ob, 4.5) == 0.0, "迎风侧：不挡")
	_check(GameRules.own_shelter_lee(os, Vector2(0, 3), ob, 4.5) == 0.0, "正侧面：不挡")
	_check(GameRules.own_shelter_lee(os, Vector2(6, 0), ob, 4.5) == 0.0, "太远：不挡")
	# D16 / B4：背包上限 + 工地材料堆
	inv.wood = 0
	inv.max_wood = 4
	inv.max_bedding = 4
	inv.add("bedding", 9)
	_check(inv.bedding == 4, "垫层也受背包上限约束")
	inv.add("wood", 3)
	var pile := SitePile.new()
	var moved := pile.deposit(inv)
	_check(moved["wood"] == 3 and moved["bedding"] == 4 and inv.wood == 0 and inv.bedding == 0, "放下背包里的柴和枝条")
	inv.add("wood", 4)
	_check(pile.total("wood", inv) == 7, "堆 + 背包一共 7 根：可以超过背包上限，这就是跑几趟的意义")
	_check(not pile.spend({"wood": 8}, inv) and pile.amount("wood") == 3 and inv.wood == 4, "不够时什么都不扣")
	_check(pile.spend({"wood": 5}, inv) and pile.amount("wood") == 0 and inv.wood == 2, "先用堆里的，再用背包的")
	_check(pile.missing_text({"bedding": 6}, inv).begins_with("2"), "缺口按堆 + 背包算")
	inv.bark = 1
	pile.deposit(inv)
	_check(inv.bark == 1, "桦皮一直随身")
	inv.free()
	return {"passed": _passed, "failures": _failures}

func _check(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures.append(msg)
