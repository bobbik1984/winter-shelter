class_name SceneryBuilder
extends Node3D

## M1 微缩景观地标：多层积雪云杉、枯立木、倒木树根、迎风脊岩石。
## 全部由原地形高度函数落地，不依赖外部资产。

var _mat_green: StandardMaterial3D
var _mat_snow: StandardMaterial3D
var _mat_bark: StandardMaterial3D
var _mat_deadwood: StandardMaterial3D
var _mat_rock: StandardMaterial3D

const SPRUCES := [
	Vector3(-13.0, 0.0, -9.0), Vector3(-17.0, 0.0, 7.0), Vector3(-9.0, 0.0, 17.0),
	Vector3(-20.0, 0.0, 20.0), Vector3(12.0, 0.0, -13.0), Vector3(17.0, 0.0, 2.0),
	Vector3(22.0, 0.0, 15.0), Vector3(26.0, 0.0, -20.0), Vector3(31.0, 0.0, -30.0),
	Vector3(34.0, 0.0, 26.0), Vector3(16.0, 0.0, 32.0), Vector3(5.0, 0.0, 34.0),
	Vector3(-4.0, 0.0, 29.0), Vector3(28.0, 0.0, -27.0), Vector3(-6.0, 0.0, -19.0),
	Vector3(9.0, 0.0, 21.0),
]

const DEADWOODS := [
	Vector3(-8.0, 0.0, 3.0), Vector3(6.0, 0.0, 12.0), Vector3(15.0, 0.0, -6.0),
	Vector3(24.0, 0.0, 8.0), Vector3(29.0, 0.0, -14.0), Vector3(-2.0, 0.0, -25.0),
]

const ROOTBALLS := [
	Vector3(10.0, 0.0, 14.0), Vector3(20.0, 0.0, 23.0), Vector3(18.0, 0.0, -4.0),
]

const ROCKS := [
	Vector3(-16.0, 0.0, -2.0), Vector3(-18.0, 0.0, 10.0), Vector3(-12.0, 0.0, -15.0),
	Vector3(-20.0, 0.0, -19.0), Vector3(-14.0, 0.0, 23.0), Vector3(-9.0, 0.0, 5.0),
]

func _ready() -> void:
	_make_materials()
	_build_spruces()
	_build_deadwoods()
	_build_rootballs()
	_build_rocks()

func _make_materials() -> void:
	_mat_green = _make_material(Color(0.07, 0.16, 0.11), 0.92)
	_mat_snow = _make_material(Color(0.90, 0.94, 1.0), 0.80)
	_mat_bark = _make_material(Color(0.16, 0.11, 0.07), 0.95)
	_mat_deadwood = _make_material(Color(0.30, 0.27, 0.23), 0.96)
	_mat_rock = _make_material(Color(0.10, 0.11, 0.14), 0.98)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func _build_spruces() -> void:
	var index := 0
	for p in SPRUCES:
		var scale_factor := 0.85 + float(index % 4) * 0.13
		_spruce(p, scale_factor, -5.0)
		index += 1

func _spruce(pos: Vector3, scale_factor: float, tilt_degrees: float) -> void:
	var root := Node3D.new()
	root.name = "Spruce"
	root.position = Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) - 0.15, pos.z)
	root.rotation.z = deg_to_rad(tilt_degrees)
	root.scale = Vector3.ONE * scale_factor
	add_child(root)

	_add_cylinder(root, 0.16, 0.24, 2.1, 1.05, _mat_bark)
	_add_cone(root, 1.80, 2.8, 2.6, _mat_green)
	_add_cone(root, 1.35, 2.4, 3.9, _mat_green)
	_add_cone(root, 0.95, 2.0, 5.2, _mat_green)

	_add_cone(root, 1.10, 0.60, 3.65, _mat_snow)
	_add_cone(root, 0.82, 0.52, 4.85, _mat_snow)
	_add_cone(root, 0.60, 0.70, 5.95, _mat_snow)

func _build_deadwoods() -> void:
	var index := 0
	for p in DEADWOODS:
		var root := Node3D.new()
		root.name = "Deadwood"
		root.position = Vector3(p.x, TerrainHeight.height_at(p.x, p.z) - 0.1, p.z)
		root.rotation.y = deg_to_rad(float(index) * 37.0)
		add_child(root)

		_add_cylinder(root, 0.13, 0.28, 7.0, 3.5, _mat_deadwood)
		_add_cone(root, 0.14, 1.2, 7.4, _mat_deadwood)
		for branch in range(5):
			_add_branch(root, 3.0 + float(branch) * 0.8, float(branch) * 67.0,
				1.1 + float(branch % 3) * 0.35, 0.045, _mat_deadwood)
		index += 1

func _build_rootballs() -> void:
	var index := 0
	for p in ROOTBALLS:
		var root := Node3D.new()
		root.name = "Rootball"
		root.position = Vector3(p.x, TerrainHeight.height_at(p.x, p.z) - 0.15, p.z)
		root.rotation.y = deg_to_rad(35.0 + float(index) * 25.0)
		add_child(root)

		var trunk := _add_cylinder(root, 0.22, 0.34, 4.6, 0.7, _mat_deadwood)
		trunk.rotation_degrees.z = 90.0
		trunk.position = Vector3(1.4, 0.7, 0.0)

		var ball_mesh := SphereMesh.new()
		ball_mesh.radius = 1.0
		ball_mesh.height = 2.0
		ball_mesh.radial_segments = 8
		ball_mesh.rings = 4
		var ball := MeshInstance3D.new()
		ball.name = "RootBall"
		ball.mesh = ball_mesh
		ball.material_override = _mat_deadwood
		ball.position = Vector3(3.4, 0.8, 0.0)
		ball.scale = Vector3(0.22, 1.0, 1.0)
		root.add_child(ball)

		for spike in range(6):
			var root_spike := _add_cylinder(root, 0.02, 0.08, 1.0, 0.5, _mat_deadwood)
			root_spike.position = Vector3(3.4, 0.55, 0.0)
			root_spike.rotation_degrees = Vector3(0.0, float(spike) * 60.0, 90.0)
		index += 1

func _build_rocks() -> void:
	var index := 0
	for p in ROCKS:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		var rock := MeshInstance3D.new()
		rock.name = "RidgeRock"
		rock.mesh = mesh
		rock.material_override = _mat_rock
		rock.position = Vector3(p.x, TerrainHeight.height_at(p.x, p.z) + 0.15, p.z)
		rock.rotation.y = deg_to_rad(float(index) * 41.0)
		rock.scale = Vector3(1.6, 0.75, 1.15)
		add_child(rock)
		index += 1

func _add_cone(parent: Node3D, bottom_radius: float, height: float, y: float,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 8
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
		height: float, y: float, material: StandardMaterial3D) -> MeshInstance3D:
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
		length: float, radius: float, material: StandardMaterial3D) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, y, 0.0)
	pivot.rotation_degrees = Vector3(0.0, yaw_degrees, 58.0)
	parent.add_child(pivot)
	var branch := _add_cylinder(pivot, 0.02, radius, length, length * 0.5, material)
	branch.position = Vector3(0.0, length * 0.5, 0.0)
