# Winter Shelter (wild) — 需求池

> 只放**尚未进入施工合同**的需求、Bug、待决定事项和需要人来做的事。正在施工的任务见 [`CURRENT_STAGE.md`](CURRENT_STAGE.md)，进度见 [`progress.yaml`](progress.yaml)。

## 🙋 需要你来做（阻塞 Agent）

- [ ] **安装 Godot 4.3+ stable**（T0.1）——全局关键路径。装好后告诉 Agent `godot` 可执行文件路径，或把它加入 PATH
- [ ] **拍板 D4**：`Deeper snow` 标签是否只在探测过的位置出现
- [ ] **拍板 D6**：Godot 唯一生产线，Web 原型冻结
- [ ] **拍板 D7**：美术以参考图为准，像素风只属于原型
- [ ] 在网络正常的环境构建 Web 原型（不要在 OneDrive 目录内 `npm install`），做一次试玩并记录 `playtests/PT00_web.md`（T0.7）
- [ ] M1 完成后找 3 人做 PT01（不给引导，5 分钟）

## 🤔 待判断

- [ ] 天空可见性：M1 后决定是否加屏幕顶部天空带，或夜间拉远相机（D1 已知限制）
- [x] 参考图剖面标注"顶厚 ≥1.5 m"有误：剖面面板现在从 Tuning 读，显示 "≥ 0.30 m · built 0.45 m"（visual-pass-1）；参考图本身 M4 重绘时再改
- [ ] 调研文档的原始出处尚未逐条核验，`[REAL]` 规则上线前是否需要补核

## 📌 Backlog（已在路线中，尚未派发）

- [ ] 雪洞 Cutaway 剖面 shader（T3.6）
- [ ] 移植 Web 原型 `world.ts` 深度场算法（并入 T1.1a / T1.2，门槛按 D5 改）
- [ ] 天空背景层（Canvas 背景 + 渐变 shader，非 Skybox）与 `AtmosphereState` 连续日落（T3.2 / T3.3）

## 🎨 visual-pass-1 遗留（需要你拍板）

- [ ] **相机红线（AGENTS.md §4.1 / D1）**：本轮没改默认值，仍是正交。`IsometricCameraRig.view_mode` 新增实验性 `TILT_SHIFT`（运行时按 **V** 切换，滚轮推拉近景建造 / 远景侦察）。若决定采用，需同步改 AGENTS.md §4.1 与 PRODUCTION_PLAN D1。天空为此用了 Sky shader（`sky_backdrop.gdshader`），而不是 D1 的 Canvas 背景，因为透视相机需要真实天空。
- [ ] **落日进不了画面**：1 月下午太阳在西南 ≈225°；偏航 45° 的相机朝西北，太阳永远在画面左外。要概念图那种"太阳在画面里"，相机需朝西南（偏航 135°），并同步改 `player_controller.gd` 写死的 45° 输入旋转和罗盘。
- [ ] 以上改动的 Forward+ 效果（SSAO / 雾 / SSS）与 F5 实际操作尚未人工验证。
