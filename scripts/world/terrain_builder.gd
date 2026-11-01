class_name TerrainBuilder
extends Node3D

## M1 地形网格 + 碰撞。100 m x 100 m，1 m 网格分辨率。
## 顶点色 R 通道写入归一化雪深，供 snow_terrain.gdshader 使用。

const TERRAIN_SHADER := preload("res://shaders/snow_terrain.gdshader")

@export var resolution: int = 100
@export var world_size: float = 100.0

var _material: ShaderMaterial

func _ready() -> void:
	# V7：订阅 AtmosphereState（WeatherController 可能稍后才 ready，延迟连接）
	_connect_atmosphere.call_deferred()
	add_to_group("terrain")
	_build_terrain()

func _connect_atmosphere() -> void:
	var a := AtmosphereState.of(get_tree())
	if a:
		a.changed.connect(func(s: AtmosphereState) -> void: set_sun_dir(s.sun_dir))
		set_sun_dir(a.sun_dir)

## 雪面 shader 的太阳方向（来自 AtmosphereState）。
func set_debug_depth(on: bool) -> void:
	if _material:
		_material.set_shader_parameter("debug_depth", on)

func set_low_quality(on: bool) -> void:
	if _material:
		_material.set_shader_parameter("low_quality", on)

func set_sun_dir(dir: Vector3) -> void:
	if _material:
		_material.set_shader_parameter("sun_dir_world", dir)

func _build_terrain() -> void:
	var half := world_size * 0.5
	var step := world_size / float(resolution)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for j in range(resolution):
		var z0 := -half + float(j) * step
		var z1 := z0 + step
		for i in range(resolution):
			var x0 := -half + float(i) * step
			var x1 := x0 + step

			var p00 := Vector3(x0, TerrainHeight.height_at(x0, z0), z0)
			var p10 := Vector3(x1, TerrainHeight.height_at(x1, z0), z0)
			var p01 := Vector3(x0, TerrainHeight.height_at(x0, z1), z1)
			var p11 := Vector3(x1, TerrainHeight.height_at(x1, z1), z1)

			_add_vertex(st, p00)
			_add_vertex(st, p11)
			_add_vertex(st, p01)
			_add_vertex(st, p00)
			_add_vertex(st, p10)
			_add_vertex(st, p11)

	var mesh := st.commit()
	if mesh == null:
		push_error("[TerrainBuilder] SurfaceTool.commit() 返回 null")
		return

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	var wind := load("res://resources/default_wind.tres") as WindData
	if wind:
		var b := wind.get_blow_direction_3d()   # 已随地图旋转（L3）
		mat.set_shader_parameter("wind_blow", Vector2(b.x, b.z))
	mesh_instance.material_override = mat
	_material = mat
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var collision := CollisionShape3D.new()
	collision.name = "TerrainCollision"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)

func _add_vertex(st: SurfaceTool, p: Vector3) -> void:
	st.set_normal(TerrainHeight.normal_at(p.x, p.z))
	var snow_norm := clampf(TerrainHeight.snow_depth_at(p.x, p.z) / 2.5, 0.0, 1.0)
	# G 通道 = 湖面（冰）遮罩（S1）
	st.set_color(Color(snow_norm, 1.0 if TerrainHeight.is_lake_at(p.x, p.z) else 0.0, 0.0, 1.0))
	st.add_vertex(p)
