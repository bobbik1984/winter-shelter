class_name ShelterCutawayRig
extends Node3D

## M2 45° 等距剖面高床雪洞（主创 SurfaceTool 连续厚雪断面版）：
## 彻底摒弃方形 BoxMesh 盒子，用连续数学曲面生成：
##   1. 外层自然隆起雪丘曲面 (OuterHillMesh)
##   2. 1.5m 厚实心冰蓝横截面切口 (CutFaceMesh: 拱顶上方厚雪层 + 底部实心高床雪台与冷气坑断面)
##   3. 内腔圆拱雪壁与阶梯底面 (InnerVaultMesh: 下倾入口隧道 -> 下凹冷气坑 -> 抬高雪床台)
##   4. 洞内陈设：松针垫层、棕橙睡袋、卸下红背包、靠墙雪铲、2700K 暖光烛灯、穿顶排湿通风管与冷气流线。

const CUTAWAY_SHADER := preload("res://shaders/cutaway_shelter.gdshader")
const LANTERN_LOCAL := Vector3(0.35, 1.02, -0.95)

@export var place_on_terrain: bool = false
@export var world_origin: Vector3 = Vector3(19.5, 0.0, 10.5)

var _mat_outer: ShaderMaterial
var _mat_inner: ShaderMaterial
var _mat_cut: ShaderMaterial
var _mat_bedding: StandardMaterial3D
var _mat_bag: StandardMaterial3D
var _mat_pack: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_vent: StandardMaterial3D
var _mat_cold: StandardMaterial3D
var _mat_flame: StandardMaterial3D

func _ready() -> void:
	if place_on_terrain:
		global_position = Vector3(
			world_origin.x,
			TerrainHeight.height_at(world_origin.x, world_origin.z) - 0.10,
			world_origin.z
		)
	_make_materials()
	_build_continuous_snow_shell()
	_build_interior_props()
	_build_cold_air_arrows()
	_build_vent_chimney()
	_build_candle_lantern()


func _make_materials() -> void:
	_mat_outer = _cutaway_material(0.10, 0.0)
	_mat_inner = _cutaway_material(1.0, 0.0)
	_mat_cut = _cutaway_material(0.35, 1.0)

	_mat_bedding = _solid(Color(0.28, 0.34, 0.19), 0.95)
	_mat_bag = _solid(Color(0.58, 0.31, 0.15), 0.88)
	_mat_pack = _solid(Color(0.76, 0.24, 0.16), 0.85)
	_mat_metal = _solid(Color(0.64, 0.70, 0.76), 0.35)
	_mat_wood = _solid(Color(0.34, 0.23, 0.14), 0.92)
	_mat_vent = _solid(Color(0.68, 0.84, 0.98), 0.40)
	_mat_cold = _solid(Color(0.48, 0.74, 0.98), 0.30)
	_mat_cold.emission_enabled = true
	_mat_cold.emission = Color(0.36, 0.64, 0.96)
	_mat_cold.emission_energy_multiplier = 0.45
	_mat_flame = _solid(Color(1.0, 0.68, 0.24), 0.20)
	_mat_flame.emission_enabled = true
	_mat_flame.emission = Color(1.0, 0.52, 0.14)
	_mat_flame.emission_energy_multiplier = 3.2


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


## 外雪丘表面高度函数 (x: -3.8..3.6, z: 0.0..-3.8)
static func _outer_hill_y(x: float, z: float) -> float:
	var nx: float = (x - 0.25) / 3.55
	var nz: float = z / 3.85
	var dome: float = maxf(0.0, 1.0 - nx * nx * 0.82 - nz * nz * 0.75)
	var base_skirt: float = smoothstep(-3.8, -1.8, x) * 0.45
	return -0.25 + pow(dome, 0.78) * 3.15 + base_skirt * (1.0 - absf(nz) * 0.5)


## 内腔拱顶高度函数 (左侧低矮入口隧道 -> 中右高挑圆拱室)
static func _inner_ceil_y(x: float, z: float) -> float:
	var depth_taper: float = clampf(1.0 - pow(absf(z + 0.95) / 1.65, 2.2), 0.15, 1.0)
	if x < -1.25:
		# 左侧下倾入口隧道顶
		var tx: float = clampf((x + 3.1) / 1.85, 0.0, 1.0)
		return (0.62 + tx * 0.42) * depth_taper
	# 主拱室圆穹顶
	var cx: float = (x - 0.55) / 2.05
	var arch: float = maxf(0.0, 1.0 - cx * cx)
	return (0.72 + sqrt(arch) * 1.22) * depth_taper


## 内腔阶梯底面高度函数 (入口缓降 -> 下沉冷气坑 -> 右侧抬高睡台)
static func _inner_floor_y(x: float) -> float:
	if x < -1.35:
		# 入口隧道微向下倾
		var t: float = clampf((x + 3.1) / 1.75, 0.0, 1.0)
		return lerpf(0.18, 0.05, t)
	if x < -0.05:
		# 下沉冷气槽 (Cold-air pit)
		var p: float = (x + 0.70) / 0.65
		return -0.32 + p * p * 0.36
	# 右侧高床雪台 (Raised sleeping platform)
	var step_up: float = smoothstep(-0.05, 0.22, x)
	return lerpf(0.04, 0.68, step_up)


