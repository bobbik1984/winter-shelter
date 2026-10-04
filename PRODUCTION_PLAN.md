# PRODUCTION_PLAN.md — Snow Shelter Challenge 生产计划 v1.0

> **依据**：[参考图 North Star v0.1](design_assets/Codex%20Image%20Sep%2012,%202026,%2003_30_15%20PM.png) · 4 份设计文档 · `ARCHITECTURE_GODOT.md` · `references/20260919_fable5_mvp`（Web 原型）
> **原则**：同一个游戏，逐步提高保真度（参考图底栏 *Same Game, Increasing Fidelity*）。
> **每个里程碑结束必须产出**：① 一个可运行版本 ② 一张快照 ③ 一份试玩记录。
> 本文所有工期均为 `[TUNE]` 估算，按单人开发计。

---

## 0. 一页摘要

**最终产物**：一个 Godot 4 垂直切片。单局 10–20 分钟，约 100 m × 100 m 地图，完整走完 *观察 → 探测 → 采集 → 建造 → 过夜 → 复盘*，画面达到参考图第 4 格 "Target Look"。

**现状（2026-10-04）**

| 资产 | 状态 | 说明 |
| :--- | :--- | :--- |
| 设计文档 v0.2 | ✅ 冻结约 80% | VISION / CORE_GAMEPLAY / MVP / VISUAL / ARCHITECTURE |
| Godot 工程骨架 | ⚠️ 已写代码，**从未在 Godot 中打开运行过** | 本机未找到 Godot。代码审阅发现：相机直接放在玩家位置、没有向后偏移，正交相机的近裁剪面很可能切掉角色和身后地形（推断，未验证） |
| Web 原型 `fable5_mvp` | ⚠️ 代码上是完整循环，**本次未能验证构建** | 简报→探测→采集→建造→生火→过夜→6 维报告都有实现。`npm ci` 因网络/代理失败，所以没有跑过类型检查和构建 |

**路线**：M0 对齐 → M1 Blockout → M2 Playable → M3 Systems+UI → M4 Target Look，合计约 **43–44 个专注工作日**。

**开工前需要你拍板 7 个决策**（§3），其中 D2（木头和火的用途）和 D5（雪深门槛）会直接影响数值和代码。

---

## 1. 参考图拆解：这张图承诺了什么

| # | 图中元素 | 对应系统 / 资产 | 首次出现 | 达到图中水准 |
| :-- | :--- | :--- | :--- | :--- |
| 1 | 标题 *SNOW SHELTER CHALLENGE · FIND · GATHER · BUILD · SURVIVE* | 标题画面 / 开场简报 | M2（纯文字简报） | M4 |
| 2 | ISO 雪坡主画面（迎风坡、脊线、林缘、岩石） | 地形 + 植被 | M1 灰模 | M4 |
| 3 | 角色（红背包、探针、身后脚印） | 玩家 | M1 胶囊 | M4（脚印 M4） |
| 4 | `Good depth ~2.1 m` | 探针读数世界标签 | M1 | M3 样式 |
| 5 | `Deeper snow — Ideal for shelter` | 选址标记（见 D4） | M2 | M3 |
| 6 | `Deadwood — Harvest for fuel` + 淡橙圈 | 交互高亮 / 采集 | M2 | M3 |
| 7 | 环境卡 `Jan 14 14:20 · Sunset 16:18 · −17°C · W 32 km/h` + 提示行 | HUD | M1（已有简版） | M3 |
| 8 | 右下罗盘 | HUD 风向罗盘 | M3 | M3 |
| 9 | 雪洞剖面 5 标注：通风管 / 顶厚 / 高床 / 入口隧道 / 冷气坑 | 庇护所预设 + Cutaway 视图 | M2（几何代理） | M3 剖面，M4 材质 |
| 10 | 洞内烛灯、装备、睡袋 | 内部陈设 + 暖光（见 D3） | M3 | M4 |
| 11 | Key Resources：桦树皮 / 干草 / 木材 | 资源与背包 | M2 | M3 图标 |
| 12 | Read the Land 4 条规则 | 环境线索 ↔ 机制（§2） | M1–M2 | M3 |
| 13 | 远景山谷 + 落日天空 | 天空背景层（见 D1） | M3 | M4 |
| 14 | 底栏 4 阶段 | 本计划 M1–M4 | — | — |
| 15 | *Survival Starts with Understanding* | 复盘报告的语气与结尾 | M2 | M3 |

