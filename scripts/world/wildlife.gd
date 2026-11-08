class_name Wildlife
extends Node3D

## 小动物（2026-11-09 用户建议）：雪兔和乌鸦。玩家走近，兔子竖耳、僵住、然后蹦着跑开；乌鸦扑棱棱飞走，
## 一只飞全群飞。纯视觉：不影响任何规则、没有碰撞、不进存档、夜里不显示。
## 数量很少（几只），每只只有几个网格；只在 Wildlife 自己的 _process 里动，没有物理。
## 位置按哈希（同一张地图每次一样），飞走的鸟隔一阵在远处重新落下，跑远的兔子就留在新的地方。

@export var rabbit_count: int = 5
@export var bird_count: int = 5
## 惊动距离 = base + 玩家速度 × per_speed（走路约 10 m，跑 / 贴近更远；蹲着不动几乎不惊）。
@export var rabbit_alert_m: float = 6.5
@export var bird_alert_m: float = 8.0
@export var alert_per_speed: float = 1.2
@export var map_limit_m: float = 44.0
## 视觉放大（从斜上方的镜头看，真实大小的兔子只有几个像素）。
@export var rabbit_scale: float = 0.85
@export var bird_scale: float = 1.9

var player: Node3D

var _rabbits: Array = []
var _birds: Array = []
var _mat: StandardMaterial3D
var _t := 0.0

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 1.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rmesh := _rabbit_mesh()
	var bmesh := _bird_body_mesh()
	var wmesh := _wing_mesh()
	var start := _player_xz()
	for i in rabbit_count:
		var n := _node(rmesh, rabbit_scale)
		var p := _spot(i, 3, start, 14.0, 40.0)
		n.position = _ground(p)
		add_child(n)
		_rabbits.append({"n": n, "state": "idle", "t": randf_range(1.0, 4.0), "dir": Vector3.FORWARD, "phase": 0.0, "seed": i})
	for i in bird_count:
		var n := _node(bmesh, bird_scale)
		var wl := _node(wmesh, 1.0)
		var wr := _node(wmesh, 1.0)
		wr.scale = Vector3(-1, 1, 1)
		n.add_child(wl)
		n.add_child(wr)
		wl.position = Vector3(0.05, 0.14, 0.0)
		wr.position = Vector3(-0.05, 0.14, 0.0)
		var p := _spot(i, 7, start, 12.0, 38.0)
		# 乌鸦成小群：后面几只落在第一只附近
		if i % 3 != 0 and not _birds.is_empty():
			var lead: Node3D = _birds[(i / 3) * 3]["n"]
			p = Vector2(lead.position.x, lead.position.z) + Vector2(TerrainHeight.hash2(i, 5, 211) - 0.5, TerrainHeight.hash2(i, 6, 211) - 0.5) * 5.0
		n.position = _ground(p)
		add_child(n)
		_birds.append({"n": n, "wl": wl, "wr": wr, "state": "idle", "t": randf_range(0.5, 3.0), "dir": Vector3.FORWARD, "age": 0.0, "seed": i})

func _node(mesh: Mesh, s: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.scale = Vector3.ONE * s
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

# ------------------------------------------------------------------ 网格（顶点色，朝 +Z）

func _rabbit_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fur := Color(0.80, 0.76, 0.68)
	var dark := Color(0.12, 0.10, 0.09)
	st.set_color(fur)
	PropMeshes._frustum(st, Vector3(0, 0.15, -0.2), 0.13, Vector3(0, 0.17, 0.02), 0.16, 7)   # 后身
	PropMeshes._frustum(st, Vector3(0, 0.17, 0.02), 0.16, Vector3(0, 0.2, 0.2), 0.1, 7)       # 胸
	PropMeshes._frustum(st, Vector3(0, 0.22, 0.18), 0.085, Vector3(0, 0.22, 0.31), 0.05, 6)  # 头
	PropMeshes._frustum(st, Vector3(0.04, 0.27, 0.19), 0.025, Vector3(0.06, 0.5, 0.15), 0.018, 4)   # 耳
	PropMeshes._frustum(st, Vector3(-0.04, 0.27, 0.19), 0.025, Vector3(-0.06, 0.5, 0.15), 0.018, 4)
	st.set_color(Color(0.95, 0.94, 0.92))
	PropMeshes._frustum(st, Vector3(0, 0.17, -0.3), 0.05, Vector3(0, 0.19, -0.36), 0.04, 5)   # 白尾
	st.set_color(dark)
	PropMeshes._frustum(st, Vector3(0.06, 0.47, 0.155), 0.019, Vector3(0.062, 0.5, 0.15), 0.016, 4)   # 耳尖
	PropMeshes._frustum(st, Vector3(-0.06, 0.47, 0.155), 0.019, Vector3(-0.062, 0.5, 0.15), 0.016, 4)
	PropMeshes._frustum(st, Vector3(0.05, 0.24, 0.27), 0.012, Vector3(0.052, 0.24, 0.285), 0.01, 4)   # 眼
	PropMeshes._frustum(st, Vector3(-0.05, 0.24, 0.27), 0.012, Vector3(-0.052, 0.24, 0.285), 0.01, 4)
	st.generate_normals()
	return st.commit()

func _bird_body_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.07, 0.07, 0.09))
	PropMeshes._frustum(st, Vector3(0, 0.15, -0.14), 0.035, Vector3(0, 0.15, -0.02), 0.075, 6)   # 尾→身
	PropMeshes._frustum(st, Vector3(0, 0.15, -0.02), 0.075, Vector3(0, 0.17, 0.1), 0.06, 6)
	PropMeshes._frustum(st, Vector3(0, 0.19, 0.09), 0.05, Vector3(0, 0.21, 0.14), 0.035, 5)      # 头
	PropMeshes._frustum(st, Vector3(0, 0.0, 0), 0.01, Vector3(0.015, 0.1, 0.0), 0.01, 3)         # 腿
	PropMeshes._frustum(st, Vector3(0, 0.0, 0.03), 0.01, Vector3(-0.015, 0.1, 0.03), 0.01, 3)
	st.set_color(Color(0.4, 0.34, 0.2))
	PropMeshes._frustum(st, Vector3(0, 0.205, 0.14), 0.018, Vector3(0, 0.2, 0.21), 0.004, 4)     # 喙
	st.generate_normals()
	return st.commit()

