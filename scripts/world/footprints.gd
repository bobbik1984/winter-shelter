class_name Footprints
extends MultiMeshInstance3D

## 雪地脚印（V8 / T4.2 一部分）：玩家每走一步留下带脚掌、暗底和隆起雪边的低面数鞋印，左右交替。
## 环形缓冲 MultiMesh（一次 draw call）；旧脚印被新脚印覆盖。深雪里脚印更大更深色。

const MAX_PRINTS := 160

var player: PlayerController
## 拖痕（T4.2）：背负沉重（由 GameDirector 写入）时，脚印之间多一道拖拽沟。
var heavy := false
var _drag: MultiMeshInstance3D
var _di := 0
var _i := 0
var _dist := 0.0
var _last := Vector3.INF
var _left := true

func _ready() -> void:
	var mesh := make_mesh()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_PRINTS
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0
	_drag = MultiMeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1, 1, 1)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = EnvironmentDetails.settings().compacted_snow_color
	dmat.roughness = 1.0
	dm.material = dmat
	_drag.multimesh = MultiMesh.new()
	_drag.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_drag.multimesh.mesh = dm
	_drag.multimesh.instance_count = MAX_PRINTS
	_drag.multimesh.visible_instance_count = 0
	_drag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drag.extra_cull_margin = 200.0
	add_child(_drag)

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
	if depth < 0.08: return
	var basis := surface_basis(q, f).scaled(Vector3(0.24 * s, 1.0, 0.42 * s))
	multimesh.set_instance_transform(_i, Transform3D(basis, Vector3(q.x, SnowField.height_at(q.x, q.z) + 0.012, q.z)))
	_i = (_i + 1) % MAX_PRINTS
	if heavy:
		var back := p - f * 0.55
		var db := Basis(Vector3.UP, atan2(f.x, f.z)).scaled(Vector3(0.16, 0.025, 0.7))
		_drag.multimesh.set_instance_transform(_di, Transform3D(db, Vector3(back.x, SnowField.height_at(back.x, back.z) + 0.015, back.z)))
		_di = (_di + 1) % MAX_PRINTS
		_drag.multimesh.visible_instance_count = maxi(_drag.multimesh.visible_instance_count, _di if _di > 0 else MAX_PRINTS)
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _i if _i > 0 else MAX_PRINTS)


## 只用一张不透明顶点色网格；暗底是视觉压痕，不改变雪深/碰撞。
static func make_mesh() -> ArrayMesh:
	var config := EnvironmentDetails.settings()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 鞋尖宽、鞋跟窄。尺寸归一化，世界尺寸由实例控制。
	var outline := PackedVector2Array([Vector2(0, 0.5), Vector2(0.35, 0.45), Vector2(0.48, 0.25),
		Vector2(0.4, 0), Vector2(0.29, -0.24), Vector2(0.29, -0.44), Vector2(0, -0.5),
		Vector2(-0.29, -0.44), Vector2(-0.29, -0.24), Vector2(-0.4, 0), Vector2(-0.48, 0.25), Vector2(-0.35, 0.45)])
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		# Godot 的正面使用顺时针绕序；从鞋尖顺着轮廓反向提交，法线朝上。
		st.set_color(config.compacted_snow_color)
		st.add_vertex(Vector3(0, 0.004, 0))
		st.add_vertex(Vector3(b.x * 0.7, 0.007, b.y * 0.7))
		st.add_vertex(Vector3(a.x * 0.7, 0.007, a.y * 0.7))
		_add_ring(st, a, b, 0.7, 0.007, 1.0, 0.032, config.compacted_snow_color, config.footprint_rim_color)
		_add_ring(st, a, b, 1.0, 0.032, 1.22, -0.012, config.footprint_rim_color, config.snow_color)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.08
	mesh.surface_set_material(0, mat)
	return mesh

static func _add_ring(st: SurfaceTool, a: Vector2, b: Vector2, inner: float, iy: float, outer: float, oy: float, inside: Color, outside: Color) -> void:
	st.set_color(inside); st.add_vertex(Vector3(a.x * inner, iy, a.y * inner))
	st.set_color(outside); st.add_vertex(Vector3(b.x * outer, oy, b.y * outer)); st.add_vertex(Vector3(a.x * outer, oy, a.y * outer))
	st.set_color(inside); st.add_vertex(Vector3(a.x * inner, iy, a.y * inner)); st.add_vertex(Vector3(b.x * inner, iy, b.y * inner))
	st.set_color(outside); st.add_vertex(Vector3(b.x * outer, oy, b.y * outer))

## 顺着真实雪面法线放置，避免斜坡上鞋印一半悬空。
static func surface_basis(at: Vector3, forward: Vector3) -> Basis:
	var e := 0.12
	var dx := SnowField.height_at(at.x + e, at.z) - SnowField.height_at(at.x - e, at.z)
	var dz := SnowField.height_at(at.x, at.z + e) - SnowField.height_at(at.x, at.z - e)
	var up := Vector3(-dx / (2.0 * e), 1.0, -dz / (2.0 * e)).normalized()
	var along := forward - up * forward.dot(up)
	if along.length_squared() < 0.0001: along = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	along = along.normalized()
	return Basis(up.cross(along).normalized(), up, along)
