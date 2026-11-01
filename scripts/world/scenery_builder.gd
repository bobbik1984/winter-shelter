class_name SceneryBuilder
extends Node3D

## M2 视觉群落：5 层积雪云杉、覆雪巨石、8 个生态小岛、干草丛、
## 参考图 Box 2/3 的橙色交互圈 + 雪地脚印链、远景雪山剪影。
## 全部由 TerrainHeight 落地，不依赖外部资产；不修改地形/Shader 核心公式。

const CLUSTERS := [
	Vector3(-16.0, 0.0, -8.0), Vector3(-11.0, 0.0, 14.0), Vector3(-23.0, 0.0, 2.0),
	Vector3(13.0, 0.0, -18.0), Vector3(21.0, 0.0, 2.0), Vector3(17.0, 0.0, 16.0),
	Vector3(-2.0, 0.0, 24.0), Vector3(27.0, 0.0, -24.0),
]
const MAIN_TYPES := ["spruce", "deadwood", "spruce", "spruce", "deadwood", "spruce", "spruce", "deadwood"]
const FOOTPRINT_START := Vector3(-8.0, 0.0, -6.0)
const FOOTPRINT_END := Vector3(0.0, 0.0, 0.0)
const SPECIAL_DEADWOOD := Vector3(5.5, 0.0, 3.5)

var _mat_green: StandardMaterial3D
var _mat_snow: StandardMaterial3D
var _mat_bark: StandardMaterial3D
var _mat_deadwood: Material
var _mat_rock: StandardMaterial3D
var _mat_grass: StandardMaterial3D
var _mat_footprint: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _mat_peak_rock: StandardMaterial3D
var _mat_peak_snow: StandardMaterial3D
var _mat_spruce: ShaderMaterial
## 场景立枯木位置（由 ResourceSpawner 挂采集点）。
var deadwood_points: PackedVector2Array = PackedVector2Array()
var spruce_points: PackedVector2Array = PackedVector2Array()
var _spruce_meshes: Dictionary = {}

const SPRUCE_VARIANTS := 4
const SNOW_COVER_SHADER := preload("res://shaders/snow_cover.gdshader")

## 风数据：云杉偏冠 / 迎风枝短的方向来源（SSOT：WindData）。
@export var wind_data: WindData
## [TUNE] 偏冠与迎风枝缩短强度（0 = 对称）。
@export var wind_lean: float = 0.38
## 地图内 10–16 m 圆锥"远山"占位默认关闭，由 FarTerrainBuilder 的真实远景取代。
@export var show_distant_peaks: bool = false

func _ready() -> void:
	_make_materials()
	_build_clusters()
	# 交互立枯木与橙圈改由 ResourceSpawner + InteractionController 提供（T2.1）
	_build_footprints()
	if show_distant_peaks:
		_build_distant_peaks()
	# 碰撞：只挡树干（与 ForestScatter 一致）
	var body := StaticBody3D.new()
	body.name = "SceneryColliders"
	add_child(body)
	for p in spruce_points:
		ForestScatter.add_trunk(body, p, 0.3)
	for p in deadwood_points:
		ForestScatter.add_trunk(body, p, 0.28)

func _make_materials() -> void:
	_mat_green = _make_material(Color(0.07, 0.16, 0.11), 0.92)
	_mat_spruce = ShaderMaterial.new()
	_mat_spruce.shader = SNOW_COVER_SHADER
	_mat_spruce.set_shader_parameter("base_color", Color(0.035, 0.11, 0.07))
	_mat_spruce.set_shader_parameter("snow_amount", 0.56)
	_mat_spruce.set_shader_parameter("occlusion_fade", true)
	_mat_spruce.set_shader_parameter("sway_amount", 1.0)
	var bd := _wind_dir()
	_mat_spruce.set_shader_parameter("wind_dir", Vector2(bd.x, bd.z))
	add_to_group("occlusion_fade")
	add_to_group("scenery")
	_mat_snow = _make_material(Color(0.92, 0.95, 1.0), 0.78)
	_mat_bark = _make_material(Color(0.16, 0.11, 0.07), 0.95)
	var dw := ShaderMaterial.new()
	dw.shader = SNOW_COVER_SHADER
	dw.set_shader_parameter("base_color", Color(0.30, 0.28, 0.26))
	dw.set_shader_parameter("snow_amount", 0.22)
	dw.set_shader_parameter("occlusion_fade", true)
	dw.set_shader_parameter("rim_amount", 0.45)
	_mat_deadwood = dw
	_mat_rock = _make_material(Color(0.12, 0.13, 0.16), 0.98)
	_mat_grass = _make_material(Color(0.68, 0.56, 0.32), 0.94)
	_mat_footprint = _make_material(Color(0.42, 0.49, 0.60), 0.92)
	_mat_peak_rock = _make_material(Color(0.28, 0.34, 0.46), 0.98)
	_mat_peak_snow = _make_material(Color(0.70, 0.81, 0.95), 0.78)
	_mat_ring = _make_material(Color(1.0, 0.55, 0.12), 0.45)
	_mat_ring.emission_enabled = true
	_mat_ring.emission = Color(1.0, 0.55, 0.12)
	_mat_ring.emission_energy_multiplier = 2.2

