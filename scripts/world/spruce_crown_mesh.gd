class_name SpruceCrownMesh
extends RefCounted
## Candidate-only variations of the coherent legacy crown. All ring ratios are model geometry.
## One opaque material surface; no leaf cards, textures or extra per-tree processing.
const PROFILES := ["res://resources/tree_candidates/full.tres", "res://resources/tree_candidates/open.tres", "res://resources/tree_candidates/drooping.tres"]

static func build(seed_idx: int, wind: Vector3, profile: SpruceCrownProfile = null, wind_bias: float = 0.38) -> ArrayMesh:
	if profile == null: profile = load(PROFILES[0]) as SpruceCrownProfile
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wd := Vector3(wind.x, 0, wind.z)
	var bias := clampf(wind_bias, 0, 1) if wd.length_squared() > 0.0001 else 0.0
	wd = wd.normalized() if wd.length_squared() > 0.0001 else Vector3.RIGHT
	var tiers := clampi(profile.tiers, 4, 9)
	var segments := clampi(profile.radial_segments, 12, 24)
	segments -= segments % 2
	var lower := maxf(0.7, profile.lower_tier_y)
	var upper := maxf(lower + 1.5, profile.upper_tier_y)
	var lean := wd * clampf(profile.crown_lean, 0, 0.5) * bias
	_trunk(st, upper + maxf(0.5, profile.upper_bough_height), lean)
	for tier in tiers:
		var f := float(tier) / float(tiers - 1)
		var center := Vector3(0, lerpf(lower, upper, f), 0) + lean * f * f
		var radius := lerpf(maxf(0.8, profile.lower_radius), maxf(0.15, profile.upper_radius), f)
		radius *= 1.0 + (TerrainHeight.hash2(seed_idx, tier, 907) - 0.5) * clampf(profile.tier_variation, 0, 0.2)
		var rise := lerpf(maxf(0.8, profile.lower_bough_height), maxf(0.5, profile.upper_bough_height), f)
		var drop := minf(clampf(profile.droop, 0, 0.75) * lerpf(1.0, 0.5, f), lower * 0.8)
		_layer(st, seed_idx, tier, center, radius, rise, drop, segments, wd, bias, clampf(profile.edge_variation, 0, 0.25), clampf(profile.valley_radius_ratio, 0.55, 0.8))
	st.generate_normals()
	return st.commit()

static func _layer(st: SurfaceTool, seed_idx: int, tier: int, center: Vector3, radius: float, rise: float, drop: float, n: int, wd: Vector3, bias: float, variation: float, valley: float) -> void:
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	var phase := TerrainHeight.hash2(seed_idx, tier, 911) * TAU
	st.set_color(Color.WHITE)
	# Shared normals across the connected leaf volume create a continuous frost-to-needle edge.
	st.set_smooth_group(100 + tier)
	for i in n:
		var a := TAU * float(i) / float(n) + phase
		var dir := Vector3(cos(a), 0, sin(a))
		var tip := i % 2 == 0
		var wave := sin(a * 3.0 + phase) * 0.6 + sin(a * 5.0 - phase * 0.7) * 0.4
		var k := (1.0 + variation * wave) * (1.0 + dir.dot(wd) * bias * 0.45)
		var r := radius * k * (1.0 if tip else valley)
		var y := -drop * (0.88 + wave * 0.12) if tip else rise * 0.09
		outer.append(center + dir * r + Vector3.UP * y)
		inner.append(center + dir * r * 0.52 + Vector3.UP * (rise * 0.34 + (0.07 if tip else 0.0)))
	var apex := center + Vector3.UP * rise
	var bottom := center + Vector3.UP * 0.04
	for i in n:
		var j := (i + 1) % n
		_crown_triangle(st, apex, inner[i], inner[j])
		_crown_triangle(st, inner[i], outer[i], outer[j])
		_crown_triangle(st, inner[i], outer[j], inner[j])
		_crown_triangle(st, bottom, outer[j], outer[i])

static func _trunk(st: SurfaceTool, height: float, lean: Vector3) -> void:
	st.set_color(Color.BLACK)
	st.set_smooth_group(1)
	var rings: Array[PackedVector3Array] = []
	for ring in 3:
		var f := float(ring) / 2.0
		var c := Vector3.UP * height * f + lean * f * f
		var r := lerpf(0.17, 0.025, f)
		var points := PackedVector3Array()
		for i in 8:
			var a := TAU * float(i) / 8.0
			points.append(c + Vector3(cos(a), 0, sin(a)) * r)
		rings.append(points)
	for i in 8:
		var j := (i + 1) % 8
		var a := TAU * (float(i) + 0.5) / 8.0
		var outward := Vector3(cos(a), 0, sin(a))
		for ring in 2:
			_triangle(st, rings[ring][i], rings[ring][j], rings[ring + 1][j], outward)
			_triangle(st, rings[ring][i], rings[ring + 1][j], rings[ring + 1][i], outward)
		_triangle(st, Vector3.ZERO, rings[0][j], rings[0][i], Vector3.DOWN)
		_triangle(st, Vector3.UP * height + lean, rings[2][i], rings[2][j], Vector3.UP)

## Godot front faces are clockwise; orient from an explicit outward direction before generating normals.
static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (c - a).cross(b - a).dot(outward) >= 0.0:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	else:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)


## Ring topology already defines clockwise winding. Concave leaf tips may face partly down;
## do not flip individual triangles toward a radial vector, which would open the fringe.
static func _crown_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
