class_name ResourceSpawner
extends Node3D

## 可采集资源与天然挡风物的摆放（T2.2 / Read the Land 第 4 条）：
##   立枯木 deadwood → 干木材；白桦 birch → 桦树皮（引火物）；干草 / 云杉低枝 → 垫层；
##   半埋湿倒木 wet_log → "湿木不能烧"教学反馈；翻倒树根 rootball → 天然挡风（倒棚 / 生火）。
## 摆放确定性（哈希），避开出生点、雪洞位与视野走廊中心。

const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")
## 固定点位：参考图标志性的交互立枯木、篝火旁的树根盘。

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
	# 树根盘与交互枯木的位置来自 MapLayout（S2：旧地图 = 旧坐标；其它配方按规则摆放）
	var layout := MapLayout.get_layout()
	for p in layout["rootballs"]:
		_spawn_rootball(p, _placed.size())
	_spawn_deadwood(layout["special_deadwood"], 0)
	var k := 0
	k = _scatter(int(round((tuning.deadwood_spots - 1) * LevelState.snag_density_scale())), 10.0, 38.0, 11, _spawn_deadwood)
	k = _scatter(tuning.birch_spots, 8.0, 34.0, 23, _spawn_birch)
	k = _scatter(int(tuning.bedding_spots * 0.6), 4.0, 26.0, 37, _spawn_grass)
	k = _scatter(tuning.bedding_spots - int(tuning.bedding_spots * 0.6), 6.0, 30.0, 41, _spawn_bough)
	k = _scatter(tuning.fallen_log_spots, 6.0, 30.0, 53, _spawn_wet_log)
	_attach_existing_snags.call_deferred()

## "occlusion_fade" 组回调：立枯木挡住玩家 / 工地时镂空。（立枯木材质早就开了镂空，但一直没收到焦点，所以从未生效。）
func set_focus(pos: Vector3) -> void:
	if _mat_snag:
		_mat_snag.set_shader_parameter("focus_pos", pos)
		_mat_root.set_shader_parameter("focus_pos", pos)

func set_focus_fade(radius: float, strength: float) -> void:
	if _mat_snag:
		_mat_snag.set_shader_parameter("occlusion_radius", radius)
		_mat_snag.set_shader_parameter("occlusion_strength", strength)
		_mat_root.set_shader_parameter("occlusion_radius", radius)
		_mat_root.set_shader_parameter("occlusion_strength", strength)

## 剖面切开（"occlusion_fade" 组回调，见 snow_cover.gdshader 的 section_*）。
func set_section(on: bool, point: Vector3, normal: Vector3, radius: float) -> void:
	for m in [_mat_snag, _mat_root]:
		if m is ShaderMaterial:
			var sm := m as ShaderMaterial
			sm.set_shader_parameter("section_on", on)
			sm.set_shader_parameter("section_point", point)
			sm.set_shader_parameter("section_normal", normal)
			sm.set_shader_parameter("section_radius", radius)

func _make_materials() -> void:
	add_to_group("occlusion_fade")
	_mat_snag = _snow_mat(Color(0.32, 0.30, 0.28), 0.25)
	_mat_snag.set_shader_parameter("occlusion_fade", true)
	_mat_snag.set_shader_parameter("rim_amount", 0.45)
	_mat_log = _snow_mat(Color(0.20, 0.15, 0.10), 0.55)
	_mat_root = _snow_mat(Color(0.24, 0.18, 0.13), 0.35)
	_mat_root.set_shader_parameter("occlusion_fade", true)   # 翻倒的树根盘有 3 m 高，会挡住走到它后面的玩家
	_mat_bough = _snow_mat(Color(0.20, 0.46, 0.22), 0.16)
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
		var p := MapLayout.spawn() + Vector2(cos(a), sin(a)) * r
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
	if TerrainHeight.is_lake_at(p.x, p.y):
		return false
	if p.distance_to(MapLayout.spawn()) < 3.5 or p.distance_to(MapLayout.get_layout()["cutaway"]) < 3.0:
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