## "occlusion_fade" 组回调（见 snow_cover.gdshader）。
func set_focus(pos: Vector3) -> void:
	for m in [_mat_spruce, _mat_deadwood]:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("focus_pos", pos)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

# -----------------------------------------------------------------------------
# A. 5 层自然积雪云杉
# -----------------------------------------------------------------------------

func _spruce(pos: Vector3, scale_factor: float, tilt_deg: float, seed_idx: int) -> void:
	spruce_points.append(Vector2(pos.x, pos.z))
	var root := Node3D.new()
	root.name = "Spruce"
	root.position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) - 0.12, pos.z)
	root.rotation.z = deg_to_rad(tilt_deg)
	root.scale = Vector3.ONE * scale_factor
	add_child(root)

	if not _spruce_meshes.has(seed_idx % SPRUCE_VARIANTS):
		_spruce_meshes[seed_idx % SPRUCE_VARIANTS] = SpruceMesh.build(
			seed_idx % SPRUCE_VARIANTS, _wind_dir(), wind_lean
		)
	var mi := MeshInstance3D.new()
	mi.name = "SpruceMesh"
	mi.mesh = _spruce_meshes[seed_idx % SPRUCE_VARIANTS]
	mi.material_override = _mat_spruce
	# 不绕 Y 旋转：偏冠 / 迎风枝缩短方向必须与风向一致，玩家靠它读风。
	root.add_child(mi)


func _wind_dir() -> Vector3:
	if wind_data == null:
		wind_data = load("res://resources/default_wind.tres") as WindData
	return wind_data.get_blow_direction_3d() if wind_data else Vector3.RIGHT

# -----------------------------------------------------------------------------
# B. 顶面覆雪巨石 + 背风侧雪枕
# -----------------------------------------------------------------------------

func _rock_outcrop(pos: Vector3, scale_vec: Vector3, yaw_deg: float) -> void:
	var ground_y := TerrainHeight.height_at(pos.x, pos.z)
	var root := Node3D.new()
	root.name = "RockOutcrop"
	root.position = Vector3(pos.x, ground_y, pos.z)
	root.rotation.y = deg_to_rad(yaw_deg)
	add_child(root)

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	rock.mesh = mesh
	rock.material_override = _mat_rock
	rock.position = Vector3(0.0, scale_vec.y * 0.45, 0.0)
	rock.scale = scale_vec
	root.add_child(rock)

	var cap := MeshInstance3D.new()
	cap.name = "SnowCap"
	cap.mesh = mesh
	cap.material_override = _mat_snow
	cap.position = Vector3(0.0, scale_vec.y * 0.95, 0.0)
	cap.scale = Vector3(scale_vec.x * 0.92, scale_vec.y * 0.42, scale_vec.z * 0.92)
	root.add_child(cap)

	# 背风侧雪枕：局部 +x（东侧）1.1m 处贴地隆起。
	var pillow_mesh := SphereMesh.new()
	pillow_mesh.radius = 1.0
	pillow_mesh.height = 2.0
	pillow_mesh.radial_segments = 8
	pillow_mesh.rings = 4
	var pillow := MeshInstance3D.new()
	pillow.name = "SnowPillow"
	pillow.mesh = pillow_mesh
	pillow.material_override = _mat_snow
	pillow.position = Vector3(1.1, 0.12, 0.0)
	pillow.scale = Vector3(1.8, 0.55, 1.3)
	root.add_child(pillow)

# -----------------------------------------------------------------------------
# C. 8 个生态小岛
# -----------------------------------------------------------------------------

