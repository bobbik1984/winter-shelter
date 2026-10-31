# ARCHITECTURE_GODOT.md — Godot 4 技术架构与实现图景

> **引擎版本定位**：Godot 4.x (Forward+ / Mobile)  
> **核心渲染模型**：移轴透视 3D（默认，D8；正交等距为 V 键备用）+ 2D CanvasLayer HUD · Godot **4.3 stable** · Forward+（Vulkan）
> **修订**：2026-11-01（§1–§4 按实际代码更新；标 *规划* 的条目尚未实现）  
> **参数标注规范**：`[REAL]` 现实规律 | `[GAME]` 机制抽象 | `[TUNE]` 调参基准

---

## 1. 工程文件目录规范 (Project Structure)

```text
wild/
├── project.godot                     # 主工程配置（FSR 0.67 渲染缩放、阴影 4096、输入映射）
├── scenes/
│   ├── main.tscn                     # 顶层集成场景（只由主控 Agent 修改）
│   ├── world/blockout_terrain.tscn   # 地形 + Scenery + Forest + FarTerrain
│   ├── player/player.tscn            # CharacterBody3D + 拼装角色 + 探针射线
│   ├── camera/camera_rig.tscn        # 相机云台（移轴 / 正交）
│   └── ui/                           # hud.tscn、hud_warmth.tscn、shelter_cutaway_panel.tscn
├── scripts/                          # 见 §4.4
├── shaders/                          # 见 §4.2
├── resources/                        # tuning.tres（SSOT）、default_wind.tres
├── tests/                            # headless 逻辑测试，入口 run_all.gd
├── tools/capture_snapshot.gd         # 窗口模式实机截图
└── snapshots/                        # 里程碑与过程快照
```

---

## 2. 场景与节点架构 (Node Tree Hierarchy)

### `res://scenes/main.tscn` 顶层节点结构（现状）：

```text
Main (Node3D) [main.gd]
├── WorldEnvironment [atmosphere_setup.gd]   # Sky shader、ACES、泛光、SSAO、雾；组 sun_receivers / lens_receivers
├── SunLight (DirectionalLight3D)            # 方向 / 颜色 / 强度由 WeatherController 按 SunModel 驱动
├── WindParticles [wind_particles.gd]        # 方向读 WindData.get_blow_direction_3d()
├── BlockoutTerrain [blockout_terrain.tscn]
│   ├── (TerrainMesh + TerrainBody)  [terrain_builder.gd]     # 100×100 m 高度场，组 sun_receivers
│   ├── Scenery   [scenery_builder.gd]       # 8 个生态小岛、交互枯木圈、脚印链；组 occlusion_fade
│   ├── Forest    [forest_scatter.gd]        # 密林 / 枯立木 / 岩石 MultiMesh（25 m 分块）；组 occlusion_fade
│   └── FarTerrain [far_terrain_builder.gd]  # 地图外远景谷 / 远山 / 远景林（110 m 分块），无碰撞
├── ShelterCutaway (隐藏) / CampfirePot      # 世界内雪洞位置占位、篝火锅
├── Player [player.tscn] + WarmthController
├── CameraRig [camera_rig.tscn]              # 跟随玩家；每帧推送 lens / occlusion focus
├── WeatherController                        # 时钟、太阳（SunModel）、天气信号
└── HUD [hud.tscn]                           # 环境卡、体温卡、罗盘、世界标签、雪洞剖面面板（独立 SubViewport）
```

**跨节点通信约定**：视觉"接收方"通过节点组接收推送，而不是互相持有引用——
`sun_receivers.set_sun_dir(dir)`（天空、雪面、环境光 / 雾）、`lens_receivers.set_lens(...)`（天空镜头修正）、`occlusion_fade.set_focus(pos)`（遮挡镂空）。V7 计划把前两者收拢进 `AtmosphereState`。

---

## 3. 核心子系统技术设计 (System Specifications)

