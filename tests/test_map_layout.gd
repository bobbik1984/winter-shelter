extends RefCounted

## S2（D13）：地物与出生点按规则摆放。旧地图 = 旧坐标（逐位）；其它配方在 4 山谷 × 2 风向下都满足摆放规则；结果可复现。

var _passed := 0
var _failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_failures.append(msg)

func run() -> Dictionary:
	_passed = 0
	_failures = []
	var seed0 := TerrainHeight.SEED
	var recipe0 := TerrainHeight.RECIPE
	var rot0 := TerrainHeight.ROTATION_DEG

	# 1. 旧地图 = 旧坐标（含旋转）
	TerrainHeight.RECIPE = TerrainRecipe.new()
	for rot in [0.0, 90.0]:
		TerrainHeight.ROTATION_DEG = rot
		var L := MapLayout.get_layout()
		_check(bool(L["legacy"]), "默认配方走旧布局")
		_check(L["spawn"] == TerrainHeight.to_world(MapLayout.LEGACY_SPAWN) and L["rootballs"].size() == 3
			and L["rootballs"][1] == TerrainHeight.to_world(MapLayout.LEGACY_ROOTBALLS[1])
			and L["clusters"].size() == 8 and L["keep_out"].size() == 6, "旋转 %d°：旧布局坐标不变（只随地图旋转）" % int(rot))

	# 2. 规则布局
	for sh in ["basin", "lakeshore", "cliff_band"]:
		for v in TerrainHeight.VALLEY_SEEDS:
			for rot in [0.0, 90.0]:
				TerrainHeight.SEED = v
				TerrainHeight.ROTATION_DEG = rot
				TerrainHeight.RECIPE = TerrainRecipe.preset(sh)
				var L := MapLayout.get_layout()
				var tag := "%s 山谷 %d 旋转 %d" % [sh, v, int(rot)]
				var sp: Vector2 = L["spawn"]
				_check(not bool(L["legacy"]), tag + "：走规则布局")
				_check(not TerrainHeight.is_lake_at(sp.x, sp.y) and TerrainHeight.slope_at(sp.x, sp.y) <= MapLayout.SPAWN_MAX_SLOPE
					and not MapLayout._near_steep(sp, 6.0), tag + "：出生点平缓、不在冰上、不在崖脚")
				var nd := _nearest_deep(sp)
				var deep_frac := float(SnowField.map_facts(load("res://resources/tuning.tres"))["frac_cave"])
				if deep_frac >= MapLayout.DEEP_MIN_FRACTION:
					_check(nd <= 32.0, tag + "：出生点 32 m 内有雪洞深度的雪（%.0f m）" % nd)
				var sd: Vector2 = L["special_deadwood"]
				_check(sd.distance_to(sp) >= 5.0 and sd.distance_to(sp) <= 12.0 and not TerrainHeight.is_lake_at(sd.x, sd.y), tag + "：交互枯木在出生点 5–12 m")
				var roots: Array = L["rootballs"]
				_check(roots.size() == MapLayout.ROOTBALL_COUNT, tag + "：%d 个树根盘（实际 %d）" % [MapLayout.ROOTBALL_COUNT, roots.size()])
				var ok_r := true
				for a in range(roots.size()):
					var p: Vector2 = roots[a]
					var d := p.distance_to(sp)
					if TerrainHeight.is_lake_at(p.x, p.y) or TerrainHeight.slope_at(p.x, p.y) > MapLayout.ROOTBALL_MAX_SLOPE or d < MapLayout.ROOTBALL_DIST.x or d > MapLayout.ROOTBALL_DIST.y:
						ok_r = false
					for b in range(a + 1, roots.size()):
						if p.distance_to(roots[b]) < MapLayout.ROOTBALL_SPACING:
							ok_r = false
				_check(ok_r, tag + "：树根盘平缓、不在冰上、离出生点 10–34 m、彼此 ≥ 12 m")
				var cl: Array = L["clusters"]
				var ok_c := cl.size() >= 6
				for a in range(cl.size()):
					var p: Vector2 = cl[a]
					if TerrainHeight.is_lake_at(p.x, p.y) or p.distance_to(sp) < 10.0:
						ok_c = false
					for b in range(a + 1, cl.size()):
						if p.distance_to(cl[b]) < MapLayout.CLUSTER_SPACING:
							ok_c = false
				_check(ok_c, tag + "：≥ 6 个生态小岛，不在冰上，彼此 ≥ 14 m（%d 个）" % cl.size())
				var k0: Vector3 = L["keep_out"][0]
				_check(Vector2(k0.x, k0.y) == sp, tag + "：避让圆包含出生点")
				# 可复现：清缓存后重算一致
				MapLayout._key = ""
				_check(MapLayout.get_layout() == L, tag + "：同一张图布局可复现")
	# 3. 换山谷 → 布局跟着变（缓存键）
	TerrainHeight.ROTATION_DEG = 0.0
	TerrainHeight.RECIPE = TerrainRecipe.preset("basin")
	TerrainHeight.SEED = 7
	var a7: Vector2 = MapLayout.spawn()
	TerrainHeight.SEED = 13
	_check(MapLayout.spawn() != a7, "换山谷后出生点重新计算")

	TerrainHeight.SEED = seed0
	TerrainHeight.RECIPE = recipe0
	TerrainHeight.ROTATION_DEG = rot0
	MapLayout._key = ""
	return {"passed": _passed, "failures": _failures}

func _nearest_deep(sp: Vector2) -> float:
	var best := INF
	var x := -46.0
	while x <= 46.0:
		var z := -46.0
		while z <= 46.0:
			if not TerrainHeight.is_lake_at(x, z) and TerrainHeight.snow_depth_at(x, z) >= MapLayout.DEEP_SNOW_M:
				best = minf(best, sp.distance_to(Vector2(x, z)))
			z += 2.0
		x += 2.0
	return best
