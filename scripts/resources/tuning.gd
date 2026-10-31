class_name Tuning
extends Resource

## T0.5 唯一调参源：环境、玩家动作、庇护所、夜间结算的全部数值集中在这里。
## 每个字段注释都带 [REAL] / [GAME] / [TUNE] 身份标签：
##   [REAL] 有现实依据（出处见 research/SNOW_SHELTER_RESEARCH.md）
##   [GAME] 为可玩性做的规则抽象
##   [TUNE] 临时平衡值，随试玩调整
## 单位约定：绝对时刻用分钟，时长用小时，风速统一 km/h，长度统一 m。

# -----------------------------------------------------------------------------
# 时间
# -----------------------------------------------------------------------------

@export_group("Clock")
## [GAME] 开局时刻，14:20 = 860 分钟。
@export var start_minutes: int = 860
## [GAME] 日落/黄昏起点，16:18 = 978 分钟（CORE_GAMEPLAY §2）。
@export var dusk_minutes: int = 978
## [GAME] 入夜时刻，17:10 = 1030 分钟；也是倒棚备柴计时的零点。
@export var night_minutes: int = 1030
## [TUNE] 入夜到天亮的名义时长，用于判断备柴能否烧到天亮。
@export var night_duration_hours: float = 13.8
## [TUNE] 一个游戏小时对应的现实秒数。
@export var real_seconds_per_game_hour: float = 300.0

# -----------------------------------------------------------------------------
# 天气
# -----------------------------------------------------------------------------

@export_group("Weather")
## [REAL] 默认风速 32 km/h（Web 原型 9 m/s ≈ 32.4 km/h，取整与 HUD/default_wind 一致）。
@export var wind_speed_kmh: float = 32.0
## [TUNE] 主风向角度（度）。0 = 西风（自西向东吹），角度顺时针增加。
@export var wind_angle_deg: float = 0.0
## [TUNE] 阵风振幅 12.6 km/h（Web 原型 3.5 m/s × 3.6）。
@export var gust_amplitude_kmh: float = 12.6
## [TUNE] 降雪粒子密度（相对强度，不换算物理降雪率）。
@export var snowfall_density: float = 240.0
## [TUNE] 风速达到此值时节风影响封顶，72 km/h（Web 原型 20 m/s）。
@export var wind_full_effect_kmh: float = 72.0
## [GAME] 入口夹角小于此值判定为“正迎风”（CORE_GAMEPLAY §2 的 45°）。
@export var windward_entrance_angle_deg: float = 45.0
## [GAME] 入口夹角大于此值判定为“背风”（CORE_GAMEPLAY §2 的 90°）。
@export var lee_entrance_angle_deg: float = 90.0

# -----------------------------------------------------------------------------
# 温度与风寒
# -----------------------------------------------------------------------------

@export_group("Temperature")
## [TUNE] 开局气温 -8 °C（Web 原型 tempAtStart）。
@export var temp_at_start_c: float = -8.0
## [TUNE] 夜间最低气温 -24 °C（Web 原型 tempAtNight）。
@export var temp_at_night_c: float = -24.0
## [GAME] 每 km/h 风速带来的风寒降温，0.25 °C/(km/h)（Web 原型 0.9 °C/(m/s) 换算）。
@export var wind_chill_per_kmh: float = 0.25

# -----------------------------------------------------------------------------
# 玩家动作
# -----------------------------------------------------------------------------

@export_group("Player Actions")
## [TUNE] 基础移动速度，3.6 m/s。
@export var move_speed_mps: float = 3.6
## [TUNE] 上坡速度衰减系数（越大越慢）。
@export var slope_slowdown: float = 1.5
## [TUNE] 探针按住时长 0.85 s（T1.6 / 冒烟测试口径）。
@export var probe_seconds: float = 0.85
## [TUNE] 单次采集动作时长 1.35 s。
@export var gather_seconds: float = 1.35
## [TUNE] 每秒建造工作量 8.2。
@export var build_work_per_second: float = 8.2
## [TUNE] 黄昏效率下限 0.45（非硬切换）。
@export var dusk_efficiency_floor: float = 0.45
## [TUNE] 每点寒冷锁定带来的效率惩罚 0.012。
@export var cold_efficiency_penalty: float = 0.012
## [TUNE] 最大可建造坡度 22°。
@export var max_build_slope_deg: float = 22.0

