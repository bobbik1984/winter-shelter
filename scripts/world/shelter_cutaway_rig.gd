class_name ShelterCutawayRig
extends Node3D

## M2 45° 等距剖面高床雪洞（主创 SurfaceTool 完整 3D 山体切片沙盘 v4 精修版）：
## 严格对标参考图右上角 SHELTER DESIGN (SNOW CAVE) — CUTAWAY VIEW (45° ISOMETRIC)：
##   1. 连续平滑无折痕的内拱曲线（入口隧道 -> 主洞室圆拱平滑过渡）与自然接地的外雪坡裙边
##   2. 剖面正上方半切开的穿顶排湿通风井凹槽 (Vent / Chimney) + 垂直气流双箭头
##   3. 后景高挑覆雪冷杉林 + 前方分层冰砖雪坪基底
##   4. 洞内写实陈设：松针隔热垫、多节绗缝睡袋、带侧袋登山包、D柄雪铲、2700K 暖光烛灯与冷气回流箭头。

const CUTAWAY_SHADER := preload("res://shaders/cutaway_shelter.gdshader")
const LANTERN_LOCAL := Vector3(0.18, 0.68, -1.08)

@export var place_on_terrain: bool = false
@export var world_origin: Vector3 = Vector3(20.5, 0.0, 11.2)

var _mat_outer: ShaderMaterial
var _mat_inner: ShaderMaterial
var _mat_cut: ShaderMaterial
var _mat_rim: StandardMaterial3D
var _mat_bedding: StandardMaterial3D
var _mat_bag: StandardMaterial3D
var _mat_bag_trim: StandardMaterial3D
var _mat_pack: StandardMaterial3D
var _mat_pack_strap: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_vent: StandardMaterial3D
var _mat_cold: StandardMaterial3D
var _mat_flame: StandardMaterial3D
var _mat_pine_dark: StandardMaterial3D
var _mat_pine_snow: StandardMaterial3D

func _ready() -> void:
	if place_on_terrain:
		global_position = Vector3(
			world_origin.x,
			TerrainHeight.height_at(world_origin.x, world_origin.z) - 0.10,
			world_origin.z
		)
	_make_materials()
	_build_continuous_snow_shell()
	_build_diorama_trees()
	_build_interior_props()
	_build_cold_air_arrows()
	_build_vent_chimney()
	_build_candle_lantern()


func _make_materials() -> void:
	_mat_outer = _cutaway_material(0.0, 0.0)
	_mat_inner = _cutaway_material(1.0, 0.0)
	_mat_cut = _cutaway_material(0.0, 1.0)

	_mat_rim = _solid(Color(0.74, 0.85, 0.96), 0.55)
	_mat_bedding = _solid(Color(0.24, 0.29, 0.18), 0.92)
	_mat_bag = _solid(Color(0.54, 0.28, 0.14), 0.82)
	_mat_bag_trim = _solid(Color(0.36, 0.19, 0.10), 0.88)
	_mat_pack = _solid(Color(0.52, 0.36, 0.20), 0.86)
	_mat_pack_strap = _solid(Color(0.28, 0.20, 0.13), 0.90)
	_mat_metal = _solid(Color(0.62, 0.69, 0.76), 0.35)
	_mat_wood = _solid(Color(0.35, 0.23, 0.13), 0.90)
	_mat_vent = _solid(Color(0.26, 0.38, 0.56), 0.68)
	_mat_cold = _solid(Color(0.68, 0.86, 0.99), 0.30)
	_mat_cold.emission_enabled = true
	_mat_cold.emission = Color(0.48, 0.75, 0.98)
	_mat_cold.emission_energy_multiplier = 0.42
	_mat_flame = _solid(Color(1.0, 0.72, 0.28), 0.15)
	_mat_flame.emission_enabled = true
	_mat_flame.emission = Color(1.0, 0.56, 0.16)
	_mat_flame.emission_energy_multiplier = 2.8
	_mat_pine_dark = _solid(Color(0.09, 0.16, 0.22), 0.92)
	_mat_pine_snow = _solid(Color(0.58, 0.72, 0.88), 0.85)


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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## 外雪丘表面高度函数 (x: -4.2..4.0, z: 0.0..-3.6)
static func _outer_hill_y(x: float, z: float) -> float:
	var nx: float = (x - 0.10) / 4.05
	var nz: float = (z + 0.30) / 3.85
	var dome: float = maxf(0.0, 1.0 - nx * nx * 0.78 - nz * nz * 0.58)
	var shoulder_left: float = smoothstep(-4.2, -1.6, x) * (1.0 - smoothstep(-0.6, 1.4, x)) * 0.32
	var shoulder_right: float = (1.0 - smoothstep(1.8, 4.0, x)) * 0.18
	var drift_ripple: float = sin(x * 2.2 + z * 1.6) * 0.035
	# 顶部排湿通风口碗状凹陷 (x ≈ 0.25, z ≈ -0.18)
	var vent_dist: float = Vector2(x - 0.25, z + 0.18).length()
	var vent_dip: float = (1.0 - smoothstep(0.14, 0.42, vent_dist)) * 0.28
	return -0.36 + pow(dome, 0.74) * 2.82 + shoulder_left + shoulder_right + drift_ripple - vent_dip


