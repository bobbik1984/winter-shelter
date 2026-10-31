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

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		level = clampi(int(cfg.get_value("graphics", "level", 1)), 0, 2)
		AudioServer.set_bus_mute(0, bool(cfg.get_value("audio", "muted", false)))
	apply.call_deferred()

## [M] 静音（保存）；[F11] 全屏（不保存，跟随窗口）。
func toggle_mute() -> bool:
	var muted := not AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, muted)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("audio", "muted", muted)
	cfg.save(PATH)
	return muted

func toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

func cycle() -> void:
	level = (level + 1) % PRESETS.size()
	apply()
	cycled.emit(level)
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "level", level)
	cfg.save(PATH)

func apply() -> void:
	var p: Array = PRESETS[level]
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = float(p[0])
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p[6]) as RenderingServer.ShadowQuality)
	var env_node := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if env_node and env_node.environment:
		env_node.environment.ssao_enabled = bool(p[1])
		env_node.environment.glow_enabled = bool(p[3])
	var rig := get_tree().get_first_node_in_group("camera_rig")
	if rig:
		rig.dof_enabled = bool(p[2])
		rig.reapply()
	var sun := get_tree().current_scene.get_node_or_null("SunLight") as DirectionalLight3D if get_tree().current_scene else null
	if sun:
		sun.directional_shadow_max_distance = float(p[4])
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(p[7]) == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	for n in get_tree().get_nodes_in_group("near_forest"):
		(n as GeometryInstance3D).visibility_range_end = float(p[8])
		(n as GeometryInstance3D).visibility_range_end_margin = 8.0 if float(p[8]) > 0.0 else 0.0
	for n in get_tree().get_nodes_in_group("far_forest"):
		(n as Node3D).visible = bool(p[5])
	changed.emit(level)

func level_name() -> String:
	return NAMES[level]
