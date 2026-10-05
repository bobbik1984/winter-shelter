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

> **路线**：[**`PRODUCTION_PLAN.md`**](file:///d:/OneDrive/Learning/Code/Gemini/wild/PRODUCTION_PLAN.md) —— M0–M4 任务、完成标准、退出闸门与决策记录。

---

## 现在在做什么

| 想知道 | 看这里 |
| :--- | :--- |
| 当前里程碑、可派发任务、依赖与任务卡 | [`CURRENT_STAGE.md`](file:///d:/OneDrive/Learning/Code/Gemini/wild/CURRENT_STAGE.md) |
| 各任务状态 | [`progress.yaml`](file:///d:/OneDrive/Learning/Code/Gemini/wild/progress.yaml) |
| 需要人来做的事、待判断事项 | [`todo.md`](file:///d:/OneDrive/Learning/Code/Gemini/wild/todo.md) |
| Agent 工作规则 | [`AGENTS.md`](file:///d:/OneDrive/Learning/Code/Gemini/wild/AGENTS.md) |

路线：M0 对齐与能跑 → M1 Blockout → M2 Playable → M3 Systems + UI → M4 Target Look。

**Godot 版本**：尚未安装（T0.1 完成后写入）。

---

## 工程目录结构

```text
wild/
├── project.godot                 # Godot 4 主工程配置
├── icon.svg                      # 项目图标
├── README.md                     # 项目入口索引
├── AGENTS.md                     # Agent 工作规则与 subagent 协议
├── CURRENT_STAGE.md              # 当前施工合同（任务依赖、任务卡、闸门）
├── PRODUCTION_PLAN.md            # M0–M4 路线、任务 ID 与决策记录
├── todo.md                       # 需求池与需要人来做的事
├── progress.yaml                 # 机器可读进度投影
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
