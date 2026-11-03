class_name IsometricCameraRig
extends Node3D

enum ViewMode { ORTHO, TILT_SHIFT }

## 相机沿 rig 本地 +Z 的后移距离（米）。
## [TUNE] 40.0 是当前 blockout 的视感值；后续由 T0.5 / T1.3 迁入 tuning。
@export var camera_distance: float = 40.0
## 正交视口高度（米）。
## [TUNE] 18.0 与 ARCHITECTURE_GODOT.md §3.1 一致；后续由 T0.5 / T1.3 迁入 tuning。
@export var camera_size: float = 18.0
## 俯仰角（度）。-38° 为当前仓库既有值，保持到 T1.3 再定稿。
@export var camera_pitch_degrees: float = -38.0
## 偏航角（度）。135° = 镜头朝西南：1 月午后太阳的真实方位（SunModel），
## 太阳与影子随时间在画面里移动、变长。玩家输入与罗盘都从相机朝向推导。
@export var camera_yaw_degrees: float = 135.0
@export var target: Node3D
@export var follow_speed: float = 6.0

@export_group("Tilt-shift")
## 默认 TILT_SHIFT（2026-11-01 用户拍板：以 north star 的表现力为准）；按 V 切回正交。
## 真移轴：光轴接近水平（树干保持竖直不汇聚），镜头向下平移看地面，天际线留在画面上沿。
@export var view_mode: ViewMode = ViewMode.TILT_SHIFT
## [TUNE] 垂直视场角（度）。
@export var tilt_shift_fov_deg: float = 48.0
## [TUNE] 光轴俯仰（度）：接近 0 = 竖线不汇聚。
@export var tilt_shift_pitch_degrees: float = -21.5
## [TUNE] 镜头下移量（占半高比例，负 = 向下看地面）。
@export var lens_shift: float = -0.38
## [TUNE] 玩家在画面中的高度（自顶向下 0..1）。
@export var player_screen_y: float = 0.58
## [TUNE] 默认相机到玩家的距离（m）；滚轮按比例推拉。
@export var tilt_shift_distance: float = 28.0
@export var default_zoom: float = 1.0
@export var zoom_min: float = 0.45
@export var zoom_max: float = 2.6
@export var zoom_step: float = 1.12
## [TUNE] 移轴景深：焦平面前后的虚化过渡（米）。
@export var dof_transition_m: float = 14.0
@export var dof_amount: float = 0.08

var _zoom: float = -1.0
## D16 建造特写：只覆盖跟随目标与距离；偏航、移轴、太阳都不变，用户的 _zoom 退出后原样恢复。
var _focus_on := false
var _focus_point := Vector3.ZERO
var _focus_zoom := 1.0
var _focus_blend := 0.0
var focus_blend_seconds := 0.6
var focus_fade_radius := 1.3
## 画质档位可关闭景深（GraphicsSettings）。
var dof_enabled: bool = true
## 地形挡视线时的抬升（度）。绕 rig 原点转，所以目标在屏幕上的位置不变（见 BuildSession.view_lift）。
var _lift_deg := 0.0
## 进到庇护所里时当前相机不是这台，天空镜头由 ShelterInterior 推送。
var lens_suspended := false
## 人在庇护所里时的镂空焦点（开口外几米）：挡在相机和它之间的树都淡掉，否则树井里相机就在树冠中。INF = 不用。
var interior_focus := Vector3.INF
var _lift_want := 0.0
var _lift_check_t := 0.0
var lift_max_deg := 30.0
var lift_rise_rate := 4.0
var lift_fall_rate := 1.2
var _attrs: CameraAttributesPractical

@onready var camera_3d: Camera3D = $Camera3D

func _ready() -> void:
	_load_tuning()
	# 固定 ISO 机位角度：Yaw 45°、Pitch -38°（真等距 -35.264° 的视感微调区间）
	rotation_degrees = Vector3(camera_pitch_degrees, camera_yaw_degrees, 0.0)
	add_to_group("camera_rig")
	if _zoom < 0.0:
		_zoom = default_zoom
	if camera_3d:
		camera_3d.near = 0.05
		_apply_view_mode()

