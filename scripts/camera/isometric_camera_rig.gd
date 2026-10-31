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
## 偏航角（度）。-45°：从迎风脊线一侧俯看背风坡与远处山谷 / 落日（north star 构图）。
## 玩家输入与罗盘都从相机朝向推导，改这里不需要改别处。
@export var camera_yaw_degrees: float = -45.0
@export var target: Node3D
@export var follow_speed: float = 6.0

@export_group("Tilt-shift")
## 默认 TILT_SHIFT（2026-11-01 用户拍板：以 north star 的表现力为准）；按 V 切回正交。
## 真移轴：光轴接近水平（树干保持竖直不汇聚），镜头向下平移看地面，天际线留在画面上沿。
@export var view_mode: ViewMode = ViewMode.TILT_SHIFT
## [TUNE] 垂直视场角（度）。
@export var tilt_shift_fov_deg: float = 48.0
## [TUNE] 光轴俯仰（度）：接近 0 = 竖线不汇聚。
@export var tilt_shift_pitch_degrees: float = 0.0
## [TUNE] 镜头下移量（占半高比例，负 = 向下看地面）。
@export var lens_shift: float = -0.52
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
var _attrs: CameraAttributesPractical

@onready var camera_3d: Camera3D = $Camera3D

func _ready() -> void:
	# 固定 ISO 机位角度：Yaw 45°、Pitch -38°（真等距 -35.264° 的视感微调区间）
	rotation_degrees = Vector3(camera_pitch_degrees, camera_yaw_degrees, 0.0)
	if _zoom < 0.0:
		_zoom = default_zoom
	if camera_3d:
		camera_3d.near = 0.05
		_apply_view_mode()

func _apply_view_mode() -> void:
	rotation_degrees.x = camera_pitch_degrees if view_mode == ViewMode.ORTHO else tilt_shift_pitch_degrees
	if view_mode == ViewMode.ORTHO:
		camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera_3d.size = camera_size
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
		var dist := tilt_shift_distance * _zoom
		camera_3d.position = Vector3(0.0, dist * sin(dep), dist * cos(dep))
		camera_3d.projection = Camera3D.PROJECTION_FRUSTUM
		camera_3d.keep_aspect = Camera3D.KEEP_HEIGHT
		var near := camera_3d.near
		camera_3d.size = 2.0 * near * half_t
		camera_3d.frustum_offset = Vector2(0.0, lens_shift * near * half_t)
		camera_3d.far = 1400.0
		if _attrs == null:
			_attrs = CameraAttributesPractical.new()
		_attrs.dof_blur_far_enabled = true
		_attrs.dof_blur_near_enabled = true
		_attrs.dof_blur_far_distance = dist + dof_transition_m * _zoom * 2.0
		_attrs.dof_blur_far_transition = dof_transition_m * _zoom * 6.0
		_attrs.dof_blur_near_distance = maxf(0.5, dist - dof_transition_m * _zoom)
		_attrs.dof_blur_near_transition = dof_transition_m * _zoom
		_attrs.dof_blur_amount = dof_amount
		camera_3d.attributes = _attrs

## 把真实镜头参数推给天空 shader（Godot 天空背景不认 frustum_offset）。
func _push_lens() -> void:
	if camera_3d == null or not is_inside_tree():
		return
	var vp_size := get_viewport().get_visible_rect().size
	var aspect := vp_size.x / maxf(vp_size.y, 1.0)
	var half_t := tan(deg_to_rad(tilt_shift_fov_deg) * 0.5)
	get_tree().call_group("lens_receivers", "set_lens", view_mode == ViewMode.TILT_SHIFT,
		half_t, aspect, lens_shift * half_t, camera_3d.global_transform.basis.orthonormalized())

func set_view_mode(mode: ViewMode) -> void:
	view_mode = mode
	if camera_3d:
		_apply_view_mode()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		set_view_mode(ViewMode.TILT_SHIFT if view_mode == ViewMode.ORTHO else ViewMode.ORTHO)
	elif event is InputEventMouseButton and event.pressed and view_mode == ViewMode.TILT_SHIFT:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom / zoom_step, zoom_min, zoom_max)
			_apply_view_mode()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * zoom_step, zoom_min, zoom_max)
			_apply_view_mode()

func _process(delta: float) -> void:
	if is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, follow_speed * delta)
	# 基向量只随模式变；每帧推送开销很小，也顺带处理窗口缩放后的宽高比
	_push_lens()