## 一只翅膀：从肩往外伸（+X），扁平三角面片，双面。
func _wing_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.08, 0.08, 0.1))
	var a := Vector3(0, 0, 0.06)
	var b := Vector3(0, 0, -0.1)
	var c := Vector3(0.34, 0.0, -0.06)
	var d := Vector3(0.3, 0.0, 0.0)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	st.generate_normals()
	return st.commit()

# ------------------------------------------------------------------ 位置

func _player_xz() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z) if player != null else Vector2.ZERO

func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, TerrainHeight.height_at(p.x, p.y), p.y)

## 哈希选点：离玩家 min..max 米、在地图内、不在冰面上。
func _spot(i: int, salt: int, around: Vector2, dmin: float, dmax: float) -> Vector2:
	for k in 24:
		var a := TerrainHeight.hash2(i, k, 191 + salt) * TAU
		var r := lerpf(dmin, dmax, TerrainHeight.hash2(i, k, 197 + salt))
		var p := around + Vector2(cos(a), sin(a)) * r
		if absf(p.x) < map_limit_m and absf(p.y) < map_limit_m and not TerrainHeight.is_lake_at(p.x, p.y):
			return p
	return around + Vector2(dmin, 0.0)

func _clamp_dir(pos: Vector3, dir: Vector3) -> Vector3:
	# 快到地图边缘就往里拐
	var d := dir
	if absf(pos.x) > map_limit_m - 3.0 and signf(d.x) == signf(pos.x):
		d.x = -d.x
	if absf(pos.z) > map_limit_m - 3.0 and signf(d.z) == signf(pos.z):
		d.z = -d.z
	return d.normalized()

# ------------------------------------------------------------------ 每帧

func _process(delta: float) -> void:
	if player == null or not visible:
		return
	_t += delta
	var pp := player.global_position
	var spd := 0.0
	if "current_speed" in player:
		spd = float(player.current_speed)
	for r in _rabbits:
		_tick_rabbit(r, delta, pp, spd)
	for b in _birds:
		_tick_bird(b, delta, pp, spd)

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _tick_rabbit(r: Dictionary, delta: float, pp: Vector3, spd: float) -> void:
	var n: Node3D = r["n"]
	var dist := _flat(n.position, pp)
	var alert := rabbit_alert_m + spd * alert_per_speed
	r["t"] = float(r["t"]) - delta
	match String(r["state"]):
		"idle":
			n.position.y = TerrainHeight.height_at(n.position.x, n.position.z)
			n.rotation.x = 0.0
			# 偶尔小蹦一下 / 转头，不是死站着
			if float(r["t"]) <= 0.0:
				r["t"] = randf_range(2.0, 5.0)
				n.rotation.y += randf_range(-0.8, 0.8)
			if dist < alert * 1.4:
				r["state"] = "alert"
				r["t"] = 0.55
		"alert":
			# 竖耳僵住，朝向玩家
			var to := Vector3(pp.x - n.position.x, 0.0, pp.z - n.position.z).normalized()
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), clampf(delta * 10.0, 0.0, 1.0))
			n.rotation.x = -0.12
			if dist < alert or float(r["t"]) <= 0.0 and dist < alert * 1.4:
				var away := Vector3(n.position.x - pp.x, 0.0, n.position.z - pp.z).normalized().rotated(Vector3.UP, randf_range(-0.6, 0.6))
				r["dir"] = _clamp_dir(n.position, away)
				r["state"] = "flee"
				r["t"] = randf_range(2.0, 3.2)
				r["phase"] = 0.0
			elif dist > alert * 1.8:
				r["state"] = "idle"
				r["t"] = randf_range(1.0, 3.0)
		"flee":
			var dir: Vector3 = _clamp_dir(n.position, r["dir"])
			r["dir"] = dir
			r["phase"] = float(r["phase"]) + delta * 9.5
			var hop := absf(sin(float(r["phase"])))
			var p := n.position + dir * 6.5 * delta * (0.35 + 0.65 * hop)
			if TerrainHeight.is_lake_at(p.x, p.z):
				r["t"] = 0.0
			else:
				n.position.x = p.x
				n.position.z = p.z
			n.position.y = TerrainHeight.height_at(n.position.x, n.position.z) + hop * 0.38
			n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), clampf(delta * 14.0, 0.0, 1.0))
			n.rotation.x = -0.25 * cos(float(r["phase"]))   # 前冲时抬头 / 落地时压低
			if float(r["t"]) <= 0.0:
				r["state"] = "idle"
				r["t"] = randf_range(1.5, 3.0)

func _tick_bird(b: Dictionary, delta: float, pp: Vector3, spd: float) -> void:
	var n: Node3D = b["n"]
	var wl: Node3D = b["wl"]
	var wr: Node3D = b["wr"]
	var dist := _flat(n.position, pp)
	var alert := bird_alert_m + spd * alert_per_speed
	b["t"] = float(b["t"]) - delta
	match String(b["state"]):
		"idle":
			n.visible = true
			# 落地时翅膀收拢：沿着身体往后折（翅膀网格朝 ±X 伸，绕 Y 转 ~83° 就贴在身侧）
			wl.rotation = Vector3(0.0, 1.45, 0.1)
			wr.rotation = Vector3(0.0, -1.45, -0.1)
			n.position.y = TerrainHeight.height_at(n.position.x, n.position.z)
			# 啄地：身体前倾点头
			n.rotation.x = 0.35 * maxf(0.0, sin(_t * 5.0 + float(b["seed"]) * 1.7)) if int(_t * 0.5 + float(b["seed"])) % 3 != 0 else 0.0
			if float(b["t"]) <= 0.0:
				b["t"] = randf_range(1.5, 4.0)
				n.rotation.y += randf_range(-1.2, 1.2)
			if dist < alert:
				_flush(b, pp, 0.0)
				# 一只飞，附近的也跟着飞
				for o in _birds:
					if o != b and String(o["state"]) == "idle" and _flat((o["n"] as Node3D).position, n.position) < 9.0:
						_flush(o, pp, randf_range(0.05, 0.35))
		"flying":
			var delay := float(b.get("delay", 0.0))
			if delay > 0.0:
				b["delay"] = delay - delta
				return
			b["age"] = float(b["age"]) + delta
			var age := float(b["age"])
			var dir: Vector3 = b["dir"]
			var climb := minf(age * 3.2, float(b.get("alt", 6.0)))
			n.position.x += dir.x * 8.0 * delta
			n.position.z += dir.z * 8.0 * delta
			n.position.y = TerrainHeight.height_at(n.position.x, n.position.z) + climb
			n.rotation.y = atan2(dir.x, dir.z)
			n.rotation.x = -0.35
			var flap := sin(age * 24.0) * 0.95
			wl.rotation = Vector3(0.0, 0.0, flap)
			wr.rotation = Vector3(0.0, 0.0, -flap)
			if age > 3.6 or absf(n.position.x) > map_limit_m + 6.0 or absf(n.position.z) > map_limit_m + 6.0:
				b["state"] = "gone"
				b["t"] = randf_range(20.0, 40.0)
				n.visible = false
		"gone":
			if float(b["t"]) <= 0.0:
				var p := _spot(int(b["seed"]) + int(_t) % 50, 13, Vector2(pp.x, pp.z), 22.0, 40.0)
				n.position = _ground(p)
				n.rotation = Vector3.ZERO
				b["state"] = "idle"
				b["t"] = randf_range(1.0, 3.0)
				n.visible = true

func _flush(b: Dictionary, pp: Vector3, delay: float) -> void:
	var n: Node3D = b["n"]
	var away := Vector3(n.position.x - pp.x, 0.0, n.position.z - pp.z).normalized().rotated(Vector3.UP, randf_range(-0.7, 0.7))
	b["dir"] = _clamp_dir(n.position, away)
	b["state"] = "flying"
	b["age"] = 0.0
	b["delay"] = delay
	b["alt"] = randf_range(5.0, 9.0)

## 测试 / 调试：最近的兔子 / 乌鸦（位置，状态）。
func nearest_rabbit(to: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for r in _rabbits:
		var d := _flat((r["n"] as Node3D).position, to)
		if d < bd:
			bd = d
			best = r
	return best

func rabbit_state(r: Dictionary) -> String:
	return String(r.get("state", ""))

func bird_states() -> Array:
	return _birds.map(func(b): return String(b["state"]))

func rabbit_count_alive() -> int:
	return _rabbits.size()
