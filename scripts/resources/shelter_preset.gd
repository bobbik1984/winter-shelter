class_name ShelterPreset
extends Resource

## 统一庇护所策略预设（支持 4 条求生路线，共用同一套 5 阶渐进建造与 0-100 体温/夜间模拟框架）：
##   1. "RaisedCave" — 高床雪洞（深雪 >=2.0m，对应参考图右上角 45° 剖面图）
##   2. "BasicCave"  — 基础雪洞（中深雪 >=1.5m，省时但无冷气沉降坑）
##   3. "SnowTrench" — 浅坑雪沟（浅雪 0.3~1.2m，挖浅坑+两侧砌雪墙+树枝封顶）
##   4. "LeanTo"     — 倒木/树根挡风斜棚 + 反射火（任意雪深，直接依托倒木树根挡风并靠通宵篝火取暖）

@export var preset_id: String = "RaisedCave"
@export var display_name: String = "Raised Snow Cave"
## 每阶材料（索引 0..4）[GAME] / [TUNE]。背包上限见 Tuning.max_wood / max_bedding（D16 §12.5）。
@export var stage_costs: Array = [{}, {}, {}, {}, {}]
## 每阶占总工时的比例（空 = 平均）。雪堆屋堆雪最费力，通风孔只要几分钟。
@export var stage_weights: Array = []
## 这一阶开工前要等多久（游戏分钟，空 = 不等）。雪堆屋：堆好的雪要凝结才能掏空。
@export var stage_wait_minutes: Array = []
@export var min_snow_depth: float = 2.0       ## [REAL]->[TUNE] 最低雪深门槛 (m)
@export var max_snow_depth: float = 10.0      ## 适用雪深上限 (m)
@export var requires_natural_windbreak: bool = false ## 是否可吸附于倒木树根 (Rootball) 旁
@export var allows_open_fire: bool = false    ## [REAL] 雪洞内严禁明火，仅 LeanTo 允许开口反射火
@export var build_minutes_total: float = 135.0 ## [TUNE] 完整 5 阶总工时 (游戏分钟)
@export var wood_cost: int = 1                ## 消耗木材数
@export var bedding_cost: int = 2             ## 消耗松针/干草垫层数

## 5 个渐进施工阶段的标题与即时收益说明（用于 HUD 与 45° 剖面标注）
@export var stage_titles: PackedStringArray = PackedStringArray([
	"1. Entrance Tunnel & Main Arch",
	"2. Cold-Air Pit (Traps cold air lower)",
	"3. Raised Sleeping Platform & Bedding",
	"4. Telescopic Vent / Chimney",
	"5. Cozy Interior Lantern (2700K)"
])

## 各阶段完成时提供的庇护所保温等级 (0=露天, 1=锁住体温不降, 2=靠自发热/反射火稳步回升)
@export var stage_shelter_levels: PackedInt32Array = PackedInt32Array([1, 1, 2, 2, 2])
## 各阶段完成时的环境风噪低通滤波衰减比例 (0.0=原声呼啸, 0.70=深沉安静)
@export var stage_wind_muffle: PackedFloat32Array = PackedFloat32Array([0.50, 0.58, 0.65, 0.68, 0.72])


