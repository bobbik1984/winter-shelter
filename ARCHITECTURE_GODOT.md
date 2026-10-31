# ARCHITECTURE_GODOT.md — Godot 4 技术架构与实现图景

> **引擎版本定位**：Godot 4.x (Forward+ / Mobile)  
> **核心渲染模型**：Orthographic 45° Isometric 3D + 2D CanvasLayer HUD  
> **参数标注规范**：`[REAL]` 现实规律 | `[GAME]` 机制抽象 | `[TUNE]` 调参基准

---

## 1. 工程文件目录规范 (Project Structure)

```text
wild/
├── project.godot                     # Godot 4 主工程配置文件
├── icon.svg                          # 项目图标
├── scenes/                           # 场景文件 (.tscn)
│   ├── main.tscn                     # 顶层集成场景 (主关卡)
│   ├── world/
│   │   └── blockout_terrain.tscn     # 灰模地形 (CSG 80-120m 斜坡与背风区)
│   ├── player/
│   │   └── player.tscn               # 玩家实体 (CharacterBody3D + 探针)
│   ├── camera/
│   │   └── camera_rig.tscn           # 45° 正交相机云台 (平滑跟随)
│   └── ui/
│       └── hud.tscn                  # 右上角气象卡片 + 世界空间探针深度读数
├── scripts/                          # GDScript 核心逻辑 (.gd)
│   ├── main.gd                       # 顶层关卡主控
│   ├── player/
│   │   └── player_controller.gd      # 45° ISO 运动解算与输入
│   ├── camera/
│   │   └── isometric_camera_rig.gd   # 正交镜头平滑追踪
│   ├── systems/
│   │   ├── weather_controller.gd     # 时间、落日、风向控制器
│   │   └── night_simulator.gd        # 6 维可解释雪洞评估与报告生成器
│   ├── ui/
│   │   └── hud_controller.gd         # HUD 数据驱动刷新
│   └── resources/                    # 自定义 Resource 脚本类
│       ├── wind_data.gd              # 气象数据类定义
│       └── shelter_preset.gd         # 雪洞预设数据结构定义
└── resources/                        # 资源实例 (.tres)
    └── default_wind.tres             # 默认西风资源实例
```

---

## 2. 场景与节点架构 (Node Tree Hierarchy)

### `res://scenes/main.tscn` 顶层节点结构：

```text
Main (Node3D) [main.gd]
├── WorldEnvironment (环境光: 极寒蓝冷色调, 启用法线与粗糙度)
├── SunLight (DirectionalLight3D: 低角度斜射, 暖金橙色, 开启硬阴影)
│
├── BlockoutTerrain (Node3D) [blockout_terrain.tscn]
│   ├── BaseGround (CSGBox3D: 100m x 2m x 100m, [TUNE] 积雪深 0.65m)
│   ├── SnowSlope (CSGBox3D 倾斜 30°: 适宜雪洞选址, [TUNE] 积雪深 2.15m)
│   └── Trees (Node3D)
│       ├── Spruce1, Spruce2 (活针叶树)
│       └── DeadwoodTree (立枯木，带 harvestable 标签)
│
├── Player (CharacterBody3D) [player.tscn]
│   ├── CollisionShape3D (CapsuleShape3D)
│   ├── Visual (Node3D: 橙色防寒服小人 + 背包)
│   └── AvalancheProbe (RayCast3D: 向下探测深度与碰撞体元数据)
│
├── CameraRig (Node3D) [camera_rig.tscn]
│   └── Camera3D (Projection=Orthogonal, Size=18m [TUNE], Rot=[-38°, 45°, 0°])
│
├── WeatherController (Node) [weather_controller.gd]
│   └── (驱动 SunLight 旋转俯角、颜色与日落时间流逝)
│
└── HUD (CanvasLayer) [hud.tscn]
    └── HUDController (Control)
        ├── TopRightCard (PanelContainer: 时间/落日/温度/风向)
        └── ProbePopup (PanelContainer: 世界投影浮动测深读数)
```

---

## 3. 核心子系统技术设计 (System Specifications)

### 3.1 45° 正交相机云台 (Isometric Camera Rig)
- **数学对齐**：
  - 水平旋转（Yaw）：固定 `45.0°`（镜头对角对齐世界网格对角线）；
  - 俯角（Pitch）：默认 `-38.0°`（经典 True Isometric 为 `-35.264°`，保留视感微调区间）；
  - 投影模式：`Camera3D.PROJECTION_ORTHOGONAL`；
  - 视口尺寸（Size）：`18.0` `[TUNE]`。  
    *注：Godot 正交 size 代表完整视口跨度（在默认 16:9 横屏 `KEEP_HEIGHT` 下，高度为 18m，水平宽度约为 32m）。*
