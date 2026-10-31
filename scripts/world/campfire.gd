class_name Campfire
extends Node3D

## 营火（T2.7）：石圈 + 柴堆 + 火苗 + 2700K 闪烁火光；燃料以游戏分钟计。
## 火在雪庇护所内禁止（D3）；营火只修正入夜状态（pre-warm），不整夜供热（D2），倒棚反射火除外。

signal burned_out()

var fuel_minutes: float = 0.0
var lit: bool = false

var _light: OmniLight3D
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
		fm.bottom_radius = 0.16 - i * 0.03
		fm.height = 0.55 - i * 0.1
		fm.radial_segments = 6
		f.mesh = fm
		f.material_override = _mat_flame
		f.position = Vector3((i - 1) * 0.1, 0.35, (i % 2) * 0.08)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		_flames.append(f)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.58, 0.24)
	_light.omni_range = 7.0
	_light.light_energy = 2.2
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.8, 0)
	add_child(_light)
	_apply_lit()

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