## 内腔拱顶高度函数：用连续 smoothstep 融合左侧入口隧道与主圆穹顶，消除任何生硬折角
static func _inner_ceil_y(x: float, z: float) -> float:
	var z_norm: float = clampf(absf(z) / 2.05, 0.0, 1.0)
	var depth_taper: float = sqrt(maxf(0.06, 1.0 - z_norm * z_norm * 0.90))

	# 左侧入口隧道拱高 (x: -3.15 .. -1.10)
	var tx: float = clampf((x + 3.15) / 2.05, 0.0, 1.0)
	var tunnel_arch: float = (-0.02 + sin(tx * PI * 0.78) * 0.58 + tx * 0.28)

	# 主洞室圆穹顶高 (x: -1.65 .. +2.35)
	var cx: float = clampf((x - 0.42) / 1.95, -1.0, 1.0)
	var dome_arch: float = -0.05 + pow(maxf(0.0, 1.0 - cx * cx), 0.56) * 1.62

	var blend: float = smoothstep(-1.75, -0.95, x)
	return lerpf(tunnel_arch, dome_arch, blend) * depth_taper


## 内腔阶梯底面高度函数 (左侧下倾入口 -> 中左深凹冷气坑 -> 右侧宽阔高床雪台)
static func _inner_floor_y(x: float) -> float:
	if x < -1.35:
		var t: float = clampf((x + 3.15) / 1.80, 0.0, 1.0)
		return lerpf(-0.04, -0.18, t)
	if x < -0.12:
		var p: float = (x + 0.74) / 0.62
		return -0.50 + p * p * 0.06
	return 0.50


func _build_continuous_snow_shell() -> void:
	var x_steps := 64
	var z_steps := 28
	var x_min := -4.15
	var x_max := 3.95
	var z_front := 0.0
	var z_back := -3.45
	var base_y := -0.58

	# 1. 45° 剖面正前切口实心厚雪墙 (CutFaceMesh @ z = 0.0)
	var st_cut := SurfaceTool.new()
	st_cut.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(x_steps):
		var x0: float = lerpf(x_min, x_max, float(i) / float(x_steps))
		var x1: float = lerpf(x_min, x_max, float(i + 1) / float(x_steps))
		var xm: float = 0.5 * (x0 + x1)

		var out0: float = maxf(base_y, _outer_hill_y(x0, z_front))
		var out1: float = maxf(base_y, _outer_hill_y(x1, z_front))
		var in_cavity: bool = xm >= -3.12 and xm <= 2.35

		var top_inner0: float = maxf(base_y, _inner_ceil_y(x0, z_front)) if in_cavity else base_y
		var top_inner1: float = maxf(base_y, _inner_ceil_y(x1, z_front)) if in_cavity else base_y

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
		if in_cavity:
			var fl0: float = _inner_floor_y(x0)
			var fl1: float = _inner_floor_y(x1)
			_add_quad(
				st_cut,
				Vector3(x0, base_y, z_front),
				Vector3(x1, base_y, z_front),
				Vector3(x1, fl1, z_front),
				Vector3(x0, fl0, z_front),
				Vector3(0.0, 0.0, 1.0)
			)

	var cut_mi := MeshInstance3D.new()
	cut_mi.name = "CutFaceMesh"
	cut_mi.mesh = st_cut.commit()
	cut_mi.material_override = _mat_cut
	add_child(cut_mi)

	# 2. 外雪丘连续曲面 + 前方雪地基底裙边 (OuterHillMesh)
	var st_outer := SurfaceTool.new()
	st_outer.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(z_steps):
		var z0: float = lerpf(z_front, z_back, float(j) / float(z_steps))
		var z1: float = lerpf(z_front, z_back, float(j + 1) / float(z_steps))
		for i in range(x_steps):
			var x0: float = lerpf(x_min, x_max, float(i) / float(x_steps))
			var x1: float = lerpf(x_min, x_max, float(i + 1) / float(x_steps))
			var p00 := Vector3(x0, maxf(base_y, _outer_hill_y(x0, z0)), z0)
			var p10 := Vector3(x1, maxf(base_y, _outer_hill_y(x1, z0)), z0)
			var p11 := Vector3(x1, maxf(base_y, _outer_hill_y(x1, z1)), z1)
			var p01 := Vector3(x0, maxf(base_y, _outer_hill_y(x0, z1)), z1)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_add_quad(st_outer, p00, p10, p11, p01, n)

	# 前方雪地小坪与左侧入口外雪坪 (z: 0.0 .. +1.55)
	var z_apron := 1.55
	_add_quad(
		st_outer,
		Vector3(x_min, base_y, z_apron),
		Vector3(x_max, base_y, z_apron),
		Vector3(x_max, base_y + 0.02, z_front),
		Vector3(x_min, base_y + 0.02, z_front),
		Vector3(0.0, 1.0, 0.0)
	)
	_add_quad(
		st_cut,
		Vector3(x_min, base_y - 0.28, z_apron),
		Vector3(x_max, base_y - 0.28, z_apron),
		Vector3(x_max, base_y, z_apron),
		Vector3(x_min, base_y, z_apron),
		Vector3(0.0, 0.0, 1.0)
	)

	var outer_mi := MeshInstance3D.new()
	outer_mi.name = "OuterHillMesh"
	outer_mi.mesh = st_outer.commit()
	outer_mi.material_override = _mat_outer
	add_child(outer_mi)

	# 3. 封闭无死角的 3D 内腔穹顶、背墙、高床垂直立面台阶与地板 (InnerVaultMesh)
	var st_inner := SurfaceTool.new()
	st_inner.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cav_steps_x := 48
	var cav_steps_z := 18
	var cx_min := -3.12
	var cx_max := 2.35
	var cz_back := -2.05

	for j in range(cav_steps_z):
		var z0: float = lerpf(z_front, cz_back, float(j) / float(cav_steps_z))
		var z1: float = lerpf(z_front, cz_back, float(j + 1) / float(cav_steps_z))
		for i in range(cav_steps_x):
			var x0: float = lerpf(cx_min, cx_max, float(i) / float(cav_steps_x))
			var x1: float = lerpf(cx_min, cx_max, float(i + 1) / float(cav_steps_x))

			var c00 := Vector3(x0, _inner_ceil_y(x0, z0), z0)
			var c10 := Vector3(x1, _inner_ceil_y(x1, z0), z0)
			var c11 := Vector3(x1, _inner_ceil_y(x1, z1), z1)
			var c01 := Vector3(x0, _inner_ceil_y(x0, z1), z1)
			_add_quad(st_inner, c00, c10, c11, c01, Vector3(0.0, -0.65, 0.75).normalized())

			var f00 := Vector3(x0, _inner_floor_y(x0), z0)
			var f10 := Vector3(x1, _inner_floor_y(x1), z0)
			var f11 := Vector3(x1, _inner_floor_y(x1), z1)
			var f01 := Vector3(x0, _inner_floor_y(x0), z1)
			_add_quad(st_inner, f00, f10, f11, f01, Vector3(0.0, 1.0, 0.2).normalized())

	# 高床雪台左侧垂直立面墙 (x = -0.12, y: -0.50 .. +0.50, z: 0.0 .. cz_back)
	_add_quad(
		st_inner,
		Vector3(-0.12, -0.50, z_front),
		Vector3(-0.12, -0.50, cz_back),
		Vector3(-0.12, 0.50, cz_back),
		Vector3(-0.12, 0.50, z_front),
		Vector3(-1.0, 0.0, 0.35).normalized()
	)

	# 冷气坑左侧台阶立面墙 (x = -1.35, y: -0.50 .. -0.18, z: 0.0 .. cz_back)
	_add_quad(
		st_inner,
		Vector3(-1.35, -0.50, cz_back),
		Vector3(-1.35, -0.50, z_front),
		Vector3(-1.35, -0.18, z_front),
		Vector3(-1.35, -0.18, cz_back),
		Vector3(1.0, 0.0, 0.35).normalized()
	)

	# 洞室最右侧封闭端墙 (x = cx_max, z: 0.0 .. cz_back)
	for j in range(cav_steps_z):
		var z0: float = lerpf(z_front, cz_back, float(j) / float(cav_steps_z))
		var z1: float = lerpf(z_front, cz_back, float(j + 1) / float(cav_steps_z))
		_add_quad(
			st_inner,
			Vector3(cx_max, 0.50, z0),
			Vector3(cx_max, 0.50, z1),
			Vector3(cx_max, maxf(0.50, _inner_ceil_y(cx_max, z1)), z1),
			Vector3(cx_max, maxf(0.50, _inner_ceil_y(cx_max, z0)), z0),
			Vector3(-1.0, 0.0, 0.2).normalized()
		)

	# 洞室后背封闭雪墙 (z = cz_back)
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

	# 4. 剖切面内外缘冰晶高光描边带 (RimHighlightMesh)
	var st_rim := SurfaceTool.new()
	st_rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim_z := 0.015
	for i in range(x_steps):
		var x0: float = lerpf(x_min, x_max, float(i) / float(x_steps))
		var x1: float = lerpf(x_min, x_max, float(i + 1) / float(x_steps))
		var out0: float = maxf(base_y, _outer_hill_y(x0, z_front))
		var out1: float = maxf(base_y, _outer_hill_y(x1, z_front))
		_add_quad(
			st_rim,
			Vector3(x0, out0 - 0.04, rim_z),
			Vector3(x1, out1 - 0.04, rim_z),
			Vector3(x1, out0, rim_z),
			Vector3(x0, out0, rim_z),
			Vector3(0.0, 0.0, 1.0)
		)
		var xm: float = 0.5 * (x0 + x1)
		if xm >= -3.12 and xm <= 2.35:
			var c0: float = maxf(base_y, _inner_ceil_y(x0, z_front))
			var c1: float = maxf(base_y, _inner_ceil_y(x1, z_front))
			_add_quad(
				st_rim,
				Vector3(x0, c0, rim_z),
				Vector3(x1, c1, rim_z),
				Vector3(x1, c1 + 0.038, rim_z),
				Vector3(x0, c0 + 0.038, rim_z),
				Vector3(0.0, 0.0, 1.0)
			)

	var rim_mi := MeshInstance3D.new()
	rim_mi.name = "RimHighlightMesh"
	rim_mi.mesh = st_rim.commit()
	rim_mi.material_override = _mat_rim
	add_child(rim_mi)


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