> **玩家文案 vs 设计支柱**：`FIND · GATHER · BUILD · SURVIVE` 用作面向玩家的标语；`Read the Land / Make a Plan / Survive the Night` 保留为内部设计支柱。两者不冲突。

---

## 2. "Read the Land" 契约

参考图右下的 4 条规则是**视觉和系统之间的合同**：每条规则必须同时有 *看得见的线索* 和 *不读就吃亏的机制后果*。只做到一半就不算完成。

| 规则 | 玩家看到什么 | 系统里是什么 | 不读会怎样 | 里程碑 |
| :--- | :--- | :--- | :--- | :--- |
| Trees show wind direction | 风雪粒子方向、树冠东倾、迎风侧挂雪少 | `WindData.direction` 驱动粒子与 `wind_sway.gdshader` | 入口朝西 → Wind 分低、灌雪 | M1 粒子 / M3 树摆 |
| Snow drifts reveal depth | 背风坡雪面圆润、更亮、有雪檐 | `SnowField` 深度场驱动雪面形状与着色 | 在浅雪处无法放置，或结构分低 | M1 深度场 / M2 视觉 |
| Leeward slopes collect snow | 脊线东侧明显积深雪 | 深度场生成：上风侧高度差越大，雪越深（Web 原型 `world.ts` 已实现） | 同上 | M1 |
| Standing dead trees mean fuel | 灰色、无针叶、树皮剥落的立枯木；半埋的倒木 | `Harvestable.kind = standing_dead / fallen_wet` | 采到湿倒木 → 生火失败 | M2 |

---

## 3. 开工前决策（括号内为建议，请确认或修改）

| ID | 问题 | 冲突来源 | 建议 |
| :--- | :--- | :--- | :--- |
| **D1** | 正交相机看不到参考图里的地平线和太阳 | 35°–38° 俯角的正交画面只有地面；参考图主画面其实是海报构图 | 游戏画面保持正交；落日靠光色和长阴影表达；远景天空做成**固定背景层**（Web 原型的 `drawSky` 就是这么做的）。参考图当宣传图看，不当逐帧目标 |
| **D2** | 木头和火在 MVP 里到底干什么 | 文档规定雪洞内禁火；Godot 的 `NightSimulator` 完全没用到木材；Web 原型让洞口篝火**整夜**加温 | 火 = **睡前**在背风处生火"暖身 + 烘干"，提高入夜时的核心体温（报告里的一个修正项），**不整夜供热**。木材第二用途 = Raised Cave 的支撑和床架（Web 原型已有 `woodCost`）。由此形成"时间分给挖洞还是生火"的取舍 |
| **D3** | 洞内能不能有烛灯 | 参考图洞内有一盏小灯；*Cozy Inside* 需要这团暖光；文档禁火 | 允许**一盏烛灯**，标为 `[GAME]`，只做照明和氛围、不做主要热源；明火取暖仍然禁止 |
| **D4** | `Deeper snow — Ideal for shelter` 标签什么时候出现 | 直接显示等于替玩家读了地形 | 只在玩家**探测或查看过**的位置出现。知识要自己挣来 |
| **D5** | 雪深门槛统一 | 文档：Basic ≥1.5 m / Raised ≥2.0 m（参考图 ~2.1 m）；Web 原型：0.72 / 0.95 m，且地图雪深大多不到 2 m | 采用**文档量级**（与参考图和真实雪洞一致），按此重标定深度场。另外，参考图写的"顶厚 ≥ 1.5 m"偏保守：常见野外指南给的顶厚约在 30–60 cm 量级，1.5 m 更像总雪深要求。建议先改为 `[TUNE]` 顶厚 ≥ 0.5 m，查证后再定 |
| **D6** | 哪个原型是主线 | Godot 骨架 vs Web 原型 | **Godot 是唯一生产线**。Web 原型冻结为参考 + 快速调参沙盒，不再加功能；把它的 `nightSim.ts`、`tune.ts`、`world.ts` 规则移植进 Godot 当数值起点 |
| **D7** | 最终美术方向 | Web 原型是像素风（1/3 分辨率、色阶化、VT323 字体）；参考图是风格化低模 3D + 绘画感光照 | 以参考图为准。像素风只属于原型。资产来源：M1 用 Godot 原生几何体；M2–M3 自制低模或 CC0 素材；M4 定制或购买 |

