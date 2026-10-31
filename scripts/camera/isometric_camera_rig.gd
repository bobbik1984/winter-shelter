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
## 偏航角（度）。45° 为工程红线固定值。
@export var camera_yaw_degrees: float = 45.0
@export var target: Node3D
@export var follow_speed: float = 6.0

@export_group("Tilt-shift (experimental)")
## 默认 ORTHO（AGENTS.md §4.1 红线）；TILT_SHIFT 是可选实验模式，运行时按 V 切换。
@export var view_mode: ViewMode = ViewMode.ORTHO
## [TUNE] 移轴透视的垂直视场角（度）。
@export var tilt_shift_fov_deg: float = 40.0
## [TUNE] 移轴模式的俯仰角（度）：更浅，天际线才会进入画面顶部（正交模式仍用 camera_pitch_degrees）。
@export var tilt_shift_pitch_degrees: float = -27.0
## [TUNE] 镜头上移量，占近平面半高的比例：不改俯仰就能把天际线推进画面顶部。
@export var lens_shift: float = 0.5
## [TUNE] 滚轮缩放范围（相对 1.0 = 默认距离）：小 = 近景建造，大 = 远景侦察。
@export var zoom_min: float = 0.45
@export var zoom_max: float = 2.4
@export var zoom_step: float = 1.12
## [TUNE] 移轴景深：焦平面上下的虚化过渡（米）。
@export var dof_transition_m: float = 18.0
@export var dof_amount: float = 0.10

var _zoom: float = 1.0
var _attrs: CameraAttributesPractical

@onready var camera_3d: Camera3D = $Camera3D

func _ready() -> void:
	# 固定 ISO 机位角度：Yaw 45°、Pitch -38°（真等距 -35.264° 的视感微调区间）
	rotation_degrees = Vector3(camera_pitch_degrees, camera_yaw_degrees, 0.0)
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
		var fov := deg_to_rad(tilt_shift_fov_deg)
		# 在焦平面（rig 原点）处的取景高度与正交 camera_size 相同
		var dist := (camera_size * 0.5) / tan(fov * 0.5) * _zoom
		camera_3d.position = Vector3(0.0, 0.0, dist)
		camera_3d.projection = Camera3D.PROJECTION_FRUSTUM
		var near := camera_3d.near
		camera_3d.keep_aspect = Camera3D.KEEP_HEIGHT
		camera_3d.size = 2.0 * near * tan(fov * 0.5)
		camera_3d.frustum_offset = Vector2(0.0, lens_shift * near * tan(fov * 0.5))
		camera_3d.far = 1400.0
		if _attrs == null:
			_attrs = CameraAttributesPractical.new()
		_attrs.dof_blur_far_enabled = true
		_attrs.dof_blur_near_enabled = true
		_attrs.dof_blur_far_distance = dist + dof_transition_m * _zoom
		_attrs.dof_blur_far_transition = dof_transition_m * _zoom * 3.0
		_attrs.dof_blur_near_distance = maxf(0.5, dist - dof_transition_m * _zoom)
		_attrs.dof_blur_near_transition = dof_transition_m * _zoom
		_attrs.dof_blur_amount = dof_amount
		camera_3d.attributes = _attrs

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
