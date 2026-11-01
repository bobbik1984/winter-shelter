class_name LevelDef
extends Resource

## D12 关卡阶梯：一关 = 一个固定课题（环境条件）+ 关内随机范围。
## 关卡只改环境输入，不改庇护所规则、D5 门槛与评分（CORE_GAMEPLAY §8）。
## 结构身份 [GAME]；各关数值 [TUNE]（L6 机器人平衡后定稿）。
## 实例：resources/levels/level_free.tres、level_01.tres … level_05.tres。

## [GAME] 关卡序号：1..5；0 = 自由模式。
@export var index: int = 0
## [GAME] 简报页课题（英文源串，显示处再包 Loc.t；L5 补中文）。
@export_multiline var lesson: String = ""
## [GAME] 章节主题键（D13 §9.5）：deep_drift / hidden_pockets / blowdown / open_flat / storm_mix / free。报告"本关要点"按它选文案。
@export var theme: String = "free"

@export_group("Clock")
## [GAME] 开局时刻（分钟）。14:20 = 860；10:00 = 600（整个白天）。
@export var start_minutes: int = 860

@export_group("Weather")
## [GAME] 本关天气池权重（晴 / 阴 / 暴风雪将至）；全为 0 视为只有晴。
@export var weather_weight_clear: float = 1.0
@export var weather_weight_overcast: float = 0.0
@export var weather_weight_storm: float = 0.0
## [TUNE] 在 Tuning.wind_speed_kmh 基础上的风速偏移（km/h）。暴风雪的额外风速另由 Tuning 加。
@export var wind_speed_offset_kmh: float = 0.0

@export_group("Snow")
## [TUNE] 雪深倍率候选：每局抽一个（第 5 关三选一；其余关只有一个值）。
@export var snow_depth_scale_choices: PackedFloat32Array = PackedFloat32Array([1.0])
## [TUNE] 雪深斑驳度 0..1（0 = 不变）：风蚀——少数保留斑块以外的雪按 (1 − 斑驳度) 削薄，背风深雪带断成几块。
@export_range(0.0, 1.0) var snow_patchiness: float = 0.0

@export_group("Resources")
## [TUNE] 立枯木密度倍率（1 = 不变）。
@export var snag_density_scale: float = 1.0

@export_group("Difficulty (stage 10)")
## D13 §9.6：同一章内第 1 阶 = 上面各字段的值，第 10 阶 = 下面的值，中间线性插值。[TUNE]
@export var start_minutes_hard: int = 860
@export var wind_speed_offset_kmh_hard: float = 0.0
@export var snag_density_scale_hard: float = 1.0
@export var snow_patchiness_hard: float = 0.0
## [TUNE] 夜间气温偏移（°C，负 = 更冷），第 1 / 10 阶。
@export var night_temp_offset_c: float = 0.0
@export var night_temp_offset_c_hard: float = 0.0
## [TUNE] 第 10 阶额外加到阴天权重上的值（光线更差、影子更淡）。
@export var overcast_bonus_hard: float = 0.0

@export_group("Terrain (D13)")
## [GAME] 地形形态候选（TerrainRecipe.SHAPES）。
@export var shape_choices: PackedStringArray = PackedStringArray(["ridge_valley"])
## [TUNE] 起伏度 / 树木密度（第 1 / 10 阶）。树木密度可 > 1（更密的老林）。
@export var roughness: float = 1.0
@export var roughness_hard: float = 1.0
@export var tree_density: float = 1.0
@export var tree_density_hard: float = 1.0
## [TUNE] 形态参数抖动：每张图的脊 / 岸 / 崖位置与高度在预设值附近随机（0 = 用预设值，旧地图）。
@export var feature_jitter: float = 0.0
## [GAME] 额外的树根盘（风倒区，第 1 / 10 阶）。
@export var rootball_bonus: int = 0
@export var rootball_bonus_hard: int = 0

@export_group("Randomness")
## [GAME] 山谷候选（TerrainHeight 噪声种子）；为空 = 全部 TerrainHeight.VALLEY_SEEDS。
@export var valley_seeds: PackedInt32Array = PackedInt32Array()
## [GAME] 风向 = 整图布局旋转角候选（度，L3 实现）。
@export var wind_rotation_choices_deg: PackedFloat32Array = PackedFloat32Array([0.0, 90.0, 180.0, 270.0])
## [GAME] 在所选旋转角上再加的随机抖动（± 度）。L3 退路：旋转候选只留 0、抖动 30。
@export var wind_jitter_deg: float = 0.0

@export_group("Gear")
## [GAME] 本关装备（D13 §9.5：装备是关卡的固定条件，越往后越少，不是奖励）。
@export var has_shovel: bool = true
@export var has_extra_layer: bool = true
@export var has_sleeping_pad: bool = false
## [GAME] 开局背包里已有的材料。
@export var start_wood: int = 0
@export var start_bark: int = 0
@export var start_bedding: int = 0

@export_group("Shelters")
## [GAME] 本关引入（可用）的庇护所，即使还没学会（D13 §9.2）。学会 = 用它熬过一夜。
@export var introduced_presets: PackedStringArray = PackedStringArray()

@export_group("Intent")
## [GAME] 本关目标路线（ShelterPreset.preset_id）。只给机器人平衡与报告文案用，不限制玩家。
@export var target_presets: PackedStringArray = PackedStringArray()

func is_free() -> bool:
	return index == 0
