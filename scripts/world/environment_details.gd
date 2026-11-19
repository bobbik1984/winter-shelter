class_name EnvironmentDetails
extends RefCounted
## Opaque, unshadowed ground details around existing anchors. No extra gameplay features.
## Mesh vertices follow actual snow height; local slopes and lakes are filtered per vertex.
const SETTINGS_PATH := "res://resources/environment_detail.tres"

static func settings() -> EnvironmentDetailSettings:
	return load(SETTINGS_PATH) as EnvironmentDetailSettings

static func build(parent: Node3D, rocks: Array[Vector3], trees: PackedVector2Array, config: EnvironmentDetailSettings = null) -> void:
	if config == null: config = settings()
	if config == null or not config.enabled: return
	var buckets := {}
	# Shared apron vertices repeat; cache expensive terrain samples for this build only.
	var samples := {"valid": {}, "height": {}}
	for r in rocks:
		if not _valid(Vector2(r.x, r.y), config, samples): continue
		var st := _bucket(buckets, Vector2(r.x, r.y), config)
		_snow_apron(st, Vector2(r.x, r.y), r.z * 0.72, r.z * 1.55, config, samples)
		for i in clampi(config.rock_chips_per_group, 0, 6):
			var a := TerrainHeight.hash2(roundi(r.x * 10), i, 823) * TAU
			var rad := r.z * (1.12 + 0.45 * TerrainHeight.hash2(roundi(r.y * 10), i, 827))
			var q := Vector2(r.x, r.y) + Vector2(cos(a), sin(a)) * rad
			if not _valid(q, config, samples): continue
			# Modest fragments, never confused with harvestable resources or large obstacles.
			_chip(st, q, 0.09 + TerrainHeight.hash2(i, roundi(r.x * 10), 829) * 0.13, config, samples)
	for i in range(0, trees.size(), maxi(1, config.tree_base_stride)):
		var q := trees[i]
		if _valid(q, config, samples): _snow_apron(_bucket(buckets, q, config), q, 0.24, 0.7, config, samples)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.1
	for key in buckets:
		var st: SurfaceTool = buckets[key]
		if not st.has_meta("triangles"): continue
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "GroundDetail_%d_%d" % [key.x, key.y]
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = maxf(8.0, config.view_distance_m)
		mi.extra_cull_margin = 0.5
		mi.add_to_group("environment_detail")
		parent.add_child(mi)

static func _valid(q: Vector2, config: EnvironmentDetailSettings, samples: Dictionary) -> bool:
	if not samples.valid.has(q):
		samples.valid[q] = not TerrainHeight.is_lake_at(q.x, q.y) and TerrainHeight.snow_depth_at(q.x, q.y) >= 0.08 and TerrainHeight.slope_at(q.x, q.y) <= config.max_slope_deg
	return samples.valid[q]

static func _bucket(buckets: Dictionary, q: Vector2, config: EnvironmentDetailSettings) -> SurfaceTool:
	var size := maxf(5.0, config.chunk_size_m)
	var key := Vector2i(floori(q.x / size), floori(q.y / size))
	if not buckets.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		buckets[key] = st
	return buckets[key]

static func _point(q: Vector2, lift: float, samples: Dictionary) -> Vector3:
	if not samples.height.has(q): samples.height[q] = SnowField.height_at(q.x, q.y)
	return Vector3(q.x, float(samples.height[q]) + lift, q.y)

static func _snow_apron(st: SurfaceTool, q: Vector2, inner: float, outer: float, config: EnvironmentDetailSettings, samples: Dictionary) -> void:
	# Irregular bank around the anchor; its broad outer edge sinks into the terrain.
	for i in 12:
		var a := TAU * float(i) / 12.0
		var b := TAU * float(i + 1) / 12.0
		var da := Vector2(cos(a), sin(a))
		var db := Vector2(cos(b), sin(b))
		var ra := outer * (0.9 + 0.18 * TerrainHeight.hash2(roundi(q.x * 10), i, 853))
		var rb := outer * (0.9 + 0.18 * TerrainHeight.hash2(roundi(q.x * 10), (i + 1) % 12, 853))
		var qa := q + da * ra
		var qb := q + db * rb
		if not _valid(qa, config, samples) or not _valid(qb, config, samples): continue
		var ridge := minf(0.24, inner * 0.2) + 0.04 * TerrainHeight.hash2(roundi(q.x * 10), i, 831)
		st.set_color(config.snow_color)
		_tri(st, _point(q + da * inner, ridge, samples), _point(qb, -0.018, samples), _point(qa, -0.018, samples))
		_tri(st, _point(q + da * inner, ridge, samples), _point(q + db * inner, ridge, samples), _point(qb, -0.018, samples))

static func _chip(st: SurfaceTool, q: Vector2, radius: float, config: EnvironmentDetailSettings, samples: Dictionary) -> void:
	var top := _point(q, radius * 0.9, samples)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var b := TAU * float(i + 1) / 5.0
		var p := q + Vector2(cos(a), sin(a)) * radius
		var r := q + Vector2(cos(b), sin(b)) * radius
		if not _valid(p, config, samples) or not _valid(r, config, samples): continue
		st.set_color(config.snow_color if i % 3 == 0 else config.rock_color)
		_tri(st, top, _point(r, -0.015, samples), _point(p, -0.015, samples))

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_meta("triangles", int(st.get_meta("triangles", 0)) + 1)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