---

## 4. 里程碑

### M0 — 对齐与能跑（1–2 天）

**目标问题**：工程能跑吗？规则和数值有唯一来源吗？

| ID | 任务 | 涉及文件 | 完成标准 | 估时 |
| :--- | :--- | :--- | :--- | :--- |
| T0.1 | 安装 Godot 4.3+ stable，打开工程，让编辑器重新生成 uid / import | `project.godot` | 编辑器打开时零报错；Godot 版本写进 README | 0.25 d |
| T0.2 | 修相机：`Camera3D` 在 rig 内沿本地 +Z 后移约 40 m，`far ≥ 200` | `scenes/camera/camera_rig.tscn` | 角色居中、无裁切 | 0.1 d |
| T0.3 | F5 冒烟测试 | `scenes/main.tscn` | 能移动；探针在坡上读 2.15 m、平地读 0.65 m；Output 零错误 | 0.25 d |
| T0.4 | 把 D1–D7 的结论写进文档；`snapshots/README.md` 已改为 4 阶段命名 | `CORE_GAMEPLAY.md`, `MVP_SNOW_SHELTER.md`, `VISUAL_LANGUAGE.md` | 文档之间没有矛盾 | 0.25 d |
| T0.5 | 建立唯一调参源：把 `tune.ts` 的全部参数迁成 `@export`；风速单位统一（建议 km/h，与 HUD 一致） | `scripts/resources/tuning.gd`, `resources/tuning.tres` | 代码里不再出现散落的魔法数字 | 0.25 d |
| T0.6 | 移植 `nightSim.ts` → `night_simulator.gd`（保留 6 维 + 权重 + 阈值 + 文案），按 D2 改写火的作用；写一个 headless 测试跑 5 个典型案例 | `scripts/systems/night_simulator.gd`, `tests/test_night_sim.gd` | 完美 / 无通风 / 入口迎风 / 无垫层 / 未完工 五种情况的结论都符合预期 | 0.5 d |
| T0.7 | 用 Web 原型做一次试玩（你自己 + 1 人） | `playtests/PT00_web.md` | 记下哪一步好玩、哪一步无聊。这是最便宜的验证，先做 | 0.25 d |

**退出闸门**：Godot 能跑；决策已入档；夜间模拟有测试覆盖。

---

### M1 — Blockout（约 5 天）· 参考图第 1 格

> *Core space and scale · Movement and camera (45° isometric) · Test gameplay flow*

**目标问题**（MVP 文档的唯三验收）：① 移动舒服吗？② 只看画面能读出风向吗？③ 玩家会主动去背风坡扎第一针吗？

| ID | 任务 | 涉及文件 | 完成标准 | 估时 |
| :--- | :--- | :--- | :--- | :--- |
| T1.1 | 高度场地形：从高度函数生成 `ArrayMesh` + `HeightMapShape3D`（移植 `world.ts` 的 `buildTerrain`）。布局：西侧迎风坡 → 脊线 → 东侧背风深雪坡 → 平台 → 沟谷；东北密林，西南稀疏 | `scripts/world/terrain_builder.gd`, `scenes/world/terrain.tscn` | 100 m 内可走遍，坡度肉眼可辨 | 1.5 d |
| T1.2 | 雪深场：`snow_at / slope_at / lee_factor`；探针改为查询 `SnowField`，不再读碰撞体 meta；F3 开发热力图 | `scripts/world/snow_field.gd`, `player_controller.gd` | 同一斜坡上不同位置读数连续变化 | 0.75 d |
| T1.3 | 相机调参热键：size 14 / 18 / 24，pitch 35° / 38° / 42°；定稿写入 tuning | `isometric_camera_rig.gd` | 选定值入档 | 0.25 d |
| T1.4 | 移动阻尼：上坡减速、深雪减速 `[TUNE]` | `player_controller.gd` | 深雪区明显变慢但不烦人 | 0.25 d |
| T1.5 | 最小风：跟随玩家的 `GPUParticles3D`，方向取 `WindData`；树木静态东倾约 5° | `scenes/world/wind_particles.tscn` | 截一张静帧也能看出风向 | 0.5 d |
| T1.6 | 探针手感：按住约 0.85 s、下蹲代理动作、探针杆 mesh、地面留下持久标记和读数 | `player.tscn`, `scripts/world/probe_marker.gd` | 连扎 5 针后，地面形成一张"雪深地图" | 0.5 d |
| T1.7 | 3 种灰模树：活云杉 / 立枯木 / 倒木，只用颜色和轮廓区分（暂不可交互） | `scenes/world/tree_*.tscn` | 灰度截图里也能分清 | 0.5 d |
| T1.8 | 试玩 PT01：3 人，不给引导，5 分钟 | `playtests/PT01.md` | 记录首针位置、能否说出风向 | 0.5 d |

