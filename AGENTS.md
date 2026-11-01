# AGENTS.md — Winter Shelter Project (wild)

> **适用范围**：所有在 `wild/` 内写代码、搭场景、改文档的 AI Agent（主控 Agent 与 subagent）。
> **继承**：根目录 [`AGENTS.md`](../AGENTS.md) 与 [`docs/standards/project_documentation_standard.md`](../docs/standards/project_documentation_standard.md)（UTF-8、零硬编码、SSOT、证据优先）。本文件只写本项目特有规则，不复制通用规则。
> **本文件不写当前进度**。现在做什么 → [`CURRENT_STAGE.md`](CURRENT_STAGE.md)。

---

## 1. 项目身份

**Snow Shelter Challenge**（代号 `wild`，标语 `FIND · GATHER · BUILD · SURVIVE`）：冬季荒野中阅读环境 → 选址 → 收集材料 → 建庇护所 → 熬过一夜 → 复盘。
设计支柱：*Read the Land / Make a Plan / Survive the Night*；情绪基调：*Brutal Outside, Cozy Inside*；原则：**Hard ≠ Obscure**（可以失败，但必须知道为什么）。
技术栈：Godot 4.3+ / GDScript / 移轴透视相机（可切正交）/ 6 维可解释 `NightSimulator`。

---

## 2. 文档路由（JIT：只读当前任务需要的）

| 标准角色 | 本项目文件 | 何时读 |
| :--- | :--- | :--- |
| PROJECT_VISION | [`VISION.md`](VISION.md) | 想新增功能 / 判断是否越界时 |
| FEATURES（规则） | [`CORE_GAMEPLAY.md`](CORE_GAMEPLAY.md) | 改任何玩法规则、结算、资源、火、庇护所 |
| FEATURES（MVP 验收） | [`MVP_SNOW_SHELTER.md`](MVP_SNOW_SHELTER.md) | 判断某项是否属于 MVP |
| 视觉规范 | [`VISUAL_LANGUAGE.md`](VISUAL_LANGUAGE.md) | 相机、光照、天空、UI、资产 |
| ARCHITECTURE + COMPONENT_MAP | [`ARCHITECTURE_GODOT.md`](ARCHITECTURE_GODOT.md) | 新增节点 / 脚本 / 资源类型 |
| DEVELOPMENT_ROUTE + DECISIONS | [`PRODUCTION_PLAN.md`](PRODUCTION_PLAN.md)（§3 决策、§4 里程碑与任务 ID） | 查任务定义、完成标准、闸门 |
| CURRENT_STAGE | [`CURRENT_STAGE.md`](CURRENT_STAGE.md) | **每次开工必读**：当前可派发任务、依赖、任务卡 |
| `[REAL]` 依据 | [`research/SNOW_SHELTER_RESEARCH.md`](research/SNOW_SHELTER_RESEARCH.md) | 写或改带 `[REAL]` 的规则 |
| Demand backlog | [`todo.md`](todo.md) | 记录新需求 / Bug / 需要人做的事 |
| 进度投影 | [`progress.yaml`](progress.yaml) | 只在事实对齐时更新（见 §6） |
| 参考（非真相源） | `references/`、`design_assets/` | 仅按需查阅；Web 原型 `references/20260919_fable5_mvp` 已冻结 |

---

## 3. 设计红线

1. **Godot 是唯一生产线**。Web 原型只作参考与调参沙盒，不再加功能。移植其规则时：雪深门槛按 D5 改；篝火"整夜加温"按 D2 改。
2. **参数身份**：文档与 `tuning.tres` 中的每个规则或数值必须标 `[REAL]`（有现实依据，出处在 `research/`）/ `[GAME]`（为可玩性抽象）/ `[TUNE]`（临时平衡值）。不得把 `[TUNE]` 写成物理事实。
3. **零硬编码**：物理、环境、平衡参数只能来自 `Resource`（`WindData`、`Tuning` 等 `@export`）。只有纯几何/数学常量允许留在脚本中，且要注释说明。
4. **火与庇护所**（D2 / D3）：雪庇护所内禁止明火（烛灯只做醒着时照明）；雪庇护所外可生睡前篝火，但不整夜供热；倒棚 + 反射火是非雪庇护所方案，需备足通宵燃料；封闭帐篷/泥屋/石屋 + 烟囱属于 MVP 之后。**Telescopic Vent（雪庇护所）与 Stove Pipe（火庇护所）是两种不同物品**。
5. **雪深区间**（D5，`[REAL]`→`[TUNE]` 落地）：< 0.3 m 只能非雪庇护所；0.3–0.9 m 砌墙雪沟；≈1.0 m 标准雪沟；≥ 1.5 m 雪洞；≥ 2.0 m 高床雪洞；顶厚下限约 0.3 m。
6. **结算可解释**：`NightSimulator` 输出 6 项分数 + 每项一句归因 + 结论；不得引入玩家无法从报告中理解的隐藏惩罚。
7. **夜里不会无声地死去**（D14，依据 Outdoor Boys："You don't freeze to death without waking up at least once."）：玩家在严重失温之前一定至少醒来一次、并有机会行动；结局由整夜体温曲线决定，不用会让整局翻转的硬阈值。
8. **范围**：新功能先过 `VISION.md` 决策过滤器；每个里程碑的"不做"清单优先于任何 Agent 的自发扩展。

---

## 4. 工程红线