## V9：移轴参数唯一来源 = Tuning（@export 值仅作 Tuning 缺失时的回退）。
func _load_tuning() -> void:
	var t := load("res://resources/tuning.tres") as Tuning
	if t == null:
		return
	camera_yaw_degrees = t.tilt_yaw_deg
	tilt_shift_fov_deg = t.tilt_fov_deg
	tilt_shift_pitch_degrees = t.tilt_pitch_deg
	lens_shift = t.tilt_lens_shift
	player_screen_y = t.tilt_player_screen_y
	tilt_shift_distance = t.tilt_distance_m
	zoom_min = t.tilt_zoom_min
	zoom_max = t.tilt_zoom_max
	focus_blend_seconds = t.build_focus_blend_seconds
	focus_fade_radius = t.build_focus_fade_radius
	lift_max_deg = t.tilt_lift_max_deg
	lift_rise_rate = t.tilt_lift_rise_rate
	lift_fall_rate = t.tilt_lift_fall_rate

func _apply_view_mode() -> void:
	rotation_degrees.x = camera_pitch_degrees if view_mode == ViewMode.ORTHO else tilt_shift_pitch_degrees - _lift_deg
	if view_mode == ViewMode.ORTHO:
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera_3d.size = camera_size * lerpf(1.0, _focus_zoom, _smooth_blend())
		camera_3d.frustum_offset = Vector2.ZERO
		# 沿 rig 本地 +Z 后移，让 rig 原点（target 跟随点）落在正交画面中心
		camera_3d.position = Vector3(0.0, 0.0, camera_distance)
		# [GAME] 裁剪面：far 200 覆盖 100 m 地图最远角（最坏约 175 m）
		camera_3d.far = 200.0
		camera_3d.attributes = null
	else:
		var half_t := tan(deg_to_rad(tilt_shift_fov_deg) * 0.5)
		# 画面窗口在 tan 空间是 [(-1+s), (1+s)]·half_t；玩家位于自顶向下 player_screen_y 处
		var top_t := (1.0 + lens_shift) * half_t
		var player_t := top_t - 2.0 * half_t * player_screen_y
		var dep := -atan(player_t)               # 玩家相对光轴的俯角
		var eff := lerpf(_zoom, _focus_zoom, _smooth_blend())
		var dist := tilt_shift_distance * eff
		camera_3d.position = Vector3(0.0, dist * sin(dep), dist * cos(dep))
		camera_3d.projection = Camera3D.PROJECTION_FRUSTUM
		camera_3d.keep_aspect = Camera3D.KEEP_HEIGHT
		var near := camera_3d.near
		camera_3d.size = 2.0 * near * half_t
		camera_3d.frustum_offset = Vector2(0.0, lens_shift * near * half_t)
		camera_3d.far = 1400.0
		if _attrs == null:
			_attrs = CameraAttributesPractical.new()
		_attrs.dof_blur_far_enabled = dof_enabled
		_attrs.dof_blur_near_enabled = dof_enabled
		_attrs.dof_blur_far_distance = dist + dof_transition_m * eff * 2.0
		_attrs.dof_blur_far_transition = dof_transition_m * eff * 6.0
		_attrs.dof_blur_near_distance = maxf(0.5, dist - dof_transition_m * eff)
		_attrs.dof_blur_near_transition = dof_transition_m * eff
		_attrs.dof_blur_amount = dof_amount
		camera_3d.attributes = _attrs

func _smooth_blend() -> float:
	return smoothstep(0.0, 1.0, _focus_blend)

## D16：以 world 为目标拉近；zoom = 特写距离 / 默认距离。
func set_focus(world: Vector3, zoom: float) -> void:
	_focus_on = true
	_focus_point = world
	_focus_zoom = zoom

## 手机默认距离（玩家没有滚轮可以自己调）。
func set_default_zoom(z: float) -> void:
	_zoom = clampf(z, zoom_min, zoom_max)
	if camera_3d:
		_apply_view_mode()

func clear_focus() -> void:
	_focus_on = false

func is_focusing() -> bool:
	return _focus_on

## 当前特写的取景点与距离比例（测试 / 截图检查用）。
func focus_zoom() -> float:
	return _focus_zoom

