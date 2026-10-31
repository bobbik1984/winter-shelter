class_name CampfirePotRig
extends Node3D

## 树根挡风凹窝旁的睡前营火 + 小铝锅：
## 石圈、木柴架、2700K 火光、火苗几何体、三脚架 + 银灰 Camp Pot，
## 以及后侧翻倒树根（Rootball）挡风墙。

var _mat_stone: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_flame: StandardMaterial3D
var _mat_ember: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _mat_bark: StandardMaterial3D

func _ready() -> void:
	global_position.y = TerrainHeight.height_at(global_position.x, global_position.z) + 0.03
	rotation.y = deg_to_rad(30.0)
	_make_materials()
	_build_rootball()
	_build_stone_ring()
	_build_logs_and_fire()
	_build_pot()

func _make_materials() -> void:
	_mat_stone = _solid(Color(0.24, 0.25, 0.28), 0.96)
	_mat_wood = _solid(Color(0.29, 0.20, 0.12), 0.95)
	_mat_flame = _solid(Color(1.0, 0.58, 0.16), 0.30)
	_mat_flame.emission_enabled = true
	_mat_flame.emission = Color(1.0, 0.45, 0.10)
	_mat_flame.emission_energy_multiplier = 3.2
	_mat_ember = _solid(Color(1.0, 0.30, 0.05), 0.32)
	_mat_ember.emission_enabled = true
	_mat_ember.emission = Color(1.0, 0.22, 0.03)
	_mat_ember.emission_energy_multiplier = 2.2
	_mat_metal = _solid(Color(0.66, 0.69, 0.72), 0.32)
	_mat_bark = _solid(Color(0.26, 0.19, 0.13), 0.96)

func _solid(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func _build_rootball() -> void:
	# 翻倒树根：横倒树干 + 竖直根盘 + 几根裸露根须，作为背风挡风墙。
	var trunk := _add_cylinder(Vector3(-1.65, 0.55, 0.75), 0.26, 0.38, 3.6, _mat_bark)
	trunk.rotation_degrees.z = 90.0
	var plate := _add_sphere(Vector3(-3.25, 0.85, 0.75), 1.0, _mat_bark)
	plate.scale = Vector3(0.22, 1.0, 1.1)
	for root in range(5):
		var spike := _add_cylinder(Vector3(-3.25, 0.55, 0.75), 0.04, 0.10, 1.0, _mat_bark)
		spike.rotation_degrees = Vector3(0.0, float(root) * 72.0, 90.0)

func _build_stone_ring() -> void:
	for i in range(8):
		var angle := float(i) * TAU / 8.0
		var stone := _add_sphere(
			Vector3(cos(angle) * 1.10, 0.18, sin(angle) * 1.10),
			0.28 + float(i % 3) * 0.04, _mat_stone
		)
		stone.scale = Vector3(1.25, 0.80, 1.0)

func _build_logs_and_fire() -> void:
	for i in range(4):
		var log := _add_cylinder(Vector3(0.0, 0.17, 0.0), 0.11, 0.13, 1.65, _mat_wood)
		log.rotation_degrees = Vector3(90.0, float(i) * 45.0, 8.0)
		log.position = Vector3(float(i % 2) * 0.12 - 0.06, 0.17, 0.0)

	for i in range(3):
		var flame := _add_cone(
			Vector3(float(i - 1) * 0.18, 0.62 + float(i) * 0.08, float(i) * 0.06),
			0.24 - float(i) * 0.04, 0.75 + float(i) * 0.18, _mat_flame
		)
		flame.name = "Flame"
	var ember := _add_sphere(Vector3(0.0, 0.24, 0.0), 0.45, _mat_ember)
	ember.scale = Vector3(1.0, 0.28, 1.0)

	var light := OmniLight3D.new()
	light.name = "CampfireLight2700K"
	light.light_color = Color(1.0, 0.55, 0.20)
	light.light_energy = 2.4
	light.omni_range = 6.0
	light.position = Vector3(0.0, 0.9, 0.0)
	add_child(light)

func _build_pot() -> void:
	for i in range(3):
		var angle := float(i) * TAU / 3.0
		var stake := _add_cylinder(Vector3(cos(angle) * 0.68, 1.1, sin(angle) * 0.68), 0.03, 0.04, 2.2, _mat_wood)
		stake.rotation_degrees = Vector3(sin(angle) * 20.0, 0.0, cos(angle) * 20.0)
	var pot := _add_cylinder(Vector3(0.0, 1.55, 0.0), 0.30, 0.26, 0.28, _mat_metal)
	pot.name = "CampPot"
	var rim := _add_torus(Vector3(0.0, 1.68, 0.0), 0.24, 0.31, _mat_metal)
	rim.rotation_degrees.x = 90.0
	var handle := _add_torus(Vector3(0.0, 1.78, 0.0), 0.20, 0.26, _mat_metal)
	handle.rotation_degrees.x = 90.0

func _add_cylinder(pos: Vector3, top_radius: float, bottom_radius: float,
		height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 8
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
	mesh.radial_segments = 8
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
	mesh.rings = 20
	mesh.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi
