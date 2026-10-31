class_name HikerVisual
extends Node3D

## 低模登山求生者：防寒裤、冲锋衣兜帽、红色登山包 + 黄色防潮垫、
## 木柴捆、右手探针杆与雪地探孔圆环。只构建 Visual 子节点，不改碰撞/控制脚本。

## 背负挂件（T2.2：采集结果直接体现在背包外侧）
var _logs: Array[MeshInstance3D] = []
var _bedding: Array[MeshInstance3D] = []
var _mat_grass: StandardMaterial3D

var _mat_pants: StandardMaterial3D
var _mat_coat: StandardMaterial3D
var _mat_hood: StandardMaterial3D
var _mat_pack: StandardMaterial3D
var _mat_pad: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_white: StandardMaterial3D
var _mat_hole: StandardMaterial3D

const GLB := "res://assets/models/char_survivor.glb"

var _anim: AnimationPlayer
## 体感表现（VISUAL_LANGUAGE §3）：呼出的白汽频率 + 寒颤幅度，随体温变化。
var _breath: GPUParticles3D
var _shiver := 0.0
var _t := 0.0
var _inst: Node3D
var _current := ""

func _ready() -> void:
	_make_materials()
	if ResourceLoader.exists(GLB):
		_build_from_glb()
		return
	# 回退：原生几何体拼装（没有 glb 时）
	_build_legs()
	_build_torso()
	_build_backpack()
	_build_probe()

## V4：Blender 生成的角色（tools/blender/build_hiker.py）。角色面朝 +Z，背包在 -Z。
func _build_from_glb() -> void:
	var inst := (load(GLB) as PackedScene).instantiate()
	add_child(inst)
	_inst = inst
	_build_breath()
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_anim = inst.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer if not inst.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	if _anim:
		# Godot 导入时会去掉 "-loop" 后缀；这里显式设置循环
		for name_ in ["Idle", "Walk", "Dig"]:
			if _anim.has_animation(name_):
				_anim.get_animation(name_).loop_mode = Animation.LOOP_LINEAR
		_play("Idle")
	# 背负挂件（随背包内容显示）：原木横绑在包底，干草束插在包侧
	for log_idx in range(4):
		var log_mesh := _add_cylinder(Vector3(0.0, 0.88 + float(log_idx) * 0.09, -0.40), 0.04, 0.05, 0.62, _mat_wood)
		log_mesh.rotation_degrees.z = 90.0
		log_mesh.rotation_degrees.y = 6.0 * float(log_idx - 1)
		log_mesh.visible = false
		_logs.append(log_mesh)
	_mat_grass = _mat(Color(0.74, 0.60, 0.33), 0.95)
	for b in range(3):
		var bundle := _add_cylinder(Vector3(0.24 + b * 0.04, 1.25 + b * 0.05, -0.26), 0.07, 0.09, 0.5, _mat_grass)
		bundle.rotation_degrees.x = -15.0
		bundle.visible = false
		_bedding.append(bundle)

func _build_breath() -> void:
	_breath = GPUParticles3D.new()
	_breath.amount = 10
	_breath.lifetime = 1.1
	_breath.explosiveness = 0.85
	_breath.local_coords = false
	_breath.position = Vector3(0, 1.55, 0.2)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.25, 1)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0, 0.15, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_breath.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.95, 1.0, 0.6)
	q.material = m
	_breath.draw_pass_1 = q
	add_child(_breath)

## 体温 0..100 → 呼吸间隔（冷 = 急促）与寒颤幅度（< 35 明显发抖）。
func set_body_state(warmth: float, exerting: bool) -> void:
	if _breath:
		var cold := clampf(1.0 - warmth / 100.0, 0.0, 1.0)
		_breath.lifetime = lerpf(1.4, 0.7, cold) * (0.8 if exerting else 1.0)
	_shiver = clampf((40.0 - warmth) / 40.0, 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	if _inst:
		_inst.position = Vector3(sin(_t * 41.0) * 0.012, 0, cos(_t * 37.0) * 0.008) * _shiver

func _play(name_: String, blend: float = 0.2) -> void:
	if _anim == null or _current == name_ or not _anim.has_animation(name_):
		return
	_current = name_
	_anim.play(name_, blend)

## 由 PlayerController 每帧调用：速度 → 走 / 站；探针 → Probe；施工 / 采集 → Dig。
func set_motion(speed: float, probing: bool, working: bool) -> void:
	if probing:
		_play("Probe", 0.12)
	elif working:
		_play("Dig")
	elif speed > 0.3:
		_play("Walk")
		if _anim:
			_anim.speed_scale = clampf(speed / 2.6, 0.6, 1.5)
		return
	else:
		_play("Idle", 0.3)
	if _anim:
		_anim.speed_scale = 1.0

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

	for log_idx in range(4):
		var log_mesh := _add_cylinder(
			Vector3(0.0, 0.86 + float(log_idx) * 0.09, 0.53),
			0.04, 0.05, 0.62, _mat_wood
		)
		log_mesh.rotation_degrees.z = 90.0
		log_mesh.rotation_degrees.y = 6.0 * float(log_idx - 1)
		log_mesh.visible = false
		_logs.append(log_mesh)
	_mat_grass = _mat(Color(0.74, 0.60, 0.33), 0.95)
	for b in range(3):
		var bundle := _add_cylinder(Vector3(-0.30 + b * 0.04, 1.30 + b * 0.05, 0.36), 0.07, 0.09, 0.5, _mat_grass)
		bundle.rotation_degrees.x = 15.0
		bundle.visible = false
		_bedding.append(bundle)

## 背包外观随背包内容变化：每 3 根木材多挂一根原木，每份垫层一束干草。
func set_load(wood: int, bedding: int) -> void:
	for i in range(_logs.size()):
		_logs[i].visible = wood > i * 3
	for i in range(_bedding.size()):
		_bedding[i].visible = bedding > i

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