1. **相机**（2026-11-01 用户拍板修订：以 `snapshots/snapshot_00_visual_north_star.png` 的表现力为准）：默认 **移轴透视（TILT_SHIFT）**——光轴接近水平（竖线不汇聚）、镜头下移看地面、天际线与落日在画面上沿；偏航 **135°**（镜头朝西南 = 1 月午后太阳真实方位，越过迎风脊线看远景）。**太阳走真实日轨**（`SunModel` + Tuning `Sun` 组：纬度 / 赤纬 / 正午），影子长→短→长就是玩家的时钟，不得为构图把太阳挪到假方位。挡住玩家的树用 `snow_cover.gdshader` 的 `occlusion_fade` 镂空。正交等距保留为备用模式（**V** 键切换）。玩家输入与罗盘一律从相机朝向推导，**不得再写死偏航角**。不得裁切角色与雪坡。Godot 天空背景不认 `frustum_offset`，移轴参数需推给 `sky_backdrop.gdshader`（见 `IsometricCameraRig._push_lens`）。
2. **UTF-8**：所有 `.gd` / `.tscn` / `.tres` / `.md` / `.yaml` 用 UTF-8（无 BOM）。中文文件只用编辑工具或 Python/Node 修改，**禁止** PowerShell `Get-Content`/`Set-Content`/`-replace`。
3. **场景文件串行**：同一时刻只有一个 Agent 写某个 `.tscn`；`scenes/main.tscn` 只由主控 Agent 合并。新增功能优先做成独立子场景，再由主控接入。
4. **不手写 uid**：新建 `.tscn`/`.tres` 时 `ext_resource` 用 `path=` 引用，不编造 `uid://`；由 Godot 导入时生成。
5. **测试**：纯逻辑（`NightSimulator`、`SnowField`、校验函数）必须有 headless 测试，放 `tests/`，入口 `tests/run_all.gd`（`extends SceneTree`，失败时 `quit(1)`）。
6. **禁止**：安装软件、联网下载、重型构建，除非用户明确授权；在 OneDrive 目录内 `npm install`。

### Godot 命令（2026-11-01 已在 Linux 本机校准：Godot 4.3 stable，`/home/bobbik/.local/bin/godot`）

- 新增带 `class_name` 的脚本后，**先跑一次 `--import`**，否则其它脚本会报 "Identifier not declared"。
- 截图需要真实显示（或 Xvfb）；headless 无法渲染。截图 / 测试走 `-s` 脚本模式时 `[shader_globals]` 不生效，不要依赖 global uniform（见 ARCHITECTURE §3.7）。
- 视觉改动的回执要附 FPS（`RenderingServer.viewport_get_measured_render_time_gpu`）。

```bash
# 导入 / 生成 .godot 缓存（首次打开工程）
godot --headless --path . --import
# 单脚本语法检查
godot --headless --path . --check-only -s res://scripts/systems/night_simulator.gd
# 跑全部逻辑测试（退出码非 0 即失败）
godot --headless --path . -s res://tests/run_all.gd
# 截图（headless 无法渲染，必须窗口模式）
godot --path . -s res://tools/capture_snapshot.gd -- --out=snapshots/<name>.png
```

---

## 5. 验证诚实（强制）

任务状态只有四种，**Agent 自报不等于完成**：

| 状态 | 含义 |
| :--- | :--- |
| `todo` | 未开始 |
| `written-unverified` | 代码/文档已写，但没有在 Godot 中运行验证（本机未装 Godot 时的上限） |
| `done` | 完成标准逐条有证据：测试输出、零报错日志、截图路径 |
| `blocked` | 需要人（安装、拍板、试玩）或外部条件，注明阻塞原因 |
| `superseded` | 被新决策替代、不再执行（注明替代任务，如 T1.3 → V9） |

- 没跑过 Godot 的代码，报告里必须写"未运行"。不得写"应该能用""已修复"。
- 证据存放：测试输出与截图路径写进任务回执；需要长期保留的放 `snapshots/` 或 `playtests/`。

---

## 6. Subagent 协作协议

**角色**（由主控 Agent 派发，主控对结果负责）：

| 角色 | 职责 | 可写范围 |
| :--- | :--- | :--- |
| 主控 Orchestrator | 读 `CURRENT_STAGE.md`，发任务卡，合并 `main.tscn`，审回执，更新 `progress.yaml`、提交 git | 全部 |
| `godot-dev` | 按任务卡实现 | 仅任务卡 `Files` 列出的文件 |
| `verifier` | 独立对照完成标准验证：跑测试、看日志、截图并检查 | `tests/`、`snapshots/`、回执；不改实现 |
| `research` | 查资料，为 `[REAL]` 规则补出处 | `research/` |

**任务卡**（一次一张，格式见 `CURRENT_STAGE.md` §4）必须包含：Task ID、Read first、Files（可写范围）、Depends、Done when、Do NOT、Needs Godot?。

**回执**（subagent 结束时返回）：

```text
Task:      T0.6
Status:    written-unverified | done | blocked
Changed:   文件列表
Evidence:  命令 + 输出摘要 / 截图路径 / "未运行：原因"
Deviations: 与任务卡不一致之处及理由
Open:      未完成项、发现的新问题（主控决定是否进 todo.md）
```

**主控收尾**：审回执 → 需要时派 `verifier` → 只有证据齐全才把 `progress.yaml` 改为 `done` → 规则变化同步回对应设计文档（不新建平行文档）。

---

## 7. Git

- 提交信息：`[wild] <描述>`，一个任务一个提交为宜；只 `git add` 本任务文件。
- 不提交：`references/`（外部与历史材料）、`.godot/`、构建产物。
- 里程碑完成：git tag（`m1-blockout` 等）+ `snapshots/snapshot_0N_*.png` + `playtests/PT0N.md`。
