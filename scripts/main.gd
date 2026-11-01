class_name MainLevel
extends Node3D

## 出生点（地图坐标；L3 随地图旋转，用 TerrainHeight.to_world3 换算）。
const SPAWN_POSITION := Vector3(18.0, 0.0, 8.0)

@onready var player: PlayerController = $Player
@onready var camera_rig: IsometricCameraRig = $CameraRig
@onready var weather: WeatherController = $WeatherController
@onready var hud: HUDController = $HUD/HUDController
@onready var warmth: WarmthController = $Player/WarmthController

## 在子节点（地形 / 森林）_ready 之前设置地形开关：_init 先于整棵子树执行。
func _init() -> void:
	var t := load("res://resources/tuning.tres") as Tuning
	TerrainHeight.SADDLE = (t != null and t.ridge_saddle) or "--saddle" in OS.get_cmdline_user_args()
	# D12：命令行 --level=N [--seed=S] 进入关卡模式（只在首次加载时；重开由 GameDirector 重新抽取）
	if not LevelState.active():
		var a := LevelState.parse_args(OS.get_cmdline_user_args())
		if int(a["level"]) >= 0:
			LevelState.begin(int(a["level"]), int(a["seed"]))
	LevelState.apply_world()

func _ready() -> void:
	if player:
		var sp := TerrainHeight.to_world3(SPAWN_POSITION)
		player.global_position = Vector3(sp.x, TerrainHeight.height_at(sp.x, sp.z) + 1.0, sp.z)

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
