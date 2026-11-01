extends SceneTree

## T0.3-prep 截图工具：加载主场景 → 等待渲染提交 → 保存根视口 PNG → 退出。
## 必须以窗口模式运行（headless 无法渲染，脚本会显式报错退出）：
##   godot --path . -s res://tools/capture_snapshot.gd -- --out=snapshots/m0_smoke.png
##   godot --path . -s res://tools/capture_snapshot.gd -- --out snapshots/m0_smoke.png
## 未提供 --out 时，默认写到 res://snapshots/capture_<时间戳>.png。

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const DEFAULT_OUTPUT_DIR := "snapshots"
## 等待帧数：至少 8 帧，让材质 / 光照 / 相机跟随在首帧后稳定下来。
const WARMUP_FRAMES := 8


func _initialize() -> void:
	LevelState.auto_begin = false  # 截图用固定基准（山谷 7、不旋转），便于前后对比
	# _run_capture() 是协程：它自己 await 渲染帧，成功或失败都会 quit()。
	_run_capture()


func _run_capture() -> void:
	# headless 没有渲染设备，get_image() 拿不到真实画面，必须显式拒绝，不能假装成功。
	if DisplayServer.get_name() == "headless":
		printerr("[capture_snapshot] ERROR: headless 模式无法渲染截图。请用窗口模式运行：godot --path . -s res://tools/capture_snapshot.gd -- --out=<path>")
		quit(1)
		return

	var output_path := _resolve_output_path(OS.get_cmdline_user_args())
	if output_path.is_empty():
		quit(1)
		return

	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		printerr("[capture_snapshot] ERROR: 无法加载主场景 %s" % MAIN_SCENE_PATH)
		quit(1)
		return

	var main_instance := packed_scene.instantiate()
	if main_instance == null:
		printerr("[capture_snapshot] ERROR: 无法实例化主场景 %s" % MAIN_SCENE_PATH)
		quit(1)
		return
	get_root().add_child(main_instance)

	# 先跑若干空闲帧，再等一次 frame_post_draw，确保该帧已经提交到渲染目标。
	for _frame in WARMUP_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw

	var viewport_texture := get_root().get_texture()
	var image: Image = viewport_texture.get_image() if viewport_texture else null
	if image == null:
		printerr("[capture_snapshot] ERROR: 取图失败，根视口没有可用图像（渲染后端未就绪？）")
		quit(1)
		return

	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir)
		if mkdir_err != OK:
			printerr("[capture_snapshot] ERROR: 无法创建输出目录 %s（错误码 %d）" % [output_dir, mkdir_err])
			quit(1)
			return

	var save_err := image.save_png(output_path)
	if save_err != OK:
		printerr("[capture_snapshot] ERROR: 保存 PNG 失败 %s（错误码 %d）" % [output_path, save_err])
		quit(1)
		return

	print("[capture_snapshot] saved: %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	quit(0)


## 从 `--` 之后的用户参数里解析 --out=<path> 或 --out <path>。
## 相对路径按项目根解析为绝对路径；绝对路径原样使用。
func _resolve_output_path(user_args: PackedStringArray) -> String:
	var raw_path := ""
	var index := 0
	while index < user_args.size():
		var arg := user_args[index]
		if arg.begins_with("--out="):
			raw_path = arg.substr("--out=".length())
		elif arg == "--out":
			if index + 1 >= user_args.size():
				printerr("[capture_snapshot] ERROR: --out 后面缺少路径参数")
				return ""
			index += 1
			raw_path = user_args[index]
		index += 1

	if raw_path.is_empty():
		var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
		raw_path = "%s/capture_%s.png" % [DEFAULT_OUTPUT_DIR, timestamp]

	if raw_path.is_absolute_path():
		return raw_path
	if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
		return ProjectSettings.globalize_path(raw_path)
	return ProjectSettings.globalize_path("res://" + raw_path)