## 树干类资源的碰撞（立枯木 / 白桦 / 树根盘）。
func _trunk(root: Node3D, radius: float, height: float = 4.0) -> void:
	var body := StaticBody3D.new()
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position = Vector3(0, height * 0.4, 0)
	body.add_child(cs)

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
	_trunk(root, 0.25)
	_interactable(root, "deadwood", Loc.t("Harvest standing deadwood (dry fuel)"), tuning.deadwood_uses, 1.0)

## 森林 / 场景里已有的立枯木（MultiMesh 或拼装体）同样是燃料：只挂采集点，不另建网格。
func _attach_existing_snags() -> void:
	var pts := PackedVector2Array()
	for g in ["forest", "scenery"]:
		var n := get_tree().get_first_node_in_group(g)
		if n == null:
			continue
		pts.append_array(n.snag_points if g == "forest" else n.deadwood_points)
	for p in pts:
		var root := Node3D.new()
		root.name = "SnagHarvest"
		root.position = _ground(p)
		add_child(root)
		_interactable(root, "deadwood", Loc.t("Harvest standing deadwood (dry fuel)"), tuning.deadwood_uses, 1.0)


func _spawn_birch(p: Vector2, i: int) -> void:
	var root := _root("Birch", p)
	_mesh(root, PropMeshes.birch(80 + i), _mat_birch, TerrainHeight.hash2(i, 7, 9) * TAU)
	_trunk(root, 0.2)
	_interactable(root, "birch", Loc.t("Peel birch bark (tinder)"), 3, 0.8)

func _spawn_grass(p: Vector2, i: int) -> void:
	var root := _root("DryGrass", p)
	for k in range(3):
		var m := _mesh(root, PropMeshes.grass_tuft(90 + i * 3 + k), _mat_grass, k * 1.7)
		m.position = Vector3(cos(k * 2.1) * 0.4, 0, sin(k * 2.1) * 0.4)
	_interactable(root, "grass", Loc.t("Gather dry grass (bedding)"), 1, 0.8)

func _spawn_bough(p: Vector2, i: int) -> void:
	var root := _root("SpruceBoughs", p)
	_mesh(root, PropMeshes.bough_clump(100 + i), _mat_bough, TerrainHeight.hash2(i, 5, 11) * TAU)
	_interactable(root, "bough", Loc.t("Cut low spruce boughs (bedding)"), 2, 1.0)

func _spawn_wet_log(p: Vector2, i: int) -> void:
	LandFeatures.logs.append(p)
	var root := _root("WetLog", p)
	root.position.y -= 0.08
	_mesh(root, PropMeshes.wet_log(110 + i), _mat_log, TerrainHeight.hash2(i, 3, 9) * TAU)
	_interactable(root, "wet_log", Loc.t("Chop fallen log"), 1, 1.2)

func _spawn_rootball(p: Vector2, i: int) -> void:
	LandFeatures.logs.append(p)   # 翻倒的树干也是现成的脊梁
	var root := _root("Rootball", p)
	root.add_to_group("windbreaks")
	# 树根盘面朝西（迎风），倒伏树干朝东躺下：背风侧（东）形成避风凹窝
	_mesh(root, PropMeshes.rootball(120 + i), _mat_root, 0.0)
	# 树根盘（竖立圆盘）碰撞：薄盒
	var body := StaticBody3D.new()
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 3.0, 3.0)
	cs.shape = box
	cs.position = Vector3(0, 1.3, 0)
	body.add_child(cs)

## 最近的天然挡风物距离。
## 树根盘挡风度（有方向，见 GameRules.windbreak_shelter）。
static func windbreak_shelter(tree: SceneTree, pos: Vector3, blow: Vector3, radius: float = 3.5) -> float:
	var pts: Array = []
	for n in tree.get_nodes_in_group("windbreaks"):
		var w := n as Node3D
		pts.append(Vector2(w.global_position.x, w.global_position.z))
	return GameRules.windbreak_shelter(pts, Vector2(pos.x, pos.z), Vector2(blow.x, blow.z), radius)

static func nearest_windbreak_distance(tree: SceneTree, pos: Vector3) -> float:
	var best := INF
	for n in tree.get_nodes_in_group("windbreaks"):
		var w := n as Node3D
		best = minf(best, Vector2(w.global_position.x - pos.x, w.global_position.z - pos.z).length())
	return best