static func create_all_presets() -> Dictionary:
	var raised := ShelterPreset.new()
	raised.preset_id = "RaisedCave"
	raised.display_name = "Snow Cave (Raised Platform)"
	raised.min_snow_depth = 2.0
	raised.allows_open_fire = false
	raised.build_minutes_total = 135.0
	raised.wood_cost = 1
	raised.bedding_cost = 2
	raised.stage_costs = [{}, {}, {"bedding": 3, "wood": 2}, {"wood": 1}, {"bedding": 1}]
	raised.stage_titles = PackedStringArray([
		"Stage 1: Entrance tunnel (Slopes slightly down)",
		"Stage 2: Cold-air pit (Traps cold air lower)",
		"Stage 3: Raised sleeping platform (Stay above cold air)",
		"Stage 4: Vent / Chimney (Reduce CO2, expel moisture)",
		"Stage 5: Interior candle lantern (Warm 2700K glow)"
	])

	var basic := ShelterPreset.new()
	basic.preset_id = "BasicCave"
	basic.display_name = "Basic Snow Cave"
	basic.min_snow_depth = 1.5
	basic.allows_open_fire = false
	basic.build_minutes_total = 95.0
	basic.wood_cost = 0
	basic.bedding_cost = 2
	basic.stage_costs = [{}, {}, {"bedding": 3}, {"wood": 1}, {"bedding": 1}]
	basic.stage_titles = PackedStringArray([
		"Stage 1: Dig horizontal entrance",
		"Stage 2: Hollow main sleeping chamber",
		"Stage 3: Lay pine & dry grass bedding",
		"Stage 4: Pierce roof ventilation hole",
		"Stage 5: Wind-block entrance & light lantern"
	])

	var trench := ShelterPreset.new()
	trench.preset_id = "SnowTrench"
	trench.display_name = "Shallow Snow Trench"
	trench.min_snow_depth = 0.3
	trench.allows_open_fire = false
	trench.build_minutes_total = 55.0
	trench.wood_cost = 2
	trench.bedding_cost = 1
	trench.stage_costs = [{}, {}, {"bedding": 2}, {"wood": 3}, {"bedding": 1}]
	trench.stage_titles = PackedStringArray([
		"Stage 1: Cut narrow body-length trench",
		"Stage 2: Stack snow-block side walls",
		"Stage 3: Lay ground insulation boughs",
		"Stage 4: Roof with deadwood & snow slabs",
		"Stage 5: Seal windward end & vent gap"
	])

	var leanto := ShelterPreset.new()
	leanto.preset_id = "LeanTo"
	leanto.display_name = "Rootball Lean-To + Reflector Fire"
	leanto.min_snow_depth = 0.0
	leanto.requires_natural_windbreak = true
	leanto.allows_open_fire = true
	leanto.build_minutes_total = 50.0
	leanto.wood_cost = 4
	leanto.bedding_cost = 2
	leanto.stage_costs = [{"wood": 2}, {"bedding": 2}, {"bedding": 2}, {"wood": 3}, {"wood": 2, "bark": 1}]
	leanto.stage_titles = PackedStringArray([
		"Stage 1: Anchor ridgepole against fallen rootball",
		"Stage 2: Thatch windward roof with spruce boughs",
		"Stage 3: Pile thick dry grass & bough bed",
		"Stage 4: Stack log heat-reflector wall in front",
		"Stage 5: Light long-burning reflector campfire"
	])

	# S5 树井：老云杉树干周围的浅坑 + 枝条屋顶。条件 = 老云杉 + 周围积雪 ≥ tree_well_min_snow_m；不需要雪铲；枝条当屋顶和垫层。
	var treewell := ShelterPreset.new()
	treewell.preset_id = "TreeWell"
	treewell.display_name = "Tree Well Shelter"
	treewell.min_snow_depth = 1.0   ## 被 validate_site 用 Tuning.tree_well_min_snow_m 覆盖（周围积雪）
	treewell.allows_open_fire = false
	treewell.build_minutes_total = 40.0   ## [TUNE] 坑大多是现成的：掏出浮雪、修枝、铺枝、补顶
	treewell.wood_cost = 0
	treewell.bedding_cost = 4
	treewell.stage_costs = [{}, {}, {"bedding": 3}, {"bedding": 2}, {"bedding": 1}]
	treewell.stage_titles = PackedStringArray([
		"1. Scoop out the well around the trunk",
		"2. Trim low inner branches (headroom)",
		"3. Spruce-bough floor",
		"4. Thatch the gaps in the bough roof",
		"5. Close the entrance with boughs",
	])
	treewell.stage_shelter_levels = PackedInt32Array([1, 1, 2, 2, 2])
	treewell.stage_wind_muffle = PackedFloat32Array([0.45, 0.5, 0.55, 0.62, 0.66])

	# S5 雪堆屋：不挑地方，堆雪 → 凝结（这段时间可以去采集）→ 掏空。最费时的庇护所。
	var quinzhee := ShelterPreset.new()
	quinzhee.preset_id = "Quinzhee"
	quinzhee.display_name = "Quinzhee"
	quinzhee.min_snow_depth = 0.3   ## 被 validate_site 用 Tuning.quinzhee_min_snow_m 覆盖
	quinzhee.allows_open_fire = false
	quinzhee.build_minutes_total = 80.0   ## [TUNE] 不含凝结等待（[GAME] 压缩，现实要数小时）；保持顺序：树井 < 雪沟 < 倒棚 ≈ 小雪洞 < 高床雪洞 < 雪堆屋（含等待）
	quinzhee.wood_cost = 3
	quinzhee.bedding_cost = 4
	quinzhee.stage_costs = [{}, {"wood": 2}, {}, {"wood": 1}, {"bedding": 4}]
	quinzhee.stage_weights = [0.45, 0.1, 0.35, 0.05, 0.05]
	quinzhee.stage_wait_minutes = [0.0, 0.0, 60.0, 0.0, 0.0]   ## 被 Tuning.quinzhee_set_minutes 覆盖
	quinzhee.stage_titles = PackedStringArray([
		"1. Heap a snow mound about 1.4 m high",
		"2. Push in sticks as depth gauges, then let it set",
		"3. Hollow it out from the low side, down to the sticks",
		"4. Poke a vent through the roof",
		"5. Bough floor and a snow-block door",
	])
	quinzhee.stage_shelter_levels = PackedInt32Array([0, 0, 1, 2, 2])
	quinzhee.stage_wind_muffle = PackedFloat32Array([0.0, 0.1, 0.6, 0.7, 0.8])

	# S5 岩檐：岩体 / 悬崖脚的背风处。省力、干燥，但冷岩吸热，靠厚垫层和火。
	var rock := ShelterPreset.new()
	rock.preset_id = "RockOverhang"
	rock.display_name = "Rock Overhang"
	rock.min_snow_depth = 0.0
	rock.allows_open_fire = true
	rock.build_minutes_total = 30.0   ## [TUNE] 岩体就是墙：清雪、搭枝条、铺床
	rock.wood_cost = 3
	rock.bedding_cost = 5
	rock.stage_costs = [{}, {"wood": 2}, {"bedding": 3}, {"bedding": 2}, {"wood": 1}]
	rock.stage_titles = PackedStringArray([
		"1. Clear the snow from under the rock",
		"2. Lean poles against the rock face",
		"3. Thick bough bed: cold rock drinks your heat",
		"4. Thatch the poles with boughs",
		"5. Block the open end with a log",
	])
	rock.stage_shelter_levels = PackedInt32Array([0, 1, 1, 2, 2])
	rock.stage_wind_muffle = PackedFloat32Array([0.3, 0.4, 0.4, 0.6, 0.65])

	# S5 倒木斜棚：倒木当脊梁，枝条搭顶。没有根盘那样的风墙和反射面。
	var fallen := ShelterPreset.new()
	fallen.preset_id = "FallenLog"
	fallen.display_name = "Fallen-Log Lean-To"
	fallen.min_snow_depth = 0.0
	fallen.allows_open_fire = true
	fallen.build_minutes_total = 40.0   ## [TUNE] 现成脊梁，比树根倒棚（55 min）快
	fallen.wood_cost = 3
	fallen.bedding_cost = 5
	fallen.stage_costs = [{"wood": 1}, {"wood": 2}, {"bedding": 3}, {"bedding": 2}, {}]
	fallen.stage_titles = PackedStringArray([
		"1. Check the trunk is stable and clear under it",
		"2. Lean ribs along the trunk",
		"3. Thatch the ribs with boughs",
		"4. Bough bed off the snow",
		"5. Pile snow against the windward side",
	])
	fallen.stage_shelter_levels = PackedInt32Array([0, 1, 1, 2, 2])
	fallen.stage_wind_muffle = PackedFloat32Array([0.1, 0.3, 0.5, 0.5, 0.65])

	return {
		"Quinzhee": quinzhee,
		"RockOverhang": rock,
		"FallenLog": fallen,
		"RaisedCave": raised,
		"TreeWell": treewell,
		"BasicCave": basic,
		"SnowTrench": trench,
		"LeanTo": leanto,
	}