- **坐标系转换（ISO Movement Mapping）**：
  - 在 45° 相机下，屏幕正上方（W 键）对应世界坐标的 `(-1, 0, -1).normalized()`；
  - 屏幕正右方（D 键）对应世界坐标的 `(1, 0, -1).normalized()`；
  - `player_controller.gd` 使用 `raw_dir.rotated(Vector3.UP, deg_to_rad(45.0))` 进行底层向量转换，保证移动方向绝对符合玩家屏幕直觉。

### 3.2 探针测深系统 (Snowpack Probing System)
- **采样方案**：
  - 地形网格区域赋予 `metadata["snow_depth"]`：
    - 深雪坡设置 `metadata["snow_depth"] = 2.15`；
    - 浅雪平原设置 `metadata["snow_depth"] = 0.65`；
  - 探针向落点发射射线采样，命中后触发信号 `probe_activated(world_pos, depth)`；
  - `MainLevel` 调度器通过 `camera.unproject_position(world_pos)` 将 3D 碰撞点实时映射到 2D 屏幕坐标，由 HUD 弹出微标签。

### 3.3 气象、连续日落与暮光抉择 (Continuous Daylight System)
- **`[GAME]` 连续衰减曲线（拒绝硬性开关惩罚）**：
  - 时间步进：`14:20`（860m）匀速向 `16:18`（978m）推进；
  - `DirectionalLight3D` 俯角从 `-25°` 逐渐压低至 `-4°`，光色由冷白平滑过渡到落日熔金；
  - 日落后不触发暴力翻倍，而是通过能见度收缩、温度持续下探、风寒效应加剧，诱导玩家在“冒黑赶工作业”与“提前钻洞过夜”之间进行心理权衡。

### 3.3b 大气状态与天空背景层 (AtmosphereState & Sky Backdrop)
- **`AtmosphereState`**（`scripts/systems/atmosphere_state.gd`）是时间和天气的**唯一数据源**：时间、太阳方向和颜色、天空渐变三色、雾色和雾密度、云量、降雪强度。`WeatherController` 每帧写入；以下节点只读：`SunLight`、`WorldEnvironment`（环境光、雾）、`BlizzardParticles`、`SkyBackdrop`。
- **`SkyBackdrop`**：`Environment.background_mode = BG_CANVAS`，配合一个低层级的 CanvasLayer（`background_canvas_max_layer` 指向它），里面是全屏 `ColorRect` + `shaders/sky_gradient.gdshader`（渐变、太阳 / 星点、2–3 层远山剪影，uniform 来自 `AtmosphereState`）。只在 3D 地形没覆盖的地方露出来。
- **约束**：远景雾色必须等于天空地平线颜色。规格和已知限制见 `VISUAL_LANGUAGE.md` §2.1。

### 3.4 6 维可解释夜间模拟 (Night Review System)
纯逻辑无状态评估器 `NightSimulator.gd`，输入庇护所几何与施工指标，产出 6 项 0-100 分及自然语言归因复盘。
> 待办（T2.7b）：增加倒棚 + 反射火分支（备柴能否烧到天亮、反射墙、棚背朝向），见 `CORE_GAMEPLAY.md` §6。顶厚阈值已按调研改为 0.3 / 0.45 m。

```gdscript
class_name NightSimulator

static func evaluate_shelter(
    shelter_type: String,         # "RaisedCave", "BasicCave", "SnowTrench", "None"
    wind_angle_diff: float,       # 入口朝向与迎风方向夹角 (0度迎风, 180度背风)
    has_cold_pit: bool,           # 是否挖出沉降冷气槽
    has_vent: bool,               # 是否插设可伸缩通风管 (Telescopic Vent)
    vent_snow_clogged: bool,      # 夜间降雪是否部分遮蔽通气管
    bedding_quality: float,       # 地面垫层质量 (0.0=无垫层, 1.0=厚松针干草)
    roof_thickness_meters: float, # 顶部雪层厚度 (m)
    completion_ratio: float       # 施工完成度 (0.0 - 1.0)
) -> Dictionary:
    # 返回：
    # {
    #   "outcome": "SAFE" / "COLD" / "DANGEROUS",
    #   "outcome_title": "SURVIVED COZY" / "SURVIVED HYPOTHERMIC" / "PERISHED IN FROST" / "SUFFOCATED",
    #   "scores": { thermal_protection, ventilation, wind_protection, ground_insulation, structural_safety, completion },
    #   "notes": [ "西风 32 km/h，入口偏向西北造成风冷侵入...", "高床与冷空气槽改善了睡眠区热环境...", ... ]
    # }
```

