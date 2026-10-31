# Visual Milestones (Development Snapshots)

本目录用于归档项目在各个开发关键节点生成的**开发快照 (Development Snapshots)**。

---

## 归档命名规范

每次完成对应里程碑阶段的验证，在此存入实机截图或渲染图：

```text
snapshots/
├── README.md
├── snapshot_00_visual_north_star.png   # 初始概念视觉锚点（参考图）
├── snapshot_01_blockout.png             # M1：比例、镜头、灰模地形、最小风
├── snapshot_02_playable.png             # M2：采集 + 建造 + 过夜报告完整循环
├── snapshot_03_systems_ui.png           # M3：天气、HUD、世界标签、雪洞剖面
└── snapshot_04_target_look.png          # M4：终版画面，与 00 并排评审
```

> 与 [`PRODUCTION_PLAN.md`](../PRODUCTION_PLAN.md) 的 M1–M4 一一对应。

### 过程快照（不替代里程碑快照）

| 文件 | 内容 |
| :--- | :--- |
| `m0_smoke.png` / `m1_*.png` / `m2_*.png` | 早期正交 45° 阶段的实机截图 |
| `visual_pass1_cutaway.png` | V0.1 SDF 雪洞剖面面板（放大 2×） |
| `visual_pass2_ortho.png` | V 键正交备用模式 |
| `visual_pass3_1420.png` | 默认移轴透视 14:20（当前主画面） |
| `visual_pass3_sun_cycle.png` | 真实日轨：10:00 / 14:20 / 16:05 / 16:40 四格对比 |

新增过程快照命名：`visual_passN_<描述>.png`；涉及性能的改动在提交信息或回执中附 FPS。

---

## 规则

1. **真实来自当前工程**：除 00 号概念图外，其余快照必须来自实际可运行的原型或渲染，严禁提前拿未实现的高概念图充数。
2. **直面简陋**：Snapshot 01 就算只有白盒子和橙色胶囊人也是及格的，核心是确认比例与视角。
3. **对照反思**：每次生成新快照，对照 Snapshot 00 提问：*“我们是否正走在正确的视觉与心流轨道上？”*
