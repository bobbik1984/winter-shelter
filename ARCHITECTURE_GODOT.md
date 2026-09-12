# ARCHITECTURE_GODOT.md — Godot 4 技术架构与实现图景

> **引擎版本定位**：Godot 4.x (Forward+ / Mobile)  
> **核心渲染模型**：Orthographic 45° Isometric 3D + 2D CanvasLayer HUD

---

## 1. 工程文件目录规范 (Project Structure)

```text
wild/
├── project.godot                     # Godot 4 主工程配置文件
├── scenes/                           # 场景文件
│   ├── main.tscn                     # 顶层集成场景 (主关卡)
│   ├── world/
│   │   ├── blockout_terrain.tscn     # 灰模地形 (CSG 80-120m 斜坡与背风区)
│   │   ├── tree_spruce.tscn          # 灰模针叶树
│   │   └── tree_deadwood.tscn        # 立枯木与采集判定
│   ├── player/
│   │   └── player.tscn               # 玩家实体 (CharacterBody3D + 探针)
│   ├── camera/
│   │   └── camera_rig.tscn           # 45° 正交相机云台 (平滑跟随)
│   └── ui/
│       ├── hud.tscn                  # 右上角气象卡片 + 右下角风向罗盘
│       └── world_label.tscn          # 3D 投射到 2D 的微标签
├── scripts/                          # GDScript 核心逻辑
│   ├── player/
│   │   └── player_controller.gd      # 45° ISO 运动解算与输入
│   ├── camera/
│   │   └── isometric_camera_rig.gd   # 正交镜头平滑追踪
│   ├── systems/
│   │   ├── weather_controller.gd     # 时间、落日、风向控制器
│   │   ├── probe_system.gd           # 探针测深与地形采样
│   │   └── night_simulator.gd        # 夜间热力学判定与报告生成器
│   └── ui/
│       ├── hud_controller.gd         # HUD 数据驱动刷新
│       └── world_label_manager.gd    # 世界空间标签投射管理
├── resources/                        # 自定义 Resource 定义与预设
│   ├── wind_data.gd                  # 气象数据类
│   ├── default_wind.tres             # 默认西风资源
│   └── shelter_preset.gd             # 雪洞预设数据结构
└── shaders/                          # 着色器
    └── wind_sway.gdshader            # 树木随风摇摆着色器
```

---

## 2. 场景与节点架构 (Node Tree Hierarchy)

### `res://scenes/main.tscn` 顶层节点结构：

```text
Main (Node3D) [main.gd]
├── WorldEnvironment (环境光: 极寒蓝冷色调, 启用法线与粗糙度)
├── DirectionalLight3D (太阳光: 低角度 18° 斜射, 暖金橙色, 开启硬阴影)
│
├── World (Node3D)
│   ├── BlockoutTerrain (Node3D) [blockout_terrain.tscn]
│   │   ├── BaseGround (CSGBox3D: 100m x 2m x 100m)
│   │   ├── SnowSlope (CSGPolygon3D / 斜坡 30°: 适宜雪洞选址)
│   │   ├── LeewardDrift (CSGBox3D / 背风深积雪堆: 标定雪深 2.2m)
│   │   └── FlatClearing (平缓区: 标定雪深 0.6m)
│   │
│   ├── Vegetation (Node3D)
│   │   ├── Conifers (多实例针叶树，迎风倾斜)
│   │   └── StandingDeadwoods (直立枯木，挂载 HarvestableComponent)
│   │
│   └── WeatherController (Node) [weather_controller.gd]
│       ├── WindData (Resource)
│       └── BlizzardParticles (GPUParticles3D: 迎风水平飞雪)
│
├── Player (CharacterBody3D) [player.tscn]
│   ├── CollisionShape3D (CapsuleShape3D)
│   ├── MeshInstance3D (测试胶囊人 / 低模求生者)
│   ├── AvalancheProbe (RayCast3D: 向下探测深度与碰撞组)
│   └── InteractionArea (Area3D: 枯木与建造点扫描)
│
├── CameraRig (Node3D) [camera_rig.tscn]
│   └── Camera3D (Projection=Orthogonal, Size=18m, Rot=[-35.264°, 45°, 0°])
│
└── UI (CanvasLayer) [hud.tscn]
    ├── EnvironmentCard (MarginContainer: 右上角气象与日落时间)
    ├── WindCompass (Control: 右下角风向罗盘)
    ├── WorldLabels (Control: 3D 世界坐标标签映射容器)
    └── NightReportModal (Control: 结算报告面板)
```

---

## 3. 核心子系统技术设计 (System Specifications)

### 3.1 45° 正交相机云台 (Isometric Camera Rig)
- **数学对齐**：
  - 水平旋转（Yaw）：固定 `45.0°`（镜头对角对齐世界网格对角线）；
  - 俯角（Pitch）：默认 `-35.264°`（经典 True Isometric）或 `-38.0°`（视感微调）；
  - 投影模式：`Camera3D.PROJECTION_ORTHOGONAL`；
  - 视口尺寸（Size）：`18.0`（视野覆盖约 25m × 15m 的局部工作区）。
