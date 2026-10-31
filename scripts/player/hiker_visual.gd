extends Node3D

## 低模登山求生者：防寒裤、冲锋衣兜帽、红色登山包 + 黄色防潮垫、
## 木柴捆、右手探针杆与雪地探孔圆环。只构建 Visual 子节点，不改碰撞/控制脚本。

var _mat_pants: StandardMaterial3D
var _mat_coat: StandardMaterial3D
var _mat_hood: StandardMaterial3D
var _mat_pack: StandardMaterial3D
var _mat_pad: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_white: StandardMaterial3D
var _mat_hole: StandardMaterial3D

func _ready() -> void:
	_make_materials()
	_build_legs()
	_build_torso()
	_build_backpack()
	_build_probe()

func _make_materials() -> void:
	_mat_pants = _mat(Color(0.18, 0.20, 0.24), 0.94)
	_mat_coat = _mat(Color(0.46, 0.36, 0.24), 0.86)
	_mat_hood = _mat(Color(0.33, 0.25, 0.17), 0.90)
	_mat_pack = _mat(Color(0.78, 0.22, 0.16), 0.80)
	_mat_pad = _mat(Color(0.86, 0.66, 0.18), 0.82)
	_mat_wood = _mat(Color(0.34, 0.24, 0.14), 0.95)
	_mat_dark = _mat(Color(0.10, 0.10, 0.11), 0.90)
	_mat_white = _mat(Color(0.90, 0.93, 0.95), 0.55)
	_mat_hole = _mat(Color(0.62, 0.82, 1.0), 0.35)
	_mat_hole.emission_enabled = true
	_mat_hole.emission = Color(0.45, 0.70, 1.0)
	_mat_hole.emission_energy_multiplier = 0.9

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _build_legs() -> void:
	_add_capsule(Vector3(-0.15, 0.42, 0.10), 0.10, 0.78, _mat_pants, Vector3(8.0, 0.0, 0.0))
	_add_capsule(Vector3(0.15, 0.42, -0.10), 0.10, 0.78, _mat_pants, Vector3(-8.0, 0.0, 0.0))
	_add_box(Vector3(-0.15, 0.10, 0.22), Vector3(0.18, 0.16, 0.32), _mat_dark)
	_add_box(Vector3(0.15, 0.10, -0.20), Vector3(0.18, 0.16, 0.32), _mat_dark)

func _build_torso() -> void:
	var torso := _add_capsule(Vector3(0.0, 1.05, 0.0), 0.30, 0.85, _mat_coat)
	torso.scale = Vector3(1.0, 1.0, 0.82)

	_add_capsule(Vector3(-0.34, 1.10, 0.0), 0.09, 0.52, _mat_coat, Vector3(0.0, 0.0, 18.0))
	_add_capsule(Vector3(0.34, 1.10, 0.0), 0.09, 0.52, _mat_coat, Vector3(0.0, 0.0, -18.0))

	var hood := _add_sphere(Vector3(0.0, 1.56, 0.0), 0.28, _mat_hood)
	hood.scale = Vector3(1.0, 1.08, 1.02)
	_add_sphere(Vector3(0.0, 1.56, -0.18), 0.17, _mat_dark)
	# 兜帽前沿
	var rim := _add_cylinder(Vector3(0.0, 1.47, -0.20), 0.26, 0.26, 0.08, _mat_hood)
	rim.rotation_degrees.x = 90.0

func _build_backpack() -> void:
	_add_box(Vector3(0.0, 1.14, 0.36), Vector3(0.44, 0.58, 0.26), _mat_pack)
	_add_box(Vector3(-0.15, 1.28, 0.22), Vector3(0.06, 0.42, 0.06), _mat_dark)
	_add_box(Vector3(0.15, 1.28, 0.22), Vector3(0.06, 0.42, 0.06), _mat_dark)

	var pad := _add_cylinder(Vector3(0.0, 1.48, 0.36), 0.10, 0.10, 0.56, _mat_pad)
	pad.rotation_degrees.z = 90.0

	for log_idx in range(3):
		var log_mesh := _add_cylinder(
			Vector3(0.31, 0.92 + float(log_idx) * 0.10, 0.36),
			0.035, 0.045, 0.46, _mat_wood
		)
		log_mesh.rotation_degrees.z = 90.0
		log_mesh.rotation_degrees.y = 8.0 * float(log_idx - 1)

func _build_probe() -> void:
	var pole := _add_cylinder(Vector3(0.47, 1.05, 0.04), 0.024, 0.030, 2.10, _mat_dark)
	pole.name = "ProbePole"
	for band in range(5):
		var band_mesh := _add_cylinder(
			Vector3(0.47, 0.25 + float(band) * 0.38, 0.04),
			0.032, 0.032, 0.11,
			_mat_white if band % 2 == 0 else _mat_dark
		)
		band_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var hole_mesh := TorusMesh.new()
	hole_mesh.inner_radius = 0.12
	hole_mesh.outer_radius = 0.21
	hole_mesh.rings = 16
	hole_mesh.ring_segments = 8
	var hole := MeshInstance3D.new()
	hole.name = "ProbeHole"
	hole.mesh = hole_mesh
	hole.material_override = _mat_hole
	hole.position = Vector3(0.47, 0.035, 0.04)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hole)

func _add_capsule(pos: Vector3, radius: float, height: float,
		material: StandardMaterial3D, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rotation_deg
	add_child(mi)
	return mi

func _add_cylinder(pos: Vector3, top_radius: float, bottom_radius: float,
		height: float, material: StandardMaterial3D) -> MeshInstance3D:
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

func _add_box(pos: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi

func _add_sphere(pos: Vector3, radius: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi
