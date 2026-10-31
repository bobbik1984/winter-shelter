class_name ShelterCutawayRig
extends Node3D

## M2 45° 剖面高床雪洞：外层半剖雪穹顶 + 入口隧道 + 冷气槽 +
## 抬高睡台/松针垫层/睡袋/背包/雪铲 + 通风管 + 2700K 烛灯。
## 使用 shaders/cutaway_shelter.gdshader，不修改其核心公式。

const ORIGIN := Vector3(11.5, 0.0, 10.5)
const CUTAWAY_SHADER := preload("res://shaders/cutaway_shelter.gdshader")
const LANTERN_LOCAL := Vector3(1.6, 1.15, -1.2)

var _mat_outer: ShaderMaterial
var _mat_inner: ShaderMaterial
var _mat_cut: ShaderMaterial
var _mat_snow: StandardMaterial3D
var _mat_bedding: StandardMaterial3D
var _mat_bag: StandardMaterial3D
var _mat_pack: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_vent: StandardMaterial3D
var _mat_cold: StandardMaterial3D
var _mat_flame: StandardMaterial3D
var _mat_cave_dark: StandardMaterial3D
var _mat_cave_floor: StandardMaterial3D

func _ready() -> void:
	global_position = Vector3(
		ORIGIN.x,
		TerrainHeight.height_at(ORIGIN.x, ORIGIN.z) + 0.05,
		ORIGIN.z
	)
	rotation.y = deg_to_rad(45.0)
	_make_materials()
	_build_dome()
	_build_interior()
	_build_props()
	_build_vent()
	_build_lantern()

func _make_materials() -> void:
	_mat_outer = _cutaway_material(0.28, 0.0)
	_mat_inner = _cutaway_material(1.0, 0.0)
	_mat_cut = _cutaway_material(0.8, 1.0)

	_mat_snow = _solid(Color(0.88, 0.92, 1.0), 0.82)
	_mat_bedding = _solid(Color(0.30, 0.34, 0.18), 0.96)
	_mat_bag = _solid(Color(0.55, 0.30, 0.16), 0.90)
	_mat_pack = _solid(Color(0.78, 0.22, 0.16), 0.82)
	_mat_metal = _solid(Color(0.62, 0.66, 0.70), 0.38)
	_mat_wood = _solid(Color(0.30, 0.22, 0.14), 0.95)
	_mat_vent = _solid(Color(0.72, 0.86, 1.0), 0.45)
	_mat_cold = _solid(Color(0.42, 0.62, 0.90), 0.35)
	_mat_flame = _solid(Color(1.0, 0.58, 0.18), 0.35)
	_mat_flame.emission_enabled = true
	_mat_flame.emission = Color(1.0, 0.48, 0.12)
	_mat_flame.emission_energy_multiplier = 2.0
	_mat_cave_dark = _solid(Color(0.10, 0.16, 0.27), 0.92)
	_mat_cave_floor = _solid(Color(0.16, 0.25, 0.40), 0.90)

func _cutaway_material(interior: float, cut: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CUTAWAY_SHADER
	mat.set_shader_parameter("is_interior_surface", interior)
	mat.set_shader_parameter("is_cut_face", cut)
	mat.set_shader_parameter("lantern_warmth", 1.0)
	mat.set_shader_parameter("lantern_local_pos", LANTERN_LOCAL)
	return mat

func _solid(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func _build_dome() -> void:
	# 外层雪包：放在内腔后方，作为被切开的雪丘背景，不遮挡剖面。
	var mound_mesh := SphereMesh.new()
	mound_mesh.radius = 1.0
	mound_mesh.height = 2.0
	mound_mesh.radial_segments = 18
	mound_mesh.rings = 9
	var mound := MeshInstance3D.new()
	mound.name = "OuterSnowMound"
	mound.mesh = mound_mesh
	mound.material_override = _mat_outer
	mound.scale = Vector3(5.6, 3.8, 3.0)
	mound.position = Vector3(0.0, 0.0, -7.2)
	mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mound)

	# 内腔：开放前脸盒式剖面。背墙/侧墙/地面/顶板都用 cutaway shader 的内表面材质。
	_add_box(Vector3(0.0, 1.65, -2.9), Vector3(6.4, 3.3, 0.30), _mat_inner)
	_add_box(Vector3(-3.20, 1.65, -1.45), Vector3(0.30, 3.3, 3.0), _mat_inner)
	_add_box(Vector3(0.0, 0.02, -1.45), Vector3(6.4, 0.18, 3.0), _mat_inner)

	# 45° 剖面：切掉朝向相机的右墙與整个前顶板，只保留后侧雪檐，
	# 让内部睡台/冷气槽/烛灯真正可见。
	_add_box(Vector3(0.0, 3.15, -2.45), Vector3(6.4, 0.30, 1.1), _mat_inner)
	_add_box(Vector3(0.0, 3.45, -2.45), Vector3(6.7, 0.42, 1.3), _mat_snow)
	_add_box(Vector3(0.0, 3.15, 1.90), Vector3(6.4, 0.36, 0.32), _mat_cut)
	_add_box(Vector3(-3.20, 1.55, 1.90), Vector3(0.32, 3.4, 0.32), _mat_cut)
	_add_box(Vector3(3.20, 1.55, 1.90), Vector3(0.32, 3.4, 0.32), _mat_cut)

	# 45° 剖面椭圆边缘，强调“被切开”的冰蓝断面。
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 2.75
	rim_mesh.outer_radius = 3.15
	rim_mesh.rings = 32
	rim_mesh.ring_segments = 8
	var rim := MeshInstance3D.new()
	rim.name = "CutRim"
	rim.mesh = rim_mesh
	rim.material_override = _mat_cut
	rim.scale = Vector3(1.0, 0.55, 1.0)
	rim.position = Vector3(0.0, 1.70, 1.90)
	rim.rotation_degrees.x = 90.0
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)

func _build_interior() -> void:
	# 深色内腔背板/地面：让 2700K 烛光与睡袋/背包从雪壁中跳出来。
	_add_box(Vector3(0.0, 1.65, -2.71), Vector3(5.95, 3.0, 0.04), _mat_cave_dark)
	_add_box(Vector3(0.0, 0.14, -1.55), Vector3(5.95, 0.03, 2.85), _mat_cave_floor)
	# 内腔地面
	_add_box(Vector3(0.0, 0.06, -1.7), Vector3(6.3, 0.16, 4.4), _mat_inner)
	# 下沉冷气槽
	var pit := _add_cylinder(Vector3(-1.85, 0.10, -0.65), 0.95, 0.95, 0.10, _mat_cold)
	pit.rotation_degrees.x = 0.0
	var pit_ring := _add_torus(Vector3(-1.85, 0.16, -0.65), 0.78, 0.95, _mat_cold)
	pit_ring.rotation_degrees.x = 90.0
	for line in range(3):
		var flow := _add_cylinder(
			Vector3(-1.85 + float(line - 1) * 0.35, 0.10, -0.65 + float(line) * 0.12),
			0.018, 0.018, 1.1, _mat_cold
		)
		flow.rotation_degrees.z = 90.0
		flow.rotation_degrees.x = 8.0 * float(line - 1)

	# 抬高睡台
	_add_box(Vector3(1.25, 0.45, -1.85), Vector3(2.7, 0.9, 2.1), _mat_inner)
	_add_box(Vector3(1.25, 0.94, -1.85), Vector3(2.3, 0.12, 1.8), _mat_bedding)
	var bag := _add_capsule(Vector3(1.25, 1.06, -1.85), 0.32, 1.55, _mat_bag)
	bag.rotation_degrees.z = 90.0
	_add_box(Vector3(0.15, 1.08, -1.25), Vector3(0.42, 0.48, 0.26), _mat_pack)
	_add_cylinder(Vector3(0.15, 1.42, -1.25), 0.09, 0.09, 0.38, _mat_metal).rotation_degrees.z = 90.0
	_add_shovel()