**交付**：`snapshots/snapshot_01_blockout.png`，git tag `m1-blockout`
**退出闸门**：≥ 2/3 测试者 30 秒内说出风向；首针落在背风区；没人抱怨移动。
**没过怎么办**：只改相机、风、地形，**不进 M2**。
**不做**：交互、背包、建造、UI 美化。

---

### M2 — Playable（约 10 天）· 参考图第 2 格

> *Basic art and readability · Gather and build loop · Core survival mechanics*

**原则**：先让完整循环跑通，哪怕很丑。**过夜报告在 M2 就出现**（纯文字），否则无法验证循环本身是否好玩。

| ID | 任务 | 涉及文件 | 完成标准 | 估时 |
| :--- | :--- | :--- | :--- | :--- |
| T2.1 | 交互框架：`Interactable` 组件（提示文字、按住时长、消耗游戏分钟）；玩家选最近目标；淡橙圈高亮 | `scripts/components/interactable.gd` | 任何可交互物都通过它接入 | 1 d |
| T2.2 | 资源与背包：`wood / bark / bedding`。立枯木 → wood；倒木 → "湿木"提示，无收获；桦树 → bark；干草 / 云杉枝 → bedding。数量上限 `[TUNE]`（Web 原型为 6–8 处） | `scripts/systems/inventory.gd` | HUD 上显示 3 种数量 | 1 d |
| T2.3 | 时间模型：时钟实时流动；动作耗时 = 按住时长 × 效率；效率随暮光和体感温度下降（移植 `efficiency()`） | `weather_controller.gd` | 16:00 后挖掘明显变慢 | 0.75 d |
| T2.4 | 建造模式（B）：3 种预设的 ghost；校验雪深 / 坡度 / 树干 / 木材，不合格时显示**第一条原因**（移植 `validate()`） | `scripts/systems/shelter_builder.gd` | 不合格时总能看到原因 | 1.5 d |
| T2.5 | 预设参数：入口旋转、通风管数量、垫层厚度（消耗 bedding）、Raised 消耗木材 | 同上，`shelter_preset.gd` | 参数全部传进 `NightSimulator` | 1 d |
| T2.6 | 挖掘进度：Space 按住推进；几何代理按阶段出现：入口 → 腔体 → 平台 → 通风 → 完工 | `scenes/shelter/*.tscn` | 中途停下，完工度正确传进报告 | 1 d |
| T2.7 | 生火（F，按 D2）：需要 wood + bark；判定背风暴露度；结果影响入夜核心体温 | `scripts/systems/campfire.gd` | 在迎风处点火会被吹灭，并有提示 | 0.75 d |
| T2.8 | 过夜：按 N，或时间到点强制进入 → 黑屏约 3 秒 → 纯文字报告（6 项分数 + 归因 + 结论）→ 重开 | `scenes/ui/report.tscn` | 一局能从头玩到尾，再重开 | 0.75 d |
| T2.9 | 开场简报（纯文字，参照 Web 原型 `Briefing`） | `scenes/ui/briefing.tscn` | — | 0.25 d |
| T2.10 | 基础美术：低模配色资产（云杉 / 立枯木 / 白桦 / 倒木 / 岩石 / 角色） | `assets/models/` | 默认缩放下的灰度截图里，立枯木和活树依然分得清 | 1.5 d |
| T2.11 | 试玩 PT02 | `playtests/PT02.md` | — | 0.5 d |

