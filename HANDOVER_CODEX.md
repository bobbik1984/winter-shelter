# HANDOVER — Winter Shelter / Snow Shelter Challenge

> 交接给同一台设备上的 Codex。  
> 最后更新：2026-11-19 · 当前发布代码：`014d907`（0.4；master 可包含后续文档提交） · 默认/唯一开发分支：`master`

---

## 1. 先读什么

按顺序读：

1. [`AGENTS.md`](AGENTS.md) —— 工程红线、测试、UTF-8、零硬编码、验证诚实
2. [`CURRENT_STAGE.md`](CURRENT_STAGE.md) —— 当前阶段、任务卡、未完成项
3. [`CORE_GAMEPLAY.md`](CORE_GAMEPLAY.md) —— 玩法规则；帐篷见 §13（D17）
4. [`ARCHITECTURE_GODOT.md`](ARCHITECTURE_GODOT.md) —— 节点 / 脚本 / 资源边界
5. [`VISUAL_LANGUAGE.md`](VISUAL_LANGUAGE.md) —— 相机、光照、UI 与建造特写
6. [`PRODUCTION_PLAN.md`](PRODUCTION_PLAN.md) —— 决策与里程碑
7. [`todo.md`](todo.md) / [`progress.yaml`](progress.yaml) —— 需求池与进度投影

不要新建平行规则文档；规则改动写回 `CORE_GAMEPLAY.md`。

---

## 2. 项目位置

```text
项目根目录：
  /home/bobbik/dsh_projects/winter-shelter

Godot 主场景：
  scenes/main.tscn

核心代码：
  scripts/systems/      GameDirector、NightCurve/NightSimulator、LevelState、Inventory、Records
  scripts/world/        ShelterSite、ShelterInterior、Campfire、地形 / 森林 / 资源
  scripts/ui/           GameUI、HUD、WorldCallouts、NightReportText、TouchControls
  scripts/resources/    Tuning、LevelDef、ChapterStage、ShelterPreset
  resources/            tuning.tres、levels/*.tres、default_wind.tres
  assets/               UI / 模型 / 音效
  tests/                headless 逻辑测试；入口 tests/run_all.gd
  tools/                导出、部署、触屏、输入、截图、机器人
  web/                  Web 页面注入片段
  snapshots/            截图证据（大量未跟踪文件）
  playtests/            试玩日志 / 报告（大量未跟踪文件）
  build/                历史构建产物（忽略）；新包输出至 ~/work/local/stage/winter-shelter/
```

**不要**把 `references/`、`snapshots/`、`playtests/`、`build/` 当成生产源码；它们通常是证据或历史材料。

---

## 3. 开发环境（本机）

| 项 | 值 |
| :--- | :--- |
| OS / 桌面 | Linux，X11 `DISPLAY=:0` |
| Xauthority | `/run/user/1000/gdm/Xauthority` |
| Godot | `/home/bobbik/.local/bin/godot`，`4.3.stable.official` |
| Java | OpenJDK 21 |
| Android SDK | `/usr/lib/android-sdk` |
| Build tools | `/usr/lib/android-sdk/build-tools/debian` |
| Web / Android 导出模板 | `/home/bobbik/.local/share/godot/export_templates/4.3.stable` |
| GitHub CLI | `gh` 已登录 `bobbik1984` |
| Git 远端 | `git@github.com:bobbik1984/winter-shelter.git` |

Godot 截图必须窗口模式；headless 不能渲染。  
新增带 `class_name` 的脚本后，先跑一次 `--import`。

---

## 4. 运行 / 测试

在项目根目录执行：

```bash
# 导入
/home/bobbik/.local/bin/godot --headless --path . --import

# 全量逻辑测试（必须 0 失败）
/home/bobbik/.local/bin/godot --headless --path . -s res://tests/run_all.gd

# 触屏全流程
/home/bobbik/.local/bin/godot --headless --path . \
  -s res://tools/touch_smoke_test.gd -- --touch --touch-css=390

# 键盘全流程
/home/bobbik/.local/bin/godot --headless --path . \
  -s res://tools/input_smoke_test.gd

# 真实窗口试玩（1280×720）
DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority \
  /home/bobbik/.local/bin/godot --path . \
  --resolution 1280x720 --audio-driver Dummy
```

