class_name NightSimulator
extends RefCounted

## 6 维可解释雪洞评估模型 (MVP 01)
## 遵循 Hard != Obscure 原则：向玩家提供透明的 6 项评分与自然语言归因复盘。

static func evaluate_shelter(
	shelter_type: String,             # "RaisedCave", "BasicCave", "SnowTrench", "None"
	wind_angle_diff: float,           # 入口朝向与迎风方向夹角 (0度=正对迎风面, 180度=完全背风)
	has_cold_pit: bool,               # 是否挖出沉降冷气槽
	has_vent: bool,                   # 是否插设可伸缩通风管 (Telescopic Vent)
	vent_snow_clogged: bool,          # 夜间降雪是否部分遮蔽通气管
	bedding_quality: float,           # 地面垫层质量 (0.0=无垫层贴雪, 1.0=厚松针干草层)
	roof_thickness_meters: float,     # 顶部雪层厚度 (m)
	completion_ratio: float           # 施工完成度 (0.0 - 1.0)
) -> Dictionary:
	
	var report_notes: Array[String] = []
	
	# 1. Thermal Protection (保暖指数 0-100)
	var thermal_score: float = 0.0
	if shelter_type == "RaisedCave":
		thermal_score = 85.0 if has_cold_pit else 70.0
		if has_cold_pit:
			report_notes.append("高床与冷空气槽有效隔离了底层沉积冷空气，显著改善了睡眠区热环境。")
		else:
			report_notes.append("卧榻高度与底面齐平，缺少冷气槽沉淀重冷空气。")
	elif shelter_type == "BasicCave":
		thermal_score = 60.0
		report_notes.append("基础雪洞提供基本隔温，但热空气容易随平底隧道向外流失。")
	elif shelter_type == "SnowTrench":
		thermal_score = 42.0
		report_notes.append("雪沟空间狭窄且覆顶薄弱，热量散失较快。")
	else:
		thermal_score = 10.0
		report_notes.append("未构筑有效庇护所，露天暴露在极寒气温中。")

	# 2. Wind Protection (防风指数 0-100)
	# wind_angle_diff: 0度迎风, 180度背风
	var wind_score: float = clamp(remap(wind_angle_diff, 0.0, 180.0, 20.0, 95.0), 10.0, 100.0)
	if wind_angle_diff < 45.0:
		report_notes.append("西风强劲，入口直接朝向迎风面，造成严重的穿堂风与积雪倒灌。")
	elif wind_angle_diff < 90.0:
		report_notes.append("入口处于侧风区，偶有强阵风切入入口，造成部分风冷渗透。")
	else:
		report_notes.append("入口处于背风安全面，有效避开了夜间 32–45 km/h 的凛冽西风。")

	# 3. Ground Insulation (地面隔热 0-100)
	var insulation_score: float = clamp(remap(bedding_quality, 0.0, 1.0, 15.0, 95.0), 0.0, 100.0)
	if bedding_quality >= 0.8:
		report_notes.append("铺设了厚实的干松针与干燥树皮垫层，有效切断了冰雪的直接传导散热。")
	elif bedding_quality >= 0.3:
		report_notes.append("垫层厚度单薄，后半夜背部结霜，体感寒冷刺骨。")
	else:
		report_notes.append("严重失误：人体直接接触雪面过夜，雪地迅速抽干核心体温！")

	# 4. Ventilation (通风指数 0-100)
	var vent_score: float = 95.0
	if not has_vent:
		vent_score = 10.0
		report_notes.append("致命隐患：未插设可伸缩通风管！密闭雪洞内二氧化碳急剧上升，引发窒息危险。")
	elif vent_snow_clogged:
		vent_score = 55.0
		report_notes.append("通风孔在后半夜被新增降雪部分掩埋，空气流通受阻，出现轻微缺氧头痛。")
	else:
		report_notes.append("可伸缩通风管高度合适且保持通畅，成功排出湿气并保持洞内新鲜氧气。")

	# 5. Structural Safety (结构安全 0-100)
	# [REAL] 野外指南常见顶厚下限约 0.3 m，保守建议 0.6 m（research/SNOW_SHELTER_RESEARCH.md §2）
	# [TUNE] 阈值暂定为常量，T0.5 迁入 tuning.tres
	const ROOF_DANGER_M := 0.3
	const ROOF_GOOD_M := 0.45
	var struct_score: float = 85.0
	if roof_thickness_meters < ROOF_DANGER_M:
		struct_score = 30.0
		report_notes.append("顶部雪层不足 %.2fm，承重和隔热都不够，存在塌陷风险。" % ROOF_DANGER_M)
	elif roof_thickness_meters < ROOF_GOOD_M:
		struct_score = 65.0
		report_notes.append("顶部雪层约 %.2fm，勉强合格，后半夜体温会让顶棚变薄。" % roof_thickness_meters)
	else:
		struct_score = 92.0
		report_notes.append("穹顶匀称，顶部雪层约 %.2fm，结构稳固。" % roof_thickness_meters)

	# 6. Completion (完工度 0-100)
	var completion_score: float = clamp(completion_ratio * 100.0, 0.0, 100.0)
	if completion_ratio < 0.7:
		report_notes.append("赶工仓促，入口挡雪墙与修整工作未彻底完成即进入黑夜。")

	# 综合判定 Outcome: SAFE / COLD / DANGEROUS
	var outcome: String = "SAFE"
	var outcome_title: String = "SURVIVED COZY"
	
	if vent_score < 30.0:
		outcome = "DANGEROUS"
		outcome_title = "SUFFOCATED (窒息)"
	elif insulation_score < 30.0 or (wind_score < 35.0 and thermal_score < 45.0):
		outcome = "DANGEROUS"
		outcome_title = "PERISHED IN FROST (严重失温致死)"
	elif thermal_score < 55.0 or wind_score < 50.0 or insulation_score < 50.0 or vent_score < 60.0:
		outcome = "COLD"
		outcome_title = "SURVIVED HYPOTHERMIC (轻度失温熬过)"
	else:
		outcome = "SAFE"
		outcome_title = "SURVIVED COZY (舒适安全过夜)"

	return {
		"outcome": outcome,
		"outcome_title": outcome_title,
		"scores": {
			"thermal_protection": int(thermal_score),
			"ventilation": int(vent_score),
			"wind_protection": int(wind_score),
			"ground_insulation": int(insulation_score),
			"structural_safety": int(struct_score),
			"completion": int(completion_score)
		},
		"notes": report_notes
	}
