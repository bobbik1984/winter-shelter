class_name BuildInfo
extends RefCounted

## 这是哪一次构建（tools/deploy_web.sh 导出前写 build_info.txt）：试玩反馈时能对上代码。

## 网页版固定用兼容渲染器（Godot 4.3 没有直接查询当前渲染器的接口）。
static func is_compat() -> bool:
	return OS.has_feature("web") or String(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")) == "gl_compatibility"

static func line() -> String:
	var txt := FileAccess.get_file_as_string("res://build_info.txt").strip_edges()
	var s := txt if txt != "" else "dev"
	return "build %s  ·  %d FPS  ·  %s" % [s, int(Engine.get_frames_per_second()), "web" if OS.has_feature("web") else "native"]
