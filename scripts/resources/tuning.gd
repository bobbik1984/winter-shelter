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

@export_group("Sun")
## [REAL] 场景纬度 47.8°N（中纬度山地；与 1 月 14 日 16:18 日落一致）。
@export var sun_latitude_deg: float = 47.8
## [REAL] 1 月 14 日太阳赤纬约 -21.3°。
@export var sun_declination_deg: float = -21.3
## [GAME] 真太阳时正午 12:00 = 720 分钟（忽略时差方程与时区偏移）。
@export var solar_noon_minutes: float = 720.0

# -----------------------------------------------------------------------------
# 天气
# -----------------------------------------------------------------------------

@export_group("Weather")
## [REAL] 默认风速 32 km/h（Web 原型 9 m/s ≈ 32.4 km/h，取整与 HUD/default_wind 一致）。
@export var wind_speed_kmh: float = 32.0
## [TUNE] 主风向角度（度）。0 = 西风（自西向东吹），角度顺时针增加。
## [LEGACY] 未使用：风向角（风向 SSOT 是 WindData.direction）。
@export var wind_angle_deg: float = 0.0
## [TUNE] 阵风振幅 12.6 km/h（Web 原型 3.5 m/s × 3.6）。
## [LEGACY] 未使用：阵风幅度（尚未接入；阵风目前只影响树摆与音频包络）。
@export var gust_amplitude_kmh: float = 12.6
## [TUNE] 降雪粒子密度（相对强度，不换算物理降雪率）。
## [LEGACY] 未使用：降雪密度（已由 AtmosphereState.snowfall 时间曲线取代）。
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
## [TUNE] 开局气温 -17 °C（与简报 / HUD 一致；Web 原型为 -8）。气温随时间线性降到 temp_at_night_c。
@export var temp_at_start_c: float = -17.0
## [TUNE] 夜间最低气温 -24 °C（Web 原型 tempAtNight）。
@export var temp_at_night_c: float = -24.0
## [GAME] 每 km/h 风速带来的风寒降温，0.25 °C/(km/h)（Web 原型 0.9 °C/(m/s) 换算）。
@export var wind_chill_per_kmh: float = 0.25

# -----------------------------------------------------------------------------
# 玩家动作
# -----------------------------------------------------------------------------

@export_group("Night (D14)")
## CORE_GAMEPLAY §10。夜间体温 W 每游戏小时的变化 = −失温 + 热源。全部 [TUNE]，按 §10.2 标定表由机器人验证。
## 基础失温（W/小时）：完全没有保护、在参考气温下。
@export var night_base_loss_per_h: float = 32.0
## 参考夜温（°C）与敏感度：每比参考温度冷 1 °C，失温 +4%。
@export var night_temp_ref_c: float = -24.0
@export var night_temp_sensitivity: float = 0.04
## 保护度 → 失温的曲线指数：失温 = 基础 × (1 − 保护度)^γ（γ = 2：好庇护所几乎不掉，露天掉得很快）。
@export var night_protection_gamma: float = 2.0
## [REAL] 方向 / [TUNE] 数值：湿衣入睡额外失温（W/小时，按受潮程度），与庇护所好坏无关——湿衣服在雪洞里一样冷。
@export var night_wet_loss_per_h: float = 4.0
## 火：燃烧期间失温 × (1 − 火的作用)。有反射墙（倒棚）作用更大。
@export var night_fire_factor_reflector: float = 0.85
@export var night_fire_factor_open: float = 0.6
## [OB] 入睡时火里只架得下约 2.5 小时的柴，其余是"备柴"，要醒来时往里添（每次最多添几根）。
@export var night_fire_initial_hours: float = 2.5
@export var night_add_wood_logs: int = 2
## 睡前暖身 / 热饮：前几小时失温打折。
@export var night_prewarm_hours: float = 2.0
@export var night_prewarm_factor: float = 0.6
## [OB] 冷醒阈值、"一定会醒"的极危阈值；两次醒来最少间隔（游戏分钟）；整夜最多醒几次（极危不计入上限）。
@export var night_wake_cold_w: float = 40.0
@export var night_wake_critical_w: float = 15.0
@export var night_wake_spacing_min: float = 90.0
@export var night_max_wakes: int = 5
## 起来活动：体温 +W，出汗受潮 +，睡眠质量 −1。
@export var night_exercise_warmth: float = 10.0
@export var night_exercise_damp: float = 0.05
## 事件时刻（入睡后多少游戏分钟）：脚冷（湿袜子）、没通风管闷醒、通风管被堵头痛、积雪压顶。
@export var night_wet_feet_wake_min: float = 150.0
@export var night_no_vent_wake_min: float = 120.0
@export var night_no_vent_fatal_min: float = 240.0
@export var night_clog_wake_min: float = 240.0
@export var night_snow_load_wake_min: float = 180.0
## 积雪压顶没处理：此后失温 × 倍数；夜间降雪达到多少算会压顶。
@export var night_snow_load_penalty: float = 1.5
@export var night_snow_load_snowfall: float = 0.7
## 模拟步长（游戏分钟）与结局阈值。
@export var night_step_min: float = 5.0
@export var night_safe_min_w: float = 50.0
@export var night_safe_max_wakes: int = 1

