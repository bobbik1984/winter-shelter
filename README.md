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
   45° 正交等距视角（Orthographic 45° ISO）、冷暖对比色彩规则、极简 UI 与 **5 阶段视觉里程碑制度（Snapshot System）**。

---

## 项目当前阶段

```text
[阶段 0：文档冻结]  <-- 当前已完成
        ↓
[阶段 1：Prototype 0 — Snowfield Blockout]  <-- 下一步
        ↓
[阶段 2：Snapshot 02 — Environmental Reading]
        ↓
[阶段 3：Snapshot 03 — Shelter & Cutaway]
        ↓
[阶段 4：Snapshot 04 — First Night & Report]
        ↓
[阶段 5：Snapshot 05 — Target Prototype]
```

---

## 目录结构

```text
wild/
├── README.md                 # 项目索引与当前开发状态
├── VISION.md                 # 愿景、设计边界与非目标
├── CORE_GAMEPLAY.md          # 核心循环与底层物理/环境参数
├── MVP_SNOW_SHELTER.md       # MVP 01 范围与 12 项检查清单
├── VISUAL_LANGUAGE.md        # 45° ISO、画面语言与 Snapshot 规范
├── design_assets/            # 概念设计与视觉参考
│   └── Codex Image...png     # Visual North Star v0.1
└── snapshots/                # 各里程碑视觉快照归档
    └── README.md
```
