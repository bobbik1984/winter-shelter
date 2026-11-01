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
## [TUNE] 雪深对比度（围绕均值放大起伏；1 = 不变）。> 1 时深雪更集中在少数背风处。
@export var snow_contrast: float = 1.0

@export_group("Resources")
## [TUNE] 立枯木密度倍率（1 = 不变）。
@export var snag_density_scale: float = 1.0

@export_group("Randomness")
## [GAME] 山谷候选（TerrainHeight 噪声种子）；为空 = 全部 TerrainHeight.VALLEY_SEEDS。
@export var valley_seeds: PackedInt32Array = PackedInt32Array()
## [GAME] 风向 = 整图布局旋转角候选（度，L3 实现）。
@export var wind_rotation_choices_deg: PackedFloat32Array = PackedFloat32Array([0.0, 90.0, 180.0, 270.0])
## [GAME] 在所选旋转角上再加的随机抖动（± 度）。L3 退路：旋转候选只留 0、抖动 30。
@export var wind_jitter_deg: float = 0.0

@export_group("Intent")
## [GAME] 本关目标路线（ShelterPreset.preset_id）。只给机器人平衡与报告文案用，不限制玩家。
@export var target_presets: PackedStringArray = PackedStringArray()

func is_free() -> bool:
	return index == 0
