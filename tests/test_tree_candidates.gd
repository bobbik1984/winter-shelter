extends RefCounted
## Candidate-only invariants. A technical PASS never substitutes for user visual approval.
var passed := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func validate(mesh: ArrayMesh, limit: int, label: String) -> void:
	check(mesh.get_surface_count() == 1, label + " one opaque crown surface")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	check(vertices.size() > 0 and vertices.size() / 3 <= limit, label + " bounded face count")
	var finite := vertices.size() == normals.size()
	for v in vertices: finite = finite and v.is_finite()
	for n in normals: finite = finite and n.is_finite() and n.length_squared() > 0.8
	check(finite, label + " finite vertices and unit normals")
	var edges := {}
	var orientation := {}
	for i in range(0, vertices.size(), 3):
		for j in 3:
			var a := key(vertices[i + j])
			var b := key(vertices[i + (j + 1) % 3])
			var id := a + ":" + b if a < b else b + ":" + a
			edges[id] = int(edges.get(id, 0)) + 1
			orientation[id] = int(orientation.get(id, 0)) + (1 if a < b else -1)
	check(edges.values().all(func(v): return v == 2), label + " closed canopy volumes have no open edges")
	check(orientation.values().all(func(v): return v == 0), label + " clockwise face winding is consistent")
	check(mesh.get_aabb().position.y >= -0.001, label + " crown stays above ground")
func key(v: Vector3) -> String:
	return str(Vector3i(roundi(v.x * 100000), roundi(v.y * 100000), roundi(v.z * 100000)))
func center(mesh: ArrayMesh) -> Vector3:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var sum := Vector3.ZERO
	for v in vertices: sum += v
	return sum / vertices.size()
func run() -> Dictionary:
	var ids := []
	for path in SpruceCrownMesh.PROFILES:
		var profile := load(path) as SpruceCrownProfile
		check(profile != null and not ids.has(profile.sample_id), "candidate profile has a unique identifier")
		ids.append(profile.sample_id)
		var mesh := SpruceCrownMesh.build(21, Vector3.RIGHT, profile)
		validate(mesh, 1000, profile.sample_id)
		var arrays := mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_COLOR].has(Color.BLACK), profile.sample_id + " separate bark vertex mask")
		check(arrays[Mesh.ARRAY_VERTEX] == SpruceCrownMesh.build(21, Vector3.RIGHT, profile).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], profile.sample_id + " repeatable seed")
		check(arrays[Mesh.ARRAY_VERTEX] != SpruceCrownMesh.build(22, Vector3.RIGHT, profile).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], profile.sample_id + " model variants differ")
		check(center(mesh).x > center(SpruceCrownMesh.build(21, Vector3.LEFT, profile)).x, profile.sample_id + " downwind crown asymmetry retained")
		check(continuous_canopy(mesh, profile), profile.sample_id + " foliage spans the crown height without empty horizontal bands")
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		check(n[0].dot(Vector3(v[0].x, 0, v[0].z)) > 0.0, profile.sample_id + " bark normal points outward")
	validate(SpruceCrownMesh.build(21, Vector3.ZERO), 1000, "zero wind/default profile")
	var bad := SpruceCrownProfile.new()
	bad.tiers = 100
	bad.radial_segments = 100
	bad.lower_tier_y = -9
	bad.upper_tier_y = -10
	bad.lower_radius = -1
	bad.upper_radius = -1
	bad.droop = 9
	validate(SpruceCrownMesh.build(21, Vector3.ZERO, bad, -1.0), 1000, "invalid editor values")
	check(SpruceMesh.build_baseline(21, Vector3.RIGHT).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3 == 542, "pre-detail baseline remains exactly 542 triangles")
	check(SpruceMesh.build(9, Vector3.RIGHT, 0.38, 6).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == SpruceMesh.build_baseline(9, Vector3.RIGHT, 0.38, 6).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "production far-tree path is unchanged")
	check(SpruceMesh.build(21, Vector3.RIGHT).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3 == 596, "production near tree is not silently replaced by a candidate")
	return {"passed": passed, "failures": failures}

func continuous_canopy(mesh: ArrayMesh, profile: SpruceCrownProfile) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for slice in 25:
		var y := lerpf(profile.lower_tier_y, profile.upper_tier_y + profile.upper_bough_height * 0.2, float(slice) / 24.0)
		var radius := 0.0
		for i in range(0, vertices.size(), 3):
			if colors[i].r < 0.5: continue # Bark cannot hide an empty canopy interval.
			for j in 3:
				var a := vertices[i + j]
				var b := vertices[i + (j + 1) % 3]
				if absf(b.y - a.y) < 0.00001 or y < minf(a.y, b.y) or y > maxf(a.y, b.y): continue
				var p := a.lerp(b, (y - a.y) / (b.y - a.y))
				radius = maxf(radius, Vector2(p.x, p.z).length())
		if radius < 0.12: return false
	return true
