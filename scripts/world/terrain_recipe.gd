class_name TerrainRecipe
extends RefCounted

## D13 / S1 地形配方：一局地形 = 基础形态 × 起伏度 × 树木密度（+ 形态参数）。
## 所有形态都在"规范风向帧"里定义：风从 -X（网格 i 减小方向）吹来，i 增大 = 下风。
## 之后由 TerrainHeight.ROTATION_DEG 整体旋转到本局风向（L3），所以背风积雪永远在脊 / 崖 / 岸坎的下风侧。
## 默认值 = 旧的固定地图（逐字节一致，tests/test_terrain_recipe 断言）。

const SHAPES := ["ridge_valley", "basin", "lakeshore", "cliff_band"]

## [GAME] 基础形态。
var shape: String = "ridge_valley"
## [TUNE] 起伏度倍率：中尺度起伏与风积肋的幅度（1 = 旧地图；0.3 平坦，2 崎岖）。
var roughness: float = 1.0
## [TUNE] 树木密度 0..1（1 = 旧地图的林分；0 = 几乎无树）。ForestScatter 读取。
var tree_density: float = 1.0
## [TUNE] 脊线 / 崖线 / 湖岸在规范帧里的网格位置（i，0..51；旧脊线 = 17.8）。
var feature_i: float = 17.8
## [TUNE] 脊顶 / 崖高 / 岸坎高（m；旧脊顶 = 5.5）。
var feature_h: float = 5.5

static func default_recipe() -> TerrainRecipe:
	return TerrainRecipe.new()

## 形态的典型参数（测试与开发参数用）；随机抽取由关卡层（S3）决定。
static func preset(shape_name: String) -> TerrainRecipe:
	var r := TerrainRecipe.new()
	r.shape = shape_name
	match shape_name:
		"basin":
			r.feature_i = 0.0
			r.feature_h = 0.0
			r.roughness = 1.3
			r.tree_density = 0.6
		"lakeshore":
			r.feature_i = 15.0   # 湖岸线（i < 岸线 = 湖面）
			r.feature_h = 2.6    # 岸坎高
			r.roughness = 0.8
			r.tree_density = 0.8
		"cliff_band":
			r.feature_i = 16.0   # 崖线
			r.feature_h = 7.5    # 崖高
			r.roughness = 0.9
			r.tree_density = 0.9
	return r

func is_default() -> bool:
	return shape == "ridge_valley" and roughness == 1.0 and tree_density == 1.0 and feature_i == 17.8 and feature_h == 5.5

func describe() -> String:
	return "%s rough=%.2f trees=%.2f i=%.1f h=%.1f" % [shape, roughness, tree_density, feature_i, feature_h]

## 开发参数：--shape=<名字> [--rough=x] [--trees=x]。没有 --shape 时返回 null。
static func from_args(args: PackedStringArray) -> TerrainRecipe:
	var r: TerrainRecipe = null
	for a in args:
		if a.begins_with("--shape=") and a.substr(8) in SHAPES:
			r = preset(a.substr(8))
	if r == null:
		return null
	for a in args:
		if a.begins_with("--rough=") and a.substr(8).is_valid_float():
			r.roughness = float(a.substr(8))
		elif a.begins_with("--trees=") and a.substr(8).is_valid_float():
			r.tree_density = clampf(float(a.substr(8)), 0.0, 1.0)
	return r
