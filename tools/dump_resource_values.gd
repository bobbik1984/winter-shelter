extends SceneTree
## 把资源里实际读到的值逐行写出来，给 deploy_web.sh 比较"源码"和"导出包"。
## Godot 导出时把 .tres 转成二进制并缓存在 .godot/exported；.tres 本身没变时会继续用旧的转换结果，
## 里面的脚本默认值停留在旧版本（2026-11-04：tilt_pitch_deg 因此在线上一直是 0）。
## 用法：godot --headless ... -s tools/dump_resource_values.gd -- <输出文件> <资源路径列表文件>

const SKIP := ["script", "resource_path", "resource_local_to_scene", "resource_name"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := FileAccess.open(args[0], FileAccess.WRITE)
	for path in FileAccess.get_file_as_string(args[1]).split("\n", false):
		var res: Resource = load(path)
		if res == null:
			out.store_line("%s MISSING" % path)
			continue
		for prop in res.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE == 0 or prop.name in SKIP:
				continue
			out.store_line("%s %s=%s" % [path, prop.name, var_to_str(res.get(prop.name)).replace("\n", " ")])
	out.close()
	quit()
