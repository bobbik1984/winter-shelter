class_name ForestScatter
extends Node3D

## 100 m 地图内的密林散布：云杉 / 枯立木 / 岩石露头，全部 MultiMesh。
## 只是视觉层（无碰撞，与 SceneryBuilder 现有树木一致）；
## 用噪声做林窗 + 避让点（出生点、篝火、剖面、交互枯木、脚印路径）保证可玩路线通畅。

const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")
const SPRUCE_VARIANTS := 4
const ROCK_VARIANTS := 3
const SNAG_VARIANTS := 3

## 避让圆：Vector3(x, z, 半径)，x / z 为地图坐标（L3 随地图旋转）
const KEEP_OUT := [
	Vector3(18.0, 8.0, 7.0),     # 出生点
	Vector3(-4.2, 9.2, 5.0),     # 篝火
	Vector3(20.5, 11.2, 5.0),    # 剖面雪洞位置
	Vector3(5.5, 3.5, 4.0),      # 交互枯木
	Vector3(-4.0, -3.0, 5.5),    # 脚印路径
	Vector3(10.0, 5.0, 5.0),     # 出生点 → 交互枯木的通道
]

## 视野走廊：从出生点朝远景（相机前方 / 落日）方向稀疏化树木，露出山谷与天际线。
const VISTA_ORIGIN := Vector2(18.0, 8.0)
const VISTA_DIR := Vector2(-0.7071, 0.7071)
## [TUNE] 走廊半角（度）与走廊内保留比例。
@export var vista_half_angle_deg: float = 28.0
@export var vista_keep_ratio: float = 0.12

@export var wind_data: WindData
@export var half_extent: float = 49.0
## [TUNE] 采样网格间距（m）与林分密度阈值。
@export var spruce_spacing: float = 3.8
@export var density_threshold: float = 0.5
@export var snag_count: int = 34
@export var rock_count: int = 46
@export var seed_idx: int = 3

var _fade_materials: Array[ShaderMaterial] = []
## 云杉树干位置（树冠下生火 / 落雪判定用）。
var spruce_points: PackedVector2Array = PackedVector2Array()
## 立枯木位置（每棵都可采集干柴：Read the Land 第 4 条）。
var snag_points: PackedVector2Array = PackedVector2Array()
## 岩石 (x, z, 半径)：碰撞用。
var rock_spheres: Array[Vector3] = []

## "occlusion_fade" 组回调：玩家位置，用于把挡住玩家的树镂空。
func set_focus(pos: Vector3) -> void:
	for m in _fade_materials:
		m.set_shader_parameter("focus_pos", pos)

func _ready() -> void:
	add_to_group("occlusion_fade")
	add_to_group("forest")
	if wind_data == null:
		wind_data = load("res://resources/default_wind.tres") as WindData
	var blow := wind_data.get_blow_direction_3d() if wind_data else Vector3.RIGHT
	_scatter_spruce(blow)
	_scatter_snags()
	_scatter_rocks()
	_place_outcrops()
	_build_colliders()


## 大型棱角岩体（T4.7 差距 2）：Blender 生成的 rock_outcrop_A/B/C.glb，放在脊线与陡坡上。
const OUTCROPS := ["res://assets/models/rock_outcrop_A.glb", "res://assets/models/rock_outcrop_B.glb", "res://assets/models/rock_outcrop_C.glb"]
@export var outcrop_count: int = 10

func _place_outcrops() -> void:
	var meshes: Array[Mesh] = []
	for path in OUTCROPS:
		if not ResourceLoader.exists(path):
			return
		var inst := (load(path) as PackedScene).instantiate()
		var mi := inst.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
		meshes.append(mi.mesh)
		inst.free()
	var mat := _material(Color(0.17, 0.17, 0.20), 0.38, 0.07)
	mat.set_shader_parameter("rim_amount", 0.35)
	_enable_fade(mat)
	var buckets: Array = [[], [], []]
	var placed := 0
	var k := 0
	while placed < outcrop_count and k < 600:
		k += 1
		var x := (TerrainHeight.hash2(k, 71, seed_idx * 31) - 0.5) * half_extent * 2.0
		var z := (TerrainHeight.hash2(k, 73, seed_idx * 31) - 0.5) * half_extent * 2.0
		if _blocked(x, z, 3.0) or _in_vista(x, z):
			continue
		if TerrainHeight.slope_at(x, z) < 14.0 and TerrainHeight.height_at(x, z) < 4.0:
			continue
		var s := lerpf(1.6, 3.2, TerrainHeight.hash2(k, 2, 77))
		var basis := Basis(Vector3.UP, TerrainHeight.hash2(k, 3, 77) * TAU).scaled(Vector3(s * 1.2, s, s))
		buckets[k % 3].append(Transform3D(basis, Vector3(x, TerrainHeight.height_at(x, z) - s * 0.25, z)))
		rock_spheres.append(Vector3(x, z, s * 0.9))
		placed += 1
	for v in range(3):
		_add_multimesh("Outcrop%d" % v, meshes[v], mat, buckets[v], true)