@export_group("Gear")
## [TUNE] 没有雪铲、用随身的锅（billy pot）挖雪的工时倍数。`[OB]`：Outdoor Boys《Lost in Alaska》只带锯、打火棒、刀、锅、勺也熬过冬夜——靠的是换策略（树井 / 倒棚 / 火），不是硬挖雪洞。
@export var no_shovel_dig_factor: float = 3.0
## [TUNE] 连锅都没有、徒手挖的工时倍数；徒手挖时手套袖口湿得更快（受潮倍数）。
@export var bare_hands_dig_factor: float = 5.0
@export var bare_hands_damp_factor: float = 1.5
## [GAME] 地面隔热（bedding_quality 0..1）由几层叠起来：庇护所的枝条地板阶段给底子；
## 每多带一捆枝条 / 干草铺上去 +step（最多 +max）；防潮垫、兽皮各是一份可选加成。没有垫子也能靠多铺枝条做到满分，只是更花时间。
@export var bedding_base_quality: float = 0.65
@export var bedding_extra_step: float = 0.1
@export var bedding_extra_max: float = 0.35
## [TUNE] 防潮垫 / 兽皮对地面隔热的加成。`[OB]`：驯鹿皮空心毛发隔热极好。
@export var sleeping_pad_bedding_bonus: float = 0.35
@export var hides_bedding_bonus: float = 0.35

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
## [LEGACY] 未使用：Web 原型工作量模型（已由 ShelterPreset.build_minutes_total 取代）。
@export var build_work_per_second: float = 8.2
## [TUNE] 黄昏效率下限 0.45（非硬切换）。
@export var dusk_efficiency_floor: float = 0.45
## [TUNE] 每点寒冷锁定带来的效率惩罚 0.012。
## [LEGACY] 未使用：寒冷效率惩罚（已由 WarmthController 体温档效率取代）。
@export var cold_efficiency_penalty: float = 0.012
## [TUNE] 最大可建造坡度 22°。
@export var max_build_slope_deg: float = 22.0

# -----------------------------------------------------------------------------
# 相机
# -----------------------------------------------------------------------------

@export_group("Camera")
## [TUNE] Camera3D 在 rig 内沿本地 +Z 的后移距离，40 m（AGENTS §4.1 / T0.2）。
## [LEGACY] 未使用：正交相机参数（正交为备用模式，参数在 IsometricCameraRig @export）。
@export var camera_distance_m: float = 40.0
## [GAME] 正交相机俯仰，35.264° 为真等距。
## [LEGACY] 未使用：同上。
@export var camera_pitch_deg: float = 35.264
## [GAME] 正交相机绕 Y 轴偏航 45°（AGENTS §4.1）。
## [LEGACY] 未使用：同上。
@export var camera_yaw_deg: float = 45.0
## [TUNE] 默认正交 size 18.0（VISUAL_LANGUAGE 相机章节）。
## [LEGACY] 未使用：同上。
@export var camera_size_default: float = 18.0
## [TUNE] 最小缩放 0.3（Web 原型 minZoom）。
@export var zoom_min: float = 0.3
## [TUNE] 最大缩放 1.25（Web 原型 maxZoom）。
@export var zoom_max: float = 1.25
## 以下为移轴透视默认相机（D8，V9 定稿；IsometricCameraRig 从这里读取）。
## [GAME] 偏航 135° = 镜头朝西南（1 月午后太阳方位）。
@export var tilt_yaw_deg: float = 135.0
## [TUNE] 垂直视场角。
@export var tilt_fov_deg: float = 48.0
## [TUNE] 光轴俯仰（0 = 竖线不汇聚）。
@export var tilt_pitch_deg: float = 0.0
## [TUNE] 镜头下移量（占半高，负 = 看地面）。
@export var tilt_lens_shift: float = -0.38
## [TUNE] 玩家在画面中的高度（自顶向下 0..1）。
@export var tilt_player_screen_y: float = 0.58
## [TUNE] 默认相机距离 28 m；滚轮缩放范围 0.45–2.6。
@export var tilt_distance_m: float = 23.0
@export var tilt_zoom_min: float = 0.45
@export var tilt_zoom_max: float = 2.6

