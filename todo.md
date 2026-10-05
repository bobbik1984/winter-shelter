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
- [ ] 参考图剖面标注"顶厚 ≥1.5 m"有误（应为 ≥0.3 m），M4 重绘时修正
- [ ] 调研文档的原始出处尚未逐条核验，`[REAL]` 规则上线前是否需要补核

## 📌 Backlog（已在路线中，尚未派发）

- [ ] 雪洞 Cutaway 剖面 shader（T3.6）
- [ ] 移植 Web 原型 `world.ts` 深度场算法（并入 T1.1a / T1.2，门槛按 D5 改）
- [ ] 天空背景层（Canvas 背景 + 渐变 shader，非 Skybox）与 `AtmosphereState` 连续日落（T3.2 / T3.3）
