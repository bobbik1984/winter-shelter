extends RefCounted
var passed := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func run() -> Dictionary:
	var recipe := TerrainHeight.RECIPE
	var seed0 := TerrainHeight.SEED
	TerrainHeight.RECIPE = TerrainRecipe.new()
	TerrainHeight.SEED = 7
	var cfg := EnvironmentDetails.settings().duplicate() as EnvironmentDetailSettings
	var at := Transform3D(Basis(Vector3.UP, 0.8), Vector3(8, SnowField.height_at(8, 10), 10))
	var pile0 := CampGroundDress.pile_position(Vector3(8, 0, 10), Vector3.RIGHT, Vector3.FORWARD, PackedVector2Array(), [])
	var occupied := PackedVector2Array([Vector2(pile0.x, pile0.z)])
	var moved := CampGroundDress.pile_position(Vector3(8, 0, 10), Vector3.RIGHT, Vector3.FORWARD, occupied, [])
	check(moved.distance_to(pile0) > 1.8, "supply layout avoids existing tree crowns")
	check(moved == CampGroundDress.pile_position(Vector3(8, 0, 10), Vector3.RIGHT, Vector3.FORWARD, occupied, []), "supply placement deterministic")
	var depth := SnowField.snow_at(8, 10)
	check(CampGroundDress.build(at, 2.3, 0, true, cfg) == null, "unstarted site has no established camp traces")
	check(CampGroundDress.build(at, 2.3, 1, true, cfg) == null, "first tunnel stage adds no completed approach dressing")
	var mesh := CampGroundDress.build(at, 2.3, 5, true, cfg)
	valid(mesh, 720, true, "rotated camp")
	var again := CampGroundDress.build(at, 2.3, 5, true, cfg)
	check(vertices(mesh) == vertices(again), "camp dressing deterministic")
	check(SnowField.snow_at(8, 10) == depth, "camp does not change physical snow depth")
	var verts := vertices(mesh)
	var doorway_clear := true
	var grounded := true
	for v in verts:
		var w: Vector3 = at * v
		var lift := w.y - SnowField.height_at(w.x, w.z)
		grounded = grounded and lift >= -0.03 and lift <= cfg.camp_mound_height_m + 0.03
		if absf(v.x) < 0.5 and v.z > 2.3: doorway_clear = doorway_clear and lift < 0.04
	check(grounded, "all rotated dress vertices follow actual snow height")
	check(doorway_clear, "no raised spoil pile blocks entrance approach")
	var dry := CampGroundDress.build(at, 1.0, 5, false, cfg)
	valid(dry, 80, true, "non-snow camp")
	check(vertices(dry).size() < verts.size(), "non-excavated shelter has no fake snow spoil")
	cfg.camp_enabled = false
	check(CampGroundDress.build(at, 2.3, 5, true, cfg) == null, "camp presentation can be disabled")
	cfg.camp_enabled = true
	cfg.camp_mound_count = 999
	cfg.camp_entry_width_m = -8
	cfg.camp_entry_length_m = 999
	cfg.camp_mound_height_m = 99
	valid(CampGroundDress.build(at, 2.3, 5, true, cfg), 1040, true, "clamped editor values")
	valid(CampGroundDress.log_mesh(), 64, false, "stored wood")
	valid(CampGroundDress.bough_mesh(), 20, true, "stored bough")
	TerrainHeight.RECIPE = TerrainRecipe.preset("lakeshore")
	var found := false
	for x in range(-40, 41, 4):
		for z in range(-40, 41, 4):
			if TerrainHeight.is_lake_at(x, z):
				found = true
				var ice := Transform3D(Basis.IDENTITY, Vector3(x, 0, z - 3.2))
				var patch := CampGroundDress.build(ice, 2.3, 5, false, cfg)
				if patch:
					var clear := true
					for v in vertices(patch):
						var w := ice * v
						clear = clear and not TerrainHeight.is_lake_at(w.x, w.z)
					check(clear, "camp vertices never decorate lake surface")
				else: check(true, "lake patch omitted")
				break
		if found: break
	check(found, "lake fixture available")
	TerrainHeight.RECIPE = recipe
	TerrainHeight.SEED = seed0
	return {"passed": passed, "failures": failures}
func vertices(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mesh else PackedVector3Array()
func valid(mesh: ArrayMesh, budget: int, upward: bool, label: String) -> void:
	check(mesh != null and mesh.get_surface_count() == 1, label + " has single opaque surface")
	if mesh == null: return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check(verts.size() > 0 and verts.size() / 3 <= budget, label + " stays within budget")
	var finite := true
	var facing := true
	for v in verts: finite = finite and v.is_finite()
	for n in normals:
		finite = finite and n.is_finite() and n.length_squared() > 0.5
		facing = facing and n.y > 0
	check(finite, label + " has valid normals and vertices")
	if upward: check(facing, label + " surface faces upward")
