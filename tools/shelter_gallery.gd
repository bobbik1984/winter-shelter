extends SceneTree
## 模型画廊：七种庇护所（第 1 / 3 / 5 阶段的外观 + 进入后的剖面）和人物特写，逐张截图，方便前后对比。
## 必须窗口模式：godot --path . --resolution 1280x720 -s res://tools/shelter_gallery.gd -- --out=<目录> [--only=TreeWell,LeanTo]
## 不写存档、不写试玩日志。

const PRESETS := ["RaisedCave", "BasicCave", "Quinzhee", "SnowTrench", "TreeWell", "LeanTo", "RockOverhang", "FallenLog"]
const STAGES := [1, 3, 5]

var out_dir := ""
var only: PackedStringArray = []
var d
var main_n: Node

func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Loc.lang = "en"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	_run.call_deferred()

func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, name_]
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## 平坦、离树远的空地（树井例外：放在老云杉底下）。
func _open_spot(near: Vector3) -> Vector3:
	var trees: PackedVector2Array = []
	for n in get_nodes_in_group("forest") + get_nodes_in_group("scenery"):
		if "spruce_points" in n:
			trees.append_array(n.spruce_points)
	var best := near
	var best_score := -INF
	for r in range(4, 40, 3):
		for k in 16:
			var a := TAU * k / 16.0
			var p := near + Vector3(cos(a), 0, sin(a)) * r
			var clear := INF
			for t in trees:
				clear = minf(clear, t.distance_to(Vector2(p.x, p.z)))
			var slope := absf(TerrainHeight.height_at(p.x + 2, p.z) - TerrainHeight.height_at(p.x - 2, p.z)) \
				+ absf(TerrainHeight.height_at(p.x, p.z + 2) - TerrainHeight.height_at(p.x, p.z - 2))
			var score := minf(clear, 14.0) - slope * 4.0 - r * 0.03
			if score > best_score:
				best_score = score
				best = p
	return Vector3(best.x, TerrainHeight.height_at(best.x, best.z), best.z)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shelter_gallery needs a window")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	LevelState.begin(1, -1, 1, 0)
	main_n = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_n)
	current_scene = main_n
	await _frames(40)
	d = main_n.get_node("GameDirector")
	d.start_game()
	await _frames(20)
	d.weather.current_time_minutes = 12.5 * 60.0
	d.player.controls_enabled = false
	var rig = d.rig
	var spawn: Vector3 = d.player.global_position
	var open := _open_spot(spawn)
	# 人物特写
	# 人物站在开阔的向阳处（离开那块空地中心几米，避开倒木的影子）
	var hp: Vector3 = open + rig.global_transform.basis.x * 5.0
	hp.y = TerrainHeight.height_at(hp.x, hp.z)
	d.player.global_position = hp + Vector3(0, 0.3, 0)
	d._set_figure_particles(false)
	_hide_hud()
	var face: Vector3 = rig.global_transform.basis.z
	for k in 3:
		# 正面 3/4、侧面、背面 3/4
		var yaw: float = atan2(face.x, face.z) + [deg_to_rad(-35.0), deg_to_rad(-90.0), deg_to_rad(150.0)][k]
		d.player.visual_node.rotation = Vector3(0, yaw, 0)
		rig.set_focus(hp + Vector3(0, 0.9, 0), 0.16)
		await _frames(100)
		await _shot("hiker_close_%d" % k)
	rig.clear_focus()
	d._set_figure_particles(true)
	for preset in PRESETS:
		if not only.is_empty() and not (preset in only):
			continue
		var pos := open
		if preset == "TreeWell":
			var t: Dictionary = OldSpruces.nearest(Vector2(open.x, open.z))
			pos = Vector3(t["point"].x, TerrainHeight.height_at(t["point"].x, t["point"].y), t["point"].y)
		_hide_hud()
		# 入口朝镜头左前方：和游戏里一样，玩家能看见门
		var cam_dir: Vector3 = rig.global_transform.basis.z
		cam_dir.y = 0.0
		var door := cam_dir.normalized().rotated(Vector3.UP, deg_to_rad(-35.0))
		var site := ShelterSite.new()
		site.name = "GallerySite"
		site.setup(preset, door, 2.6, 0.0, preset in ["RockOverhang", "FallenLog"])
		site.position = pos
		main_n.add_child(site)
		d.site = site
		# 人物站到旁边去（镜头右侧），不挡住庇护所
		var right_dir: Vector3 = rig.global_transform.basis.x
		d.player.global_position = pos + right_dir * 3.6 + door * 1.2 + Vector3(0, 0.3, 0)
		var aim := pos + Vector3(0, 0.7, 0)
		# 画廊自己的相机：和游戏一样 35° 俯角、同一个朝向，只是更近，好看清模型
		var gcam := Camera3D.new()
		gcam.fov = 40.0
		main_n.add_child(gcam)
		var back: Vector3 = rig.global_transform.basis.z
		back.y = 0.0
		var view_from := aim + (back.normalized() * cos(deg_to_rad(35.0)) + Vector3.UP * sin(deg_to_rad(35.0))) * (12.0 if preset == "TreeWell" else 9.0)
		gcam.global_position = view_from
		gcam.look_at(aim + (Vector3(0, 0.8, 0) if preset == "TreeWell" else Vector3.ZERO), Vector3.UP)
		for s in STAGES:
			while site.stage() < s:
				site.advance()
			gcam.make_current()
			await _frames(30)
			await _shot("%s_s%d" % [preset, s])
		gcam.queue_free()
		d._enter_shelter()
		await _frames(170)
		_hide_hud()
		await _shot("%s_section" % preset)
		d._leave_shelter()
		await _frames(60)
		rig.clear_focus()
		d.site = null
		d._update_section(false)
		site.queue_free()
		await _frames(10)
	quit(0)

func _hide_hud() -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