## 碰撞（只挡树干与岩石，林间仍可穿行）：一个 StaticBody3D 挂所有形状。
func _build_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "ForestColliders"
	add_child(body)
	for p in spruce_points:
		add_trunk(body, p, 0.32)
	for p in snag_points:
		add_trunk(body, p, 0.25)
	for r in rock_spheres:
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = r.z * 0.85
		cs.shape = sph
		cs.position = Vector3(r.x, TerrainHeight.height_at(r.x, r.y), r.y)
		body.add_child(cs)

static func add_trunk(body: StaticBody3D, p: Vector2, radius: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 4.0
	cs.shape = cyl
	cs.position = Vector3(p.x, TerrainHeight.height_at(p.x, p.y) + 1.5, p.y)
	body.add_child(cs)


func _blocked(x: float, z: float, extra: float = 0.0) -> bool:
	for k in KEEP_OUT:
		var c := TerrainHeight.to_world(Vector2(k.x, k.y))
		if Vector2(x - c.x, z - c.y).length() < k.z + extra:
			return true
	return false


func _in_vista(x: float, z: float) -> bool:
	# 走廊起点 = 出生点（随地图旋转）；方向 = 相机前方 / 落日（世界坐标，不旋转）
	var d := Vector2(x, z) - TerrainHeight.to_world(VISTA_ORIGIN)
	if d.length() < 6.0:
		return false
	# 前方视野走廊 + 出生点身后（相机一侧）25 m 内的空地
	if d.dot(-VISTA_DIR) > 0.0 and d.length() < 25.0 and absf(rad_to_deg(d.angle_to(-VISTA_DIR))) < 40.0:
		return true
	return absf(rad_to_deg(d.angle_to(VISTA_DIR))) < vista_half_angle_deg


func _enable_fade(m: ShaderMaterial) -> void:
	m.set_shader_parameter("occlusion_fade", true)
	_fade_materials.append(m)


func _material(base: Color, snow_amount: float, softness: float = 0.16) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SNOW_COVER_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("snow_amount", snow_amount)
	m.set_shader_parameter("snow_softness", softness)
	return m


func _scatter_spruce(blow: Vector3) -> void:
	var buckets: Array = []
	for v in range(SPRUCE_VARIANTS):
		buckets.append([])
	var n := int(half_extent * 2.0 / spruce_spacing)
	for j in range(n):
		for i in range(n):
			var jx := TerrainHeight.hash2(i, j, seed_idx * 11) - 0.5
			var jz := TerrainHeight.hash2(i, j, seed_idx * 13) - 0.5
			var x := -half_extent + (float(i) + 0.5 + jx * 0.9) * spruce_spacing
			var z := -half_extent + (float(j) + 0.5 + jz * 0.9) * spruce_spacing
			# 林分噪声：大块林地 + 林窗
			var dens := TerrainHeight.fbm(x * 0.035 + 11.0, z * 0.035 - 4.0, seed_idx * 7, 3)
			if dens < density_threshold:
				continue
			if _blocked(x, z):
				continue
			if _in_vista(x, z) and TerrainHeight.hash2(i, j, seed_idx * 29) > vista_keep_ratio:
				continue
			if TerrainHeight.slope_at(x, z) > 32.0:
				continue
			var r := TerrainHeight.hash2(i, j, seed_idx * 17)
			# 林缘树更矮
			var edge := smoothstep(density_threshold, density_threshold + 0.12, dens)
			var s := lerpf(0.45, 1.25, r) * lerpf(0.65, 1.0, edge)
			var t := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * lerpf(0.95, 1.18, r), s)),
				Vector3(x, TerrainHeight.height_at(x, z) - 0.15, z))
			buckets[(i * 7 + j * 3) % SPRUCE_VARIANTS].append(t)
			spruce_points.append(Vector2(x, z))
	var mat := _material(Color(0.035, 0.11, 0.07), 0.56)
	_enable_fade(mat)
	mat.set_shader_parameter("sway_amount", 1.0)
	mat.set_shader_parameter("wind_dir", Vector2(blow.x, blow.z))
	for v in range(SPRUCE_VARIANTS):
		_add_multimesh("Spruce%d" % v, SpruceMesh.build(20 + v, blow), mat, buckets[v], true)


func _scatter_snags() -> void:
	var buckets: Array = [[], [], []]
	var placed := 0
	var k := 0
	var target := int(round(snag_count * LevelState.snag_density_scale()))
	while placed < target and k < target * 20:
		k += 1
		var x := (TerrainHeight.hash2(k, 5, seed_idx * 19) - 0.5) * half_extent * 2.0
		var z := (TerrainHeight.hash2(k, 9, seed_idx * 19) - 0.5) * half_extent * 2.0
		if _blocked(x, z, 1.0):
			continue
		# 枯木多出现在林缘
		var dens := TerrainHeight.fbm(x * 0.035 + 11.0, z * 0.035 - 4.0, seed_idx * 7, 3)
		if absf(dens - density_threshold) > 0.09:
			continue
		var s := 0.75 + TerrainHeight.hash2(k, 3, 7) * 0.45
		var basis := Basis(Vector3.UP, TerrainHeight.hash2(k, 4, 7) * TAU).scaled(Vector3.ONE * s)
		buckets[k % SNAG_VARIANTS].append(Transform3D(basis, Vector3(x, TerrainHeight.height_at(x, z) - 0.2, z)))
		snag_points.append(Vector2(x, z))
		placed += 1
	var mat := _material(Color(0.30, 0.28, 0.26), 0.25, 0.10)
	mat.set_shader_parameter("rim_amount", 0.45)
	_enable_fade(mat)
	for v in range(SNAG_VARIANTS):
		_add_multimesh("Snag%d" % v, PropMeshes.snag(40 + v), mat, buckets[v], true)


func _scatter_rocks() -> void:
	var buckets: Array = [[], [], []]
	var placed := 0
	var k := 0
	while placed < rock_count and k < rock_count * 30:
		k += 1
		var x := (TerrainHeight.hash2(k, 21, seed_idx * 23) - 0.5) * half_extent * 2.0
		var z := (TerrainHeight.hash2(k, 27, seed_idx * 23) - 0.5) * half_extent * 2.0
		if _blocked(x, z, 1.5):
			continue
		# 岩石偏好陡坡与浅雪（风吹露出的地方）
		var slope := TerrainHeight.slope_at(x, z)
		var depth := TerrainHeight.snow_depth_at(x, z)
		if slope < 9.0 and depth > 0.9:
			continue
		var big := TerrainHeight.hash2(k, 2, 29)
		var s := lerpf(0.6, 2.6, big * big)
		var basis := Basis(Vector3.UP, TerrainHeight.hash2(k, 3, 29) * TAU).scaled(
			Vector3(s * lerpf(1.0, 1.6, big), s * lerpf(0.55, 0.9, TerrainHeight.hash2(k, 4, 29)), s))
		buckets[k % ROCK_VARIANTS].append(Transform3D(basis, Vector3(x, TerrainHeight.height_at(x, z) - s * 0.18, z)))
		rock_spheres.append(Vector3(x, z, s * lerpf(0.8, 1.2, big)))
		placed += 1
	var mat := _material(Color(0.20, 0.20, 0.24), 0.30, 0.06)
	_enable_fade(mat)
	mat.set_shader_parameter("rim_amount", 0.5)
	for v in range(ROCK_VARIANTS):
		_add_multimesh("Rocks%d" % v, PropMeshes.rock(60 + v), mat, buckets[v], true)


func _add_multimesh(node_name: String, mesh: Mesh, mat: Material, transforms: Array, shadows: bool) -> void:
	add_chunked(self, node_name, mesh, mat, transforms, 25.0, shadows)


## 按空间分块建 MultiMesh：一整片跨全图的 MultiMesh 的 AABB 永远在视锥里、无法剔除；
## 分块后相机背后 / 画面外的树（以及阴影级联外的树）都能被剔掉。
static func add_chunked(parent: Node3D, node_name: String, mesh: Mesh, mat: Material,
		transforms: Array, chunk: float, shadows: bool) -> void:
	var groups := {}
	for t: Transform3D in transforms:
		var key := Vector2i(floori(t.origin.x / chunk), floori(t.origin.z / chunk))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)
	for key: Vector2i in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in range(list.size()):
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [node_name, key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		if node_name.begins_with("FarForest"):
			mmi.add_to_group("far_forest")
		else:
			mmi.add_to_group("near_forest")
