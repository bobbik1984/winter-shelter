class_name InteractionController
extends Node

## 选中玩家附近最近的 Interactable，按住交互键推进，完成后回调（T2.1）。
## 淡橙高亮圈画在被选中物体脚下（参考图 6 号元素）。

signal completed(target: Interactable, result: Dictionary)

var player: Node3D
var tuning: Tuning
var enabled: bool = true
var current: Interactable
## D16：建造特写时锁定工地，不靠距离（移动已锁定，不能要求玩家正好站在圈里）。
var forced: Interactable
var progress: float = 0.0   # 0..1

var _ring: MeshInstance3D

func _ready() -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.62, 0.20, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.15)
	_ring.material_override = m
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

func _process(delta: float) -> void:
	if player == null or not enabled:
		_set_current(null)
		return
	_set_current(forced if is_instance_valid(forced) and forced.current_prompt() != "" else _find_nearest())
	if current and HoldAssist.held("interact"):
		progress += delta / maxf(current.hold_seconds, 0.05)
		if progress >= 1.0:
			var target := current
			progress = 0.0
			HoldAssist.release("interact")
			var result := target.trigger()
			completed.emit(target, result)
	else:
		progress = 0.0
		if current == null:
			HoldAssist.release("interact")
	if current:
		var p := current.global_position
		_ring.global_position = Vector3(p.x, SnowField.height_at(p.x, p.z) + 0.06, p.z)
		_ring.scale = Vector3.ONE * current.ring_radius
		var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
		_ring.scale *= pulse if progress == 0.0 else 1.0 - progress * 0.35

func _set_current(it: Interactable) -> void:
	if it != current:
		progress = 0.0
	current = it
	# 特写时不画高亮圈，免得压住工地；火有自己的取暖光圈，再画一个小圈只会让人以为那是范围
	_ring.visible = it != null and forced == null and it.kind != "fire"

func _find_nearest() -> Interactable:
	var best: Interactable = null
	var best_d := INF
	var default_reach := tuning.interact_radius_m if tuning else 2.4
	var pp := player.global_position
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not it.is_inside_tree() or it.current_prompt() == "":
			continue
		var d := Vector2(it.global_position.x - pp.x, it.global_position.z - pp.z).length()
		if d < (it.reach_m if it.reach_m > 0.0 else default_reach) and d < best_d:
			best_d = d
			best = it
	return best

func prompt_text() -> String:
	return current.current_prompt() if current else ""
