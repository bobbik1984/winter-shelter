extends SceneTree
## Native-window camp fixture. Isolated records; no persistent settings or gameplay changes.
var d
var site: ShelterSite
var out := OS.get_cache_dir().path_join("winter-camp-review")
var results: Array = []
var anchors: Dictionary
func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	Records.path = "user://test_camp_review.cfg"
	Loc.lang = "zh"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	_run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Screenshots require native rendering")
	DirAccess.make_dir_recursive_absolute(out)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	d = scene.get_node("GameDirector")
	await frames(40)
	d.graphics.level = 0 if "--low" in OS.get_cmdline_user_args() else 1
	d.graphics.apply()
	d.start_game()
	d.weather.time_scale = 0.0
	d.weather.current_time_minutes = 860.0
	d.weather._apply_sun()
	d.player.set_physics_process(false)
	await frames(20)
	var forest = get_first_node_in_group("forest")
	anchors = {"trees": Array(forest.spruce_points), "snags": Array(forest.snag_points), "rocks": forest.rock_spheres.duplicate()}
	site = ShelterSite.new()
	site.position = d.player.global_position + Vector3(3, 0, -3)
	var facing: Vector3 = d.rig.camera_offset(0.5)
	facing.y = 0
	site.setup("RaisedCave", facing.normalized(), 2.5, 22.0, true)
	scene.add_child(site)
	site.builder.current_stage = 5
	site._refresh()
	# Fixture stock is explicit. Every displayed log/bough must correspond to actual stock.
	# Exercise stock refresh / stage replacement in the real node lifecycle.
	for stage_idx in [0, 1, 2, 5]:
		site.builder.current_stage = stage_idx
		site._refresh()
		await frames(2)
		assert(site._visual.find_children("CampGroundDress", "MeshInstance3D", true, false).size() == (1 if stage_idx >= 2 else 0))
		if stage_idx > 0:
			var skirt := site._visual.get_node("GroundSkirt") as MeshInstance3D
			for normal in skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]: assert(normal.y > 0)
	site.pile.stock = {"wood": 0, "bedding": 0}
	site.refresh_pile()
	assert(site._pile_root.get_child_count() == 0)
	site.pile.stock = {"wood": 12, "bedding": 4}
	site.refresh_pile()
	site.refresh_pile()
	assert(site._pile_root.get_child_count() == 2)
	assert(site._pile_root.get_node("StoredWood").multimesh.instance_count == 12)
	assert(site._pile_root.get_node("StoredBoughs").multimesh.instance_count == 4)
	print("CAMP pile=", site._pile_root.global_position, " site=", site.global_position)
	if "--stock-only" in OS.get_cmdline_user_args():
		d.rig.set_focus(site._pile_root.global_position, 0.3)
		await sample("stock_close")
		quit()
		return
	d.rig.set_focus(site.global_position, 0.52)
	await sample("camp_close")
	d.rig.set_focus(site.global_position, 0.85)
	await sample("camp_play")
	var rock: Vector3 = forest.rock_spheres[0]
	d.rig.set_focus(Vector3(rock.x, TerrainHeight.height_at(rock.x, rock.y), rock.y), 0.5)
	await sample("rock_close")
	d.weather.current_time_minutes = 1380
	d.weather._apply_sun()
	d.rig.set_focus(site.global_position, 0.6)
	await sample("camp_night")
	d.weather.current_time_minutes = 860
	d.weather._apply_sun()
	d.rig.set_focus(site._pile_root.global_position, 0.3)
	await sample("stock_close")
	assert(anchors.trees == Array(forest.spruce_points) and anchors.snags == Array(forest.snag_points) and anchors.rocks == forest.rock_spheres)
	assert(site.pile.stock == {"wood": 12, "bedding": 4})
	var f := FileAccess.open(out.path_join("results.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"measurements": results, "anchors_unchanged": true, "stock_unchanged": true, "fixture_site": site.global_position, "fixture_pile": site._pile_root.global_position, "fixture_stock": site.pile.stock}, "\t"))
	f.close()
	print("CAMP REVIEW PASS")
	scene.queue_free()
	await frames(3)
	quit()
func sample(label: String) -> void:
	await create_timer(1.5).timeout
	var start := Time.get_ticks_usec()
	var count := Engine.get_process_frames()
	await create_timer(3.0).timeout
	var m := {"view": label, "fps": (Engine.get_process_frames() - count) / ((Time.get_ticks_usec() - start) / 1000000.0),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()), "render_scale": root.scaling_3d_scale}
	results.append(m)
	print("CAMP ", JSON.stringify(m))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + ".png"))
	# Supplementary art view keeps the same camera/material; UI-inclusive frame above is authoritative for cost.
	var layers := {}
	for layer in root.find_children("*", "CanvasLayer", true, false):
		layers[layer] = layer.visible
		layer.visible = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + "_clean.png"))
	for layer in layers: layer.visible = layers[layer]