### 3.5 微地形避风、生火仪式与融雪回暖系统 (Tactile Survival Systems)

1. **微地形避风采样与声学滤波 (`WindExposureSensor` + `AudioBus` LowPass)**
   - **空间采样**：`SnowField.lee_factor(pos)` 结合角色朝向风源方向的短距离射线 `WindBlockRay`（检测巨石、翻倒树根 `RootBall`、雪墙或雪洞腔体碰撞盒），实时计算角色当前暴露度 `exposure ∈ [0.0, 1.0]`。
   - **总线联动**：
     - `AudioServer` 的 `WindBus` 挂载 `AudioEffectLowPassFilter`，截止频率 `cutoff_hz` 由 `exposure` 驱动（暴露时 `8000 Hz` 呼啸尖锐 $\rightarrow$ 树根后/进洞后平滑降至 `450–800 Hz` 沉闷包裹感）。
     - 角色控制器与动画状态机读取 `exposure`：暴露时触发缩肩发抖 Blend、急促呼吸白气粒子；避风时切换为放松姿态并减缓寒冷累积速率。
2. **三步生火与树冠落雪判定 (`CampfireController`)**
   - **状态机**：`UNLIT` $\rightarrow$ `TINDER_SPARK`（打火石刮擦，检测当前 `exposure` 是否超标）$\rightarrow$ `KINDLING_GUARD`（火苗初起，若遇 `WeatherController.is_gusting` 需按住交互键挡风，否则火苗值衰减归零）$\rightarrow$ `BURNING`（投入干柴，点亮 `OmniLight3D` 2700K 暖光与火焰粒子）$\rightarrow$ `BOILING_WATER`（架上 `CampPot` 融雪烧水，完成后重置角色 `chill_lock` 并赋予 `pre_warmed = true`）。
   - **树冠落雪危险（Tree-Snow Hazard）**：篝火点燃进入 `BURNING` 时，向上发射垂直检测射线；若命中挂雪低矮针叶树冠（`has_meta("canopy_snow")`），升温数秒后触发树冠落雪粒子，强制将火势压回微弱或扑灭，并弹出归因提示。
3. **45° 雪洞剖面视图与 5 阶状态显隐 (`ShelterCutawayRig`)**
   - 不使用高风险的实时 CSG 布尔网格挖孔，而是采用**“模块化分阶段网格 + 朝向相机的剖切 Shader（`cutaway.gdshader`）”**：
   - 雪洞预制件内含 5 个子网格组：`Stage1_Cavity`（主腔体与入口隧道）、`Stage2_ColdPit`（下沉冷气坑 + 冷流线 Decal/Mesh）、`Stage3_Bedding`（松针垫层 + 睡袋）、`Stage4_Vent`（穿顶伸缩管 + 排气粒子）、`Stage5_Lantern`（2700K 暖光烛灯 + 洞壁次表面散射材质参数激活）。施工进度每完成一阶，立即激活对应子节点与音效。

---

## 4. 全量开发资源清单 (Complete Asset & Resource Manifest)

> 本清单直接对齐参考图 *North Star v0.1* 的全部视觉、听觉与程序要素，作为建模、美术、Shader、音效与代码的真实生产指导单。

### 4.1 3D 模型资源清单 (`assets/models/`)

所有模型遵循 **Stylized Low-Poly + 柔和倒角法线** 风格；因采用 45° 正交等距相机，树木与岩石均可通过旋转/镜像复用。

