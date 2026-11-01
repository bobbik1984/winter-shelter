extends RefCounted

## S1（D13）地形配方：默认配方 = 旧固定地图（参考值取自 S1 之前的代码）；每种形态的地形 / 积雪特征；
## 所有形态都有积雪覆盖（用户要求）；湖面判定随地图旋转；开发参数解析。

## [山谷, 世界坐标, 高度, 雪深]——S1 之前的 TerrainHeight 计算结果（逐位一致才算没改坏旧地图）。
const LEGACY_REF := [[7, Vector2(-30, -20), 3.365769, 0.392935], [7, Vector2(-10, 5), 5.396996, 0.393995], [7, Vector2(0, 0), 1.025409, 1.072908], [7, Vector2(12, -33), 0.200000, 1.128535], [7, Vector2(18, 8), 0.972762, 1.665955], [7, Vector2(25, 30), 0.411236, 2.135796], [7, Vector2(40, -10), 0.314561, 2.103256], [7, Vector2(-45, 44), 7.891225, 0.674834], [29, Vector2(-30, -20), 2.521276, 0.523565], [29, Vector2(-10, 5), 4.794275, 0.385163], [29, Vector2(0, 0), 0.641438, 0.842769], [29, Vector2(12, -33), 0.202747, 1.212635], [29, Vector2(18, 8), 0.919839, 1.538168], [29, Vector2(25, 30), 0.555277, 2.088639], [29, Vector2(40, -10), 0.597062, 2.329081], [29, Vector2(-45, 44), 7.759001, 0.583136]]

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
	TerrainHeight.ROTATION_DEG = 0.0

	# 1. 默认配方 = 旧地图
	TerrainHeight.RECIPE = TerrainRecipe.new()
	_check(TerrainHeight.RECIPE.is_default(), "新建配方是默认配方")
	var max_err := 0.0
	for r in LEGACY_REF:
		TerrainHeight.SEED = int(r[0])
		var p: Vector2 = r[1]
		max_err = maxf(max_err, absf(TerrainHeight.height_at(p.x, p.y) - float(r[2])))
		max_err = maxf(max_err, absf(TerrainHeight.snow_depth_at(p.x, p.y) - float(r[3])))
	_check(max_err < 2e-6, "默认配方与 S1 之前的地图一致（最大误差 %.2e）" % max_err)

	# 2. 每种形态（4 个山谷都要满足）
	for v in TerrainHeight.VALLEY_SEEDS:
		TerrainHeight.SEED = v
		for sh in ["basin", "lakeshore", "cliff_band"]:
			TerrainHeight.RECIPE = TerrainRecipe.preset(sh)
			var st := _stats()
			var tag := "%s 山谷 %d" % [sh, v]
			_check(st["bare"] <= 0.01, tag + "：陆地几乎不露地（有积雪覆盖）%.1f%%" % (st["bare"] * 100.0))
			_check(st["patchy"] <= 0.03, tag + "：陆地雪深 < 0.45 m 的比例很小 %.1f%%" % (st["patchy"] * 100.0))
			_check(st["h_min"] >= 0.2 and st["h_max"] < 14.0, tag + "：高度范围合理 %.1f–%.1f m" % [st["h_min"], st["h_max"]])
			match sh:
				"basin":
					_check(st["cave"] <= 0.01, tag + "：盆地几乎没有雪洞深度（%.1f%%）——雪沟 / 雪堆屋的地形" % (st["cave"] * 100.0))
					_check(st["lake"] == 0.0, tag + "：盆地没有湖")
				"lakeshore":
					_check(st["lake"] >= 0.15 and st["lake"] <= 0.45, tag + "：湖面占 15–45%% 地图（%.0f%%）" % (st["lake"] * 100.0))
					_check(st["lake_snow_max"] <= 0.3 and is_equal_approx(st["lake_h"], TerrainHeight.LAKE_ICE_H), tag + "：冰面平整、雪薄（≤ 0.3 m）")
					_check(st["cave"] >= 0.04 and st["cave"] <= 0.25, tag + "：岸后有雪洞深度但不多（%.1f%%）" % (st["cave"] * 100.0))
					_check(st["shore_band_snow"] > st["lake_snow_mean"] * 3.0, tag + "：岸坎后的积雪远深于冰面（%.2f vs %.2f m）" % [st["shore_band_snow"], st["lake_snow_mean"]])
				"cliff_band":
					_check(st["steep"] >= 0.01, tag + "：有陡于 55° 的崖面（%.1f%%）" % (st["steep"] * 100.0))
					_check(st["plateau_minus_low"] >= TerrainHeight.RECIPE.feature_h * 0.7, tag + "：高台比崖下低地高出 ≥ 0.7 × 崖高（%.1f m）" % st["plateau_minus_low"])
					_check(st["cave"] >= 0.06 and st["cave"] <= 0.3, tag + "：崖脚背风侧有雪洞深度（%.1f%%）" % (st["cave"] * 100.0))
					_check(st["deep_near_cliff"] >= 0.8, tag + "：雪洞深度的雪 ≥ 80%% 在崖线下风 16 m 内（%.0f%%）" % (st["deep_near_cliff"] * 100.0))

	# 3. 湖面判定随地图旋转
	TerrainHeight.SEED = 7
	TerrainHeight.RECIPE = TerrainRecipe.preset("lakeshore")
	var lake_pt := Vector2(-40.0, 0.0)
	_check(TerrainHeight.is_lake_at(lake_pt.x, lake_pt.y), "不旋转：西边（上风）是湖")
	TerrainHeight.ROTATION_DEG = 180.0
	var w := TerrainHeight.to_world(lake_pt)
	_check(TerrainHeight.is_lake_at(w.x, w.y) and not TerrainHeight.is_lake_at(lake_pt.x, lake_pt.y), "旋转 180°：湖跟着地图转到东边（上风仍是湖）")
	TerrainHeight.ROTATION_DEG = 0.0
	TerrainHeight.RECIPE = TerrainRecipe.new()
	_check(not TerrainHeight.is_lake_at(lake_pt.x, lake_pt.y), "非湖岸形态没有湖")

	# 4. 开发参数
	_check(TerrainRecipe.from_args(PackedStringArray(["--level=2"])) == null, "没有 --shape 不覆盖配方")
	var a := TerrainRecipe.from_args(PackedStringArray(["--shape=cliff_band", "--rough=1.6", "--trees=0.3"]))
	_check(a != null and a.shape == "cliff_band" and is_equal_approx(a.roughness, 1.6) and is_equal_approx(a.tree_density, 0.3), "--shape / --rough / --trees 解析")
	_check(TerrainRecipe.from_args(PackedStringArray(["--shape=volcano"])) == null, "未知形态忽略")

	TerrainHeight.SEED = seed0
	TerrainHeight.RECIPE = recipe0
	TerrainHeight.ROTATION_DEG = rot0
	return {"passed": _passed, "failures": _failures}

func _stats() -> Dictionary:
	var n := 0; var bare := 0; var patchy := 0; var cave := 0; var steep := 0
	var lake := 0; var lake_snow_max := 0.0; var lake_snow_sum := 0.0; var lake_h := 0.0
	var band_sum := 0.0; var band_n := 0
	var h_min := 1e9; var h_max := -1e9
	var plateau_sum := 0.0; var plateau_n := 0; var low_sum := 0.0; var low_n := 0
	var deep_near := 0
	var x := -48.0
	while x <= 48.0:
		var z := -48.0
		while z <= 48.0:
			var h := TerrainHeight.height_at(x, z)
			var s := TerrainHeight.snow_depth_at(x, z)
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
			var gi := TerrainHeight._grid_coord(x)
			var gj := TerrainHeight._grid_coord(z)
			if TerrainHeight.is_lake_at(x, z):
				lake += 1
				lake_snow_max = maxf(lake_snow_max, s)
				lake_snow_sum += s
				lake_h = h
			else:
				n += 1
				if s < 0.08: bare += 1
				if s < 0.45: patchy += 1
				if TerrainHeight.slope_at(x, z) > 55.0: steep += 1
				if TerrainHeight.RECIPE.shape == "lakeshore":
					var t := gi - TerrainHeight._shore_i(gj)
					if t >= 2.0 and t <= 6.0:
						band_sum += s
						band_n += 1
				if TerrainHeight.RECIPE.shape == "cliff_band":
					var tc := gi - TerrainHeight._cliff_i(gj)
					if tc < -3.0:
						plateau_sum += h; plateau_n += 1
					elif tc > 6.0:
						low_sum += h; low_n += 1
					if s >= 1.5 and tc >= -1.0 and tc <= 8.0:
						deep_near += 1
				if s >= 1.5: cave += 1
			z += 2.0
		x += 2.0
	var total := n + lake
	return {"bare": float(bare) / n, "patchy": float(patchy) / n, "cave": float(cave) / total, "steep": float(steep) / n,
		"lake": float(lake) / total, "lake_snow_max": lake_snow_max, "lake_snow_mean": lake_snow_sum / maxf(lake, 1),
		"lake_h": lake_h, "shore_band_snow": band_sum / maxf(band_n, 1), "h_min": h_min, "h_max": h_max,
		"plateau_minus_low": plateau_sum / maxf(plateau_n, 1) - low_sum / maxf(low_n, 1),
		"deep_near_cliff": float(deep_near) / maxf(cave, 1)}
