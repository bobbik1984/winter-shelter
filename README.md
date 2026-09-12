# Winter Shelter Project

> **"Read the Land. Make a Plan. Survive the Night."**

一款聚焦于**环境阅读、雪地工程与严寒过夜**的硬核冬季生存实验游戏。

---

## 核心设计文档 (Lean Design Docs)

本项目在立项初期**严格拒绝“大而全的 GDD 膨胀”**，仅通过 4 份短小精悍的核心文档锁定边界与设计准则：

1. [**VISION.md**](file:///d:/OneDrive/Learning/Code/Gemini/wild/VISION.md)  
   项目愿景与情绪基调（*Brutal Outside, Cozy Inside*），明确非目标（Non-Goals）与决策过滤器。
2. [**CORE_GAMEPLAY.md**](file:///d:/OneDrive/Learning/Code/Gemini/wild/CORE_GAMEPLAY.md)  
   核心循环（9 步法则）、系统环境变量、初始资源与工具、三大雪洞形态，以及 *Hard ≠ Obscure* 原则。
3. [**MVP_SNOW_SHELTER.md**](file:///d:/OneDrive/Learning/Code/Gemini/wild/MVP_SNOW_SHELTER.md)  
   MVP 01 开发范围与 12 项具体验收标准（80–120m 紧凑地图，10–20 分钟单局验证循环）。
4. [**VISUAL_LANGUAGE.md**](file:///d:/OneDrive/Learning/Code/Gemini/wild/VISUAL_LANGUAGE.md)  
   45° 正交等距视角（Orthographic 45° ISO）、冷暖对比色彩规则、极简 UI 与 **4 阶递进交付体系**。
5. [**ARCHITECTURE_GODOT.md**](file:///d:/OneDrive/Learning/Code/Gemini/wild/ARCHITECTURE_GODOT.md)  
   Godot 4 引擎技术实现图景：场景节点树、正交等距输入解算、探针与气象总线、夜间热力学模拟器。

---

## 项目当前阶段

```text
[阶段 0：设计边界与技术规格冻结]  <-- 已完成
        ↓
[阶段 1：Milestone 1 — Snowfield Blockout]  <-- 当前已完成工程骨架搭建 (可直接用 Godot 4 打开并运行)
        ↓
[阶段 2：Milestone 2 — Playable (探雪与采集闭环)]
        ↓
[阶段 3：Milestone 3 — Systems + UI (风雪粒子与雪洞剖面)]
        ↓
[阶段 4：Milestone 4 — Target Look (落日氛围与垂直切片)]
```

---

## 目录结构

```text
wild/
├── project.godot                 # Godot 4 主工程配置
├── icon.svg                      # 项目图标
├── README.md                     # 项目全局索引与进度
├── VISION.md                     # 愿景、设计边界与非目标
├── CORE_GAMEPLAY.md              # 9 步核心循环与物理参数
├── MVP_SNOW_SHELTER.md           # MVP 01 范围与 12 项检查清单
├── VISUAL_LANGUAGE.md            # 45° ISO 规范与 4 阶递进模型
├── ARCHITECTURE_GODOT.md         # Godot 4 架构与节点设计
├── design_assets/                # 概念设计与视觉参考
├── snapshots/                    # 各里程碑视觉快照归档
├── scenes/                       # Godot 场景
│   ├── main.tscn                 # 主关卡场景
│   ├── world/                    # 地形与植被
│   ├── player/                   # 玩家与探针
│   ├── camera/                   # 45° 正交相机云台
│   └── ui/                       # HUD 与微标签
└── scripts/                      # GDScript 核心逻辑
    ├── main.gd                   # 场景总控
    ├── player/                   # 45° ISO 运动解算
    ├── camera/                   # 相机追踪
    ├── systems/                  # 天气、探针、夜间热力学模拟
    ├── ui/                       # HUD 控制器
    └── resources/                # 资源类定义
```