func _build_diorama_trees() -> void:
	# 对标参考图右上角：雪丘后方左、右两侧各矗立高挑的 4 层覆雪暗夜冷杉，形成深邃林地背景
	var tree_specs := [
		{"pos": Vector3(-3.85, -0.35, -2.15), "scale": 1.28},
		{"pos": Vector3(-3.05, 0.15, -2.55), "scale": 1.45},
		{"pos": Vector3(-2.15, 0.65, -2.95), "scale": 1.22},
		{"pos": Vector3(2.55, 0.55, -2.85), "scale": 1.25},
		{"pos": Vector3(3.45, -0.05, -2.35), "scale": 1.38},
	]
	for spec in tree_specs:
		var root := Node3D.new()
		root.position = spec["pos"]
		var s: float = spec["scale"]
		root.scale = Vector3(s, s, s)
		add_child(root)
		for tier in range(4):
			var ty: float = 0.42 + float(tier) * 0.44
			var r_bot: float = 0.56 - float(tier) * 0.10
			var cone := _make_cone_node(Vector3(0.0, ty, 0.0), r_bot, 0.65, _mat_pine_dark)
			root.add_child(cone)
			var cap := _make_cone_node(Vector3(0.0, ty + 0.09, 0.0), r_bot * 0.80, 0.36, _mat_pine_snow)
			root.add_child(cap)