## 按这个距离比例，相机相对取景点的世界坐标偏移（移轴模式）。正交相机在远处、不会撞树，返回零向量。
func camera_offset(zoom: float) -> Vector3:
	if view_mode == ViewMode.ORTHO:
		return Vector3.ZERO
	var half_t := tan(deg_to_rad(tilt_shift_fov_deg) * 0.5)
	var top_t := (1.0 + lens_shift) * half_t
	# 机位相对玩家的总俯角 = 镜头下移的角度 + rig 俯仰
	var dep := -atan(top_t - 2.0 * half_t * player_screen_y) - deg_to_rad(tilt_shift_pitch_degrees)
	var dist := tilt_shift_distance * zoom
	return Basis(Vector3.UP, deg_to_rad(camera_yaw_degrees)) * Vector3(0.0, dist * sin(dep), dist * cos(dep))

## 当前地形抬升角（测试 / 截图检查用）。
func lift_degrees() -> float:
	return _lift_deg

## 地形挡住视线时抬高机位（远景和特写都适用）。正交机位本来就高，不需要。
func _update_lift(goal: Vector3, delta: float) -> void:
	if view_mode != ViewMode.TILT_SHIFT:
		_lift_deg = 0.0
		_lift_want = 0.0
		return
	_lift_check_t -= delta
	if _lift_check_t <= 0.0:
		_lift_check_t = 0.1   # 每秒查 10 次足够；视线没被挡时只采样十几个高度
		var half_t := tan(deg_to_rad(tilt_shift_fov_deg) * 0.5)
		var dep := -atan((1.0 + lens_shift) * half_t - 2.0 * half_t * player_screen_y) - deg_to_rad(tilt_shift_pitch_degrees)
		var dist := tilt_shift_distance * lerpf(_zoom, _focus_zoom, _smooth_blend())
		var ground := Vector3(goal.x, SnowField.height_at(goal.x, goal.z), goal.z)
		_lift_want = BuildSession.view_lift(ground, dist, dep, Basis(Vector3.UP, deg_to_rad(camera_yaw_degrees)),
			SnowField.height_at, lift_max_deg)
	if absf(_lift_deg - _lift_want) > 0.01:
		var rate := lift_rise_rate if _lift_want > _lift_deg else lift_fall_rate
		_lift_deg = lerpf(_lift_deg, _lift_want, minf(rate * delta, 1.0))
		rotation_degrees.x = tilt_shift_pitch_degrees - _lift_deg

## 把真实镜头参数推给天空 shader（Godot 天空背景不认 frustum_offset）。
func _push_lens() -> void:
	if camera_3d == null or not is_inside_tree() or lens_suspended:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var aspect := vp_size.x / maxf(vp_size.y, 1.0)
	var half_t := tan(deg_to_rad(tilt_shift_fov_deg) * 0.5)
	get_tree().call_group("lens_receivers", "set_lens", view_mode == ViewMode.TILT_SHIFT,
		half_t, aspect, lens_shift * half_t, camera_3d.global_transform.basis.orthonormalized())

func reapply() -> void:
	if camera_3d:
		_apply_view_mode()

func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	if camera_3d:
		_apply_view_mode()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		set_view_mode(ViewMode.TILT_SHIFT if view_mode == ViewMode.ORTHO else ViewMode.ORTHO)
	elif event is InputEventMouseButton and event.pressed and view_mode == ViewMode.TILT_SHIFT and not _focus_on:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom / zoom_step, zoom_min, zoom_max)
			_apply_view_mode()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * zoom_step, zoom_min, zoom_max)
			_apply_view_mode()

func _process(delta: float) -> void:
	var want_blend := 1.0 if _focus_on else 0.0
	if _focus_blend != want_blend:
		_focus_blend = move_toward(_focus_blend, want_blend, delta / maxf(focus_blend_seconds, 0.01))
		_apply_view_mode()
		# 只在过渡时推送：0.26 / 0.85 是 snow_cover 的默认镂空（平时只挡玩家身边）
		var k := _smooth_blend()
		get_tree().call_group("occlusion_fade", "set_focus_fade", lerpf(0.26, focus_fade_radius, k), lerpf(0.85, 1.0, k))
	var goal: Vector3 = _focus_point if _focus_on else (target.global_position if is_instance_valid(target) else global_position)
	global_position = global_position.lerp(goal, minf(follow_speed * delta, 1.0))
	_update_lift(goal, delta)
	# 基向量只随模式变；每帧推送开销很小，也顺带处理窗口缩放后的宽高比
	_push_lens()
	# 挡住"主体"的树镂空：平时主体是玩家，特写时是工地
	get_tree().call_group("occlusion_fade", "set_focus", interior_focus if interior_focus != Vector3.INF else goal)