# -----------------------------------------------------------------------------
# 资源
# -----------------------------------------------------------------------------

@export_group("Resources")
## [TUNE] 地图可采集立枯木数量 7。
## [LEGACY] 未使用：Web 原型资源数（已由 deadwood_spots / birch_spots / bedding_spots 取代）。
@export var wood_count: int = 7
## [TUNE] 地图可采集桦树皮/引火物点位 7。
## [LEGACY] 未使用：同上。
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
@export var structure_slope_penalty: float = 0.18
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
@export var isolation_snow_trench_base: float = 0.45
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
## [LEGACY] 未使用：Web 原型工作量（已由 ShelterPreset.build_minutes_total 取代）。
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
## [LEGACY] 未使用：同上。
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
## [LEGACY] 未使用：同上。
@export var snow_trench_work_required: float = 58.0
## [TUNE] 浅雪砌墙变体的额外工时 25 分钟（CORE_GAMEPLAY §5）。
## [LEGACY] 未使用：同上。
@export var snow_trench_wall_extra_work_minutes: float = 25.0
## [TUNE] 雪沟消耗木材 0。
@export var snow_trench_wood_cost: int = 0
## [TUNE] 雪沟基础保暖 0.50（Web 原型 baseThermal）。
@export var snow_trench_base_thermal: float = 0.56
## [TUNE] 雪沟基础结构 0.52（Web 原型 baseStructure）；浅雪砌墙版更弱。
@export var snow_trench_base_structure: float = 0.52
## [TUNE] 雪沟内部容积 1.35 m³（Web 原型 volume）。
@export var snow_trench_volume_m3: float = 1.35

# -----------------------------------------------------------------------------
# 预设：倒棚 + 反射火（A，T0.6 新增，D2）
# -----------------------------------------------------------------------------

@export_group("Preset: Tree Well")
## [REAL] 方向 / [TUNE] 数值：老云杉浓密的树冠接住落雪，树干周围积雪明显更浅（tree well）。
## 树干处削薄比例与树冠半径（m）。出处待 research/ 核实（Paul Kirtley 等冬季森林庇护所资料）。
@export var tree_well_canopy_snow_reduction: float = 0.6
@export var tree_well_canopy_radius_m: float = 2.2
## [GAME] 算"老云杉"（低枝浓密、能做树井）的最小缩放。
@export var old_spruce_min_scale: float = 1.0
## [TUNE] 树井需要的周围积雪（m）：周围雪够厚，挖开树干周围的浅坑才有雪墙。
@export var tree_well_min_snow_m: float = 1.0
## [GAME] 选址时离老云杉树干的最大距离（m）。
@export var tree_well_max_trunk_dist_m: float = 2.6
## [TUNE] 树井夜间参数：保暖介于雪沟与雪洞之间；枝条屋顶透气（不需通风管）；没有冷气坑。
@export var tree_well_base_thermal: float = 0.6
@export var tree_well_base_structure: float = 0.62
@export var tree_well_isolation_base: float = 0.5
@export var tree_well_air_score: float = 0.86
@export var tree_well_volume_m3: float = 1.6

@export_group("Preset: Lean-To")
## [TUNE] 倒棚搭棚工作量 55（CORE_GAMEPLAY §5 的 40–60 min 量级）。
## [LEGACY] 未使用：同上。
@export var lean_to_work_required: float = 55.0
## [TUNE] 倒棚骨架消耗木材 1。
@export var lean_to_wood_cost: int = 1
## [TUNE] 倒棚基础保暖 0.35；其余靠反射火与备柴。
@export var lean_to_base_thermal: float = 0.35
## [TUNE] 倒棚基础结构 0.62。
@export var lean_to_base_structure: float = 0.62
## [TUNE] 倒棚内部容积 1.8 m³（开放结构，仅用于体积惩罚模型）。
@export var lean_to_volume_m3: float = 1.8