| 分类 | 资源名称 | 规格与子部件要求 | 用途与对应里程碑 |
| :--- | :--- | :--- | :--- |
| **角色与挂件** | `char_survivor.glb` | 穿防寒连帽冲锋衣角色（约 1500–2500 面），绑骨含：平地走、深雪跋涉、缩肩发抖、蹲下探雪/护火、挥斧、铲雪、坐姿烤火 | M1 胶囊代理 → M2 低模 → M4 终版 |
| | `prop_backpack_red.glb` | 标志性红色登山包，预留 3 个外挂插槽：`slot_wood`（绑木柴捆）、`slot_bedding`（插干草/松枝束）、`slot_shovel`（挂雪铲） | 采集后直接体现在背上（背负感） |
| | `tool_probe / shovel / hatchet / ferrorod / pot.glb` | 折叠刻度探针（长杆带黑白刻度）、轻量雪铲、小手斧、打火棒、野营小铝锅（含锅盖与水汽挂点） | 手持工具与营地交互 |
| **树木与植被** | `tree_spruce_snow_A/B/C.glb` | 3 个变体的挂雪云杉（枝条略向东偏斜以体现常年西风），带树冠积雪碰撞标记 | 迎风/背风视觉线索、树冠落雪判定 |
| | `tree_standing_dead_A/B.glb` | 直立枯木（灰白剥落树皮、无针叶、形态苍劲），分“完整”与“已砍伐树桩”两态 | 核心干燥燃料来源（Deadwood） |
| | `tree_birch_A/B.glb` | 白桦树（白色树干带黑色斑纹，挂卷曲桦树皮条），分“未剥皮”与“已剥皮”两态 | 核心引火物（Birch Bark）来源 |
| | `tree_fallen_rootball.glb` | 翻倒的巨木连带盘结树根土盘（Root Ball）与半埋湿腐木 | **天然避风屏障**（树根凹窝挡风）+ 湿木反面教材 |
| | `foliage_dry_grass / pine_boughs.glb` | 雪地中露出的枯黄干草丛、可砍取的低矮云杉下枝 | 地面隔热垫层（Bedding）来源 |
| **地形与岩石** | `rock_ridge_A/B/C.glb` | 棱角分明的山脊裸岩（迎风面黑灰裸露，背风侧积雪覆盖） | 山脊线锚点、微地形避风掩体 |
| | `probe_marker_flag.glb` | 插在雪地上的探针读数小标记杆 | 探雪后留下的持久化雪深地图锚点 |
| **庇护所模块** | `shelter_snow_cave_cutaway.glb` | **核心亮点资产**：45° 正交剖面雪洞，拆分为外壁雪包、内腔拱顶、下沉冷气坑、高床雪台、入口隧道 | 配合 `cutaway.gdshader` 展现内部结构 |
| | `shelter_interior_props.glb` | 洞内陈设组：松针垫层网格、棕橙色睡袋、小烛灯（Lantern）、靠墙雪铲、背包卸下态、伸缩通风管（Telescopic Vent） | 5 阶建造逐步点亮“Cozy Inside” |
| | `shelter_trench_stages.glb` | 雪沟分阶段模型（浅雪砌雪砖墙变体 / 标准深沟 + 树枝雪块封顶） | 快速雪庇护所方案 |
| | `shelter_leanto_stages.glb` | 倒棚分阶段模型（A 字木架 → 云杉枝斜面覆顶 → 松针床 → 前方篝火坑 + 膝高原木反射墙） | 浅雪林区火庇护所方案 |

### 4.2 材质与 Shader 资源清单 (`shaders/`)

达到参考图画质的关键不在高模，而在以下 **6 个核心 Shader**：

| Shader 文件 | 核心技术实现 | 解决的视觉问题 |
| :--- | :--- | :--- |
| `snow_terrain.gdshader` | 基于法线与太阳夹角混合**暖金受光面**与**群青/钴蓝阴影面**；叠加视距高频闪点噪点（Sparkle Noise）；根据 `SnowField` 雪深微调柔和度 | 彻底摆脱“惨白塑料地面”，复刻参考图浓郁的冷暖色彩对比 |
| `snow_footprints.gdshader` | 结合跟随玩家的局部正交俯视 `SubViewport` 轨迹贴图，在角色走过的雪面产生下陷法线与暗部凹坑 | 实现参考图角色身后那串极具生命力的深雪脚印 |
| `cutaway_shelter.gdshader` | 朝向相机方向的平滑剖切平面 + 剖面边缘积雪质感描边 + 洞内 2700K 暖光在雪壁上的次表面散射近似（Subsurface Warmth） | 实现参考图右上角那种干净、通透又温暖的雪洞剖面图 |
| `wind_sway.gdshader` | 顶点动画：读取全局 `WindData` 的风向与风速（含阵风脉冲），让针叶树冠与干草统一向东偏摆 | 让静态截图和动态画面都能“一眼读出风向” |
| `sky_gradient.gdshader` | 渲染在背景 CanvasLayer 上：三段式夕阳渐变 + 太阳圆盘/星点 + 2~3 层远山剪影 + 地平线雾色同步 | 解决 45° 正交俯视看不到地平线和落日的问题 |
| `cold_airflow_line.gdshader` | 简单的 UV 流动半透明带状 Shader（用于剖面视图里的蓝色冷气沉降箭头与白色通风管排湿气流） | 把无形的物理规律（冷空气下沉、热湿气上排）直接画给玩家看 |