### 3.1 相机云台（移轴透视为默认，D8）
- **TILT_SHIFT**：`PROJECTION_FRUSTUM`。rig 俯仰 0°、偏航 135°；`size = 2·near·tan(fov/2)`，`frustum_offset.y = lens_shift·near·tan(fov/2)`（负值 = 镜头下移）。
  相机在 rig 局部 `(0, d·sinθ, d·cosθ)`，θ 由"玩家在画面 58 % 高度"反算，所以玩家位于光轴下方而竖线不汇聚。景深用 `CameraAttributesPractical`。
- **ORTHO**（V 键）：`PROJECTION_ORTHOGONAL`、俯仰 -38°、沿 rig 本地 +Z 后移 40 m、far 200。
- **滚轮**：只在移轴模式下推拉距离（0.45–2.6 倍）。
- **输入映射**：`player_controller.gd` 用当前相机前向的偏航角旋转输入向量（**不再写死 45°**）；罗盘同理。
- **每帧推送**：`_push_lens()` → 天空镜头修正；`occlusion_fade.set_focus(玩家位置)` → 遮挡镂空。

### 3.2 探针测深系统 (Snowpack Probing System)
- **采样方案**：
  - 地形网格区域赋予 `metadata["snow_depth"]`：
    - 深雪坡设置 `metadata["snow_depth"] = 2.15`；
    - 浅雪平原设置 `metadata["snow_depth"] = 0.65`；
  - 探针向落点发射射线采样，命中后触发信号 `probe_activated(world_pos, depth)`；
  - `MainLevel` 调度器通过 `camera.unproject_position(world_pos)` 将 3D 碰撞点实时映射到 2D 屏幕坐标，由 HUD 弹出微标签。

### 3.3 时间、太阳与连续暮光（`SunModel` + `WeatherController`）
- **`SunModel`**（`scripts/systems/sun_model.gd`，纯函数，`tests/test_sun_model.gd` 覆盖）：由纬度、赤纬、正午分钟算太阳高度角 / 方位角 / 世界方向、日出日落时刻、单位高度影长。参数在 Tuning `Sun` 组（`[REAL]`）。
- **`WeatherController`**：时钟从 `Tuning.start_minutes` 起按 `time_scale` 推进；每帧用 `SunModel` 设置 `SunLight` 的朝向（`Basis.looking_at(-to_sun)`）、颜色（低角度暖橙 → 高角度白金）、强度（日落后归零、关阴影），并向 `sun_receivers` 推送太阳方向。日落时刻由模型算出，HUD 不再写死。
- **`[GAME]` 连续衰减**：日落后不触发硬惩罚；能见度、温度、风寒持续恶化，玩家在"摸黑赶工"与"提前钻洞"之间权衡（玩法效率衰减仍待接入）。

### 3.3b 大气与天空（现状 + V7 规划）
- **现状**：`atmosphere_setup.gd` 建 `Environment`（Sky shader、ACES、泛光、SSAO、雾）；`set_sun_dir` 随太阳高度调环境光与雾；`set_lens` 把移轴镜头参数传给天空 shader。
- **规划（V7）**：`AtmosphereState` 成为时间与天气的唯一数据源（太阳、天空色、雾、云量、降雪强度），天空 / 光 / 雾 / 粒子只读它；接 T3.1 暴风雪。
- **约束**：远景雾色接近天空地平线色；不得为构图把太阳挪到假方位（D9）。

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

### 3.5 核心体温管理 (0–100 Body Warmth)、微地形避风与生火回暖系统 (Tactile Survival Systems)