func _build_clusters() -> void:
	for cluster_idx in range(CLUSTERS.size()):
		var center: Vector3 = CLUSTERS[cluster_idx]
		var main_type: String = MAIN_TYPES[cluster_idx]
		var seed_idx := 100 + cluster_idx * 37

		if main_type == "deadwood":
			_deadwood(center, 1.0 + float(cluster_idx % 3) * 0.08, float(cluster_idx) * 23.0, seed_idx)
		else:
			_spruce(center, 1.08 + float(cluster_idx % 2) * 0.08, -5.0, seed_idx)

		var young_count := 2 + cluster_idx % 2
		for young in range(young_count):
			var angle := float(young) * 2.15 + float(cluster_idx) * 0.67
			var dist := 1.6 + TerrainHeight.hash2(cluster_idx, young, 211) * 1.0
			var jitter := TerrainHeight.hash2(cluster_idx, young, 311) * 0.45
			var p := Vector3(
				center.x + cos(angle) * dist,
				0.0,
				center.z + sin(angle) * dist
			)
			var scale_factor := 0.55 + TerrainHeight.hash2(cluster_idx, young, 509) * 0.25
			_spruce(p, scale_factor, -5.0, seed_idx + young + 1)
			if jitter > 0.35:
				_dry_grass_tuft(Vector3(p.x + 0.7, 0.0, p.z - 0.4), seed_idx + young + 70)

		var rock_count := 1 + cluster_idx % 2
		for rock_idx in range(rock_count):
			var angle := 2.4 + float(rock_idx) * 2.0 + float(cluster_idx) * 0.4
			var p := Vector3(
				center.x + cos(angle) * (2.4 + float(rock_idx) * 0.7),
				0.0,
				center.z + sin(angle) * (2.2 + float(rock_idx) * 0.8)
			)
			_rock_outcrop(
				p,
				Vector3(0.8 + float(rock_idx) * 0.25, 0.55 + float(cluster_idx % 3) * 0.12, 0.95),
				float(cluster_idx) * 31.0 + float(rock_idx) * 47.0
			)

		var grass_count := 4 + cluster_idx % 3
		for grass_idx in range(grass_count):
			var angle := float(grass_idx) * 1.37 + float(cluster_idx) * 0.9
			var dist := 0.9 + TerrainHeight.hash2(cluster_idx, grass_idx, 601) * 2.2
			_dry_grass_tuft(
				Vector3(center.x + cos(angle) * dist, 0.0, center.z + sin(angle) * dist),
				seed_idx + grass_idx + 300
			)

func _dry_grass_tuft(pos: Vector3, seed_idx: int) -> void:
	var root := Node3D.new()
	root.name = "DryGrass"
	root.position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) + 0.02, pos.z)
	root.rotation.y = TerrainHeight.hash2(seed_idx, 5, 83) * TAU
	add_child(root)
	for stem in range(4):
		var rnd := TerrainHeight.hash2(seed_idx, stem, 191)
		var rnd_b := TerrainHeight.hash2(seed_idx, stem, 293)
		var height := 0.32 + rnd * 0.24
		var grass := _add_cylinder(root, 0.004, 0.018, height, height * 0.5, _mat_grass)
		grass.position = Vector3((rnd - 0.5) * 0.12, height * 0.5, (rnd_b - 0.5) * 0.12)
		grass.rotation_degrees = Vector3(
			(rnd_b - 0.5) * 42.0,
			float(stem) * 50.0,
			(rnd - 0.5) * 35.0
		)

# -----------------------------------------------------------------------------
# D. 参考图标志性交互圈 + 雪地脚印链
# -----------------------------------------------------------------------------

func _build_special_deadwood() -> void:
	var ground_y := TerrainHeight.height_at(SPECIAL_DEADWOOD.x, SPECIAL_DEADWOOD.z)
	_deadwood(SPECIAL_DEADWOOD, 1.18, 20.0, 777)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.05
	ring_mesh.outer_radius = 1.22
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.name = "DeadwoodInteractRing"
	ring.mesh = ring_mesh
	ring.material_override = _mat_ring
	ring.position = Vector3(SPECIAL_DEADWOOD.x, ground_y + 0.05, SPECIAL_DEADWOOD.z)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var light := OmniLight3D.new()
	light.name = "InteractGlow"
	light.light_color = Color(1.0, 0.52, 0.16)
	light.light_energy = 1.1
	light.omni_range = 3.2
	light.position = Vector3(SPECIAL_DEADWOOD.x, ground_y + 1.0, SPECIAL_DEADWOOD.z)
	add_child(light)

