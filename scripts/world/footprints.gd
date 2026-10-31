class_name Footprints
extends MultiMeshInstance3D

## 雪地脚印（V8 / T4.2 一部分）：玩家每走一步在雪面压一个椭圆凹印，左右交替。
## 环形缓冲 MultiMesh（一次 draw call）；旧脚印被新脚印覆盖。深雪里脚印更大更深色。

const MAX_PRINTS := 160

var player: PlayerController
var _i := 0
var _dist := 0.0
var _last := Vector3.INF
var _left := true

func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.55, 0.70)
	mat.roughness = 1.0
	mesh.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_PRINTS
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0

func _process(_delta: float) -> void:
	if player == null:
		return
	var p := player.global_position
	if _last == Vector3.INF:
		_last = p
		return
	_dist += Vector2(p.x - _last.x, p.z - _last.z).length()
	_last = p
	if _dist < 0.62 or player.current_speed < 0.2:
		return
	_dist = 0.0
	var f := player.facing()
	var side := Vector3(-f.z, 0, f.x) * (0.13 if _left else -0.13)
	_left = not _left
	var q := p + side
	var depth := SnowField.snow_at(q.x, q.z)
	var s := lerpf(0.9, 1.25, clampf(depth / 2.0, 0.0, 1.0))
	var basis := Basis(Vector3.UP, atan2(f.x, f.z)).scaled(Vector3(0.24 * s, 0.03, 0.42 * s))
	multimesh.set_instance_transform(_i, Transform3D(basis, Vector3(q.x, SnowField.height_at(q.x, q.z) + 0.02, q.z)))
	_i = (_i + 1) % MAX_PRINTS
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _i if _i > 0 else MAX_PRINTS)
