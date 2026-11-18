extends SceneTree
## Native fixed-light sample gallery + temporary whole-forest swaps. Never saves settings/records.
var d
var scene
var profiles: Array = []
var out := OS.get_cache_dir().path_join("winter-tree-candidates")
var results: Array = []
var gallery: Node3D
var gallery_labels: CanvasLayer
var hidden := {}
var forest
var scenery
var originals := {}
var overrides := {}
var original_small := {}
var mesh_cache := {}
var anchors_before := ""
var palette_materials: Dictionary = {}
var saved_play_cap := -1

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Tree candidate screenshots require a graphical display")
		quit(1)
		return
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Records.path = "user://test_tree_candidate_review.cfg"
	Loc.lang = "zh"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	_run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	for path in SpruceCrownMesh.PROFILES: profiles.append(load(path))
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(45)
	d = scene.get_node("GameDirector")
	d.graphics.level = 0 if "--low" in OS.get_cmdline_user_args() else 1
	d.graphics.apply()
	d.start_game()
	if "--uncapped" in OS.get_cmdline_user_args():
		saved_play_cap = d.graphics.power_tuning.mobile_play_fps
		# The director reapplies its budget; override that budget in this process, not just Engine.max_fps.
		d.graphics.power_tuning.mobile_play_fps = 0
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if RenderingServer.has_method("viewport_set_measure_render_time"):
		RenderingServer.call("viewport_set_measure_render_time", root.get_viewport_rid(), true)
	d.weather.time_scale = 0
	d.weather.current_time_minutes = 860
	d.player.controls_enabled = false
	forest = get_first_node_in_group("forest")
	scenery = get_first_node_in_group("scenery")
	anchors_before = JSON.stringify([Array(forest.spruce_points), Array(forest.snag_points), forest.rock_spheres])
	for node in forest.get_children():
		if node is MultiMeshInstance3D and String(node.name).begins_with("Spruce"):
			originals[node] = node.multimesh.mesh
			overrides[node] = node.material_override
	if scenery:
		for node in scenery.find_children("SpruceMesh", "MeshInstance3D", true, false):
			original_small[node] = node.mesh
			overrides[node] = node.material_override
	# Use one shared palette gain on the baseline and all candidates.
	for profile in profiles: assert(is_equal_approx(profile.needle_tone_gain, profiles[0].needle_tone_gain))
	for material in forest._fade_materials:
		if material.get_shader_parameter("tree_branches"):
			palette_materials[material] = [material.get_shader_parameter("base_color"), material.get_shader_parameter("sway_amount")]
			material.set_shader_parameter("sway_amount", 0.0)
			material.set_shader_parameter("base_color", EnvPalette.SPRUCE * profiles[0].needle_tone_gain)
	if scenery:
		palette_materials[scenery._mat_spruce] = [scenery._mat_spruce.get_shader_parameter("base_color"), scenery._mat_spruce.get_shader_parameter("sway_amount")]
		scenery._mat_spruce.set_shader_parameter("sway_amount", 0.0)
		scenery._mat_spruce.set_shader_parameter("base_color", EnvPalette.SPRUCE * profiles[0].needle_tone_gain)
	if not "--world-only" in OS.get_cmdline_user_args(): await _gallery()
	if "--gallery-only" in OS.get_cmdline_user_args():
		print("TREE GALLERY PASS")
		_restore()
		scene.queue_free()
		await frames(3)
		quit()
		return
	for style in range(-1, 3):
		_swap(style)
		await sample("forest_" + ("0" if style < 0 else profiles[style].sample_id))
	_restore()
	assert(anchors_before == JSON.stringify([Array(forest.spruce_points), Array(forest.snag_points), forest.rock_spheres]), "gameplay anchors must not move")
	var f := FileAccess.open(out.path_join("results.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"mobile_profile": GraphicsSettings.mobile_profile(), "measurements": results,
		"anchors_unchanged": true, "candidate_ids": ["0", "A", "B", "C"], "profile_paths": SpruceCrownMesh.PROFILES, "common_needle_tone_gain": profiles[0].needle_tone_gain, "sway_frozen_for_all_styles": true, "uncapped": "--uncapped" in OS.get_cmdline_user_args()}, "\t"))
	f.close()
	print("TREE CANDIDATES PASS; temporary samples only; anchors unchanged")
	scene.queue_free()
	await frames(3)
	quit()

