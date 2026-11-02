class_name MainLevel
extends Node3D


@onready var player: PlayerController = $Player
@onready var camera_rig: IsometricCameraRig = $CameraRig
@onready var weather: WeatherController = $WeatherController
@onready var hud: HUDController = $HUD/HUDController
@onready var warmth: WarmthController = $Player/WarmthController

## 在子节点（地形 / 森林）_ready 之前设置地形开关：_init 先于整棵子树执行。
func _init() -> void:
	var t := load("res://resources/tuning.tres") as Tuning
	TerrainHeight.SADDLE = (t != null and t.ridge_saddle) or "--saddle" in OS.get_cmdline_user_args()
	# D12 / D13：首次加载时进入章节模式——命令行 --level=章 [--stage=阶] [--seed=S] 优先，否则上次选的章 / 阶（该阶当前那张图）。
	# 之后的重开 / 换阶 / 换图由 GameDirector 先 LevelState.begin 再重载场景。测试工具关掉 auto_begin 保留旧基准。
	if not LevelState.active():
		var a := LevelState.parse_args(OS.get_cmdline_user_args())
		if int(a["level"]) >= 0:
			var st := maxi(int(a["stage"]), 1)
			LevelState.begin(int(a["level"]), int(a["seed"]), st, Records.map_index(int(a["level"]), st))
		elif LevelState.auto_begin:
			var sel := Records.default_selection()
			LevelState.begin(sel.x, -1, sel.y, Records.map_index(sel.x, sel.y))
	LevelState.apply_world()
	LandFeatures.reset()
	OldSpruces.reset()   # 老云杉由 ForestScatter / SceneryBuilder 在 _ready 时重新登记（S5）
	# 开发参数（S1）：--shape=basin|lakeshore|cliff_band [--rough=x] [--trees=x] 覆盖地形配方
	var dev_recipe := TerrainRecipe.from_args(OS.get_cmdline_user_args())
	if dev_recipe:
		TerrainHeight.RECIPE = dev_recipe

func _ready() -> void:
	if player:
		var sp := MapLayout.spawn()   # S2：旧地图 = 旧出生点；其它配方按规则挑选
		player.global_position = Vector3(sp.x, TerrainHeight.height_at(sp.x, sp.y) + 1.0, sp.y)

	# 相机跟随设置：首帧即对准玩家，避免截图时还在 lerp 途中
	if camera_rig and player:
		camera_rig.target = player
		camera_rig.global_position = player.global_position

	# 天气信号连接到 HUD
	if weather and hud:
		hud.set_sunset_clock(weather.sunset_clock())
		weather.time_changed.connect(hud.update_time)
		weather.weather_updated.connect(hud.update_weather)

	_build_tree_well_marks()

	# 游戏循环（M2）：GameDirector 负责简报 → 行动 → 入夜 → 报告
	var director := GameDirector.new()
	director.name = "GameDirector"
	director.setup(self, player, weather, warmth, hud)
	add_child(director)

## S5 Read the Land：老云杉树干周围的浅坑（tree well）画成一圈蓝灰色凹影，不探测也看得出"这棵树下雪浅"。
## 所有子节点（森林 / 场景）的 _ready 已执行完，OldSpruces 已登记齐。
func _build_tree_well_marks() -> void:
	if OldSpruces.points.is_empty():
		return
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.53, 0.70, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = OldSpruces.points.size()
	var r := OldSpruces.tuning().tree_well_canopy_radius_m * 0.75
	for i in range(OldSpruces.points.size()):
		var p := OldSpruces.points[i]
		var basis := Basis.IDENTITY.scaled(Vector3(r, 0.04, r))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, TerrainHeight.height_at(p.x, p.y) + 0.02, p.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TreeWellMarks"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
