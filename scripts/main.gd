class_name MainLevel
extends Node3D

const SPAWN_POSITION := Vector3(18.0, 0.0, 8.0)

@onready var player: PlayerController = $Player
@onready var camera_rig: IsometricCameraRig = $CameraRig
@onready var weather: WeatherController = $WeatherController
@onready var hud: HUDController = $HUD/HUDController
@onready var warmth: WarmthController = $Player/WarmthController

func _ready() -> void:
	if player:
		player.global_position = Vector3(
			SPAWN_POSITION.x,
			TerrainHeight.height_at(SPAWN_POSITION.x, SPAWN_POSITION.z) + 1.0,
			SPAWN_POSITION.z
		)

	# M1 演示状态：等 T1.5 WindExposureSensor / T2.6 庇护所 / T2.7 篝火接入后，
	# 这三个字段由真实采样驱动；当前先让 HUD 展示 84/100、背风区、干燥衣物。
	if warmth:
		warmth.body_warmth = 84.0
		warmth.windbreak_factor = 1.0
		warmth.has_extra_clothing = true
		warmth.in_shelter_level = 0
		warmth.near_fire_intensity = 0.0

	# 相机跟随设置：首帧即对准玩家，避免截图时还在 lerp 途中
	if camera_rig and player:
		camera_rig.target = player
		camera_rig.global_position = player.global_position

	# 天气信号连接到 HUD
	if weather and hud:
		weather.time_changed.connect(hud.update_time)
		weather.weather_updated.connect(hud.update_weather)

	# 探针检测连接
	if player and hud:
		player.probe_activated.connect(_on_player_probe_activated)

func _on_player_probe_activated(world_pos: Vector3, depth: float) -> void:
	if camera_rig and camera_rig.camera_3d and hud:
		var screen_pos = camera_rig.camera_3d.unproject_position(world_pos)
		hud.show_probe_depth(screen_pos, depth)