当前基线（2026-11-15）：

```text
15 suites, 0 failed
4,061 assertions passed
touch smoke: PASS
input smoke: PASS
```

如果在这台设备的受限沙箱里运行，`XDG_*` 可能不能写 `$HOME`。用临时目录：

```bash
export XDG_DATA_HOME=/tmp/godot_data
export XDG_CONFIG_HOME=/tmp/godot_cfg
export XDG_CACHE_HOME=/tmp/godot_cache
mkdir -p "$XDG_DATA_HOME/godot/export_templates" "$XDG_CONFIG_HOME/godot" "$XDG_CACHE_HOME"
ln -sfn /home/bobbik/.local/share/godot/export_templates/4.3.stable \
  "$XDG_DATA_HOME/godot/export_templates/4.3.stable"
```

---

## 当前营地细节：CAMP-DETAIL

2026-11-19 用户认为四版树差别不值得继续比较，批准改进营地 / 地面组合。当前实施入口踩实雪、侧边弃雪、真实库存材料批绘、岩面与岩脚覆雪、降低雪晶噪点；默认近树回到连贯旧版，样树仍保留为独立研究资源。规则、碰撞、库存扣除与雪深不改。已通过 18 suites / 4281 assertions 和窗口验证，截图与实测见 `playtests/camp_detail_20261119_results.json`；整体视觉待用户审阅。施工及验收入口 CURRENT_STAGE CAMP-DETAIL；本轮没有打包、部署或 GitHub 推送，正式发布仍为 0.3。

## 样树候选记录：已停止选择（由 CAMP-DETAIL 取代）

用户已批准按 TREE-LOOK 推进样树测试。2026-11-19 完成 0 原版 / A 饱满 / B 略疏 / C 下垂枝的资源化候选、单树与临时成林对照；17 suites / 4250 assertions PASS，手机低档在 X1T 模拟短时约 30 FPS，非真机温度或持续性能验证。建议 A 主树、B/C 变体，尚未视觉确认；游戏默认树尚未替换，也未打包部署。入口 CURRENT_STAGE TREE-SAMPLES、证据 `playtests/tree_samples_20261119_results.json`。

## 最新反馈：树形未通过视觉审阅

用户认为 c6b19ec 的树冠零散、效果不如旧版。同光照 / 同机位临时网格对照确认整体轮廓变碎；技术测试与 30 FPS 不代表美术通过。下一候选建议为连续饱满的锥形树冠、重叠枝层与下垂枝梢，先做样树审阅。研究结果见 CURRENT_STAGE TREE-LOOK 和 VISUAL_LANGUAGE §2.3b。本轮没有把临时旧树对照替换写回游戏，也未打包发布；不要把下面的工程通过误当作用户认可树形。

## 当前源码增量：ENV-DETAIL（尚未发布）

2026-11-18 已实现近景分枝云杉、岩脚 / 树根贴地积雪与碎石、坡面鞋印和施工区脚印、中性日夜补光；隐藏洞口发光矩形代理，既有灯低强度向内照明。远景简化树、真实太阳、雪深与地物/资源/碰撞位置保持原契约。视觉配置见 `resources/environment_detail.tres`；规则与结构已归并 VISUAL_LANGUAGE §2.3b、ARCHITECTURE_GODOT 的环境细节。

最终 16 suites / 4196 assertions，触屏/键盘/地物回归与桌面/手机配置窗口检查通过。手机配置在 X1T 模拟约 30 FPS，不是 Android 真机温度实测。证据与截图见 CURRENT_STAGE 的 ENV-DETAIL 验收及 `playtests/env_detail_20261118_results.json`。本轮只改源码和验证，没有打包或部署；正式版本仍是以下 0.3，后续发布需升 versionCode。

## 0.4 发布

发布源码 `014d907`，Android `versionName=0.4`、`versionCode=4`，应用 ID 与正式签名沿用 0.3。雪洞外壳、弃雪和入口压雪复用地面雪色及日照参数，洞内保留独立阴影。

- [网页版](https://test.bobbik.org/winter/) 使用 `index-b7219e3e1d.pck`。
- [Android 下载页](https://test.bobbik.org/winter/download/) 与 [GitHub Release v0.4](https://github.com/bobbik1984/winter-shelter/releases/tag/v0.4) 提供 `winter-shelter-014d907.apk`。
- 触屏整局、原生窗口、Web 666 项资源值、APK 内容与正式签名核验通过。Android 真机安装与温升待实测。证据见 `playtests/v04_20261119_delivery.json`。

## 0.3 历史交付

第一章为三关主线（读风探雪 → 高床结构 → 完整过夜准备），旧 4–10 阶为七个可选挑战；通过第三关进入第二章。旧存档迁移前备份，保留旧阶段 ID 和记录。选关只更新简报，确认开始才生成地图；天黑可继续行动，夜间能主动起床外出，实际睡点决定庇护。规则见 CORE_GAMEPLAY §9.1，结构见 ARCHITECTURE_GODOT 的第一章教学配置。

15 suites / 4160 assertions、触屏整局、输入整局、地物回归、第一章窗口专项均 PASS；三条默认图准备路线模拟均 SAFE。Web 595 项资源属性与源一致；APK 的版本 / 正式签名 / 三关资源 / 双语 / 手机限帧配置通过检查。未做 Android 真机安装及温度实测。发布证据见 `playtests/v03_20261117_delivery.json`。全局 aligner 登记路径仍无法定位本项目，未直接改进度投影。

## 5. Git / GitHub 状态

```text
默认分支：master
发布代码：9547f4ea8803dd1696636fd67ce7f05df060c24d
正式发布代码已推送 origin/master；ENV-DETAIL 为本地源码增量，尚未推送或发布，以 git log 为准
发布 Tag：v0.3（指向发布代码）
```

已发布：

```text
GitHub Release v0.3
https://github.com/bobbik1984/winter-shelter/releases/tag/v0.3
APK: winter-shelter-9547f4e.apk
SHA-256: e7c9b1c3efa05fe36098cf5f07bf5b584af818075756f28d03102bf00c8fc6b9
```

**Codex 请直接用 `master`，不要新开长期开发分支。**  
需要实验时用临时分支，合并回 `master` 后删除。

本地有未跟踪的 `snapshots/`、`playtests/` 文件；它们不是当前代码状态的一部分，不要误提交。

---

## 6. 0.3 历史线上测试页 / APK

| 项 | 地址 |
| :--- | :--- |
| Web | https://test.bobbik.org/winter/ |
| APK 下载页 | https://test.bobbik.org/winter/download/ |
| APK 直链 | https://test.bobbik.org/winter/download/winter-shelter-9547f4e.apk |
| GitHub Release | https://github.com/bobbik1984/winter-shelter/releases/tag/v0.3 |

线上 Web build 标记为 `9547f4e`（`index-4c02213836.pck`）；APK 内标记为 `9547f4e-android`。下载页已指向 0.3；服务器保留 0.2 与更早 APK 供对比。

---

## 7. 部署环境

VPS1：

```text
用户：ubuntu
公网：115.190.248.194（当前可用）
Tailscale：100.64.0.1（可能超时，优先用公网）
SSH key：~/.ssh/vps1_deploy_ed25519
目标：/opt/test/winter/（Web）
      /opt/test/winter/download/（APK）
```

**不要 sudo。** `/opt/test` 已归 `ubuntu:ubuntu`。Caddy 是静态 file_server，上传即生效；不要重启 Caddy 或机器。

两个部署脚本默认写 `ubuntu@100.64.0.1`：

```bash
tools/deploy_web.sh
tools/deploy_apk.sh <apk>
```

如果 Tailscale 不通，在这台机器加 SSH 别名（不要改仓库）：

```sshconfig
Host 100.64.0.1
  HostName 115.190.248.194
  User ubuntu
  IdentityFile ~/.ssh/vps1_deploy_ed25519
  IdentitiesOnly yes
```

APK 签名材料（只在本机，不提交）：

```text
~/credentials/bobbik-release.p12
~/.config/winter-shelter/keystore-pass
```

---

## 8. 打包

### Web

```bash
export GODOT=/home/bobbik/.local/bin/godot
tools/deploy_web.sh
```

该脚本会：

- 要求工作区已提交（否则拒绝）；
- 重新导出 Web；
- 按内容哈希命名 pck；
- 注入手机 `<head>`；
- 上传到 `/opt/test/winter/`；
- 验证线上 build 标记和 pck。

### Android APK

```bash
export GODOT=/home/bobbik/.local/bin/godot
tools/build_apk_local.sh
# → ~/work/local/stage/winter-shelter/android/winter-shelter-<sha>.apk
tools/deploy_apk.sh ~/work/local/stage/winter-shelter/android/winter-shelter-<sha>.apk
```

当前 Android 配置：

```text
package: org.bobbik.wintershelter
version: 0.3 (code 3)
arch: arm64-v8a
signing: release key
```

0.3 APK 未在本机连接的真机安装验证；正式签名与 v0.2 一致、版本号、包结构、导出资源及公开下载均已核验。

---

## 9. 当前功能状态（不要从旧记录猜测）

### 已完成并在线

- 2026-11-15：690 条译文迁入 Godot i18n（CSV→TranslationServer）；手机 30/15 FPS、后台暂停、阴影与隐藏重绘优化；庇护所火源/柴耗与重复 UI 修复。见 CURRENT_STAGE 与 CORE_GAMEPLAY。

- D14 可玩夜晚、D16 建造特写 / 材料往返；
- S5 其余庇护所、S7 章节平衡；
- 更细的雪面 / 积雪 / 枯木着色，无额外贴图或 draw call；
- 庇护所 Intel 双图卡片、简报 / 暂停 / 报告 / HUD 精修；
- **D17 帐篷套装**：
  - 简报 `[T]` / 触屏 Tent kit；
  - 背帐篷：木材上限 0、速度 ×0.72、只能搭 Tent；
  - 第 2 阶后恢复木材 4 / 速度 1；
  - 5 阶：草甸 → 帐篷 → 火盆/烟囱 → 睡袋 → 压边/柴堆；
  - 帐篷内柴堆供火盆；
  - NightSimulator Tent：无火 DANGEROUS，有火 + 睡袋 COLD；
  - `tests/test_tent.gd` 覆盖。

### 已知限制

- Tent 外观是程序化简单模型，没有专用 Intel 图鉴卡片；
- Tent / TreeWell 在密林里的相机遮挡和树冠可读性仍需继续改；
- 帐篷火盆的平衡（柴耗、最低体温）只做过逻辑/夜间模拟，没有真人长时间试玩；
- APK 未在真机安装；
- 线上 Web、APK 下载页和 GitHub Release v0.3 已更新为 `9547f4e`；后续改动发布新版本，不覆盖历史 Release。

---

## 10. 交接约定

Codex 接手后：

1. `git pull origin master`，确认 `HEAD == origin/master`；
2. 先跑 `tests/run_all.gd`、touch、input，先建立基线；
3. 改规则前读 `CORE_GAMEPLAY.md` 对应章节；参数进 `Tuning` / `ShelterPreset` / `LevelDef`，不要硬编码；
4. 新功能先写逻辑测试；UI / 构建改动附真实窗口截图；
5. 只改自己任务需要的文件；`scenes/main.tscn` 串行修改；
6. 提交到 `master`，不要留长期分叉；提交信息 `[wild] ...`；
7. 更新 `CURRENT_STAGE.md` / `progress.yaml` / `todo.md`（只写事实）；
8. 打包前确认工作区已提交；Web 和 APK 上传后验证线上；
9. 不把私钥、keystore 密码、APK、build 产物提交进 Git。

**交接文件就是本文件：`HANDOVER_CODEX.md`。**