func _gallery() -> void:
	for node in scene.get_children():
		if node is Node3D and node != d.rig and not node is Light3D:
			_hide(node)
	for node in scene.find_children("*", "CanvasLayer", true, false):
		_hide(node)
	for node in scene.find_children("*", "GeometryInstance3D", true, false):
		_hide(node)
	gallery = Node3D.new()
	scene.add_child(gallery)
	var center: Vector3 = d.player.global_position
	center.y = TerrainHeight.height_at(center.x, center.z) + 0.04
	var plane := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60, 60)
	plane.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = EnvironmentDetails.settings().snow_color
	floor_mat.roughness = 1.0
	plane.material_override = floor_mat
	plane.position = center - Vector3.UP * 0.02
	gallery.add_child(plane)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/snow_cover.gdshader")
	mat.set_shader_parameter("base_color", EnvPalette.SPRUCE * profiles[0].needle_tone_gain)
	mat.set_shader_parameter("bark_color", EnvPalette.DEAD_WOOD)
	mat.set_shader_parameter("tree_branches", true)
	mat.set_shader_parameter("snow_amount", 0.56)
	gallery_labels = CanvasLayer.new()
	scene.add_child(gallery_labels)
	var side: Vector3 = d.rig.camera_3d.global_basis.x
	side.y = 0
	side = side.normalized()
	var wind: Vector3 = d.wind.get_blow_direction_3d()
	for i in 4:
		var mesh := SpruceMesh.build_baseline(21, wind) if i == 0 else SpruceCrownMesh.build(21, wind, profiles[i - 1])
		var node := MeshInstance3D.new()
		mesh.surface_set_material(0, mat)
		node.mesh = mesh
		node.position = center + side * (float(i) - 1.5) * 5.3
		gallery.add_child(node)
		var label := Label.new()
		label.text = "0" if i == 0 else profiles[i - 1].sample_id
		label.add_theme_font_size_override("font_size", 36)
		label.add_theme_constant_override("outline_size", 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(100, 55)
		label.set_meta("anchor", node.position)
		gallery_labels.add_child(label)
		print("TREE MESH ", label.text, " triangles=", triangle_count(mesh))
	d.rig.set_focus(center + Vector3.UP * 0.4, 0.75)
	await create_timer(2).timeout
	await shot("gallery_near")
	d.rig.set_focus(center + Vector3.UP * 0.4, 1.0)
	await create_timer(1).timeout
	await shot("gallery_play_distance")
	gallery.visible = false
	gallery_labels.visible = false
	for node in hidden: node.visible = hidden[node]
	d.rig.clear_focus()
	await frames(30)

func _mesh(style: int, seed_idx: int, bias: float, material: Material) -> Mesh:
	var key := "%d:%d:%d:%d" % [style, seed_idx, roundi(bias * 1000), material.get_instance_id()]
	if not mesh_cache.has(key):
		var wind: Vector3 = d.wind.get_blow_direction_3d()
		mesh_cache[key] = SpruceMesh.build_baseline(seed_idx, wind, bias) if style < 0 else SpruceCrownMesh.build(seed_idx, wind, profiles[style], bias)
		mesh_cache[key].surface_set_material(0, material)
	return mesh_cache[key]
func _swap(style: int) -> void:
	for node in originals:
		var variant := int(String(node.name).trim_prefix("Spruce").split("_")[0])
		node.material_override = null
		node.multimesh.mesh = _mesh(style, 20 + variant, 0.38, overrides[node])
	for node in original_small:
		for variant in scenery._spruce_meshes:
			if original_small[node] == scenery._spruce_meshes[variant]:
				node.material_override = null
				node.mesh = _mesh(style, variant, scenery.wind_lean, overrides[node])
				break
func _restore() -> void:
	if saved_play_cap >= 0:
		d.graphics.power_tuning.mobile_play_fps = saved_play_cap
		d.graphics.set_scene_mode("playing")
	for material in palette_materials:
		material.set_shader_parameter("base_color", palette_materials[material][0])
		material.set_shader_parameter("sway_amount", palette_materials[material][1])
	for node in originals:
		node.multimesh.mesh = originals[node]
		node.material_override = overrides[node]
	for node in original_small:
		node.mesh = original_small[node]
		node.material_override = overrides[node]
func sample(name_: String) -> void:
	if "--uncapped" in OS.get_cmdline_user_args():
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(1.0).timeout
	var start := Time.get_ticks_usec()
	var before := Engine.get_process_frames()
	await create_timer(3.0).timeout
	var m := {"view": name_, "fps": float(Engine.get_process_frames() - before) / ((Time.get_ticks_usec() - start) / 1000000.0),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_scale": root.scaling_3d_scale, "max_fps": Engine.max_fps, "gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())}
	if "--uncapped" in OS.get_cmdline_user_args(): assert(Engine.max_fps == 0, "uncapped comparison must actually be uncapped")
	results.append(m)
	print("TREE PERF ", JSON.stringify(m))
	await shot(name_)
func shot(name_: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if gallery_labels != null and gallery_labels.visible:
		for label in gallery_labels.get_children():
			label.position = d.rig.camera_3d.unproject_position(label.get_meta("anchor")) + Vector2(-50, 24)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name_ + ".png"))

func triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count(): count += mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size() / 3
	return count

func _hide(node: Node) -> void:
	# A direct child can also be found in the geometry traversal. Save its original state once.
	if not hidden.has(node): hidden[node] = node.visible
	node.visible = false
