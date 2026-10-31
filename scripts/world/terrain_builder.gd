class_name TerrainBuilder
extends Node3D

## M1 地形网格 + 碰撞。100 m x 100 m，1 m 网格分辨率。
## 顶点色 R 通道写入归一化雪深，供 snow_terrain.gdshader 使用。

const TERRAIN_SHADER := preload("res://shaders/snow_terrain.gdshader")

@export var resolution: int = 100
@export var world_size: float = 100.0

func _ready() -> void:
	_build_terrain()

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
	mesh_instance.material_override = mat
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
	st.set_color(Color(snow_norm, 0.0, 0.0, 1.0))
	st.add_vertex(p)