# -----------------------------------------------------------------------------
# 0–100 核心体温（T2.3 / CORE_GAMEPLAY §4 / ARCHITECTURE §3.5）
# -----------------------------------------------------------------------------

@export_group("Body Warmth")
## [GAME] 核心体温上限，100 = 状态最佳。
@export var warmth_max: float = 100.0
## [TUNE] 迎风暴露区基础掉温速率（Warmth/现实秒）。0.25 → 完全暴露约 6.7 分钟从 100 掉到 0。
@export var warmth_cold_decay_exposed: float = 0.25
## [TUNE] 树根/巨石背风区最大减免比例；0.25 × (1 - 0.70) ≈ 0.075/s。
@export var warmth_windbreak_mitigation_max: float = 0.70
## [TUNE] 额外衣物/烘干层的掉温减缓比例 35%。
@export var warmth_clothing_mitigation_bonus: float = 0.35
## [TUNE] 靠近燃烧篝火的回温速率（Warmth/s）。
@export var warmth_fire_recovery_rate: float = 2.5
## [TUNE] 铝锅融雪热饮的瞬时回温量（Warmth）。
@export var warmth_hot_drink_instant_boost: float = 15.0
## [REAL] 基础雪沟/初挖雪洞依靠雪体绝热锁住体温；[TUNE] 0.0/s。
@export var warmth_shelter_hold_rate: float = 0.0
## [REAL] 完备雪洞（冷气槽 + 松针垫层）靠人体自发热缓慢回升；[TUNE] +0.55/s。
@export var warmth_shelter_cozy_gain_rate: float = 0.55
## [GAME] 体温 >= 70 时作业效率 1.0。
@export var warmth_tier_warm: float = 70.0
## [GAME] 体温 >= 35 时作业效率 0.75；低于 35 为 0.5。
@export var warmth_tier_chilled: float = 35.0
## [TUNE] 入夜低体温对 NightSimulator Heat 分的惩罚系数。
@export var warmth_night_heat_penalty: float = 0.35

# -----------------------------------------------------------------------------
# 游戏循环（M1 收尾 + M2：移动阻尼、探针、交互、背包、建造、生火、过夜）
# -----------------------------------------------------------------------------

@export_group("Movement")
## [TUNE] 深雪开始拖慢的雪深 0.6 m。
@export var deep_snow_start_m: float = 0.6
## [TUNE] 深雪拖慢饱和的雪深 2.0 m。
@export var deep_snow_full_m: float = 2.0
## [TUNE] 最深雪中的速度倍率 0.55（不烦人，但明显变慢）。
@export var deep_snow_speed_min: float = 0.55
## [TUNE] 上坡速度下限倍率 0.45。
@export var uphill_speed_min: float = 0.45

@export_group("Interaction")
## [GAME] 可交互距离 2.4 m。
@export var interact_radius_m: float = 2.4
## [GAME] 采集一次的游戏分钟消耗 6。
@export var gather_minutes: float = 6.0
## [GAME] 每次砍立枯木获得木材 2。
@export var wood_per_harvest: int = 2
## [GAME] 每棵立枯木可砍次数 2。
@export var deadwood_uses: int = 2
## [GAME] 每次剥桦树皮获得引火物 1。
@export var bark_per_harvest: int = 1
## [GAME] 每丛干草 / 云杉枝获得垫层 1。
@export var bedding_per_harvest: int = 1
## [TUNE] 立枯木 / 桦树 / 干草点位数量。
@export var deadwood_spots: int = 6
@export var birch_spots: int = 4
@export var bedding_spots: int = 8
## [GAME] 背包上限（木材）。
@export var max_wood: int = 12

@export_group("Building")
## [GAME] 每个施工阶段按住交互键的现实秒数（按住时游戏时间按工时跳进）。
@export var stage_hold_seconds: float = 2.4
## [GAME] 建造预览距玩家前方的距离 3.0 m。
@export var ghost_distance_m: float = 3.0
## [GAME] 视为"在庇护所内"的半径 2.2 m。
@export var shelter_inside_radius_m: float = 2.2
## [GAME] 视为"靠近天然挡风物（翻倒树根）"的半径 4.5 m。
@export var windbreak_radius_m: float = 4.5
## [GAME] 跳进游戏时间时，劳作的体温流失按暴露率的比例计（干活发热）。
@export var work_exposure_factor: float = 0.35