# -----------------------------------------------------------------------------
# 相机
# -----------------------------------------------------------------------------

@export_group("Camera")
## [TUNE] Camera3D 在 rig 内沿本地 +Z 的后移距离，40 m（AGENTS §4.1 / T0.2）。
@export var camera_distance_m: float = 40.0
## [GAME] 正交相机俯仰，35.264° 为真等距。
@export var camera_pitch_deg: float = 35.264
## [GAME] 正交相机绕 Y 轴偏航 45°（AGENTS §4.1）。
@export var camera_yaw_deg: float = 45.0
## [TUNE] 默认正交 size 18.0（VISUAL_LANGUAGE 相机章节）。
@export var camera_size_default: float = 18.0
## [TUNE] 最小缩放 0.3（Web 原型 minZoom）。
@export var zoom_min: float = 0.3
## [TUNE] 最大缩放 1.25（Web 原型 maxZoom）。
@export var zoom_max: float = 1.25

# -----------------------------------------------------------------------------
# 资源
# -----------------------------------------------------------------------------

@export_group("Resources")
## [TUNE] 地图可采集立枯木数量 7。
@export var wood_count: int = 7
## [TUNE] 地图可采集桦树皮/引火物点位 7。
@export var tinder_count: int = 7

# -----------------------------------------------------------------------------
# 火
# -----------------------------------------------------------------------------

@export_group("Fire")
## [TUNE] 生一次火消耗木材 2。
@export var fire_wood_cost: int = 2
## [TUNE] 生一次火消耗引火物 1。
@export var fire_tinder_cost: int = 1
## [TUNE] 火对保暖的最大归一化加成 0.28（Web 原型 fireThermalBonus）。
@export var fire_thermal_bonus: float = 0.28
## [TUNE] 露天火被吹灭的迎风暴露阈值 0.35（Web 原型 fireBlowoutDot）。
@export var fire_blowout_dot: float = 0.35
## [TUNE] 火被吹灭时仍保留的余热系数 0.12（Web 原型 nightSim）。
@export var fire_blowout_fuel_factor: float = 0.12
## [TUNE] 每根通宵备柴可燃烧的小时数（倒棚整夜燃料换算）。
@export var fire_fuel_hours_per_log: float = 2.0
## [TUNE] 倒棚砌反射墙带来的归一化保暖加成 0.14。
@export var fire_reflector_wall_bonus: float = 0.14
## [GAME] 睡前篝火（pre-warm）只修正入夜状态，给雪庇护所的归一化保暖加成 0.08。
@export var prewarm_heat_bonus: float = 0.08
## [TUNE] 倒棚没有火时的基础保暖分 0.32。
@export var heat_lean_to_base: float = 0.32

# -----------------------------------------------------------------------------
# 六维权重
# -----------------------------------------------------------------------------

@export_group("Six-Axis Weights")
## [TUNE] Site（选址/入口风向/地形避风）权重，来自 Web wWind 1.15。
@export var weight_site: float = 1.15
## [TUNE] Structure（雪深余量/顶厚/完工度/骨架）权重；合并 Web wStructure 1.0 与 wCompletion 1.3。
@export var weight_structure: float = 1.15
## [TUNE] Insulation（地面垫层）权重，来自 Web wInsulation 1.1。
@export var weight_insulation: float = 1.1
## [TUNE] Isolation（冷气池/高床/地面冷空气隔离）权重；T0.6 新增维度。
@export var weight_isolation: float = 1.0
## [TUNE] Air（通风管数量与堵塞）权重，来自 Web wVentilation 1.0。
@export var weight_air: float = 1.0
## [TUNE] Heat（保暖形制与火/备柴）权重，来自 Web wThermal 1.25。
@export var weight_heat: float = 1.25

# -----------------------------------------------------------------------------
# 生存阈值（CORE_GAMEPLAY §6）
# -----------------------------------------------------------------------------

@export_group("Survival Thresholds")
## [GAME] SAFE 要求每一维都 ≥ 65。
@export var safe_min_axis: float = 65.0
## [GAME] SAFE 要求加权平均 ≥ 75。
@export var safe_min_weighted_average: float = 75.0
## [GAME] 任何一维低于 40 即判 DANGEROUS（非致命维度只剩 40–65 的 COLD 区间）。
@export var cold_min_axis: float = 40.0
## [GAME] 通风低于 30 → 窒息。
@export var air_suffocation_threshold: float = 30.0
## [GAME] 地面隔热低于 30 → 严重失温。
@export var insulation_hypothermia_threshold: float = 30.0
## [GAME] 防风低于 35 → 严重失温。
@export var site_hypothermia_threshold: float = 35.0
## [GAME] 保暖低于 30 → 严重失温。
@export var heat_hypothermia_threshold: float = 30.0