### 4.3 粒子与音频资源清单 (`scenes/vfx/` & `assets/audio/`)

- **粒子（`GPUParticles3D`）**：
  1. `vfx_wind_snow_streaks`：高空斜向风雪线（体现宏观风向）；
  2. `vfx_surface_spindrift`：贴着山脊与雪坡表面滑行的吹雪烟雾（体现迎风坡与背风坡）；
  3. `vfx_breath_frost`：角色口鼻呼出的白气（随暴露度改变频率）；
  4. `vfx_campfire_smoke_sparks`：打火石火星、桦树皮青烟、篝火跃动火苗、铝锅沸腾白汽、树冠落雪砸落粒子。
- **音频（配合 `WindBus` 动态低通滤波）**：
  1. **环境风声**：`amb_wind_howl_loop.ogg`（高频呼啸）+ `amb_wind_deep_loop.ogg`（低频基底）——躲进树根后或雪洞内时高频瞬降；
  2. **脚步与工具**：`sfx_step_shallow_snow`、`sfx_step_deep_snow`（深沉咯吱声）、`sfx_probe_thrust`（金属探针扎入雪层摩擦声）、`sfx_shovel_dig`、`sfx_axe_chop_dry`（清脆）vs `sfx_axe_chop_wet`（沉闷）；
  3. **温暖与治愈（ASMR 级）**：`sfx_ferro_scrape`（打火石咔嚓）、`sfx_tinder_catch`（火苗噗地燃起）、`sfx_fire_crackle_loop`（木柴噼啪声）、`sfx_snow_melt_boil`（融雪咕嘟冒泡与喝热饮长舒一口气）。

### 4.4 程序脚本模块全图 (`scripts/`)

```text
scripts/
├── main.gd                           # 关卡生命周期、阶段切换、信号总装
├── resources/
│   ├── tuning.gd                     # [SSOT] 唯一调参表 Resource（含 [REAL]/[GAME]/[TUNE] 标注）
│   ├── wind_data.gd                  # 风向、基础风速、阵风参数
│   └── shelter_preset.gd             # 4 种庇护所预设的工时、门槛、材料需求
├── world/
│   ├── terrain_height.gd             # 纯函数高度场（西迎风坡→脊线→东背风深雪坡→林谷）
│   ├── terrain_builder.gd            # 生成 ArrayMesh、碰撞体与场景资源分布
│   ├── snow_field.gd                 # 雪深场 snow_at()、坡度 slope_at()、避风度 lee_factor()
│   └── probe_marker.gd               # 地面持久化探针浮标管理
├── player/
│   ├── player_controller.gd          # 45° ISO 移动、深雪/上坡阻尼、寒颤与背负视觉挂载
│   └── wind_exposure_sensor.gd       # 实时检测微地形挡风（树根/岩石/洞内）并驱动音频滤波与体感
├── components/
│   └── interactable.gd               # 统一上下文交互组件（探雪/砍树/剥皮/护火/烧水/挖掘）
├── systems/
│   ├── atmosphere_state.gd           # 时间、太阳高度角、光色、雾色唯一实时状态
│   ├── weather_controller.gd         # 连续日落推进、阵风脉冲、作业效率衰减计算
│   ├── inventory.gd                  # 极简背包（干柴/树皮/垫层）与角色背包挂件同步
│   ├── campfire_controller.gd        # 三步护火引燃、树冠落雪判定、小铝锅融雪烧水回暖
│   ├── shelter_builder.gd            # 45° 剖面 Ghost 选址校验（D5）、旋转、5 阶挖掘推进
│   └── night_simulator.gd            # 6 维可解释结算模型（含雪庇护所与倒棚反射火双分支）
└── ui/
    ├── hud_controller.gd             # 右上气象卡、右下风向罗盘、物资托盘、寒冷/体力条
    ├── world_label.gd                # 说明书风格引线标签（探针读数、Deeper snow、剖面 5 标注）
    └── report_view.gd                # 6 维复盘报告卡与一键重开
```
