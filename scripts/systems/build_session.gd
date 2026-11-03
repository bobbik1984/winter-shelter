class_name BuildSession
extends RefCounted

## D16 / B1–B3 建造特写的状态与判定（纯逻辑，CORE_GAMEPLAY §12、ARCHITECTURE §3.10）。
## PLACING 仍由 BuildMode 负责；工地创建后：FOCUSED ⇄ PAUSED → COMPLETE → IDLE。
## PAUSED = 退回远景、工地保留，不是取消。

enum State { IDLE, FOCUSED, PAUSED, COMPLETE }

var state: State = State.IDLE

## 镜头是否在特写（含完工后的短暂停留）。
func focused() -> bool:
	return state == State.FOCUSED or state == State.COMPLETE

## 进入 / 回到特写（已完工的工地不再进入）。
func begin(site_complete: bool = false) -> bool:
	if site_complete or state == State.COMPLETE:
		return false
	state = State.FOCUSED
	return true

## B / Esc：退回远景。工地与进度不动。
func step_back() -> bool:
	if state != State.FOCUSED:
		return false
	state = State.PAUSED
	return true

func complete() -> void:
	state = State.COMPLETE

func reset() -> void:
	state = State.IDLE

## [B] 在有 / 没有工地时的含义（§12.3：同一时间只有一个未完工工地，再按 B 是"返回 / 继续"，不是新建）。
## 返回 "place" 新建 / "resume" 回到特写 / "far" 太远，先走回去 / "done" 已完工。
static func b_key_action(has_site: bool, site_complete: bool, near: bool) -> String:
	if not has_site:
		return "place"
	if site_complete:
		return "done"
	return "resume" if near else "far"

## 角色是否真的挡住工地：屏幕矩形相交，且角色比工地中心更靠近镜头（站在工地后面的人挡不住它）。
static func blocks_site(character: Rect2, site_rect: Rect2, character_depth: float, site_depth: float) -> bool:
	return character.intersects(site_rect) and character_depth < site_depth + 0.3

## 机位的视线是否穿地形（树不用躲：特写时镜头与工地之间的树由 occlusion_fade 完全镂空）。
## height_fn(x, z) -> 地面高度。
static func view_clear(cam: Vector3, aim: Vector3, height_fn: Callable) -> bool:
	for i in range(0, 9):
		var q := cam.lerp(aim, float(i) / 9.0)
		if float(height_fn.call(q.x, q.z)) + 0.4 > q.y:
			return false
	return true

## 机位要抬高多少度（绕目标抬升，距离不变）才能越过地形看到目标；0 = 不用抬。
## 推近解决不了"脚下的坡比视线还陡"，抬高可以（2026-11-03 全部章节实测：最多 21° 就能全图可见）。
## ground：目标脚下；base_rad：平时的俯角；yaw：相机偏航（基）；放不下时返回 max_deg。
static func view_lift(ground: Vector3, dist: float, base_rad: float, yaw: Basis, height_fn: Callable,
		max_deg: float, step_deg: float = 3.0) -> float:
	var aim := ground + Vector3.UP * 0.9
	var lift := 0.0
	while lift < max_deg:
		var a := base_rad + deg_to_rad(lift)
		var cam := ground + yaw * Vector3(0.0, dist * sin(a), dist * cos(a))
		if _ray_above_ground(cam, aim, height_fn):
			return lift
		lift += step_deg
	return max_deg

static func _ray_above_ground(cam: Vector3, aim: Vector3, height_fn: Callable) -> bool:
	for i in range(0, 16):
		var q := cam.lerp(aim, float(i) / 16.0)
		if float(height_fn.call(q.x, q.z)) + 0.2 > q.y:
			return false
	return true

## 按顺序试的距离比例：先理想距离，再交替推近 / 拉远。
static func zoom_candidates(want: float, min_ratio: float, max_ratio: float, steps: int = 3) -> PackedFloat32Array:
	var out := PackedFloat32Array([want])
	for i in range(1, steps + 1):
		var k := float(i) / float(steps)
		out.append(want * lerpf(1.0, max_ratio, k))
		out.append(want * lerpf(1.0, min_ratio, k))
	return out