# -----------------------------------------------------------------------------
# 雪深门槛（D5，[REAL] 量级来自 research §1，落地数值 [TUNE]）
# -----------------------------------------------------------------------------

@export_group("Snow Depth Gates (D5)")
## [REAL] 低于 0.3 m 不能做雪庇护所，只能做倒棚等非雪庇护所。
@export var snow_depth_non_snow_max_m: float = 0.3
## [REAL] 浅雪砌墙雪沟的下限 0.3 m。
@export var snow_depth_trench_wall_min_m: float = 0.3
## [REAL] 需要砌墙的浅雪区间上限 0.9 m。
@export var snow_depth_trench_wall_max_m: float = 0.9
## [REAL] 标准雪沟约 1.0 m。
@export var snow_depth_trench_standard_m: float = 1.0
## [REAL] 雪洞下限 1.5 m。
@export var snow_depth_cave_min_m: float = 1.5
## [REAL] 高床雪洞下限 2.0 m。
@export var snow_depth_raised_cave_min_m: float = 2.0

# -----------------------------------------------------------------------------
# 顶厚门槛（[REAL] research §2：下限约 0.3 m，0.45 m 以上良好）
# -----------------------------------------------------------------------------

@export_group("Roof Thickness")
## [REAL] 顶厚危险下限 0.3 m。
@export var roof_thickness_min_m: float = 0.3
## [REAL] 顶厚良好门槛 0.45 m。
@export var roof_thickness_good_m: float = 0.45
## [TUNE] 顶厚刚好到下限时的顶厚质量分，0.55。
@export var roof_quality_at_min: float = 0.55
## [TUNE] 顶厚低于下限时顶厚质量分的上限，0.3。
@export var roof_quality_below_min_max: float = 0.3

# -----------------------------------------------------------------------------
# Site 评分系数
# -----------------------------------------------------------------------------

@export_group("Scoring: Site")
## [TUNE] 地形避风度（-1..1）带来的 Site 加成 0.18。
@export var terrain_shelter_bonus: float = 0.18
## [TUNE] 入口完全迎风时的 Site 基础惩罚 0.55。
@export var site_wind_base_penalty: float = 0.55
## [TUNE] 阵风对迎风惩罚的放大系数 0.45。
@export var site_wind_gust_penalty: float = 0.45

# -----------------------------------------------------------------------------
# Structure 评分系数
# -----------------------------------------------------------------------------

@export_group("Scoring: Structure")
## [TUNE] 雪深余量在 Structure 中的权重 0.5。
@export var structure_depth_weight: float = 0.5
## [TUNE] 顶厚质量在 Structure 中的权重 0.3。
@export var structure_roof_weight: float = 0.3
## [TUNE] 完工度在 Structure 中的权重 0.2（Web 的完工度维度并入 Structure）。
@export var structure_completion_weight: float = 0.2
## [TUNE] 支撑木对 Structure 的加成上限 0.1。
@export var structure_wood_bonus: float = 0.1
## [TUNE] 坡度超限造成的 Structure 惩罚上限 0.35。
@export var structure_slope_penalty: float = 0.35
## [TUNE] 雪深余量归一化区间 0.6 m（Web 原型同值）。
@export var structure_depth_margin_range_m: float = 0.6
## [TUNE] 雪深低于该预设门槛时 Structure 的上限 0.12。
@export var structure_invalid_depth_cap: float = 0.12
## [TUNE] 浅雪雪沟未砌墙时 Structure 的上限 0.25。
@export var structure_missing_wall_cap: float = 0.25
## [TUNE] 倒棚完工度在骨架评分中的权重 0.65。
@export var lean_to_completion_weight: float = 0.65
## [TUNE] 倒棚支撑木在骨架评分中的权重 0.35。
@export var lean_to_brace_weight: float = 0.35

# -----------------------------------------------------------------------------
# Insulation 评分
# -----------------------------------------------------------------------------