func _make_cone_node(pos: Vector3, radius: float, h: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = radius
	mesh.height = h
	mesh.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


func _build_interior_props() -> void:
	# 1. 高床雪台上的深橄榄色防潮松针隔热垫 (Raised sleeping platform)
	_add_box(Vector3(1.12, 0.54, -0.88), Vector3(1.88, 0.07, 1.05), _mat_bedding)

	# 2. 多节绗缝棕褐色羽绒睡袋 (Quilted mummy sleeping bag + 头部立领枕头)
	for seg in range(5):
		var sx: float = 0.46 + float(seg) * 0.31
		var sr: float = 0.165 - float(seg) * 0.008
		var baffle := _add_capsule(Vector3(sx, 0.65, -0.88), sr, 0.82, _mat_bag)
		baffle.rotation_degrees.x = 90.0
		if seg < 4:
			var seam := _add_box(Vector3(sx + 0.155, 0.65, -0.88), Vector3(0.025, sr * 1.85, 0.76), _mat_bag_trim)
			seam.name = "BagSeam"
	var hood := _add_box(Vector3(0.32, 0.70, -0.88), Vector3(0.26, 0.16, 0.52), _mat_bag_trim)
	hood.rotation_degrees.z = -10.0

	# 3. 卸下的探险登山包（主包体 + 顶盖 + 两侧副袋 + 背带，位于雪台内侧壁龛）
	_add_box(Vector3(-0.08, 0.75, -1.28), Vector3(0.35, 0.46, 0.28), _mat_pack)
	_add_box(Vector3(-0.08, 1.00, -1.27), Vector3(0.37, 0.12, 0.30), _mat_bag_trim)
	_add_box(Vector3(-0.27, 0.70, -1.26), Vector3(0.08, 0.25, 0.20), _mat_pack_strap)
	_add_box(Vector3(0.11, 0.70, -1.26), Vector3(0.08, 0.25, 0.20), _mat_pack_strap)

	# 4. 靠在左侧内拱壁上的 D 柄雪铲 (Snow shovel)
	var shovel_shaft := _add_cylinder(Vector3(-0.78, 0.45, -1.18), 0.022, 0.022, 0.94, _mat_wood)
	shovel_shaft.rotation_degrees = Vector3(8.0, 0.0, -16.0)
	var shovel_grip := _add_box(Vector3(-0.91, 0.88, -1.12), Vector3(0.14, 0.04, 0.04), _mat_wood)
	shovel_grip.rotation_degrees.z = -16.0
	var shovel_blade := _add_box(Vector3(-0.65, 0.02, -1.22), Vector3(0.26, 0.30, 0.035), _mat_metal)
	shovel_blade.rotation_degrees.z = -16.0


func _build_cold_air_arrows() -> void:
	# 1. 左侧入口隧道向内微倾的气流箭头
	for i in range(4):
		var t: float = float(i) / 3.0
		var ax: float = lerpf(-2.85, -1.45, t)
		var ay: float = lerpf(0.06, -0.14, t) + sin(t * PI) * 0.08
		var seg := _add_box(Vector3(ax, ay, -0.38), Vector3(0.24, 0.032, 0.05), _mat_cold)
		seg.rotation_degrees.z = -12.0 - t * 14.0
	var entry_tip := _add_cone(Vector3(-1.28, -0.20, -0.38), 0.075, 0.17, _mat_cold)
	entry_tip.rotation_degrees.z = -125.0

	# 2. 冷气坑底部下沉回流环 (Cold-air pit swirl)
	var pit_loop := _add_torus(Vector3(-0.72, -0.36, -0.62), 0.25, 0.30, _mat_cold)
	pit_loop.rotation_degrees.x = 90.0
	var pit_tip := _add_cone(Vector3(-0.47, -0.36, -0.52), 0.065, 0.15, _mat_cold)
	pit_tip.rotation_degrees.x = 90.0


func _build_vent_chimney() -> void:
	# 剖面正上方半切开的穿顶排湿通风井凹槽 (x = 0.25, y: 1.55 .. 2.38, z = -0.02) + 向上排湿箭头
	var channel := _add_box(Vector3(0.25, 1.96, 0.01), Vector3(0.28, 0.88, 0.08), _mat_vent)
	channel.name = "VentChimneyChannel"
	var collar := _add_torus(Vector3(0.25, 2.36, -0.12), 0.16, 0.24, _mat_vent)
	collar.name = "VentCollar"
	var stem := _add_cylinder(Vector3(0.25, 2.28, 0.03), 0.038, 0.038, 0.92, _mat_cold)
	stem.name = "VentArrowStem"
	var head := _add_cone(Vector3(0.25, 2.82, 0.03), 0.12, 0.24, _mat_cold)
	head.name = "VentArrowHead"


func _build_candle_lantern() -> void:
	var base := _add_cylinder(LANTERN_LOCAL + Vector3(0.0, -0.09, 0.0), 0.065, 0.08, 0.08, _mat_metal)
	base.name = "LanternBase"
	var cap := _add_cylinder(LANTERN_LOCAL + Vector3(0.0, 0.11, 0.0), 0.06, 0.075, 0.05, _mat_metal)
	cap.name = "LanternCap"
	var flame := _add_sphere(LANTERN_LOCAL, 0.052, _mat_flame)
	flame.name = "LanternWick"
	var light := OmniLight3D.new()
	light.name = "CandleLight2700K"
	light.light_color = Color(1.0, 0.64, 0.24)
	light.light_energy = 1.75
	light.omni_range = 3.2
	light.position = LANTERN_LOCAL + Vector3(0.0, 0.08, 0.18)
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
	mesh.radial_segments = 12
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