func _build_footprints() -> void:
	var dir := FOOTPRINT_END - FOOTPRINT_START
	var path_angle := atan2(dir.x, dir.z)
	var perp := Vector3(-dir.z, 0.0, dir.x).normalized()
	for i in range(12):
		var t := float(i) / 11.0
		var p := FOOTPRINT_START.lerp(FOOTPRINT_END, t)
		var side := 1.0 if i % 2 == 0 else -1.0
		p += perp * 0.22 * side
		var mesh := SphereMesh.new()
		mesh.radius = 0.20
		mesh.height = 0.40
		mesh.radial_segments = 8
		mesh.rings = 3
		var print_instance := MeshInstance3D.new()
		print_instance.name = "Footprint"
		print_instance.mesh = mesh
		print_instance.material_override = _mat_footprint
		print_instance.position = Vector3(p.x, TerrainHeight.height_at(p.x, p.z) + 0.035, p.z)
		print_instance.scale = Vector3(0.62, 0.022, 1.18)
		print_instance.rotation.y = path_angle
		print_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(print_instance)

# -----------------------------------------------------------------------------
# E. 远景雪山剪影带
# -----------------------------------------------------------------------------

func _build_distant_peaks() -> void:
	for i in range(7):
		var x := -12.0 + float(i) * 6.5
		var z := -31.0 - float(i % 2) * 1.0
		var height := 10.0 + TerrainHeight.hash2(i, 3, 811) * 6.0
		var base_radius := 4.2 + TerrainHeight.hash2(i, 7, 821) * 2.4

		var root := Node3D.new()
		root.name = "DistantPeak"
		root.position = Vector3(x, -2.0, z)
		root.rotation.y = float(i) * 0.61
		add_child(root)

		var rock_mesh := CylinderMesh.new()
		rock_mesh.top_radius = 0.0
		rock_mesh.bottom_radius = base_radius
		rock_mesh.height = height
		rock_mesh.radial_segments = 6
		rock_mesh.rings = 2
		rock_mesh.cap_top = false
		var rock := MeshInstance3D.new()
		rock.name = "PeakRock"
		rock.mesh = rock_mesh
		rock.material_override = _mat_peak_rock
		rock.position = Vector3(0.0, height * 0.5, 0.0)
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rock)

		var snow_mesh := CylinderMesh.new()
		snow_mesh.top_radius = 0.0
		snow_mesh.bottom_radius = base_radius * 0.58
		snow_mesh.height = height * 0.45
		snow_mesh.radial_segments = 6
		snow_mesh.rings = 2
		snow_mesh.cap_top = false
		var snow := MeshInstance3D.new()
		snow.name = "PeakSnow"
		snow.mesh = snow_mesh
		snow.material_override = _mat_peak_snow
		snow.position = Vector3(0.0, height * 0.72, 0.0)
		snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(snow)

# -----------------------------------------------------------------------------
# 共用几何辅助
# -----------------------------------------------------------------------------

func _deadwood(pos: Vector3, scale_factor: float, yaw_deg: float, seed_idx: int) -> void:
	deadwood_points.append(Vector2(pos.x, pos.z))
	var root := Node3D.new()
	root.name = "StandingDeadwood"
	root.position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) - 0.1, pos.z)
	root.rotation.y = deg_to_rad(yaw_deg)
	root.scale = Vector3.ONE * scale_factor
	add_child(root)

	_add_cylinder(root, 0.13, 0.28, 7.0, 3.5, _mat_deadwood)
	_add_cone(root, 0.14, 1.2, 7.4, _mat_deadwood)
	for branch in range(5):
		_add_branch(
			root, 3.0 + float(branch) * 0.8,
			float(branch) * 67.0 + TerrainHeight.hash2(seed_idx, branch, 431) * 28.0,
			1.1 + float(branch % 3) * 0.35, 0.045, _mat_deadwood
		)

func _add_cone(parent: Node3D, bottom_radius: float, height: float, y: float,
		material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 2
	mesh.cap_top = false
	mesh.cap_bottom = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = Vector3(0.0, y, 0.0)
	parent.add_child(mi)
	return mi

func _add_cylinder(parent: Node3D, top_radius: float, bottom_radius: float,
		height: float, y: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = Vector3(0.0, y, 0.0)
	parent.add_child(mi)
	return mi

func _add_branch(parent: Node3D, y: float, yaw_degrees: float,
		length: float, radius: float, material: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, y, 0.0)
	pivot.rotation_degrees = Vector3(0.0, yaw_degrees, 58.0)
	parent.add_child(pivot)
	var branch := _add_cylinder(pivot, 0.02, radius, length, length * 0.5, material)
	branch.position = Vector3(0.0, length * 0.5, 0.0)
