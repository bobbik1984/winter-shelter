extends SceneTree
## 情报 · 庇护所卡片的配图：每种庇护所完工后的外观 + 剖面，各一张，相机按庇护所实际大小取景。
## 必须窗口模式：godot --path . --resolution 1280x720 -s res://tools/shelter_cards.gd -- [--out=assets/ui/shelters] [--only=TreeWell]
## 输出 <id>_out.webp / <id>_cut.webp（480×270，有损 WebP，每张约 15–25 KB）。模型改了就重跑。
## 树井只出剖面（从外面看就是一棵树的树冠）。

const PRESETS := ["RaisedCave", "BasicCave", "SnowTrench", "LeanTo", "TreeWell", "Quinzhee", "RockOverhang", "FallenLog"]
const W := 480
const H := 270

var out_dir := "res://assets/ui/shelters"
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

func _frames(n: int) -> void:
	for i in n:
		await process_frame

## zoom > 1：裁出画面中间 1/zoom 的部分（剖面用游戏自己的洞内相机，庇护所在画面正中但偏小）。
func _shot(name_: String, zoom: float = 1.0) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if zoom > 1.0:
		var cw := int(img.get_width() / zoom)
		var ch := int(img.get_height() / zoom)
		img = img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2 - int(img.get_height() * 0.03), cw, ch))
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path(out_dir.path_join(name_ + ".webp"))
	img.save_webp(path, true, 0.82)
	print("CARD ", path)

## 庇护所所有可见网格的包围盒（世界坐标）。
func _bounds(site: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in site.find_children("*", "MeshInstance3D", true, false):
		var vi := n as MeshInstance3D
		if not vi.is_visible_in_tree() or vi.mesh == null:
			continue
		var b := vi.global_transform * vi.get_aabb()
		if b.size.length() > 12.0:
			print("  skip big mesh ", vi.name, " ", b.size)
			continue
		box = b if first else box.merge(b)
		first = false
	return box

## 平坦、离树远的空地（树井例外：放在老云杉底下）。和 shelter_gallery 同一个办法。
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

func _aim(cam: Camera3D, box: AABB, dir: Vector3, elev_deg: float, fill: float) -> void:
	var c := box.get_center()
	var r := maxf(maxf(box.size.x, box.size.z) * 0.5 + box.size.y * 0.25, 1.2)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var v := (flat * cos(deg_to_rad(elev_deg)) + Vector3.UP * sin(deg_to_rad(elev_deg))).normalized()
	var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * fill
	cam.global_position = c + v * dist
	cam.look_at(c, Vector3.UP)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("shelter_cards needs a window")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
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
	d.player.visual_node.visible = false
	d._set_figure_particles(false)
	var rig = d.rig
	var spawn: Vector3 = d.player.global_position
	var open := _open_spot(spawn)
	for preset in PRESETS:
		if not only.is_empty() and not (preset in only):
			continue
		for n in root.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		var pos: Vector3 = open
		if preset == "TreeWell":
			var t: Dictionary = OldSpruces.nearest(Vector2(open.x, open.z))
			pos = Vector3(t["point"].x, TerrainHeight.height_at(t["point"].x, t["point"].y), t["point"].y)
		var cam_dir: Vector3 = rig.global_transform.basis.z
		cam_dir.y = 0.0
		var door := cam_dir.normalized().rotated(Vector3.UP, deg_to_rad(-35.0))
		var site := ShelterSite.new()
		site.name = "CardSite"
		site.setup(preset, door, 2.6, 0.0, preset in ["RockOverhang", "FallenLog"])
		site.position = pos
		main_n.add_child(site)
		d.site = site
		while site.stage() < 5:
			site.advance()
		d.player.global_position = pos + Vector3(30, 0, 30)
		var cam := Camera3D.new()
		cam.fov = 34.0
		main_n.add_child(cam)
		await _frames(20)
		var box := _bounds(site)
		print(preset, " bounds ", box.size)
		# 外观：从入口一侧斜前方看（看得见门），35° 俯角
		if preset == "TreeWell":
			# 树井从外面看就是一棵老云杉的树冠，坑在枝条底下看不见：卡片只用剖面图
			pass
		else:
			_aim(cam, box, door.rotated(Vector3.UP, deg_to_rad(30.0)), 32.0, 0.95)
			cam.make_current()
			await _frames(25)
			await _shot(preset + "_out")
		# 剖面：和游戏里进洞一样切开（切面法线 = 工地 +X），从切开的那一侧看进去
		d.player.global_position = pos
		d._enter_shelter()
		await _frames(60)
		d.player.visual_node.visible = false
		# 剖面：用游戏里进洞时那台相机（玩家看到的就是这个画面），裁中间
		for n in root.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		await _frames(30)
		await _shot(preset + "_cut", 1.55)
		d._leave_shelter()
		await _frames(30)
		d.rig.clear_focus()
		d._update_section(false)
		cam.queue_free()
		d.site = null
		site.queue_free()
		await _frames(10)
	quit(0)
