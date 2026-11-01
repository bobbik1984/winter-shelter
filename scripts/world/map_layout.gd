class_name MapLayout
extends RefCounted

## D13 / S2 地物与出生点按规则摆放（世界坐标），取代各脚本里写死的坐标。
## - 默认配方（旧脊线山谷）：返回旧坐标（经 TerrainHeight.to_world 旋转）——逐位保持旧地图、机器人与测试基准。
## - 其它配方：在真实地形上按规则挑选：不在湖面、不在陡坡、出生点离深雪"够得着但不在脚下"、树根盘彼此分开……
## 只依赖地形函数与 TerrainHeight.SEED，同一张图永远得到同一布局；按（山谷, 配方, 旋转, 雪深旋钮）缓存。

## 旧地图坐标（地图坐标，规范帧）。
const LEGACY_SPAWN := Vector2(18.0, 8.0)
const LEGACY_SPECIAL_DEADWOOD := Vector2(5.5, 3.5)
const LEGACY_ROOTBALLS := [Vector2(-4.2, 10.5), Vector2(30.0, 22.0), Vector2(8.0, 26.0)]
const LEGACY_CLUSTERS := [
	Vector2(-16.0, -8.0), Vector2(-11.0, 14.0), Vector2(-23.0, 2.0),
	Vector2(13.0, -18.0), Vector2(21.0, 2.0), Vector2(17.0, 16.0),
	Vector2(-2.0, 24.0), Vector2(27.0, -24.0),
]
const LEGACY_FOOTPRINT_START := Vector2(-8.0, -6.0)
const LEGACY_FOOTPRINT_END := Vector2(0.0, 0.0)
const LEGACY_CUTAWAY := Vector2(20.5, 11.2)
## 旧避让圆 (x, z, 半径)：出生点、篝火、剖面雪洞、交互枯木、脚印路径、出生点→枯木通道。
const LEGACY_KEEP_OUT := [
	Vector3(18.0, 8.0, 7.0), Vector3(-4.2, 9.2, 5.0), Vector3(20.5, 11.2, 5.0),
	Vector3(5.5, 3.5, 4.0), Vector3(-4.0, -3.0, 5.5), Vector3(10.0, 5.0, 5.0),
]

## [GAME] 规则参数（几何约束；S3 的难度旋钮会接管其中的距离 / 数量）。
const GRID_STEP := 4.0          # 候选点网格（m）
const SPAN := 40.0              # 候选范围 ±m
const SPAWN_MAX_SLOPE := 12.0
const SPAWN_DEEP_DIST := Vector2(8.0, 24.0)   # 出生点到最近雪洞深度点的理想距离（m）
const ROOTBALL_COUNT := 3   # 旧地图的数量；规则布局用 rootball_count()（随难度 / 风倒区）
const ROOTBALL_DIST := Vector2(10.0, 34.0)
const ROOTBALL_SPACING := 12.0
const ROOTBALL_MAX_SLOPE := 15.0
const CLUSTER_COUNT := 8
const CLUSTER_SPACING := 14.0
const CLUSTER_MAX_SLOPE := 25.0
const DEEP_SNOW_M := 1.5        # = D5 雪洞门槛（只用于"出生点离深雪多远"的打分）
## 雪洞深度的雪至少占候选点的这个比例，才把"离深雪够得着"计入出生点打分（盆地里零星一两处不算：那张图的答案本来就不是雪洞）。
const DEEP_MIN_FRACTION := 0.02

## D13 §9.6 难度（0 = 第 1 阶，1 = 第 10 阶）与额外树根盘（风倒区章节）。由 LevelState.apply_world 设置。
static var DIFFICULTY: float = 0.0
static var ROOTBALL_BONUS: int = 0

## 本图树根盘数量：难度越高越少（4 → 2），风倒区章节另加。
static func rootball_count() -> int:
	return maxi(int(round(lerpf(4.0, 2.0, DIFFICULTY))) + ROOTBALL_BONUS, 1)

static var _key := ""
static var _cache: Dictionary = {}

static func _current_key() -> String:
	return "%d|%s|%f|%f|%f|%f|%d" % [TerrainHeight.SEED, TerrainHeight.RECIPE.describe(), TerrainHeight.ROTATION_DEG,
		TerrainHeight.SNOW_SCALE, TerrainHeight.SNOW_PATCHINESS, DIFFICULTY, ROOTBALL_BONUS]

## 本图布局：{spawn, special_deadwood, rootballs[], clusters[], footprint_start, footprint_end, cutaway, keep_out[]}
## 点均为世界坐标 Vector2(x, z)；keep_out 为 Vector3(x, z, 半径)。legacy = 是否旧地图布局。
static func get_layout() -> Dictionary:
	var key := _current_key()
	if key != _key:
		_cache = _legacy() if TerrainHeight.RECIPE.is_default() else _by_rules()
		_key = key
	return _cache

static func spawn() -> Vector2:
	return get_layout()["spawn"]

static func _legacy() -> Dictionary:
	var tw := func(p: Vector2) -> Vector2: return TerrainHeight.to_world(p)
	var keep: Array = []
	for k in LEGACY_KEEP_OUT:
		var c: Vector2 = tw.call(Vector2(k.x, k.y))
		keep.append(Vector3(c.x, c.y, k.z))
	return {"legacy": true, "spawn": tw.call(LEGACY_SPAWN), "special_deadwood": tw.call(LEGACY_SPECIAL_DEADWOOD),
		"rootballs": LEGACY_ROOTBALLS.map(tw), "clusters": LEGACY_CLUSTERS.map(tw),
		"footprint_start": tw.call(LEGACY_FOOTPRINT_START), "footprint_end": tw.call(LEGACY_FOOTPRINT_END),
		"cutaway": tw.call(LEGACY_CUTAWAY), "keep_out": keep}

# ------------------------------------------------------------------ 规则

static func _ok_ground(p: Vector2, max_slope: float) -> bool:
	return absf(p.x) <= 44.0 and absf(p.y) <= 44.0 and not TerrainHeight.is_lake_at(p.x, p.y) \
		and TerrainHeight.slope_at(p.x, p.y) <= max_slope

## 附近（r m 内）有没有崖面 / 陡坎——出生点、树根盘都不放在崖脚碎石区。
static func _near_steep(p: Vector2, r: float) -> bool:
	for a in range(8):
		var q := p + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * r
		if TerrainHeight.slope_at(q.x, q.y) > 40.0:
			return true
	return false

static func _jitter(p: Vector2, salt: int) -> float:
	return TerrainHeight.hash2(int(p.x * 7.0), int(p.y * 7.0), TerrainHeight.SEED * 131 + salt)

static func _candidates() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x := -SPAN
	while x <= SPAN:
		var z := -SPAN
		while z <= SPAN:
			# 网格抖动，避免布局看起来对齐
			var p := Vector2(x, z)
			p += Vector2(_jitter(p, 1) - 0.5, _jitter(p, 2) - 0.5) * GRID_STEP * 0.8
			out.append(p)
			z += GRID_STEP
		x += GRID_STEP
	return out

static func _by_rules() -> Dictionary:
	var cands := _candidates()
	# 雪洞深度点（打分用）
	var deep: Array[Vector2] = []
	for p in cands:
		if not TerrainHeight.is_lake_at(p.x, p.y) and TerrainHeight.snow_depth_at(p.x, p.y) >= DEEP_SNOW_M:
			deep.append(p)

	# 1. 出生点：平缓、不在湖上、不在崖脚；脚下雪中等；离最近的深雪"够得着但不在脚下"；不要太靠地图边
	var spawn_p := Vector2.ZERO
	var best := -1e9
	for p in cands:
		if not _ok_ground(p, SPAWN_MAX_SLOPE) or _near_steep(p, 6.0):
			continue
		var s := TerrainHeight.snow_depth_at(p.x, p.y)
		var score := -absf(s - 0.9) * 2.0 - maxf(0.0, p.length() - 24.0) * 0.4 + _jitter(p, 3) * 3.0
		if deep.size() >= int(DEEP_MIN_FRACTION * cands.size()) and not deep.is_empty():
			var d := 1e9
			for q in deep:
				d = minf(d, p.distance_to(q))
			# 难度越高，深雪离出生点越远（8–24 m → 16–32 m）
			var band := SPAWN_DEEP_DIST + Vector2(8.0, 8.0) * DIFFICULTY
			score -= maxf(0.0, band.x - d) * 1.0 + maxf(0.0, d - band.y) * 0.6
		if score > best:
			best = score
			spawn_p = p

	# 2. 交互枯木：出生点 6–11 m
	var special := spawn_p + Vector2(7.0, 0.0)
	best = -1e9
	for k in range(24):
		var a := TAU * float(k) / 24.0
		var p := spawn_p + Vector2(cos(a), sin(a)) * lerpf(6.0, 11.0, _jitter(Vector2(k, 3), 4))
		if not _ok_ground(p, 20.0):
			continue
		var sc := _jitter(p, 5)
		if sc > best:
			best = sc
			special = p

	# 3. 树根盘（风倒木）：离出生点 10–34 m，彼此 ≥ 12 m，平缓、不在湖上、不在崖脚
	var roots: Array[Vector2] = []
	var order: Array[Vector2] = cands.duplicate()
	order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return _jitter(a, 6) > _jitter(b, 6))
	for p in order:
		if roots.size() >= rootball_count():
			break
		var d := p.distance_to(spawn_p)
		if d < ROOTBALL_DIST.x or d > ROOTBALL_DIST.y or not _ok_ground(p, ROOTBALL_MAX_SLOPE) or _near_steep(p, 4.0):
			continue
		if p.distance_to(special) < 5.0 or roots.any(func(q: Vector2) -> bool: return p.distance_to(q) < ROOTBALL_SPACING):
			continue
		roots.append(p)

	# 4. 生态小岛（云杉 + 岩石 + 干草）：彼此 ≥ 14 m，离出生点 ≥ 10 m
	var clusters: Array[Vector2] = []
	order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return _jitter(a, 7) > _jitter(b, 7))
	for p in order:
		if clusters.size() >= CLUSTER_COUNT:
			break
		if not _ok_ground(p, CLUSTER_MAX_SLOPE) or p.distance_to(spawn_p) < 10.0:
			continue
		if clusters.any(func(q: Vector2) -> bool: return p.distance_to(q) < CLUSTER_SPACING) \
				or roots.any(func(q: Vector2) -> bool: return p.distance_to(q) < 6.0):
			continue
		clusters.append(p)

	# 5. 脚印链：从 9 m 外走到出生点旁；剖面雪洞原点：出生点旁（同旧地图的相对位置）
	var fdir := (spawn_p - special).normalized().rotated(0.9)
	var fstart := spawn_p + fdir * 9.0
	if not _ok_ground(fstart, 30.0):
		fstart = spawn_p - fdir * 9.0
	var fend := spawn_p + fdir * 2.5
	var cut := spawn_p + Vector2(2.5, 3.2)

	var keep: Array = [Vector3(spawn_p.x, spawn_p.y, 7.0), Vector3(cut.x, cut.y, 5.0), Vector3(special.x, special.y, 4.0)]
	var mid := (fstart + fend) * 0.5
	keep.append(Vector3(mid.x, mid.y, 5.5))
	var path := (spawn_p + special) * 0.5
	keep.append(Vector3(path.x, path.y, 5.0))
	if not roots.is_empty():
		keep.append(Vector3(roots[0].x, roots[0].y, 5.0))
	return {"legacy": false, "spawn": spawn_p, "special_deadwood": special, "rootballs": roots, "clusters": clusters,
		"footprint_start": fstart, "footprint_end": fend, "cutaway": cut, "keep_out": keep}
