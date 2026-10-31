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

	# 相机跟随设置：首帧即对准玩家，避免截图时还在 lerp 途中
	if camera_rig and player:
		camera_rig.target = player
		camera_rig.global_position = player.global_position

	# 天气信号连接到 HUD
	if weather and hud:
		hud.set_sunset_clock(weather.sunset_clock())
		weather.time_changed.connect(hud.update_time)
		weather.weather_updated.connect(hud.update_weather)

	# 游戏循环（M2）：GameDirector 负责简报 → 行动 → 入夜 → 报告
	var director := GameDirector.new()
	director.name = "GameDirector"
	director.setup(self, player, weather, warmth, hud)
	add_child(director)
