extends SceneTree
## 2026-11-14 真人截图回归；真实窗口、触屏布局，自动生成洞内/入睡/夜醒证据。
var d
func _initialize() -> void:
	LevelState.auto_begin = false
	SessionLog.disabled = true
	TouchMode.enabled = true
	Loc.lang = "en"
	_run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://snapshots/review_20261114_" + label + ".png")
	print("SHOT ", label)
func _run() -> void:
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	await frames(45)
	d = m.get_node("GameDirector")
	d.start_game()
	await frames(10)
	var p: Vector3 = d.player.global_position
	var site := ShelterSite.new()
	site.setup("BasicCave", Vector3(0, 0, 1), 1.8, 0.0, false)
	site.position = p
	m.add_child(site)
	d.site = site
	for i in 5: site.advance()
	d._enter_shelter()
	await frames(80)
	await shot("inside")
	var card = d.ui._shelter_card
	assert(card == null or not card.visible, "洞内工地卡必须隐藏")
	assert(not d.ui._objective.get_parent().get_parent().visible, "洞内目标与背包必须隐藏")
	d._sleep(false)
	d.ui.set_fade(1.0)
	d.ui.show_vignette(d._vignette_texture(), "Snow shelter · air vent, insulated bedding, no indoor fire", 1.0)
	await frames(2)
	await shot("sleep")
	assert(card == null or not card.visible, "入睡卡片必须隐藏")
	d._begin_night()
	d.night.wake_now()
	d._show_night_event("self")
	await frames(4)
	await shot("wake")
	print("FPS ", Engine.get_frames_per_second(), " GPU ms ", RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	print("RESULT PASS")
	quit()
