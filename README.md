# Winter Shelter Project

> **"Read the Land. Make a Plan. Survive the Night."**

一款聚焦于**环境阅读、雪地工程与严寒过夜**的硬核冬季生存实验游戏。

---

## 核心设计与工程文档 (Lean Design & Technical Docs)

本项目在立项初期**严格拒绝“大而全的 GDD 膨胀”**，仅通过 4 份设计基准文档与 1 份引擎技术规格文档锁定边界与实现路径：

1. [**`VISION.md`**](file:///d:/OneDrive/Learning/Code/Gemini/wild/VISION.md)  
   项目愿景与情绪基调（*Brutal Outside, Cozy Inside*），明确非目标（Non-Goals）与决策过滤器。
2. [**`CORE_GAMEPLAY.md`**](file:///d:/OneDrive/Learning/Code/Gemini/wild/CORE_GAMEPLAY.md)  
   核心循环（9 步法则）、参数身份规范（`[REAL]` / `[GAME]` / `[TUNE]`）、自然衰减、Telescopic Vent、雪洞内禁用明火规则，以及 6 维可解释结算模型。
3. [**`MVP_SNOW_SHELTER.md`**](file:///d:/OneDrive/Learning/Code/Gemini/wild/MVP_SNOW_SHELTER.md)  
   MVP 01 开发范围、连续暮光抉择、12 项具体验收清单，以及 Blockout 唯三验证标准。
4. [**`VISUAL_LANGUAGE.md`**](file:///d:/OneDrive/Learning/Code/Gemini/wild/VISUAL_LANGUAGE.md)  
   45° 正交等距视角（Orthographic 45° ISO）、冷暖对比色彩规则、极简 UI 与 4 阶递进交付模型。
5. [**`ARCHITECTURE_GODOT.md`**](file:///d:/OneDrive/Learning/Code/Gemini/wild/ARCHITECTURE_GODOT.md)  
   Godot 4 引擎技术实现图景：场景节点树、正交等距运动解算、探针与气象总线、6 维可解释 `NightSimulator`。

> **执行入口**：[**`PRODUCTION_PLAN.md`**](file:///d:/OneDrive/Learning/Code/Gemini/wild/PRODUCTION_PLAN.md) —— 依据参考图拆解出的 M0–M4 任务、完成标准、退出闸门与待决策项。

---

## 项目当前阶段与路线图 (Roadmap)

```text
[阶段 0：设计边界与技术规格冻结]  <-- 已完成
        ↓
[阶段 1：Milestone 1 — Snowfield Blockout]
   ├── [x] Godot 4 基础工程骨架就绪 (project.godot, scenes, scripts, resources)
   └── [ ] 核心体验验收 (1. 移动舒适 | 2. 风向可读 | 3. 主动探雪冲动)
        ↓
[阶段 2：Milestone 2 — Playable (探雪与采集闭环)]
        ↓
[阶段 3：Milestone 3 — Systems + UI (风雪粒子与雪洞剖面)]
        ↓
[阶段 4：Milestone 4 — Target Look (落日氛围与垂直切片)]
```

---

## 工程目录结构

```text
wild/
├── project.godot                 # Godot 4 主工程配置
├── icon.svg                      # 项目图标
├── README.md                     # 项目全局索引与进度
├── VISION.md                     # 愿景、设计边界与非目标
├── CORE_GAMEPLAY.md              # 9 步核心循环与 6 维可解释规则
├── MVP_SNOW_SHELTER.md           # MVP 01 范围与 12 项检查清单
├── VISUAL_LANGUAGE.md            # 45° ISO 规范与 4 阶递进模型
├── ARCHITECTURE_GODOT.md         # Godot 4 架构与节点设计
├── design_assets/                # 概念设计与视觉参考
├── snapshots/                    # 各里程碑视觉快照归档
├── resources/                    # 资源实例文件 (.tres)
│   └── default_wind.tres         # 默认西风数据
├── scenes/                       # Godot 场景 (.tscn)
│   ├── main.tscn                 # 主关卡场景
│   ├── world/                    # 地形与植被
│   ├── player/                   # 玩家与探针
│   ├── camera/                   # 45° 正交相机云台
│   └── ui/                       # HUD 与微标签
└── scripts/                      # GDScript 核心逻辑 (.gd)
    ├── main.gd                   # 场景总控
    ├── player/                   # 45° ISO 运动解算
    ├── camera/                   # 相机追踪
    ├── systems/                  # 天气控制器、探针采样、NightSimulator
    ├── ui/                       # HUD 控制器
    └── resources/                # 资源类脚本定义 (WindData, ShelterPreset)
```
