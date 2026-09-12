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

### 3.4 6 维可解释夜间模拟 (Night Review System)
纯逻辑无状态评估器 `NightSimulator.gd`，输入雪洞几何与施工指标，产出 6 项 0-100 分及自然语言归因复盘：

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

---

## 4. 四阶段开发执行路径 (Godot Milestones)

- [x] **Milestone 1: Blockout 工程骨架搭建就绪**
  - 已建立 `project.godot`、标准目录、CSG 灰模地形、CharacterBody3D 45° 屏幕坐标平滑移动、45° 正交相机云台与探针测深反馈。
- [ ] **Milestone 1: Blockout 核心体验验收 (唯三指标)**
  - 1. 角色在 45° ISO 雪地上移动是否舒服顺手？
  - 2. 风向和风势能否完全从环境画面（吹雪、树木）中直观读出来？
  - 3. 玩家进入地图后，是否会出于本能想去某个背风雪坡扎下第一根 probe？
- [ ] **Milestone 2: Playable (核心交互闭环)**
  - 立枯木识别与 `E` 键砍柴、树皮与松针垫层收集、在满足 $\ge 1.5\text{m}$ 雪深坡面放置预设雪洞。
- [ ] **Milestone 3: Systems + UI (气象与剖面切削)**
  - 西风 GPUParticles3D 粒子、雪洞 Cutaway 剖面视图、"Spend the Night" 结算弹窗与 6 维报告展示。
- [ ] **Milestone 4: Target Look (垂直切片)**
  - 材质打磨、雪地脚印 displacement、低角度落日金晖体积感、环境音效集成。