1. **实时核心体温控制器 (`WarmthController` — `0.0 .. 100.0`)**
   - **唯一生存数值**：`body_warmth: float = 100.0`（`100` 为状态最佳，`0` 为冻僵失温）。
   - **每帧更新公式**：
     $$\Delta W = \left( R_{\text{fire}} + R_{\text{shelter}} - R_{\text{cold\_env}} \times (1.0 - \text{windbreak\_factor}) \times (1.0 - \text{clothing\_mitigation}) \right) \times \Delta t$$
     - **寒冷下降 (`R_cold_env`)**：随时间接近黄昏/入夜及风速升高而加剧（迎风暴露区约 `-1.2/s`）；
     - **微地形避风减免 (`windbreak_factor`)**：躲在倒木树根凹窝、巨石背风面或初挖雪坑内可减免 `65%–75%` 风寒流失（降至约 `-0.35/s`）；
     - **额外衣物减缓 (`clothing_mitigation`)**：穿戴备用防风保暖层或在篝火旁烘干内衬后，额外减缓 `25%–50%` 下降速率；
     - **庇护所保温/自发热回升 (`R_shelter`)**：进入已成形的雪庇护所内部时，阻断外界风寒，依庇护所完备度（雪沟/基础雪洞/高床+松针垫层+冷气槽）实现**体温保持（`0.0/s`）或缓慢回升（`+0.3 ~ +0.6/s`）**；
     - **火源与热饮回升 (`R_fire`)**：处于燃烧的篝火暖光半径内时体温快速回升（`+2.5/s`）；用 `CampPot` 融雪烧水饮用立即恢复 `+15.0` 体温并赋予短时抗寒 Buff。
   - **区间联动**：
     - `70..100`：作业效率 `1.0`；
     - `35..69`：轻度受寒，作业效率 `0.75`，呼吸白气加密；
     - `1..34`：失温警告，作业效率 `0.5`，角色发抖、屏幕边缘结霜；
     - `0`：触发白天失温结算；入夜时的 `body_warmth` 直接作为 `NightSimulator` 过夜模拟的初始体温起点。
2. **微地形避风采样与声学滤波 (`WindExposureSensor` + `AudioBus` LowPass)**
   - **空间采样**：`SnowField.lee_factor(pos)` 结合角色朝向风源方向的短距离射线 `WindBlockRay`（检测巨石、翻倒树根 `RootBall`、雪墙或雪洞腔体碰撞盒），实时计算角色当前暴露度 `exposure ∈ [0.0, 1.0]`（即 `windbreak_factor = 1.0 - exposure`）。
   - **总线联动**：
     - `AudioServer` 的 `WindBus` 挂载 `AudioEffectLowPassFilter`，截止频率 `cutoff_hz` 由 `exposure` 驱动（暴露时 `8000 Hz` 呼啸尖锐 $\rightarrow$ 树根后/进洞后平滑降至 `450–800 Hz` 沉闷包裹感）。
     - 角色控制器与动画状态机读取 `exposure` 与 `body_warmth`：暴露或低体温时触发缩肩发抖 Blend、急促呼吸白气粒子；避风或回暖时切换为放松姿态。
3. **三步生火与树冠落雪判定 (`CampfireController`)**
   - **状态机**：`UNLIT` $\rightarrow$ `TINDER_SPARK`（打火石刮擦，检测当前 `exposure` 是否超标）$\rightarrow$ `KINDLING_GUARD`（火苗初起，若遇 `WeatherController.is_gusting` 需按住交互键挡风，否则火苗值衰减归零）$\rightarrow$ `BURNING`（投入干柴，点亮 `OmniLight3D` 2700K 暖光与火焰粒子，为范围内玩家提供 `+2.5/s` 体温回升与衣物烘干）$\rightarrow$ `BOILING_WATER`（架上 `CampPot` 融雪烧水，完成后立即 `+15.0` 体温并置 `pre_warmed = true`）。
   - **树冠落雪危险（Tree-Snow Hazard）**：篝火点燃进入 `BURNING` 时，向上发射垂直检测射线；若命中挂雪低矮针叶树冠（`has_meta("canopy_snow")`），升温数秒后触发树冠落雪粒子，强制将火势压回微弱或扑灭，并弹出归因提示。
4. **45° 雪洞剖面视图与 5 阶状态显隐 (`ShelterCutawayRig`)**
   - 不使用高风险的实时 CSG 布尔网格挖孔，而是采用**“模块化分阶段网格 + 朝向相机的剖切 Shader（`cutaway.gdshader`）”**：
   - 雪洞预制件内含 5 个子网格组：`Stage1_Cavity`（主腔体与入口隧道，进入即锁住体温不降）、`Stage2_ColdPit`（下沉冷气坑 + 冷流线 Decal/Mesh）、`Stage3_Bedding`（松针垫层 + 睡袋，开启洞内体温缓慢回升）、`Stage4_Vent`（穿顶伸缩管 + 排气粒子）、`Stage5_Lantern`（2700K 暖光烛灯 + 洞壁次表面散射材质参数激活）。施工进度每完成一阶，立即激活对应子节点与音效。

---

### 3.6 程序化植被与渲染性能约定
- 植被 / 岩石用 `MultiMeshInstance3D`，并通过 `ForestScatter.add_chunked()` **按空间分块**（地图内 25 m、远景 110 m）——整图一块的 MultiMesh 永远无法被视锥 / 阴影级联剔除。
- 远景林使用低面数变体（`SpruceMesh.build(..., spikes = 6)`），不投影。
- `project.godot`：FSR 渲染缩放 0.67、软阴影质量 1；阳光阴影距离 90 m；雪洞剖面 SubViewport 每 4 帧重绘一次。
- 基线（Intel UHD 620，1080p）：约 13 FPS。**新增视觉特性需在回执中报告 FPS 变化**；画质档位见 V2、底线见 D11。

### 3.7 已知 Godot 4.3 引擎坑（已规避）
| 现象 | 规避 |
| :--- | :--- |
| 天空背景按对称视锥重建 `EYEDIR`，忽略 `Camera3D.frustum_offset` → 太阳 / 地平线画错高度 | 相机 rig 推送真实镜头参数，`sky_backdrop.gdshader` 在非 cubemap pass 按屏幕 UV 重建视线 |
| 天空 shader 读 `LIGHT0_DIRECTION` 拿不到值 | 太阳方向作为普通 uniform 经 `sun_receivers` 组推送 |
| `project.godot` 的 `[shader_globals]` 在 `-s` 脚本模式（截图 / 测试）下不生效 | 不用 global uniform，改用节点组推送 |
| 新增 `class_name` 脚本后，其它脚本报 "Identifier not declared" | 先跑一次 `godot --headless --path . --import` 刷新全局类缓存 |
| unshaded 材质的 `ALBEDO` 是线性空间（0.2 显示约为 sRGB 0.48） | 在线性空间选色（见 `cutaway_sdf.gdshader` 注释） |
| `discard` 同时作用于阴影 pass | 用 `PROJECTION_MATRIX[3][3] > 0.5`（正交 = 平行光阴影）跳过 |

---

### 3.8 游戏循环层（M2，2026-11-01）
- **`GameDirector`**（`main.gd` 运行时创建）：状态机 BRIEFING → PLAYING ⇄ PAUSED → NIGHT_FADE → REPORT；输入（B / F / N / Esc / F10 / Enter / R）；每帧把暴露度、庇护等级、火源写入 `WarmthController`（`auto_update = false`）与 `AmbientAudio`；动作通过 `_skip(minutes)` 跳进游戏时间并按劳作系数结算体温；入夜时组装 `NightSimulator` 输入并用 `NightReportText` 生成英文报告。
- **规则**：`GameRules`（纯函数，`tests/test_game_rules.gd`）——移动阻尼、探针分类、入口风向夹角、暴露度（背风坡 + 树根 + 林木）、生火判定、提示文案、作业效率。
- **交互**：`Interactable`（组 `interactables`，handler / prompt_fn）+ `InteractionController`（最近目标、按住进度、淡橙圈）。
- **世界对象**：`ResourceSpawner`（资源与树根挡风物，并给森林 / 场景里全部立枯木挂采集点）、`ShelterSite`（持有 `ShelterBuilder`，5 阶外观 + 每阶材料）、`BuildMode`（预览与校验）、`Campfire`、`Footprints`、`Snowfall`、玩家头灯。
- **UI**：`GameUI`（代码构建：提示、背包、消息、建造面板、简报、暂停、黑屏、报告）；`WorldCallouts` 动态引线标签 API。
- **设置**：`GraphicsSettings`（F10，`user://settings.cfg`）。

## 4. 全量开发资源清单 (Complete Asset & Resource Manifest)

> 本清单直接对齐参考图 *North Star v0.1* 的全部视觉、听觉与程序要素，作为建模、美术、Shader、音效与代码的真实生产指导单。

### 4.1 3D 模型资源清单 (`assets/models/`)

所有模型遵循 **Stylized Low-Poly + 柔和倒角法线** 风格；树木与岩石可通过旋转/镜像复用。

> **现状（D10）**：云杉、枯立木、岩石、远景已由程序化网格（`SpruceMesh` / `PropMeshes`）+ `snow_cover.gdshader` 实现，下表中这些条目降为"需要时再替换"。**Blender 优先做角色 `char_survivor.glb` 及动画（V4）**，其次是终版雪洞内饰与工具。导入的 `.glb` 一律套 `snow_cover` 自动积雪；云杉的偏冠方向必须与 `WindData` 下风方向一致。

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
| **庇护所模块** | `shelter_snow_cave_cutaway.glb` | **核心亮点资产**：剖面雪洞（世界内分阶段模型）。HUD 剖面面板已由 `cutaway_sdf.gdshader` 程序化实现，此资产只在需要世界内显示时再做 | 世界内 5 阶建造显示 |
| | `shelter_interior_props.glb` | 洞内陈设组：松针垫层网格、棕橙色睡袋、小烛灯（Lantern）、靠墙雪铲、背包卸下态、伸缩通风管（Telescopic Vent） | 5 阶建造逐步点亮“Cozy Inside” |
| | `shelter_trench_stages.glb` | 雪沟分阶段模型（浅雪砌雪砖墙变体 / 标准深沟 + 树枝雪块封顶） | 快速雪庇护所方案 |
| | `shelter_leanto_stages.glb` | 倒棚分阶段模型（A 字木架 → 云杉枝斜面覆顶 → 松针床 → 前方篝火坑 + 膝高原木反射墙） | 浅雪林区火庇护所方案 |

### 4.2 材质与 Shader 资源清单 (`shaders/`)

| Shader 文件 | 状态 | 核心技术实现 | 解决的视觉问题 |
| :--- | :--- | :--- | :--- |
| `snow_terrain.gdshader` | ✅ | 冷暖受光 / 阴影、风蚀雪纹法线扰动、闪点、朝太阳方向的逆光暖辉；陡坡露岩；太阳方向由 `sun_receivers` 推送 | 摆脱"惨白塑料地面"，复刻参考图冷暖对比 |
| `snow_cover.gdshader` | ✅ | 按世界法线自动积雪（植被 / 岩石 / 外部 .glb 通用）；`occlusion_fade` 抖动镂空挡住玩家的物体 | 统一积雪观感；透视相机下玩家始终可见 |
| `sky_backdrop.gdshader` | ✅ | 渐变天空 + 朝阳暖带 + 太阳圆盘 / 光晕 + 暮色 / 夜色；移轴镜头修正 | 天际线、落日与时间表达 |
| `cutaway_sdf.gdshader` | ✅ | 雪丘 / 洞腔 / 冷气坑 / 隧道 / 睡台 / 通风井 / 陈设的 SDF 光线步进；平滑切口 + poché 描边 + 烛光透壁；写 DEPTH 与真实网格正确遮挡 | 参考图右上角雪洞剖面 |
| `snow_footprints.gdshader` | 规划（V8） | 跟随玩家的俯视轨迹贴图，雪面下陷法线与暗部凹坑 | 角色身后的脚印 |
| `wind_sway.gdshader` | 规划（T3.1） | 顶点动画读 `WindData`（含阵风），树冠与干草统一向下风偏摆 | 动态画面一眼读出风向 |
| `cold_airflow_line.gdshader` | 不需要 | 剖面里的气流箭头已由 2D 叠加层绘制（与 shader 共用相机投影） | — |

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

> ✅ = 已存在；其余为规划。

```text
scripts/
├── main.gd                           ✅ 关卡生命周期、信号总装（HUD 日落时刻由 WeatherController 注入）
├── resources/
│   ├── tuning.gd                     ✅ [SSOT] 唯一调参表（含 Sun 组：纬度 / 赤纬 / 正午）
│   ├── wind_data.gd                  ✅ 风的来向 direction；get_blow_direction_3d() = 下风方向
│   └── shelter_preset.gd             ✅ 庇护所预设
├── camera/
│   └── isometric_camera_rig.gd       ✅ 移轴 / 正交双模式、滚轮推拉、镜头参数与遮挡焦点推送
├── world/
│   ├── terrain_height.gd             ✅ 纯函数高度场
│   ├── terrain_builder.gd            ✅ ArrayMesh + 碰撞；sun_receivers
│   ├── snow_field.gd                 ✅ 雪深场
│   ├── atmosphere_setup.gd           ✅ Environment / Sky；sun_receivers + lens_receivers
│   ├── scenery_builder.gd            ✅ 生态小岛、交互枯木、脚印链
│   ├── forest_scatter.gd             ✅ 密林 / 枯立木 / 岩石散布 + add_chunked() 分块 MultiMesh
│   ├── far_terrain_builder.gd        ✅ 远景谷 / 远山 / 远景林
│   ├── spruce_mesh.gd                ✅ 程序化云杉（风向偏冠）
│   ├── prop_meshes.gd                ✅ 程序化枯立木 / 岩石
│   ├── shelter_cutaway_rig.gd        ✅ SDF 剖面四边形 + 几何镜像函数（改 shader 几何须同步）
│   ├── campfire_pot_rig.gd           ✅ 篝火与锅（视觉）
│   ├── wind_particles.gd             ✅ 风雪粒子
│   ├── resource_spawner.gd           ✅ 资源 / 树根 / 立枯木采集点
│   ├── shelter_site.gd               ✅ 庇护所工地 5 阶外观
│   ├── campfire.gd                   ✅ 营火
│   ├── footprints.gd                 ✅ 脚印
│   └── snowfall.gd                   ✅ 傍晚降雪（探针标记由 GameDirector 生成）
├── player/
│   ├── player_controller.gd          ✅ 相机相对移动、探针（阻尼 T1.4 待做）
│   ├── hiker_visual.gd               ✅ 拼装角色（V4 由 Blender .glb 替换）
│   ├── warmth_controller.gd          ✅ 0–100 核心体温
│   └── interaction_controller.gd     ✅ 交互选择与按住进度（挡风检测并入 GameRules 暴露度）
├── components/
│   └── interactable.gd               ✅ 统一交互组件
├── systems/
│   ├── sun_model.gd                  ✅ 真实日轨（纯函数，有测试）
│   ├── weather_controller.gd         ✅ 时钟、太阳驱动、天气信号
│   ├── shelter_builder.gd            ✅ 选址校验（D5）+ 5 阶推进（逻辑）
│   ├── night_simulator.gd            ✅ 6 维可解释结算
│   ├── atmosphere_state.gd              大气唯一数据源（V7）
│   ├── graphics_settings.gd          ✅ 画质档位
│   ├── game_director.gd              ✅ 一局游戏的状态机与编排
│   ├── game_rules.gd                 ✅ 循环纯规则（有测试）
│   ├── build_mode.gd                 ✅ 建造预览与校验
│   ├── ambient_audio.gd              ✅ 程序化音频灰盒
│   ├── inventory.gd                  ✅ 背包
│   └── （生火规则在 GameRules / GameDirector）
└── ui/
    ├── hud_controller.gd             ✅ 环境卡
    ├── hud_warmth.gd                 ✅ 体温卡
    ├── compass_rose.gd               ✅ 随相机旋转的风向罗盘
    ├── world_callouts.gd             ✅ 世界空间引线标签
    ├── shelter_cutaway_panel.gd      ✅ 剖面面板（标注、顶厚尺寸线、气流箭头）
    ├── game_ui.gd                    ✅ 循环 UI（简报 / 提示 / 报告 / 暂停）
    ├── night_report_text.gd          ✅ 英文报告文案（展示层）
    └── （提示文案在 GameRules.tip_for）
```
