class_name Campfire
extends Node3D

## 营火（T2.7）：石圈 + 柴堆 + 火苗 + 2700K 闪烁火光；燃料以游戏分钟计。
## 火在雪庇护所内禁止（D3）；营火只修正入夜状态（pre-warm），不整夜供热（D2），倒棚反射火除外。

signal burned_out()

var fuel_minutes: float = 0.0
var lit: bool = false

## 取暖半径（m）：地上的光圈就画这么大，是真实范围。
var warm_radius: float = 3.5
var _circle: MeshInstance3D
var _light: OmniLight3D
var _glow: MeshInstance3D
var _flames: Array[MeshInstance3D] = []
var _mat_flame: StandardMaterial3D
var _t := 0.0

func _ready() -> void:
	add_to_group("campfires")
	global_position.y = TerrainHeight.height_at(global_position.x, global_position.z)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.22, 0.23, 0.26)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.19, 0.11)
	for i in range(8):
		var a := TAU * i / 8.0
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.22
		sm.radial_segments = 6
		sm.rings = 3
		s.mesh = sm
		s.material_override = stone
		s.position = Vector3(cos(a) * 0.55, 0.06, sin(a) * 0.55)
		add_child(s)
	for i in range(4):
		var l := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.06
		cm.height = 0.8
		cm.radial_segments = 6
		l.mesh = cm
		l.material_override = wood
		l.position = Vector3(0, 0.22, 0)
		l.rotation = Vector3(deg_to_rad(62.0), i * PI * 0.5, 0)
		add_child(l)
	_mat_flame = StandardMaterial3D.new()
	_mat_flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_flame.albedo_color = Color(1.0, 0.62, 0.20)
	_mat_flame.emission_enabled = true
	_mat_flame.emission = Color(1.0, 0.5, 0.12)
	_mat_flame.emission_energy_multiplier = 4.0
	for i in range(3):
		var f := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.30 - i * 0.06
		fm.height = 1.15 - i * 0.25
		fm.radial_segments = 6
		f.mesh = fm
		f.material_override = _mat_flame
		f.position = Vector3((i - 1) * 0.14, 0.2 + fm.height * 0.5, (i % 2) * 0.1)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		_flames.append(f)
	# 光晕：白天的雪地上，只靠火苗和泛光（低档已关）从远处看不出有火
	var glow_tex := GradientTexture2D.new()
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.62, 0.22, 0.75))
	grad.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	glow_tex.gradient = grad
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_mat.albedo_texture = glow_tex
	_glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 3.2)
	_glow.mesh = quad
	_glow.material_override = glow_mat
	_glow.position = Vector3(0, 0.7, 0)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	_circle = _make_warm_circle()
	add_child(_circle)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.58, 0.24)
	_light.omni_range = 7.0
	_light.light_energy = 2.2
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.8, 0)
	add_child(_light)
	_apply_lit()

## 贴地的光圈：内部很淡，外缘一圈清楚，外面立刻没有，读得出"边界在这里"。
## 顶点高度取真实碰撞面：height_at 和粗网格之间在坡上能差出几十厘米，整圈会埋进雪里看不见。
func _make_warm_circle() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [[0.0, 0.2], [0.82, 0.16], [0.88, 0.8], [0.985, 0.95], [1.0, 0.0]]
	var space := get_world_3d().direct_space_state
	var segs := 48
	var base_y := global_position.y
	var point := func(a: float, k: float) -> Vector3:
		var v := Vector3(cos(a), 0.0, sin(a)) * warm_radius * k
		var wx: float = global_position.x + v.x
		var wz: float = global_position.z + v.z
		var h := TerrainHeight.height_at(wx, wz)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(wx, h + 3.0, wz), Vector3(wx, h - 3.0, wz)))
		# 打到树干 / 石头（差得太多）就用地形公式
		if not hit.is_empty() and absf(float(hit["position"].y) - h) < 0.6:
			h = float(hit["position"].y)
		v.y = h - base_y + 0.1
		return v
	for i in range(segs):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for r in range(profile.size() - 1):
			var p0: Array = profile[r]
			var p1: Array = profile[r + 1]
			var quad := [[a0, p0], [a1, p0], [a1, p1], [a0, p0], [a1, p1], [a0, p1]]
			for q in quad:
				var pr: Array = q[1]
				st.set_color(Color(1.0, 0.5, 0.08, float(pr[1])))
				st.add_vertex(point.call(float(q[0]), float(pr[0])))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func ignite(minutes: float) -> void:
	fuel_minutes = maxf(fuel_minutes, 0.0) + minutes
	lit = true
	_apply_lit()

func add_fuel(minutes: float) -> void:
	fuel_minutes += minutes
	if not lit:
		lit = true
		_apply_lit()

## 按游戏分钟燃烧。
func burn(minutes: float) -> void:
	if not lit:
		return
	fuel_minutes -= minutes
	if fuel_minutes <= 0.0:
		fuel_minutes = 0.0
		lit = false
		_apply_lit()
		burned_out.emit()

func _apply_lit() -> void:
	if _light == null:
		return
	_light.visible = lit
	_glow.visible = lit
	_circle.visible = lit
	for f in _flames:
		f.visible = lit

func _process(delta: float) -> void:
	if not lit:
		return
	_t += delta
	_light.light_energy = 2.0 + 0.35 * sin(_t * 11.0) + 0.2 * sin(_t * 23.0)
	for i in range(_flames.size()):
		_flames[i].scale = Vector3(1.0, 0.85 + 0.2 * sin(_t * (9.0 + i * 3.0)), 1.0)

## 距离衰减的取暖强度 0..1。
func warmth_at(pos: Vector3, radius: float) -> float:
	if not lit:
		return 0.0
	var d := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	return clampf(1.0 - d / radius, 0.0, 1.0)