@export_group("Scoring: Insulation")
## [TUNE] 完全无垫层时的地面隔热分 0.15。
@export var insulation_bare_score: float = 0.15
## [TUNE] 厚实垫层（quality=1）时的地面隔热分 0.95。
@export var insulation_full_score: float = 0.95
## [TUNE] 低于此垫层质量视为“直接贴雪”，0.1。
@export var bedding_bare_threshold: float = 0.1
## [TUNE] 高于此垫层质量视为“厚实垫层”，0.8。
@export var bedding_good_threshold: float = 0.8

# -----------------------------------------------------------------------------
# Isolation 评分
# -----------------------------------------------------------------------------

@export_group("Scoring: Isolation")
## [TUNE] 高床雪洞的冷空气隔离基础分 0.55。
@export var isolation_raised_cave_base: float = 0.55
## [TUNE] 基础雪洞的冷空气隔离基础分 0.38。
@export var isolation_basic_cave_base: float = 0.38
## [TUNE] 雪沟的冷空气隔离基础分 0.38（平底，无冷热分层）。
@export var isolation_snow_trench_base: float = 0.38
## [TUNE] 倒棚的隔离基础分 0.45（开放结构，无冷气池）。
@export var isolation_lean_to_base: float = 0.45
## [TUNE] 无庇护所的隔离基础分 0.0。
@export var isolation_none_base: float = 0.0
## [TUNE] 挖出冷气坑的隔离加成 0.2。
@export var isolation_cold_pit_bonus: float = 0.2
## [TUNE] 高床/床架抬离地面的隔离加成 0.12。
@export var isolation_raised_bed_bonus: float = 0.12

# -----------------------------------------------------------------------------
# Air 评分
# -----------------------------------------------------------------------------

@export_group("Scoring: Air")
## [TUNE] 开放结构（倒棚/None）的通风分 0.88。
@export var air_open_score: float = 0.88
## [TUNE] 无通风管的分 0.06（窒息短板）。
@export var air_no_vent_score: float = 0.06
## [TUNE] 单根通风管的分 0.92。
@export var air_one_vent_score: float = 0.92
## [TUNE] 两根通风管的基础分 0.78。
@export var air_two_vent_score: float = 0.78
## [TUNE] 两根通风管且入口迎风时的额外惩罚 0.15。
@export var air_two_vent_windward_penalty: float = 0.15
## [TUNE] 每多一根通风管的分数递减 0.16。
@export var air_over_vent_step: float = 0.16
## [TUNE] 过度通风的分数下限 0.25。
@export var air_over_vent_floor: float = 0.25
## [TUNE] 通风管被雪堵塞时的分数上限 0.55。
@export var air_clogged_cap: float = 0.55

# -----------------------------------------------------------------------------
# Heat 评分
# -----------------------------------------------------------------------------

@export_group("Scoring: Heat")
## [TUNE] 壁厚计算时使用的最小参考雪深 0.35 m（Web 原型同值）。
@export var heat_wall_min_reference_m: float = 0.35
## [TUNE] 壁厚系数上限 1.35（Web 原型同值）。
@export var heat_wall_thickness_max: float = 1.35
## [TUNE] 壁厚系数的常数项 0.55。
@export var heat_wall_factor_base: float = 0.55
## [TUNE] 壁厚系数的斜率项 0.45。
@export var heat_wall_factor_scale: float = 0.45
## [TUNE] 不产生体积惩罚的庇护所容积 1.2 m³。
@export var heat_volume_free_m3: float = 1.2
## [TUNE] 体积惩罚归一化跨度 4.0 m³。
@export var heat_volume_span_m3: float = 4.0
## [TUNE] 体积惩罚上限 0.18。
@export var heat_volume_penalty: float = 0.18
## [TUNE] 风对保暖折减的常数项 0.55。
@export var heat_wind_factor_base: float = 0.55
## [TUNE] 风对保暖折减的斜率项 0.45。
@export var heat_wind_factor_scale: float = 0.45
## [TUNE] 风寒惩罚开始的气温阈值 10 °C。
@export var heat_chill_start_c: float = 10.0
## [TUNE] 风寒惩罚归一化跨度 30 °C。
@export var heat_chill_range_c: float = 30.0
## [TUNE] 风寒惩罚上限 0.3。
@export var heat_chill_penalty: float = 0.3
## [TUNE] 背风 Site 分数对风寒的折减系数 0.6。
@export var heat_wind_chill_site_reduction: float = 0.6
## [TUNE] 无庇护所（None）的基础保暖分 0.05。
@export var heat_none_base: float = 0.05

