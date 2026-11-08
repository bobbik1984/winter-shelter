extends SceneTree
## 小动物测试：玩家走近，兔子要先僵住再跑开（距离变大）、乌鸦要飞起来；夜里不显示；走远了不乱跑。
## 运行：godot --headless --path . -s res://tools/wildlife_test.gd
var fails: Array[String] = []

func check(c: bool, msg: String) -> void:
	if not c:
		fails.append(msg)
	printerr(("PASS " if c else "FAIL ") + msg)

func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	_run.call_deferred()

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	LevelState.begin(1, -1, 1, 0)
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 40: await process_frame
	var d = m.get_node("GameDirector")
	d.start_game()
	for i in 30: await process_frame
	var w: Wildlife = d.wildlife
	check(w != null and w.rabbit_count_alive() == w.rabbit_count and w._birds.size() == w.bird_count, "the map has rabbits and birds")
	# 倒木：不再根根平行。树根盘顺风 ± 40°，别的倒木朝向各不相同
	var blow: Vector3 = d.wind.get_blow_direction_3d()
	var wind_yaw := atan2(-blow.z, blow.x)
	var yaws: Array[float] = []
	var within := true
	for n in get_nodes_in_group("windbreaks"):
		for c in n.get_children():
			if c is MeshInstance3D:
				yaws.append((c as MeshInstance3D).rotation.y)
				within = within and absf(angle_difference(wind_yaw, (c as MeshInstance3D).rotation.y)) <= deg_to_rad(41.0)
	var all_same := true
	for y in yaws:
		all_same = all_same and absf(y - yaws[0]) < 0.01
	check(yaws.size() >= 3 and within and not all_same, "root-plate trees fall downwind but not all alike (%d trees)" % yaws.size())
	var forest := get_first_node_in_group("forest")
	var sectors := {}
	var trunks: int = forest.fallen_trunk_yaws.size()
	for yaw in forest.fallen_trunk_yaws:
		sectors[int(floorf(fposmod(yaw, PI) / (PI / 6.0)))] = true   # 树干是轴，不分头尾：按 180° 归并成 6 个方向
	check(trunks >= 8 and sectors.size() >= 4, "fallen trunks point every which way (%d trunks in %d of 6 directions)" % [trunks, sectors.size()])
	var stumps := root.find_children("Stump*", "MultiMeshInstance3D", true, false).size()
	var shrubs := root.find_children("Shrub*", "MultiMeshInstance3D", true, false).size()
	check(stumps > 0 and shrubs > 0, "stumps and shrubs are scattered too (%d / %d chunks)" % [stumps, shrubs])
	# 离得远的时候都安安静静
	var r := w.nearest_rabbit(d.player.global_position)
	var rn: Node3D = r["n"]
	d.player.controls_enabled = false
	d.player.global_position = rn.position + Vector3(60.0, 0.5, 0.0)
	for i in 30: await process_frame
	check(w.rabbit_state(r) == "idle" and w.bird_states().all(func(s): return s == "idle"), "far from the player the animals stay put")
	# 走近：兔子先僵住（alert），再跑（flee），而且真的跑远了
	d.player.global_position = rn.position + Vector3(6.0, 0.5, 0.0)
	var d0 := _flat(rn.position, d.player.global_position)
	var seen := {}
	for i in 300:
		await process_frame
		seen[w.rabbit_state(r)] = true
	var d1 := _flat(rn.position, d.player.global_position)
	check(seen.has("alert") and seen.has("flee"), "a rabbit freezes, then bolts when you come close (%s)" % str(seen.keys()))
	check(d1 > d0 + 3.0, "and it ran away (%.1f m -> %.1f m)" % [d0, d1])
	check(absf(rn.position.x) < w.map_limit_m + 1.0 and absf(rn.position.z) < w.map_limit_m + 1.0, "it stays inside the valley")
	# 乌鸦：靠近就飞，而且飞起来
	var bn: Node3D = w._birds[0]["n"]
	d.player.global_position = bn.position + Vector3(4.0, 0.5, 0.0)
	var flew := false
	var top := 0.0
	for i in 120:
		await process_frame
		if String(w._birds[0]["state"]) == "flying":
			flew = true
			top = maxf(top, bn.position.y - TerrainHeight.height_at(bn.position.x, bn.position.z))
	check(flew and top > 1.0, "a raven takes off when you come close (up %.1f m)" % top)
	# 夜里不显示
	d._sleep(false)
	var t0 := Time.get_ticks_msec()
	while d.state != d.State.NIGHT and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	await process_frame
	check(d.state == d.State.NIGHT and not w.visible, "the animals are hidden at night")
	print("RESULT ", "PASS" if fails.is_empty() else "FAIL %d" % fails.size())
	quit(0 if fails.is_empty() else 1)
