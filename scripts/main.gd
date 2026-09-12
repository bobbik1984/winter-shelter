class_name MainLevel
extends Node3D

@onready var player: PlayerController = $Player
@onready var camera_rig: IsometricCameraRig = $CameraRig
@onready var weather: WeatherController = $WeatherController
@onready var hud: HUDController = $HUD/HUDController

func _ready() -> void:
	# 相机跟随设置
	if camera_rig and player:
		camera_rig.target = player

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
