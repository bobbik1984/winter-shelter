# Winter Shelter Project

> **"Read the Land. Make a Plan. Survive the Night."**  ·  English quick start: [`README_EN.md`](README_EN.md)

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
4. [**`VISUAL_LANGUAGE.md`**](VISUAL_LANGUAGE.md)  
   移轴透视相机（D8）、太阳就是时钟（D9）、冷暖对比色彩、自动积雪资产规则、极简 UI 与 4 阶递进交付模型。
5. [**`ARCHITECTURE_GODOT.md`**](ARCHITECTURE_GODOT.md)  
   Godot 4.3 实现图景：节点树、相机 / 太阳 / 天空子系统、程序化植被与性能约定、已知引擎坑、6 维可解释 `NightSimulator`。

> **路线**：[**`PRODUCTION_PLAN.md`**](PRODUCTION_PLAN.md) —— M0–M4 + 视觉先行轨道 V、完成标准、退出闸门与决策记录（D1–D11）。

---

## 现在在做什么

| 想知道 | 看这里 |
| :--- | :--- |
| 当前里程碑、可派发任务、依赖与任务卡 | [`CURRENT_STAGE.md`](file:///d:/OneDrive/Learning/Code/Gemini/wild/CURRENT_STAGE.md) |
| 各任务状态 | [`progress.yaml`](file:///d:/OneDrive/Learning/Code/Gemini/wild/progress.yaml) |
| 需要人来做的事、待判断事项 | [`todo.md`](file:///d:/OneDrive/Learning/Code/Gemini/wild/todo.md) |
| Agent 工作规则 | [`AGENTS.md`](file:///d:/OneDrive/Learning/Code/Gemini/wild/AGENTS.md) |

路线：M0 对齐与能跑 → M1 Blockout → M2 Playable → M3 Systems + UI → M4 Target Look；视觉先行轨道 V 并行（2026-11）。

**当前（2026-11-01）**：视觉三轮在分支 `claude/visual-pass-1`（待 F5 验证与合并）；下一步 V1–V4，然后回到 M1 剩余任务与 M2 交互循环。最新画面：[`snapshots/visual_pass3_1420.png`](snapshots/visual_pass3_1420.png)，日轨对比：[`snapshots/visual_pass3_sun_cycle.png`](snapshots/visual_pass3_sun_cycle.png)。

**Godot 版本**：4.3 stable（Forward+ / Vulkan）。

**常用命令**（工程根目录）：

```bash
godot --headless --path . --import                       # 新增 class_name 后必须先跑
tools/ci.sh [--quick]                                     # 一键回归：逻辑测试 + 输入冒烟 + 机器人平衡 + 模糊测试（自动备份 / 恢复 user:// 存档）
godot --headless --path . -s res://tests/run_all.gd      # 全部逻辑测试，非 0 退出即失败
godot --path . -s res://tools/capture_snapshot.gd -- --out=snapshots/<name>.png   # 实机截图（需窗口 / 显示）
tools/build.sh [linux|windows|all]                      # 导出独立版本到 build/（需先安装 4.3.stable 导出模板）
godot --path . -s res://tools/input_smoke_test.gd          # 真实输入冒烟测试（15 项，开始 → 报告）
godot --path . -s res://tools/fuzz_test.gd -- --seconds=90 --seed=1   # 随机输入模糊测试（不崩溃 / 状态机合法）
godot --path . -s res://tools/playtest_bot.gd -- --s=deep --valley=13  # 策略机器人（good/deep/quick/twovent/wind/late/trench/leanto_short/leanto_full/none）
```

运行时按键：**←/→** 选章 · **↑/↓** 选阶 · **N**（简报）换图 · **Enter** 开始（报告页 = 下一关）· WASD 移动 · 按住 Space 探针 · 按住 **E** 采集 / 建造 / 喝热水 · **B** 建造模式（Tab 换类型、R 转入口、T 顶厚、2 通风管、E 放置）· **F** 生火 / 添柴 · **N** 睡觉 · **H** 野外手册 · **L** English / 中文 · **Esc** 暂停 · **V** 移轴 / 正交 · 滚轮 推拉 · **F10** 画质 · **F11** 全屏 · **M** 静音 · **-** / **=** 界面大小 · **F3** 雪深热力图（开发）· **F9** 按住辅助（轻点即可探雪 / 干活 / 生火）。

存档：画质与语言 `user://settings.cfg`，每种庇护所的最好一夜 `user://records.cfg`（Linux：`~/.local/share/godot/app_userdata/Snow Shelter Challenge/`）。

**手柄**：左摇杆移动 · A 交互 / 放置 · X 探针 · Y 建造 · B 生火（建造中 = 取消）· Start 开始 / 暂停 / 重开 · Back 手册 · LB / RB 旋转入口 / 换类型 · 十字键 ↑ 顶厚 ↓ 通风管 → 睡觉 ← 语言。

**章节 × 阶（D12 / D13）**：5 章 × 10 阶（第 1 阶易 → 第 10 阶难），通关后开放自由模式。每章一个课题、一类地形（脊线山谷 / 平坦盆地 / 湖岸 / 悬崖带）和一套装备——1 读风向挖雪洞（深雪、全套装备）· 2 深雪藏在少数地方，先探再挖 · 3 风倒区、天光少：树根盘是半个庇护所（倒棚 + 火）· 4 开阔平地 / 湖岸、雪浅：挖雪沟 · 5 暴风雪、无保暖层：自己判断。每阶默认固定一张图，简报按 **N** 换新图；**←/→** 选章、**↑/↓** 选阶；结局 COLD / SAFE 开放下一阶，通过第 5 阶开放下一章；报告页 **Enter** = 下一阶、**R** = 同一个地方再来。用某种庇护所熬过一夜即学会它（新玩家只会雪沟）。开发参数（`--` 之后）：`--level=章|free`、`--stage=阶`、`--seed=S`、`--unlock-all`、`--shape=basin|lakeshore|cliff_band`。

**一局怎么玩**：简报页按 Enter 开始；自由模式里按 2 = 全天模式（10:00 开局，看影子先变短再变长）。自由模式每次重开换一个山谷（4 个：同样的迎风坡—脊线—背风坡结构，起伏与深雪分布不同）。标准模式 14:20 开局，16:18 日落（看影子长度判断剩余日照），17:50 强制入夜。探测深雪 → 收集干柴 / 桦树皮 / 垫层 → 选址建庇护所（高床雪洞 / 基础雪洞 / 雪沟 / 树根倒棚）→ 入夜后得到 6 维报告与"要记住的一件事"。

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
├── VISUAL_LANGUAGE.md            # 相机 / 太阳 / 色彩 / 资产规则与 4 阶递进模型
├── ARCHITECTURE_GODOT.md         # Godot 4 架构与节点设计
├── design_assets/                # 概念设计与视觉参考
├── snapshots/                    # 各里程碑视觉快照归档
├── resources/                    # 资源实例文件 (.tres)
│   ├── tuning.tres               # 唯一调参源（SSOT）
│   └── default_wind.tres         # 默认西风数据（direction = 风的来向）
├── shaders/                      # snow_terrain / snow_cover / sky_backdrop / cutaway_sdf
├── tests/                        # headless 逻辑测试（run_all.gd 入口）
├── tools/                        # capture_snapshot.gd 截图工具
├── scenes/                       # Godot 场景 (.tscn)
│   ├── main.tscn                 # 主关卡场景
│   ├── world/                    # 地形与植被
│   ├── player/                   # 玩家与探针
│   ├── camera/                   # 相机云台（移轴 / 正交）
│   └── ui/                       # HUD 与微标签
└── scripts/                      # GDScript 核心逻辑 (.gd)
    ├── main.gd                   # 场景总控
    ├── player/                   # 相机相对移动、体温、拼装角色
    ├── camera/                   # 相机云台
    ├── world/                    # 地形、雪深、植被散布、远景、程序化网格、剖面
    ├── systems/                  # SunModel、天气 / 时钟、ShelterBuilder、NightSimulator
    ├── ui/                       # HUD、罗盘、世界标签、剖面面板
    └── resources/                # Tuning、WindData、ShelterPreset
```