func _build_continuous_snow_shell() -> void:
	var x_steps := 48
	var z_steps := 24
	var x_min := -3.5
	var x_max := 3.3
	var z_front := 0.0
	var z_back := -3.4

	# 1. 45° 剖面正前切口实心厚雪墙 (CutFaceMesh @ z = 0.0)
	var st_cut := SurfaceTool.new()
	st_cut.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(x_steps):
		var x0: float = lerpf(x_min, x_max, float(i) / float(x_steps))
		var x1: float = lerpf(x_min, x_max, float(i + 1) / float(x_steps))

		var out0: float = _outer_hill_y(x0, z_front)
		var out1: float = _outer_hill_y(x1, z_front)
		var in_cavity0: bool = x0 >= -3.05 and x0 <= 2.50
		var in_cavity1: bool = x1 >= -3.05 and x1 <= 2.50

		var top_inner0: float = _inner_ceil_y(x0, z_front) if in_cavity0 else -0.35
		var top_inner1: float = _inner_ceil_y(x1, z_front) if in_cavity1 else -0.35

		# 拱顶上方 1.5m 厚实心雪顶切面
		_add_quad(
			st_cut,
			Vector3(x0, top_inner0, z_front),
			Vector3(x1, top_inner1, z_front),
			Vector3(x1, out1, z_front),
			Vector3(x0, out0, z_front),
			Vector3(0.0, 0.0, 1.0)
		)

		# 腔体下方实心雪床/冷气坑基座切面
		if in_cavity0 or in_cavity1:
			var fl0: float = _inner_floor_y(x0)
			var fl1: float = _inner_floor_y(x1)
			_add_quad(
				st_cut,
				Vector3(x0, -0.38, z_front),
				Vector3(x1, -0.38, z_front),
				Vector3(x1, fl1, z_front),
				Vector3(x0, fl0, z_front),
				Vector3(0.0, 0.0, 1.0)
			)

	var cut_mi := MeshInstance3D.new()
	cut_mi.name = "CutFaceMesh"
	cut_mi.mesh = st_cut.commit()
	cut_mi.material_override = _mat_cut
	add_child(cut_mi)

	# 2. 外雪丘连续曲面 (OuterHillMesh: z 从 0.0 到 -3.4)
	var st_outer := SurfaceTool.new()
	st_outer.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(z_steps):
		var z0: float = lerpf(z_front, z_back, float(j) / float(z_steps))
		var z1: float = lerpf(z_front, z_back, float(j + 1) / float(z_steps))
		for i in range(x_steps):
			var x0: float = lerpf(x_min, x_max, float(i) / float(x_steps))
			var x1: float = lerpf(x_min, x_max, float(i + 1) / float(x_steps))
			var p00 := Vector3(x0, _outer_hill_y(x0, z0), z0)
			var p10 := Vector3(x1, _outer_hill_y(x1, z0), z0)
			var p11 := Vector3(x1, _outer_hill_y(x1, z1), z1)
			var p01 := Vector3(x0, _outer_hill_y(x0, z1), z1)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_add_quad(st_outer, p00, p10, p11, p01, n)

	var outer_mi := MeshInstance3D.new()
	outer_mi.name = "OuterHillMesh"
	outer_mi.mesh = st_outer.commit()
	outer_mi.material_override = _mat_outer
	add_child(outer_mi)

	# 3. 内腔圆拱雪顶、弧形背墙与阶梯雪床 (InnerVaultMesh: z 从 0.0 到 -2.1)
	var st_inner := SurfaceTool.new()
	st_inner.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cav_steps_x := 36
	var cav_steps_z := 14
	var cx_min := -3.05
	var cx_max := 2.50
	var cz_back := -2.15
	for j in range(cav_steps_z):
		var z0: float = lerpf(z_front, cz_back, float(j) / float(cav_steps_z))
		var z1: float = lerpf(z_front, cz_back, float(j + 1) / float(cav_steps_z))
		for i in range(cav_steps_x):
			var x0: float = lerpf(cx_min, cx_max, float(i) / float(cav_steps_x))
			var x1: float = lerpf(cx_min, cx_max, float(i + 1) / float(cav_steps_x))

			# 内拱顶面
			var c00 := Vector3(x0, _inner_ceil_y(x0, z0), z0)
			var c10 := Vector3(x1, _inner_ceil_y(x1, z0), z0)
			var c11 := Vector3(x1, _inner_ceil_y(x1, z1), z1)
			var c01 := Vector3(x0, _inner_ceil_y(x0, z1), z1)
			_add_quad(st_inner, c00, c01, c11, c10, Vector3(0.0, -0.7, 0.7).normalized())

			# 阶梯雪底面 (入口 + 冷气坑 + 高床雪台)
			var f00 := Vector3(x0, _inner_floor_y(x0), z0)
			var f10 := Vector3(x1, _inner_floor_y(x1), z0)
			var f11 := Vector3(x1, _inner_floor_y(x1), z1)
			var f01 := Vector3(x0, _inner_floor_y(x0), z1)
			_add_quad(st_inner, f00, f10, f11, f01, Vector3(0.0, 1.0, 0.0))

	# 封闭内腔后背雪墙 (z = cz_back)
	for i in range(cav_steps_x):
		var x0: float = lerpf(cx_min, cx_max, float(i) / float(cav_steps_x))
		var x1: float = lerpf(cx_min, cx_max, float(i + 1) / float(cav_steps_x))
		var b00 := Vector3(x0, _inner_floor_y(x0), cz_back)
		var b10 := Vector3(x1, _inner_floor_y(x1), cz_back)
		var b11 := Vector3(x1, _inner_ceil_y(x1, cz_back), cz_back)
		var b01 := Vector3(x0, _inner_ceil_y(x0, cz_back), cz_back)
		_add_quad(st_inner, b00, b10, b11, b01, Vector3(0.0, 0.0, 1.0))

	var inner_mi := MeshInstance3D.new()
	inner_mi.name = "InnerVaultMesh"
	inner_mi.mesh = st_inner.commit()
	inner_mi.material_override = _mat_inner
	add_child(inner_mi)