**交付**：`snapshot_02_playable.png`、可导出的 Windows 构建，git tag `m2-playable`
**退出闸门**：一局 10–20 分钟能完整打完；≥ 2/3 测试者自愿再玩一局；测试者能复述"为什么是这个结果"。
**没过怎么办**：调 tuning 和报告文案，**不加新系统**。
**不做**：剖面视图、天气 shader、音频、UI 美化。

---

### M3 — Systems + UI（约 12 天）· 参考图第 3 格

> *Environment, weather, resources · UI and feedback · Early content pass*

| ID | 任务 | 涉及文件 | 完成标准 | 估时 |
| :--- | :--- | :--- | :--- | :--- |
| T3.1 | 天气：树木摆动 shader、贴地吹雪粒子、阵风、夜间降雪导致通风口堵塞的概率 | `shaders/wind_sway.gdshader`, `weather_controller.gd` | §2 的第 1 条规则完整成立 | 2 d |
| T3.2 | 连续日落：光照角度和颜色（Web 原型三段式：金黄 → 玫瑰 → 暮蓝）、雾密度与可见距离、温度曲线 | `weather_controller.gd`, `main.tscn` | 没有任何硬切换 | 1 d |
| T3.3 | 天空背景层（D1） | `scenes/world/sky_backdrop.tscn` | 画面上沿露出暮色天空 | 0.5 d |
| T3.4 | 按参考图做 HUD：环境卡（提示行由上下文选取，移植 `tips.ts`）、罗盘、资源托盘、交互提示 | `scenes/ui/hud.tscn`, `scripts/ui/tips.gd` | 与参考图 7 / 8 / 11 号元素对齐 | 2 d |
| T3.5 | 世界标签：探针读数（带标尺图标）、`Deeper snow` 标记（D4）、`Deadwood` 标签，统一用一个组件 | `scenes/ui/world_label.tscn` | 与参考图 4 / 5 / 6 号元素对齐 | 1 d |
| T3.6 | Cutaway 剖面：模块化雪洞网格 + 朝相机剖切 shader；建造模式或进洞时显示；5 个标注同参考图 | `scenes/shelter/`, `shaders/cutaway.gdshader` | 与参考图 9 号元素对齐 | 2.5 d |
| T3.7 | 报告 UI：6 条分数条 + 每条一句归因 + 结论 + "你学到了什么"（对应 §2 规则） | `scenes/ui/report.tscn` | 失败后玩家能说出主因 | 1 d |
| T3.8 | 音频灰盒：风声随风速变化、踩雪声、洞内闷声 | `assets/audio/` | — | 0.5 d |
| T3.9 | 内容一轮：最终地图布局、资源摆放、3 种预设平衡；5 种"教学性失败"都能稳定复现 | `terrain_builder.gd`, `tuning.tres` | — | 1 d |
| T3.10 | 试玩 PT03：新手，不给任何口头帮助 | `playtests/PT03.md` | — | 0.5 d |

**交付**：`snapshot_03_systems_ui.png`，git tag `m3-systems-ui`
**退出闸门**：新测试者零口头提示完成一局，并能说出风向和自己失败的主因。
**不做**：终版模型、脚印、体积雾、标题画面。

---

### M4 — Target Look（约 15 天）· 参考图第 4 格

> *Final style and atmosphere · Polished environment · Target visual quality for prototype*

| ID | 任务 | 完成标准 | 估时 |
| :--- | :--- | :--- | :--- |
| T4.1 | 终版资产：积雪云杉 2–3 个变体（可旋转、镜像复用）、立枯木、白桦、岩石 ×3、角色（红背包）+ 走 / 探 / 挖 / 砍动画 | 替换所有代理 | 5 d |
| T4.2 | 雪材质：闪点高光、蓝色阴影、按深度着色；脚印和拖痕（贴花或 render-texture 变形） | 与参考图 2 / 3 号元素对齐 | 3 d |
| T4.3 | 光照：低角度暖金方向光、体积雾、色调映射和调色（对齐 `VISUAL_LANGUAGE.md` 色板） | — | 2 d |
| T4.4 | 洞内：烛灯暖光、睡袋和装备陈设、雪壁透光近似 | 与参考图 10 号元素对齐 | 1.5 d |
| T4.5 | 标题画面（参考图左上排版） | 与参考图 1 号元素对齐 | 1 d |
| T4.6 | 性能：1080p / 60 fps / 中端机 | — | 1 d |
| T4.7 | 对照评审：同构图实机截图与 North Star 并排，列差距清单 | 差距清单入档 | 1.5 d |

**交付**：`snapshot_04_target_look.png` + 垂直切片构建，git tag `m4-target-look`
**退出闸门**：并排评审由你本人判定通过；完整一局没有阻断性 bug。

---

## 5. 资产保真度阶梯

| 资产 | M1 | M2 | M3 | M4 |
| :--- | :--- | :--- | :--- | :--- |
| 地形 | 高度场灰模 | 白雪 + 坡度着色 | 吹雪 + 深度着色 | 闪点 + 脚印 |
| 云杉 | 圆锥 + 圆柱 | 低模绿色 | + 摆动 | 积雪枝条 |
| 立枯木 | 灰圆柱 | 灰色秃干带残枝 | + 橙圈交互 | 剥落树皮 |
| 角色 | 橙色胶囊 | 低模 + 红背包 | + 动作代理 | 终版 + 动画 |
| 雪洞 | 圆顶代理 | 分阶段代理 | 剖面 + 标注 | 材质 + 内饰 |
| UI | 调试文本 | 纯文字面板 | 参考图样式 | 打磨 |

---

## 6. 工作节奏与规则

- **每个里程碑** = 1 个 git tag + 1 张快照 + 1 份试玩记录。
- **每周**：一次 30 分钟自测，并在本文件里勾选已完成的任务。
- **文档只在试玩推翻规则时修改**。新功能先过 `VISION.md` 的决策过滤器。
- **全局完成定义（DoD）**：Godot 运行零报错；新数值进 `tuning.tres` 并带 `[TUNE]`；改了规则就同步改文档；快照存进 `snapshots/`。

**给 AI Agent 的任务卡模板**（每次只发一张）：

```text
Task:       T2.4 建造模式
Read first: PRODUCTION_PLAN.md §4 M2, CORE_GAMEPLAY.md §5, ARCHITECTURE_GODOT.md
Files:      scripts/systems/shelter_builder.gd (new), scenes/main.tscn
Done when:  不合格位置显示第一条原因；合格位置可放置；数值全部取自 tuning.tres
Do NOT:     新增资源类型 / 新增预设 / 改 NightSimulator
```

**试玩记录模板**（`playtests/PTxx.md`）：日期 · 版本 tag · 测试者 · 首次探测位置 · 能否说出风向 · 一局时长 · 结局 · 是否自愿再玩 · 测试者原话 3 句 · 下一步只改哪 1–2 件事。

---

## 7. 风险

| 风险 | 应对 |
| :--- | :--- |
| Godot 工程从未运行过，手写的 `.tscn` 可能有问题 | M0 第一件事就是解决它 |
| 正交俯视缺少透视深度线索，"读地形"可能太难 | M1 闸门专门测；备选方案：等高阴影、AO、强化雪面法线 |
| 剖面视图实现复杂 | 用模块化代理 + 剖切平面，**不做**真实的布尔挖掘或体素 |
| 两个原型并行导致规则分叉 | D6：Web 原型冻结 |
| 范围膨胀 | 每个里程碑都有"不做"清单；试玩没过只调参，不加系统 |
| 调参数值被当成科学事实 | 沿用 `[REAL] / [GAME] / [TUNE]` 标注 |

---

## 8. 时间换算

| 里程碑 | 专注工作日 |
| :--- | :--- |
| M0 | 1–2 |
| M1 | 5 |
| M2 | 10 |
| M3 | 12 |
| M4 | 15 |
| **合计** | **约 43–44** |

全职约 9 周；每周投入约 2 个专注日则约 5 个月。M1 和 M2 的闸门可能导致返工，届时更新本表。