func _build_cutaway_face() -> void:
	# 45° 断面：深蓝内腔面板 + 前景睡台/冷气槽/烛灯/通风管。
	_add_box(Vector3(0.0, 1.55, 1.80), Vector3(6.0, 3.0, 0.06), _mat_cave_dark)

	var pit := _add_cylinder(Vector3(-1.8, 0.16, 1.88), 0.92, 0.92, 0.05, _mat_cold)
	var pit_ring := _add_torus(Vector3(-1.8, 0.20, 1.89), 0.74, 0.92, _mat_cold)
	pit_ring.rotation_degrees.x = 90.0

	_add_box(Vector3(1.25, 0.55, 1.90), Vector3(2.5, 1.0, 0.55), _mat_inner)
	_add_box(Vector3(1.25, 1.08, 1.92), Vector3(2.1, 0.10, 0.45), _mat_bedding)
	var bag := _add_capsule(Vector3(1.25, 1.18, 1.92), 0.26, 1.25, _mat_bag)
	bag.rotation_degrees.z = 90.0
	_add_box(Vector3(0.30, 1.20, 1.92), Vector3(0.34, 0.40, 0.20), _mat_pack)

	var lantern := _add_cylinder(Vector3(1.55, 1.45, 1.94), 0.07, 0.09, 0.20, _mat_metal)
	_add_sphere(Vector3(1.55, 1.61, 1.94), 0.07, _mat_flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.64, 0.30)
	light.light_energy = 3.0
	light.omni_range = 4.5
	light.position = Vector3(1.55, 1.78, 1.98)
	add_child(light)

	var vent := _add_cylinder(Vector3(1.65, 2.55, 1.90), 0.16, 0.20, 1.55, _mat_vent)
	vent.name = "ForegroundVent"
	_add_cylinder(Vector3(1.65, 3.44, 1.90), 0.28, 0.28, 0.10, _mat_vent)
	for arrow in range(3):
		var cone := _add_cone(Vector3(1.65, 2.55 + float(arrow) * 0.38, 1.90), 0.13, 0.24, _mat_vent)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_shovel() -> void:
	var handle := _add_cylinder(Vector3(2.45, 1.35, -2.55), 0.028, 0.028, 1.55, _mat_wood)
	handle.rotation_degrees = Vector3(18.0, 0.0, -25.0)
	var blade := _add_box(Vector3(2.78, 0.62, -2.55), Vector3(0.36, 0.42, 0.06), _mat_metal)
	blade.rotation_degrees.z = -25.0

func _build_props() -> void:
	# 入口隧道：低矮拱形，向剖面外延伸。
	var tunnel := _add_cylinder(Vector3(-2.25, 0.72, 2.20), 0.82, 0.82, 2.5, _mat_outer)
	tunnel.rotation_degrees.x = 90.0
	tunnel.scale = Vector3(1.0, 1.0, 0.86)
	var mouth := _add_cylinder(Vector3(-2.25, 0.70, 3.42), 0.62, 0.62, 0.06, _mat_inner)
	mouth.rotation_degrees.x = 90.0

func _build_vent() -> void:
	var vent := _add_cylinder(Vector3(1.65, 3.35, -2.0), 0.17, 0.21, 4.5, _mat_vent)
	vent.name = "VentChimney"
	var cap := _add_cylinder(Vector3(1.65, 5.55, -2.0), 0.30, 0.30, 0.10, _mat_vent)
	cap.name = "VentCap"
	for arrow in range(3):
		var cone := _add_cone(
			Vector3(1.65, 3.25 + float(arrow) * 0.45, -2.0),
			0.16, 0.28, _mat_vent
		)
		cone.name = "VentArrow"
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_lantern() -> void:
	var body := _add_cylinder(LANTERN_LOCAL, 0.07, 0.09, 0.22, _mat_metal)
	body.name = "LanternBody"
	var wick := _add_sphere(LANTERN_LOCAL + Vector3(0.0, 0.16, 0.0), 0.07, _mat_flame)
	wick.name = "LanternWick"
	var light := OmniLight3D.new()
	light.name = "CandleLight2700K"
	light.light_color = Color(1.0, 0.64, 0.30)
	light.light_energy = 3.0
	light.omni_range = 5.2
	light.position = LANTERN_LOCAL + Vector3(0.0, 0.25, 0.0)
	add_child(light)

func _add_box(pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi

func _add_cylinder(pos: Vector3, top_radius: float, bottom_radius: float,
		height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi

func _add_cone(pos: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi

func _add_sphere(pos: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi

func _add_capsule(pos: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi

func _add_torus(pos: Vector3, inner: float, outer: float, material: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi
