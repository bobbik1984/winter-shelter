# Visual Milestones (Development Snapshots)

本目录用于归档项目在各个开发关键节点生成的**开发快照 (Development Snapshots)**。

---

## 归档命名规范

每次完成对应里程碑阶段的验证，在此存入实机截图或渲染图：

```text
snapshots/
├── README.md
├── snapshot_00_visual_north_star.png   # 初始概念视觉锚点
├── snapshot_01_blockout.png             # 比例、镜头、灰模地形
├── snapshot_02_environmental.png        # 风雪粒子、日照、枯木、探针
├── snapshot_03_shelter_cutaway.png      # 雪坡入口、剖面高低床、排气管
├── snapshot_04_first_night.png          # 外部暴雪、内部烛火、结算报告
└── snapshot_05_target_prototype.png     # 完整垂直切片
```

---

## 规则

1. **真实来自当前工程**：除 00 号概念图外，其余快照必须来自实际可运行的原型或渲染，严禁提前拿未实现的高概念图充数。
2. **直面简陋**：Snapshot 01 就算只有白盒子和橙色胶囊人也是及格的，核心是确认比例与视角。
3. **对照反思**：每次生成新快照，对照 Snapshot 00 提问：*“我们是否正走在正确的视觉与心流轨道上？”*