func validate_site(snow_depth: float, slope_deg: float, near_windbreak: bool = false) -> Dictionary:
	if preset_id == "TreeWell":
		# 树井的"深度"是周围的开阔积雪（BuildMode 已对准最近的老云杉并取树干周围雪深）
		var need := OldSpruces.tuning().tree_well_min_snow_m
		if snow_depth < need:
			return {"ok": false, "reason": Loc.t("Snow around this spruce is too shallow for a tree well (%.2f m < %.2f m)") % [snow_depth, need]}
		if slope_deg > 30.0:
			return {"ok": false, "reason": Loc.t("Too steep around this trunk for a tree well")}
		return {"ok": true, "reason": Loc.t("Site suitable for %s") % Loc.t(display_name)}
	if preset_id == "Quinzhee":
		var tq := OldSpruces.tuning()
		if snow_depth < tq.quinzhee_min_snow_m:
			return {"ok": false, "reason": Loc.t("Not enough snow on the ground to heap a quinzhee (%.2f m < %.2f m)") % [snow_depth, tq.quinzhee_min_snow_m]}
		if slope_deg > tq.quinzhee_max_slope_deg:
			return {"ok": false, "reason": Loc.t("Too steep to heap a quinzhee (%d° > %d°): find flat ground") % [int(slope_deg), int(tq.quinzhee_max_slope_deg)]}
		return {"ok": true, "reason": Loc.t("Site suitable for %s") % Loc.t(display_name)}
	if snow_depth < min_snow_depth:
		return {
			"ok": false,
			"reason": Loc.t("Snow too shallow (%.2f m < %.2f m required for %s)") % [
				snow_depth, min_snow_depth, Loc.t(display_name)
			]
		}
	if (preset_id == "RaisedCave" or preset_id == "BasicCave") and slope_deg < 8.0:
		return {
			"ok": false,
			"reason": Loc.t("Slope too flat (%.1f° < 8.0° needed to excavate cave horizontally)") % slope_deg
		}
	if requires_natural_windbreak and not near_windbreak and slope_deg > 28.0:
		return {
			"ok": false,
			"reason": Loc.t("Too steep for Lean-To; build near fallen rootball or flatter lee ground")
		}
	return {"ok": true, "reason": Loc.t("Site suitable for %s") % Loc.t(display_name)}