## [GAME] 快速顶（顶厚 = roof_thickness_min_m）节省的施工时间比例。
@export var quick_roof_time_factor: float = 0.8

## [GAME] 入睡时降雪强度达到此值，单根且没插木棍的通风管会被新雪部分堵塞（报告里可解释、可预防）。
@export var vent_clog_snowfall: float = 0.5

## [GAME] 全天模式的开局时刻（10:00）：影子先变短、正午最短、再变长；时间更宽裕。
@export var full_day_start_minutes: int = 600

@export_group("Clothing Dampness")
## [GAME] 挖一个雪庇护所阶段，保暖层受潮 +0.22（趴在雪里干活）。
@export var damp_per_dig_stage: float = 0.22
## [GAME] 暴露在大雪中（降雪 > 0.5）每现实秒受潮 +0.004。
@export var damp_snowfall_rate: float = 0.004
## [GAME] 站在燃烧的火旁每现实秒烘干 0.05 × 火势。
@export var dry_rate_fire: float = 0.05
## [GAME] 受潮 >= 0.5 时保暖层失去减缓效果（CORE_GAMEPLAY §4：只有干燥蓬松的纤维才锁住静止空气）。
@export var damp_threshold: float = 0.5
## [TUNE] 入睡时衣服受潮对整夜 Heat 的削减（湿透 = 全额；受潮 = 部分；干 = 0）。
## 依据（[REAL] 方向，数值待 research/ 核实）：湿的衣物几乎不保暖、蒸发持续带走热量——
## 白天 HUD 说"湿了、不再保暖"，过夜结算必须一致（第一次评审 R1）。
@export var night_wet_heat_penalty: float = 0.35

## [GAME] T4.7 方案 A：迎风脊开低垭口，出生点即可看到远景山谷 / 冰湖。默认关（方案 B：爬上脊线才看到）。
@export var ridge_saddle: bool = false

@export_group("Weather Variety")
## [GAME] 每局天气的抽取权重：晴 / 阴 / 暴风雪将至。
@export var weather_weight_clear: float = 0.5
@export var weather_weight_overcast: float = 0.3
@export var weather_weight_storm: float = 0.2
## [GAME] 阴天云量（0..1）：天空发灰、太阳变弱、影子变淡。
@export var overcast_cloud: float = 0.7
## [GAME] 暴风雪：开始增强的时刻（分钟）、增强用时、最大风速增量（km/h）、夜间额外降温（°C）。
@export var storm_start_minutes: float = 930.0
@export var storm_ramp_minutes: float = 90.0
@export var storm_extra_wind_kmh: float = 20.0
@export var storm_extra_cold_c: float = 5.0

@export_group("Campfire")
## [GAME] 生火按住秒数。
@export var fire_hold_seconds: float = 2.0
## [GAME] 每根木材燃烧的游戏分钟（营火，非通宵）。
@export var campfire_minutes_per_wood: float = 25.0
## [GAME] 火的有效取暖半径 3.5 m。
@export var fire_warm_radius_m: float = 3.5
## [GAME] 树冠下生火判定半径 2.2 m（落雪压火）。
@export var canopy_radius_m: float = 2.2
## [GAME] 融雪烧水的游戏分钟。
@export var melt_snow_minutes: float = 15.0

@export_group("Night")
## [GAME] 天黑后强制入夜的宽限（分钟，从 night_minutes 起算）。
@export var forced_sleep_grace_minutes: float = 40.0
## [GAME] 入夜黑屏时长（现实秒）。
@export var night_fade_seconds: float = 3.0

## [GAME] 体温归零持续这么多现实秒 → 失温倒下，强制入夜（结算按体温 0）。
@export var collapse_seconds_at_zero: float = 8.0

@export_group("Tips")
## [GAME] 提示文案切换阈值：距日落剩余分钟。
@export var tip_plenty_minutes: float = 75.0
@export var tip_hurry_minutes: float = 35.0
## [GAME] 体温低于此值时优先提示取暖。
@export var tip_cold_warmth: float = 40.0