# -----------------------------------------------------------------------------
# 报告/None 评分
# -----------------------------------------------------------------------------

@export_group("Scoring: Report")
## [TUNE] None 预设的 Site 分 0.10（完全暴露）。
@export var none_site_score: float = 0.1
## [TUNE] None 预设的 Structure 分 0.05（无承重结构）。
@export var none_structure_score: float = 0.05
## [TUNE] 完工度低于此值在 Structure note 中提示赶工，0.7。
@export var completion_note_threshold: float = 0.7

# -----------------------------------------------------------------------------
# 预设：高床雪洞（D，tune.ts raised 迁移）
# -----------------------------------------------------------------------------

@export_group("Preset: Raised Cave")
## [TUNE] 高床雪洞工作量 148（Web 原型 workRequired）。
@export var raised_cave_work_required: float = 148.0
## [TUNE] 高床雪洞消耗木材 2（床架/支撑）。
@export var raised_cave_wood_cost: int = 2
## [TUNE] 高床雪洞基础保暖 0.90（Web 原型 baseThermal）。
@export var raised_cave_base_thermal: float = 0.9
## [TUNE] 高床雪洞基础结构 0.86（Web 原型 baseStructure）。
@export var raised_cave_base_structure: float = 0.86
## [TUNE] 高床雪洞内部容积 3.05 m³（Web 原型 volume）。
@export var raised_cave_volume_m3: float = 3.05

# -----------------------------------------------------------------------------
# 预设：基础雪洞（C，tune.ts basic 迁移）
# -----------------------------------------------------------------------------

@export_group("Preset: Basic Cave")
## [TUNE] 基础雪洞工作量 108（Web 原型 workRequired）。
@export var basic_cave_work_required: float = 108.0
## [TUNE] 基础雪洞消耗木材 1。
@export var basic_cave_wood_cost: int = 1
## [TUNE] 基础雪洞基础保暖 0.74（Web 原型 baseThermal）。
@export var basic_cave_base_thermal: float = 0.74
## [TUNE] 基础雪洞基础结构 0.78（Web 原型 baseStructure）。
@export var basic_cave_base_structure: float = 0.78
## [TUNE] 基础雪洞内部容积 2.55 m³（Web 原型 volume）。
@export var basic_cave_volume_m3: float = 2.55

# -----------------------------------------------------------------------------
# 预设：雪沟（B，tune.ts trench 迁移 + D5 砌墙变体）
# -----------------------------------------------------------------------------

@export_group("Preset: Snow Trench")
## [TUNE] 标准雪沟工作量 58（Web 原型 workRequired）。
@export var snow_trench_work_required: float = 58.0
## [TUNE] 浅雪砌墙变体的额外工时 25 分钟（CORE_GAMEPLAY §5）。
@export var snow_trench_wall_extra_work_minutes: float = 25.0
## [TUNE] 雪沟消耗木材 0。
@export var snow_trench_wood_cost: int = 0
## [TUNE] 雪沟基础保暖 0.50（Web 原型 baseThermal）。
@export var snow_trench_base_thermal: float = 0.5
## [TUNE] 雪沟基础结构 0.52（Web 原型 baseStructure）；浅雪砌墙版更弱。
@export var snow_trench_base_structure: float = 0.52
## [TUNE] 雪沟内部容积 1.35 m³（Web 原型 volume）。
@export var snow_trench_volume_m3: float = 1.35

# -----------------------------------------------------------------------------
# 预设：倒棚 + 反射火（A，T0.6 新增，D2）
# -----------------------------------------------------------------------------

@export_group("Preset: Lean-To")
## [TUNE] 倒棚搭棚工作量 55（CORE_GAMEPLAY §5 的 40–60 min 量级）。
@export var lean_to_work_required: float = 55.0
## [TUNE] 倒棚骨架消耗木材 1。
@export var lean_to_wood_cost: int = 1
## [TUNE] 倒棚基础保暖 0.35；其余靠反射火与备柴。
@export var lean_to_base_thermal: float = 0.35
## [TUNE] 倒棚基础结构 0.62。
@export var lean_to_base_structure: float = 0.62
## [TUNE] 倒棚内部容积 1.8 m³（开放结构，仅用于体积惩罚模型）。
@export var lean_to_volume_m3: float = 1.8