func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(p0)
	st.set_normal(n)
	st.add_vertex(p1)
	st.set_normal(n)
	st.add_vertex(p2)
	st.set_normal(n)
	st.add_vertex(p0)
	st.set_normal(n)
	st.add_vertex(p2)
	st.set_normal(n)
	st.add_vertex(p3)


func _build_interior_props() -> void:
	# 高床松针隔热垫与棕橙色睡袋
	_add_box(Vector3(1.18, 0.73, -0.95), Vector3(1.95, 0.09, 1.25), _mat_bedding)
	var bag := _add_capsule(Vector3(1.22, 0.85, -0.92), 0.24, 1.45, _mat_bag)
	bag.rotation_degrees.z = 90.0
	var pillow := _add_box(Vector3(1.72, 0.90, -0.92), Vector3(0.32, 0.14, 0.42), _mat_pack)
	pillow.rotation_degrees.z = 8.0

	# 卸下的红色登山包与靠墙雪铲
	_add_box(Vector3(0.05, 0.90, -1.35), Vector3(0.34, 0.42, 0.24), _mat_pack)
	var shovel_shaft := _add_cylinder(Vector3(-0.35, 0.92, -1.45), 0.022, 0.022, 1.05, _mat_wood)
	shovel_shaft.rotation_degrees = Vector3(12.0, 0.0, -18.0)
	var shovel_blade := _add_box(Vector3(-0.18, 0.48, -1.42), Vector3(0.24, 0.28, 0.04), _mat_metal)
	shovel_blade.rotation_degrees.z = -18.0


func _build_cold_air_arrows() -> void:
	# 入口向下沉入冷气槽的弧形指示流线
	for i in range(3):
		var seg := _add_cylinder(
			Vector3(-1.35 + float(i) * 0.38, 0.12 - float(i) * 0.12, -0.55),
			0.022, 0.022, 0.34, _mat_cold
		)
		seg.rotation_degrees.z = 68.0 + float(i) * 12.0
	var pit_loop := _add_torus(Vector3(-0.70, -0.14, -0.65), 0.30, 0.36, _mat_cold)
	pit_loop.rotation_degrees.x = 90.0


func _build_vent_chimney() -> void:
	# 穿透 1.5m 雪顶的伸缩通风管与排湿气流箭头
	var vent := _add_cylinder(Vector3(0.55, 2.38, -0.85), 0.11, 0.13, 1.35, _mat_vent)
	vent.name = "VentChimney"
	for i in range(2):
		var arrow := _add_cone(Vector3(0.55, 2.95 + float(i) * 0.32, -0.85), 0.11, 0.22, _mat_cold)
		arrow.name = "VentArrow"


func _build_candle_lantern() -> void:
	var base := _add_cylinder(LANTERN_LOCAL, 0.06, 0.08, 0.18, _mat_metal)
	base.name = "LanternBody"
	var flame := _add_sphere(LANTERN_LOCAL + Vector3(0.0, 0.13, 0.0), 0.055, _mat_flame)
	flame.name = "LanternWick"
	var light := OmniLight3D.new()
	light.name = "CandleLight2700K"
	light.light_color = Color(1.0, 0.66, 0.28)
	light.light_energy = 2.6
	light.omni_range = 4.2
	light.position = LANTERN_LOCAL + Vector3(0.0, 0.18, 0.15)
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

func _add_cylinder(pos: Vector3, top_r: float, bot_r: float, h: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = h
	mesh.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _add_cone(pos: Vector3, radius: float, h: float, mat: Material) -> MeshInstance3D:
	return _add_cylinder(pos, 0.0, radius, h, mat)

func _add_sphere(pos: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _add_capsule(pos: Vector3, radius: float, h: float, mat: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = h
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _add_torus(pos: Vector3, inner: float, outer: float, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi
