class_name GraphicsSettings
extends Node

## 画质档位（V2 / D11）：低 / 中 / 高。F10 循环切换，存到 user://settings.cfg。
## 只调"性价比"开关：渲染缩放、SSAO、景深、泛光、阴影距离、远景林；不改构图与玩法。

const PATH := "user://settings.cfg"
const NAMES := ["Low", "Medium", "High"]
## 每档参数：[3D 渲染缩放, SSAO, 景深, 泛光, 阴影距离 m, 远景林, 软阴影质量, 阴影级联数, 近景林可见距离 m（0 = 不限）]
## 阳光阴影在所有档位都保留——影子是玩家的时钟（D9），只降级联与距离。
const PRESETS := [
	[0.45, false, false, false, 45.0, false, 0, 2, 55.0],
	[0.6, true, true, true, 80.0, true, 1, 4, 0.0],
	[0.85, true, true, true, 120.0, true, 2, 4, 0.0],
]

signal changed(level: int)
## 只在玩家按 F10 切换时发出（启动时应用存档不提示）。
signal cycled(level: int)

var level: int = 1
## 启动后窗口会重建一次 swapchain（窗口管理器映射 / 调整窗口）。在那之前改 3D 渲染缩放 / 阴影设置
## 偶发引擎原生崩溃（模糊测试复现）。所以等 READY_FRAMES 帧后才应用设置，之前的 F10 忽略。
const READY_FRAMES := 30
var _ready_frames := 0
var _ready_to_apply := false
## 界面缩放（可读性）：[-] / [=] 切换，保存。
const UI_SCALES := [0.9, 1.0, 1.15, 1.3]
## [TUNE] 网页版每档的 3D 渲染高度（像素）。
const COMPAT_3D_HEIGHT := [480, 720, 1080]
var ui_scale_idx: int = 1

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		level = clampi(int(cfg.get_value("graphics", "level", _default_level())), 0, 2)
		AudioServer.set_bus_mute(0, bool(cfg.get_value("audio", "muted", false)))
		ui_scale_idx = clampi(int(cfg.get_value("ui", "scale_idx", 1)), 0, UI_SCALES.size() - 1)
	else:
		level = _default_level()
	set_process(true)

## 手机默认低档；帧率还不够时 TouchControls 自动降档。
func _default_level() -> int:
	return 0 if TouchMode.enabled else 1

## 把"用户选的字号 × 手机放大倍数"应用到窗口；窗口转向时也调一次。
func refresh_ui_scale() -> void:
	if _ready_to_apply:
		get_tree().root.content_scale_factor = _ui_factor()

func _ui_factor() -> float:
	var f: float = UI_SCALES[ui_scale_idx]
	if TouchMode.enabled:
		var w := get_window().size
		var h := float(mini(w.x, w.y))
		if OS.has_feature("web"):
			var css = JavaScriptBridge.eval("Math.min(window.innerWidth, window.innerHeight)", true)
			if css != null and float(css) > 0.0:
				h = float(css)
		if TouchMode.css_override > 0.0:
			h = TouchMode.css_override
		f *= TouchMode.ui_factor(h)
	return f

## 只降不存：这台设备这次跑不动。
func step_down() -> void:
	if _ready_to_apply and level > 0:
		level -= 1
		apply()
		cycled.emit(level)

## [M] 静音（保存）；[F11] 全屏（不保存，跟随窗口）。
func toggle_mute() -> bool:
	var muted := not AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, muted)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("audio", "muted", muted)
	cfg.save(PATH)
	return muted

func step_ui_scale(delta_idx: int) -> float:
	if not _ready_to_apply:
		return UI_SCALES[ui_scale_idx]
	ui_scale_idx = clampi(ui_scale_idx + delta_idx, 0, UI_SCALES.size() - 1)
	get_tree().root.content_scale_factor = _ui_factor()
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("ui", "scale_idx", ui_scale_idx)
	cfg.save(PATH)
	return UI_SCALES[ui_scale_idx]

func toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(_delta: float) -> void:
	_ready_frames += 1
	if _ready_frames >= READY_FRAMES:
		_ready_to_apply = true
		set_process(false)
		get_tree().root.content_scale_factor = _ui_factor()
		apply()

func cycle() -> void:
	if not _ready_to_apply:
		return
	level = (level + 1) % PRESETS.size()
	apply()
	cycled.emit(level)
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "level", level)
	cfg.save(PATH)

func apply() -> void:
	var p: Array = PRESETS[level]
	var vp := get_viewport()
	if BuildInfo.is_compat():
		# 网页版的渲染器没有 FSR；手机窗口像素很高，按固定的 3D 高度算比例，不按窗口比例
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(float(COMPAT_3D_HEIGHT[level]) / maxf(float(get_window().size.y), 1.0), 0.25, 1.0)
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = float(p[0])
	# 低档关闭 FXAA（画面已经过 FSR 放大；约 +2 FPS）
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if level == 0 else Viewport.SCREEN_SPACE_AA_FXAA
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p[6]) as RenderingServer.ShadowQuality)
	var env_node := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if env_node and env_node.environment:
		env_node.environment.ssao_enabled = bool(p[1])
		env_node.environment.glow_enabled = bool(p[3])
		# T4.3 体积雾：只在高档开启（逆光穿林的暖色光幕，约 +6 ms GPU）
		var env := env_node.environment
		env.volumetric_fog_enabled = level == 2
		env.volumetric_fog_density = 0.008
		env.volumetric_fog_albedo = Color(0.86, 0.89, 0.96)
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_sky_affect = 0.0
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig:
		rig.dof_enabled = bool(p[2])
		rig.reapply()
	var sun := get_tree().current_scene.get_node_or_null("SunLight") as DirectionalLight3D if get_tree().current_scene else null
	if sun:
		sun.directional_shadow_max_distance = float(p[4])
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(p[7]) == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain:
		terrain.set_low_quality(level == 0)
	for n in get_tree().get_nodes_in_group("near_forest"):
		(n as GeometryInstance3D).visibility_range_end = float(p[8])
		(n as GeometryInstance3D).visibility_range_end_margin = 8.0 if float(p[8]) > 0.0 else 0.0
	for n in get_tree().get_nodes_in_group("far_forest"):
		(n as Node3D).visible = bool(p[5])
	changed.emit(level)

func level_name() -> String:
	return NAMES[level]
