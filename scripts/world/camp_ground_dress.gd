class_name CampGroundDress
extends RefCounted
## Static opaque presentation, generated only when construction changes stage.
## Local +Z is the entrance. No resources, terrain, collision or warmth are changed.

static func build(at: Transform3D, door: float, stage: int, snow_shelter: bool,
		config: EnvironmentDetailSettings = null) -> ArrayMesh:
	if config == null: config = EnvironmentDetails.settings()
	if config == null or not config.enabled or not config.camp_enabled or stage < 2: return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples := {}
	# A narrow trampled approach; its irregular outer ring returns to clean snow.
	_patch(st, at, Vector2(0, door + 0.9), Vector2(clampf(config.camp_entry_width_m, 0.3, 1.2),
		clampf(config.camp_entry_length_m, 0.6, 2.5)), 0.0, config, samples, true, 17)
	if snow_shelter:
		# Excavation is deposited in two unequal side heaps, never across the doorway.
		var count := clampi(config.camp_mound_count, 0, 12)
		for i in count:
			var side := -1.0 if i % 2 == 0 else 1.0
			var f := float(i / 2) / maxf(1.0, float(count / 2))
			var jitter := TerrainHeight.hash2(i, roundi(at.origin.x * 10), 857)
			var q := Vector2(side * (1.05 + jitter * 0.7), door + 0.2 + f * 1.5)
			var height := clampf(config.camp_mound_height_m, 0.02, 0.4) * (0.65 + jitter * 0.35) * clampf(float(stage) / 4.0, 0.5, 1.0)
			_patch(st, at, q, Vector2(0.55 + jitter * 0.25, 0.38 + jitter * 0.24), height, config, samples, false, i + 31)
	if not st.get_meta("triangles", 0): return null
	st.generate_normals()
	return st.commit()

static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.08
	return mat

static func _point(at: Transform3D, q: Vector2, lift: float, samples: Dictionary) -> Vector3:
	if not samples.has(q):
		var w := at * Vector3(q.x, 0, q.y)
		var ok := not TerrainHeight.is_lake_at(w.x, w.z) and TerrainHeight.snow_depth_at(w.x, w.z) >= 0.08
		var p := Vector3(w.x, SnowField.height_at(w.x, w.z), w.z)
		samples[q] = at.affine_inverse() * p if ok else Vector3.INF
	return samples[q] + Vector3.UP * lift

static func _patch(st: SurfaceTool, at: Transform3D, center: Vector2, radius: Vector2,
		height: float, config: EnvironmentDetailSettings, samples: Dictionary, packed: bool, seed_idx: int) -> void:
	# Three radial strips keep the patch on the snow surface instead of bridging slopes.
	var segments := 16
	var rings: Array = []
	for ring in 4:
		var points: Array[Vector3] = []
		var t := float(ring) / 3.0
		for i in segments:
			var angle := -TAU * float(i) / float(segments)
			var jitter := 0.9 + TerrainHeight.hash2(i, seed_idx, 859) * 0.2
			var q := center + Vector2(cos(angle), sin(angle)) * radius * t * jitter
			# Raised center sinks into the surface at the edge; packed approach is a thin veneer.
			var lift := 0.014 if packed else height * pow(1.0 - t, 0.7) - 0.012 * t
			points.append(_point(at, q, lift, samples))
		rings.append(points)
	for ring in 3:
		for i in segments:
			var j := (i + 1) % segments
			var a: Vector3 = rings[ring][i]
			var b: Vector3 = rings[ring + 1][i]
			var c: Vector3 = rings[ring + 1][j]
			var e: Vector3 = rings[ring][j]
			var inner_col := config.snow_color
			var outer_col := config.snow_color
			if packed:
				inner_col = config.snow_color.lerp(config.compacted_snow_color, (1.0 - float(ring) / 3.0) * 0.42)
				outer_col = config.snow_color.lerp(config.compacted_snow_color, (1.0 - float(ring + 1) / 3.0) * 0.42)
			_tri(st, a, b, c, inner_col, outer_col, outer_col)
			if ring > 0: _tri(st, a, c, e, inner_col, outer_col, inner_col)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if not a.is_finite() or not b.is_finite() or not c.is_finite(): return
	if (b - a).cross(c - a).length_squared() < 0.00000001: return
	st.set_meta("triangles", int(st.get_meta("triangles", 0)) + 1)
	# Clockwise from above = Godot front face; radial strips use clockwise winding on XZ.
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cc); st.add_vertex(c)
	st.set_color(cb); st.add_vertex(b)

static func log_mesh() -> ArrayMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.065
	cylinder.bottom_radius = 0.075
	cylinder.height = 0.95
	cylinder.radial_segments = 8
	cylinder.rings = 1
	var arrays := cylinder.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in arrays[Mesh.ARRAY_INDEX]:
		st.set_color(EnvPalette.WOOD_IN if absf(normals[idx].y) > 0.9 else EnvPalette.DEAD_WOOD)
		st.add_vertex(Basis(Vector3.RIGHT, PI * 0.5) * vertices[idx])
	st.generate_normals()
	return st.commit()

static func bough_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Overlapping flattened bough lobes, attached along one continuous stem.
	for i in 6:
		var z := -0.35 + float(i) * 0.12
		var width := 0.25 - float(i) * 0.025
		for side in [-1.0, 1.0]:
			var a := Vector3(0, 0.025, z - 0.13)
			var b := Vector3(width * side, 0, z - 0.08)
			var c := Vector3(0, 0.045, z + 0.22)
			if side < 0: _tri(st, a, b, c, EnvPalette.SPRUCE, EnvPalette.SPRUCE, EnvPalette.SPRUCE_IN)
			else: _tri(st, a, c, b, EnvPalette.SPRUCE, EnvPalette.SPRUCE_IN, EnvPalette.SPRUCE)
	st.generate_normals()
	return st.commit()

## Visual placement only: the game's deposit / spending radius remains site-based.
static func pile_position(origin: Vector3, side: Vector3, entrance: Vector3,
		trees: PackedVector2Array, rocks: Array[Vector3]) -> Vector3:
	# Model layout proportions in meters, not an interaction or collision radius.
	var best := origin + side * 3.2 + entrance * 2.8
	var best_score := -INF
	for offset in [Vector2(3.2, 2.8), Vector2(-3.2, 2.8), Vector2(3.8, 1.8),
		Vector2(-3.8, 1.8), Vector2(2.8, 3.6), Vector2(-2.8, 3.6)]:
		var at: Vector3 = origin + side * offset.x + entrance * offset.y
		if TerrainHeight.is_lake_at(at.x, at.z): continue
		var q := Vector2(at.x, at.z)
		var clearance := 3.0
		for tree in trees: clearance = minf(clearance, q.distance_to(tree) - 1.8)
		for rock in rocks: clearance = minf(clearance, q.distance_to(Vector2(rock.x, rock.y)) - rock.z - 0.7)
		if clearance > best_score:
			best_score = clearance
			best = at
		if clearance >= 0.5: return at
	return best
