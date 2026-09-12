# MVP 01 — Snow Shelter Challenge

> **阶段唯一定义与目标**：  
> **证明“寻找地点 → 判断环境 → 设计雪洞 → 准备过夜”这个最纯粹的核心闭环本身是否好玩。**

不要将本文件当作庞大的开发排期表，它是第一阶段唯一的交付验收契约。

---

## 0. 参数身份约定 (Parameter Tags)

- **`[REAL]`**：客观现实规律（如迎风/背风受力、冷热空气分层）
- **`[GAME]`**：核心机制抽象（如 6 维评分、扇形风向判定）
- **`[TUNE]`**：临时测试数值（如地图尺寸、施工耗时，可自由调整）

---

## 1. 关卡设置与开场条件 (Initial Setup)

- **`[TUNE]` 地图尺寸**：80 × 80 米至 120 × 120 米紧凑微型沙盒。
- **`[TUNE]` 单局时长**：10 – 20 分钟现实时间。
- **地形构成**：
  - 1 个适宜开凿雪洞的向风/背风雪坡（`[TUNE]` 坡度约 25°–35°）；
  - 1 块平缓开阔雪地（用于对比雪深及测试雪沟 Trench）；
  - 1 处稀疏林缘与 1 处较密避风林；
  - 3–5 棵直立枯木（Standing Deadwood）及零散倒木；
  - 4–6 个具有鲜明雪深差异的采样区域（`[TUNE]` 0.3m、0.8m、1.5m、2.4m）。

### 开场信息面板 (Opening HUD Card)

```text
==================================================
              JANUARY 14, 14:20
           Sunset: 16:18 (1h 58m left)
       
       Ambient Temp:  -17°C
       Wind:          West 32 km/h (Brisk Gusts)
       Snowpack:      Variable (0.3m – 2.5m)
       
       OBJECTIVE:
       Read the land. Build a safe shelter before dark.
==================================================
```

---

## 2. 阶段边界约束与暮光权衡 (Scope Constraints & Twilight Dilemma)

为了保证开发速度与专注度，MVP 01 实行以下硬性减法与机制设计：

1. **简化角色微观生理模拟**：
   - 角色移动不需要复杂的卡路里/饥渴条；
   - **`[GAME]` 连续日落退化（无硬切换惩罚）**：
     - 随着 16:18 日落临近，阳光倾角变低，光色变暗，搜索视距与作业效率平滑衰减，体感寒冷加剧；
     - **允许玩家在 16:18 后摸黑赶工**：例如 16:25 时还差 10 分钟插好通风管，玩家面临“冒着夜寒继续赶工”还是“现在钻洞勉强过夜”的真实抉择；
2. **轻量化建造交互**：
   - 不做逐体素微观挖掘（Voxel Digging），采用**位置锚点 + 预设形态（Presets）微调**；
   - 在雪坡上确认位置后，选择 Trench / Basic / Raised，调整入口朝向与通风孔高度。
3. **即时结算与 6 维透明复盘**：
   - 点击“Spend the Night”，由 `NightSimulator` 进行透明可解释的 6 维打分（Thermal, Vent, Wind, Insulation, Structure, Completion），直接反馈成败原因。

---

## 3. MVP 01 十二项功能检查清单 (The 12 Checklist Items)

每一项完成后均需可实机跑通验证：

- [ ] **1. 玩家基础移动 (Player Navigation)**  
  支持键盘/鼠标在 45° 正交等距雪地中流畅移动。
- [ ] **2. 固定 45° 正交等距摄像机 (Fixed 45° ISO Camera)**  
  摄像机平滑跟随玩家，无透视畸变，正交投影准确呈现坡度与距离。
- [ ] **3. 肉眼可见的环境线索 (Visible Wind & Snow FX)**  
  风雪粒子清晰呈现自西向东吹拂，树梢摇摆方向与风力一致。
- [ ] **4. 探针探雪交互 (Snow Depth Probing)**  
  使用雪深探针扎雪，屏幕弹出对应点的数值反馈（如 `Good depth ↓ 2.15m`）。
- [ ] **5. 枯木识别与砍柴 (Deadwood Identification & Gathering)**  
  靠近树木可识别立枯木（干燥燃料）或湿倒木，消耗时间收集柴块。
- [ ] **6. 引火物与垫层收集 (Tinder & Bedding Gathering)**  
  剥取干燥桦树皮（Birch Bark），收集松针干草作为地面隔热垫。
- [ ] **7. 庇护所选址与预设选择 (Shelter Placement & Presets)**  
  在满足雪深条件的坡面激活建造模式，选择 Trench / Basic / Raised 之一。
- [ ] **8. 入口方向调整 (Entrance Orientation)**  
  旋转入口朝向（避开西向直接迎风面，防止强风倒灌）。
- [ ] **9. 内部细节调整 (Interior Tuning)**  
  调整高床冷气槽结构、插设可伸缩通风管（Telescopic Vent）。
- [ ] **10. 连续日照时间推进 (Continuous Daylight Progression)**  
  时间推进（14:20 $\rightarrow$ 16:18），光影拉长、夕阳金黄转为暮色幽蓝。
- [ ] **11. “Spend the Night” 过夜触发 (Night Transition)**  
  在庇护所内确认过夜，淡出并播放暴风雪音效切片。
- [ ] **12. 6 维可解释报告 (Explainable Shelter Report)**  
  展示 6 项评分与自然语言因果复盘（如冷空气槽成效、通气孔状态、入口避风表现）。

---

## 4. Blockout 原型阶段唯三验收目标 (Blockout Acceptance Criteria)

在展开后续所有系统前，**Prototype 0 (Blockout) 只需要验证以下 3 件事**：

1. **角色在 45° ISO 雪地上移动是否顺手舒服？**
2. **风向和风势能否完全从环境画面（吹雪、树木）中直观读出来？**
3. **玩家进入地图后，是否会出于本能想去某个背风雪坡扎下第一根 probe？**

只要这 3 件事成立，核心玩法的地基就完全站稳了。
