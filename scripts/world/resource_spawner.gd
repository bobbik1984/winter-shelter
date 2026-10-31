class_name ResourceSpawner
extends Node3D

## 可采集资源与天然挡风物的摆放（T2.2 / Read the Land 第 4 条）：
##   立枯木 deadwood → 干木材；白桦 birch → 桦树皮（引火物）；干草 / 云杉低枝 → 垫层；
##   半埋湿倒木 wet_log → "湿木不能烧"教学反馈；翻倒树根 rootball → 天然挡风（倒棚 / 生火）。
## 摆放确定性（哈希），避开出生点、雪洞位与视野走廊中心。

const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")
const SPAWN := Vector2(18.0, 8.0)
## 固定点位：参考图标志性的交互立枯木、篝火旁的树根盘。
const FIXED_DEADWOOD := [Vector2(5.5, 3.5)]
const FIXED_ROOTBALLS := [Vector2(-4.2, 10.5), Vector2(30.0, 22.0), Vector2(8.0, 26.0)]

var tuning: Tuning
var _placed: Array[Vector2] = []
var _mat_snag: ShaderMaterial
var _mat_birch: StandardMaterial3D
var _mat_grass: StandardMaterial3D
var _mat_log: ShaderMaterial
var _mat_root: ShaderMaterial
var _mat_bough: ShaderMaterial

## 由 GameDirector 注入：交互完成后的处理函数（按 kind 分发）。
var on_harvest: Callable

func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/tuning.tres") as Tuning
	_make_materials()
	for p in FIXED_ROOTBALLS:
		_spawn_rootball(p, _placed.size())
	for p in FIXED_DEADWOOD:
		_spawn_deadwood(p, 0)
	var k := 0
	k = _scatter(tuning.deadwood_spots - FIXED_DEADWOOD.size(), 10.0, 38.0, 11, _spawn_deadwood)
	k = _scatter(tuning.birch_spots, 8.0, 34.0, 23, _spawn_birch)
	k = _scatter(int(tuning.bedding_spots * 0.6), 4.0, 26.0, 37, _spawn_grass)
	k = _scatter(tuning.bedding_spots - int(tuning.bedding_spots * 0.6), 6.0, 30.0, 41, _spawn_bough)
	k = _scatter(3, 6.0, 30.0, 53, _spawn_wet_log)

func _make_materials() -> void:
	_mat_snag = _snow_mat(Color(0.42, 0.38, 0.34), 0.25)
	_mat_snag.set_shader_parameter("occlusion_fade", true)
	_mat_log = _snow_mat(Color(0.20, 0.15, 0.10), 0.55)
	_mat_root = _snow_mat(Color(0.24, 0.18, 0.13), 0.35)
	_mat_bough = _snow_mat(Color(0.07, 0.20, 0.12), 0.45)
	_mat_birch = StandardMaterial3D.new()
	_mat_birch.vertex_color_use_as_albedo = true
	_mat_birch.roughness = 0.9
	_mat_grass = StandardMaterial3D.new()
	_mat_grass.albedo_color = Color(0.74, 0.60, 0.33)
	_mat_grass.roughness = 0.95

func _snow_mat(base: Color, amount: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SNOW_COVER_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("snow_amount", amount)
	return m

## 在出生点周围 [rmin, rmax] 环带内按哈希找合法点位。
func _scatter(count: int, rmin: float, rmax: float, seed_k: int, spawn_fn: Callable) -> int:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 60:
		tries += 1
		var a := TerrainHeight.hash2(tries, seed_k, 7) * TAU
		var r := lerpf(rmin, rmax, sqrt(TerrainHeight.hash2(tries, seed_k, 13)))
		var p := SPAWN + Vector2(cos(a), sin(a)) * r
		if absf(p.x) > 44.0 or absf(p.y) > 44.0:
			continue
		if TerrainHeight.slope_at(p.x, p.y) > 26.0:
			continue
		if not _free(p, 4.0):
			continue
		spawn_fn.call(p, placed + seed_k * 10)
		placed += 1
	return placed

func _free(p: Vector2, min_d: float) -> bool:
	if p.distance_to(SPAWN) < 3.5 or p.distance_to(Vector2(20.5, 11.2)) < 3.0:
		return false
	for q in _placed:
		if p.distance_to(q) < min_d:
			return false
	return true

func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, TerrainHeight.height_at(p.x, p.y), p.y)

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, rot_y: float = 0.0, s: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation.y = rot_y
	mi.scale = Vector3.ONE * s
	parent.add_child(mi)
	return mi

func _interactable(root: Node3D, kind: String, prompt: String, uses: int, ring: float) -> Interactable:
	var it := Interactable.new()
	it.kind = kind
	it.prompt = prompt
	it.uses_left = uses
	it.ring_radius = ring
	it.hold_seconds = tuning.gather_seconds
	it.position = Vector3(0, 0.3, 0)
	root.add_child(it)
	it.handler = func() -> Dictionary: return on_harvest.call(it) if on_harvest.is_valid() else {}
	return it

func _root(name_: String, p: Vector2) -> Node3D:
	_placed.append(p)
	var root := Node3D.new()
	root.name = name_
	root.position = _ground(p)
	add_child(root)
	return root

func _spawn_deadwood(p: Vector2, i: int) -> void:
	var root := _root("Deadwood", p)
	root.position.y -= 0.2
	_mesh(root, PropMeshes.snag(70 + i), _mat_snag, TerrainHeight.hash2(i, 5, 9) * TAU, 1.0)
	_interactable(root, "deadwood", "Harvest standing deadwood (dry fuel)", tuning.deadwood_uses, 1.0)

func _spawn_birch(p: Vector2, i: int) -> void:
	var root := _root("Birch", p)
	_mesh(root, PropMeshes.birch(80 + i), _mat_birch, TerrainHeight.hash2(i, 7, 9) * TAU)
	_interactable(root, "birch", "Peel birch bark (tinder)", 3, 0.8)

func _spawn_grass(p: Vector2, i: int) -> void:
	var root := _root("DryGrass", p)
	for k in range(3):
		var m := _mesh(root, PropMeshes.grass_tuft(90 + i * 3 + k), _mat_grass, k * 1.7)
		m.position = Vector3(cos(k * 2.1) * 0.4, 0, sin(k * 2.1) * 0.4)
	_interactable(root, "grass", "Gather dry grass (bedding)", 1, 0.8)

func _spawn_bough(p: Vector2, i: int) -> void:
	var root := _root("SpruceBoughs", p)
	var m := _mesh(root, SpruceMesh.build(100 + i, Vector3.RIGHT, 0.2, 7), _mat_bough, 0.0, 0.32)
	m.scale.y = 0.22
	_interactable(root, "bough", "Cut low spruce boughs (bedding)", 2, 1.0)

func _spawn_wet_log(p: Vector2, i: int) -> void:
	var root := _root("WetLog", p)
	root.position.y -= 0.08
	_mesh(root, PropMeshes.wet_log(110 + i), _mat_log, TerrainHeight.hash2(i, 3, 9) * TAU)
	_interactable(root, "wet_log", "Chop fallen log", 1, 1.2)

func _spawn_rootball(p: Vector2, i: int) -> void:
	var root := _root("Rootball", p)
	root.add_to_group("windbreaks")
	# 树根盘面朝西（迎风），倒伏树干朝东躺下：背风侧（东）形成避风凹窝
	_mesh(root, PropMeshes.rootball(120 + i), _mat_root, 0.0)

## 最近的天然挡风物距离。
static func nearest_windbreak_distance(tree: SceneTree, pos: Vector3) -> float:
	var best := INF
	for n in tree.get_nodes_in_group("windbreaks"):
		var w := n as Node3D
		best = minf(best, Vector2(w.global_position.x - pos.x, w.global_position.z - pos.z).length())
	return best
