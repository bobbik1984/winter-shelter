extends RefCounted
## Presentation invariants: valid deterministic meshes, bounded complexity, untouched terrain/anchors.
var passed := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func mesh_ok(mesh: ArrayMesh, max_triangles: int, label: String) -> void:
	check(mesh != null and mesh.get_surface_count() == 1, label + " uses one material surface")
	if mesh == null or mesh.get_surface_count() == 0: return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check(vertices.size() > 0 and vertices.size() / 3 <= max_triangles, label + " stays within geometry budget")
	var valid := vertices.size() == normals.size()
	for v in vertices: valid = valid and v.is_finite()
	for n in normals: valid = valid and n.is_finite() and n.length_squared() > 0.5
	check(valid, label + " has finite nondegenerate geometry")
func run() -> Dictionary:
	var recipe0 := TerrainHeight.RECIPE
	var seed0 := TerrainHeight.SEED
	var rot0 := TerrainHeight.ROTATION_DEG
	TerrainHeight.RECIPE = TerrainRecipe.new()
	TerrainHeight.SEED = 7
	TerrainHeight.ROTATION_DEG = 0
	var config := EnvironmentDetails.settings()
	check(config != null and config.view_distance_m <= 50.0, "ground-detail distance is resource-driven and limited")
	var mesh := SpruceMesh.build(21, Vector3.RIGHT)
	mesh_ok(mesh, 660, "near spruce")
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0].x < 0.0, "bark faces outward with Godot clockwise winding")
	var again := SpruceMesh.build(21, Vector3.RIGHT)
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == again.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "tree seed is deterministic")
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != SpruceMesh.build(22, Vector3.RIGHT).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "tree variants differ")
	var far := SpruceMesh.build(9, Vector3.RIGHT, 0.38, 6)
	mesh_ok(far, 310, "far spruce")
	check(far.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() < mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), "far trees remain cheaper")
	mesh_ok(SpruceMesh.build(21, Vector3.ZERO), 660, "zero wind fallback")
	var right := centroid(mesh)
	var left := centroid(SpruceMesh.build(21, Vector3.LEFT))
	check(right.x > left.x, "tree crown still leans downwind")
	var footprint := Footprints.make_mesh()
	mesh_ok(footprint, 60, "bootprint")
	check(faces_up(footprint), "boot floor and rim face the camera above ground")
	var colors: PackedColorArray = footprint.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(has_color(colors, config.compacted_snow_color) and has_color(colors, config.footprint_rim_color), "bootprint has dark floor and snow rim in one surface")
	var at := Vector3(8, 0, 10)
	for forward in [Vector3.RIGHT, Vector3.FORWARD, Vector3.ZERO]:
		var basis := Footprints.surface_basis(at, forward)
		check(basis.is_finite() and absf(basis.determinant() - 1.0) < 0.001, "footprint basis handles slopes and zero heading")
	var parent := Node3D.new()
	var rocks: Array[Vector3] = [Vector3(8, 10, 1.0)]
	var trees := PackedVector2Array([Vector2(9, 12)])
	var rocks0 := rocks.duplicate()
	var trees0 := trees.duplicate()
	var depth0 := SnowField.snow_at(8, 10)
	EnvironmentDetails.build(parent, rocks, trees)
	check(parent.get_child_count() > 0, "valid rock/tree anchors gain ground details")
	for child in parent.get_children():
		check(child is MeshInstance3D and child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ground details add no collider, light or shadow caster")
		check(child.visibility_range_end == config.view_distance_m, "ground details are distance-culled")
		mesh_ok(child.mesh, 2000, "ground chunk")
		check(faces_up(child.mesh), "snow apron and fragment normals point above the ground")
	check(rocks == rocks0 and trees == trees0 and SnowField.snow_at(8, 10) == depth0, "decoration leaves gameplay anchors and depth unchanged")
	free_ground(parent)
	parent = Node3D.new()
	var disabled := config.duplicate() as EnvironmentDetailSettings
	disabled.enabled = false
	EnvironmentDetails.build(parent, rocks, trees, disabled)
	check(parent.get_child_count() == 0, "disabled details add no work")
	EnvironmentDetails.build(parent, [], PackedVector2Array(), config)
	check(parent.get_child_count() == 0, "empty anchor set is supported")
	# Broken/tweaked editor values are bounded by the generator as well as inspector hints.
	var edge := config.duplicate() as EnvironmentDetailSettings
	edge.tree_base_stride = 0
	edge.chunk_size_m = 0
	edge.rock_chips_per_group = 100
	EnvironmentDetails.build(parent, rocks, trees, edge)
	check(parent.get_child_count() <= 2, "invalid stride/chunk size are clamped")
	free_ground(parent)
	TerrainHeight.RECIPE = TerrainRecipe.preset("lakeshore")
	var lake := Vector2.ZERO
	var found := false
	for x in range(-45, 46, 5):
		for z in range(-45, 46, 5):
			if TerrainHeight.is_lake_at(x, z): lake = Vector2(x, z); found = true
	check(found, "lake test fixture exists")
	parent = Node3D.new()
	EnvironmentDetails.build(parent, [Vector3(lake.x, lake.y, 1.0)], PackedVector2Array([lake]), config)
	check(parent.get_child_count() == 0, "no loose rock or tree snow collar appears on ice")
	free_ground(parent)
	TerrainHeight.RECIPE = recipe0
	TerrainHeight.SEED = seed0
	TerrainHeight.ROTATION_DEG = rot0
	return {"passed": passed, "failures": failures}
func centroid(mesh: ArrayMesh) -> Vector3:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sum := Vector3.ZERO
	for v in vertices: sum += v
	return sum / vertices.size()

func has_color(colors: PackedColorArray, target: Color) -> bool:
	# GPU vertex colors are packed to 8-bit channels, unlike Resource float colors.
	for color in colors:
		if absf(color.r - target.r) <= 1.0 / 255.0 and absf(color.g - target.g) <= 1.0 / 255.0 and absf(color.b - target.b) <= 1.0 / 255.0: return true
	return false

func free_ground(parent: Node3D) -> void:
	# Godot 4.3 dummy renderer needs overrides released before their ArrayMesh on teardown.
	for child in parent.get_children():
		child.material_override = null
		child.mesh = null
	parent.free()

func faces_up(mesh: ArrayMesh) -> bool:
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for normal in normals:
		if normal.y <= 0.0: return false
	return true