- **坐标系转换（ISO Movement Mapping）**：
  - 在 45° 相机下，屏幕正上方（W 键）对应世界坐标的 `(-1, 0, -1).normalized()`；
  - 屏幕正右方（D 键）对应世界坐标的 `(1, 0, -1).normalized()`；
  - 角色运动向量必须乘以相机的水平偏转矩阵，确保操作方向完全符合玩家屏幕直觉。

### 3.2 探针测深系统 (Snowpack Probing System)
- **采样方案**：
  - 地形网格在特定区域预设积雪深度值。
  - 在 Blockout 阶段，采用 **Meta 属性 / 区域 Area3D 标签**：
    - 深雪坡区域设置 `metadata["snow_depth"] = 2.1`；
    - 浅雪平原设置 `metadata["snow_depth"] = 0.5`；
  - 探针向落点发射射线：
    ```gdscript
    var collider = raycast.get_collider()
    var depth = collider.get_meta("snow_depth", 0.8) # 默认 0.8m
    probe_sampled.emit(hit_position, depth)
    ```
  - UI 接收到信号后，在 `hit_position` 处生成世界微标签，显示 `Good depth: 2.1m`。

### 3.3 枯木识别与采集组件 (Harvestable Component)
- 树木分为 `Spruce`（活针叶树）与 `StandingDeadwood`（立枯木）。
- 靠近立枯木触发 `Area3D` 检测：
  - 激活高亮描边着色器（微弱浅橙色）；
  - 屏幕弹出微标签：`Deadwood (Press E to Harvest)`；
  - 耗时 15 游戏分钟采集，背包获得 `Firewood`。

### 3.4 气象与时间流逝 (Weather & Daylight Controller)
- **时间步进**：
  - 开场时间：`14:20`（游戏内时间戳：`14 * 60 + 20 = 860` 分钟）；
  - 日落时间：`16:18`（`16 * 60 + 18 = 978` 分钟）；
  - 现实时间 1 秒 = 游戏内 12 秒（一局 10 分钟现实时间相当于游戏内 120 分钟）；
- **光照响应**：
  - `DirectionalLight3D` 旋转随时间降低，光照颜色从 `Color(1.0, 0.95, 0.9)` 渐变过渡至落日金红 `Color(1.0, 0.5, 0.2)`，最后降至暗蓝夜色。

### 3.5 夜间热力学模拟器 (Night Simulator)
纯逻辑无状态计算器类，点击“Spend the Night”时计算存活指标：

```gdscript
class_name NightSimulator

static func evaluate_shelter(shelter_type: String, entrance_wind_angle: float, has_cold_pit: bool, has_vent: bool, insulation_layers: int) -> Dictionary:
    var base_temp = -24.0 # 外部极端温度
    var inside_temp = 0.0
    var oxygen_rating = 1.0 # 1.0 良好, 0.0 窒息
    var is_survived = true
    var death_reason = ""
    
    # 1. 入口迎风判定
    if abs(entrance_wind_angle) < 45.0:
        inside_temp -= 12.0 # 强风直接倒灌
    
    # 2. 结构类型与冷气槽
    if shelter_type == "RaisedCave":
        inside_temp += (18.0 if has_cold_pit else 10.0)
    elif shelter_type == "BasicCave":
        inside_temp += 10.0
    elif shelter_type == "SnowTrench":
        inside_temp += 6.0
        
    # 3. 垫层隔热
    if insulation_layers <= 0:
        inside_temp -= 8.0 # 地面直接导热失温
        
    # 4. 通气孔判定
    if not has_vent:
        oxygen_rating = 0.0
        is_survived = false
        death_reason = "Suffocation: Snow cave completely sealed without air vent."
    elif inside_temp < -15.0:
        is_survived = false
        death_reason = "Severe Hypothermia: Cold air infiltration or lack of ground insulation."
        
    return {
        "survived": is_survived,
        "inside_temp": inside_temp,
        "oxygen": oxygen_rating,
        "reason": death_reason
    }
```

---

## 4. 四阶段开发执行路径 (Godot Milestones)

- [ ] **Milestone 1: Blockout (当前目标)**
  - 建立 `project.godot`、标准目录、CSG 灰模地形、CharacterBody3D 45° 移动与平滑正交相机。
- [ ] **Milestone 2: Playable**
  - 探针探雪、立枯木识别采集、预设雪洞位置放置。
- [ ] **Milestone 3: Systems + UI**
  - 风雪粒子系统、落日渐变光影、雪洞剖面透视、夜间报告弹窗。
- [ ] **Milestone 4: Target Look**
  - 材质打磨、雪地脚印效果、音效集成，达成垂直切片。
