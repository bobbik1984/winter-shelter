class_name AmbientAudio
extends AudioStreamPlayer

## 程序化音频灰盒（T3.8 / T1.5 风声部分）：不依赖任何音频资源，一个 AudioStreamGenerator 合成：
##   风：布朗噪声 + 低通。暴露越高越响、越"亮"；躲到挡风物后 / 进庇护所变闷（低通下移）。阵风按 WindData.gust_frequency。
##   脚步：移动时按步频触发短促"咯吱"噪声包；雪越深越低沉。
##   火：靠近燃烧的营火时随机噼啪声 + 低频呼呼声。
## GameDirector 每帧写入 exposure / shelter_level / fire / speed / snow_depth。
## 网页版（2026-11-07）：风声改由浏览器播放两段预先烤好的循环（tools/bake_wind_loops.py，同一算法），
## 按截止频率交叉淡化、按帧调音量和阵风。网页版单线程，主线程一卡生成器就断音（用户报"风声一断一断"）。
## 循环由页面里的 web/wind_loops.html（window.wsWind）用浏览器自己的音频线程无缝播放；Godot 4.3 网页版的"采样"
## 播放是在主线程上收到 ended 再重新开始，一卡照样断（实测停过 2.6 秒），所以不用它。
## 本地版加 -- --wind-loops 用普通播放器试听同样的循环。脚步、火、一次性音效仍走生成器（短促，偶尔断一下听不出来）。

## 风声循环：截止频率（与烤制时一致）。
const LOOP_CUTS := [2000.0, 150.0]
const LOOP_FILES := ["res://assets/audio/wind_open.wav", "res://assets/audio/wind_muffled.wav"]
## 测试用：本地版也用循环（命令行 -- --wind-loops）。
static var force_loops := false

const RATE := 22050.0

var exposure: float = 1.0       # 0 背风 .. 1 完全迎风
var shelter_level: int = 0      # 0 露天 / 1 / 2
var fire: float = 0.0           # 0..1
var speed: float = 0.0          # m/s
var snow_depth: float = 0.5
var wind_strength: float = 0.9  # 风速归一化
var gust_frequency: float = 0.5
var master: float = 1.0

var _pb: AudioStreamGeneratorPlayback
var _brown := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _gust := 0.6
var _gust_target := 0.6
var _gust_t := 0.0
var _step_t := 0.0
var _step_env := 0.0
var _step_lp := 0.0
var _crack_env := 0.0
var _rumble := 0.0
var _cut := 1200.0
var _vol := 0.2
## 一次性音效（合成）：kind -> [包络, 衰减, 音高 Hz, 噪声比例]
var _sfx: Array = []
var _phase := 0.0
## 网页版的风声循环播放器（空 = 逐采样合成）。
var _loops: Array[AudioStreamPlayer] = []
## 网页版：循环在页面里（window.wsWind）播放。
var _js_wind := false
var _js_t := 0.0

func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	stream = gen
	# 网页版默认"采样"播放，生成器流不支持，会没声音（控制台也会警告）
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	volume_db = -6.0
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback
	if OS.has_feature("web"):
		_js_wind = str(JavaScriptBridge.eval("typeof window.wsWind")) == "object"
	elif force_loops or "--wind-loops" in OS.get_cmdline_user_args():
		_setup_loops()

func _setup_loops() -> void:
	for f in LOOP_FILES:
		var w := (load(f) as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2   # 16 位单声道
		var p := AudioStreamPlayer.new()
		p.stream = w
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		p.volume_db = -80.0
		p.bus = bus
		add_child(p)
		p.play(randf() * 4.0)
		_loops.append(p)

## 用了循环吗（测试 / 调试看）。
func uses_loops() -> bool:
	return _js_wind or not _loops.is_empty()

## 交叉淡化：当前截止频率在两段循环之间的位置（对数），0 = 全是迎风段，1 = 全是闷声段。
static func loop_mix(cut: float) -> float:
	return clampf((log(LOOP_CUTS[0]) - log(maxf(cut, 1.0))) / (log(LOOP_CUTS[0]) - log(LOOP_CUTS[1])), 0.0, 1.0)

func _update_loops(delta: float) -> void:
	# 阵风包络：逐采样版本每个采样走 0.00004，这里按经过的采样数换算成每帧
	_gust += (_gust_target - _gust) * (1.0 - pow(1.0 - 0.00004, RATE * delta))
	var amp := minf(_vol * _gust * 2.2, 2.0)   # 逐采样版本最后会削到 ±1；循环版不削波，只封个顶
	var m := loop_mix(_cut)
	# 等功率交叉淡化（两段噪声不相关）
	var gains := [amp * cos(m * PI * 0.5), amp * sin(m * PI * 0.5)]
	if _js_wind:
		# 页面里的循环不经过 Godot 的混音器：自己乘上本播放器音量和主总线音量 / 静音；每 0.1 秒发一次（浏览器那边平滑过渡）
		_js_t -= delta
		if _js_t > 0.0:
			return
		_js_t = 0.1
		var k := 0.0 if AudioServer.is_bus_mute(0) else db_to_linear(volume_db + AudioServer.get_bus_volume_db(0))
		JavaScriptBridge.eval("window.wsWind.set(%.4f,%.4f)" % [float(gains[0]) * k, float(gains[1]) * k])
		return
	for i in _loops.size():
		_loops[i].volume_db = volume_db + linear_to_db(maxf(float(gains[i]), 0.0001))

## 一次性音效：probe（金属"叮"）/ chop（木头闷响）/ gather（沙沙）/ dig（铲雪嚓嚓）/ fire（点火噼啪）。
func play_sfx(kind: String) -> void:
	match kind:
		"probe": _sfx.append([0.9, 0.9993, 2300.0, 0.15])
		"chop": _sfx.append([1.0, 0.9975, 140.0, 0.75])
		"gather": _sfx.append([0.6, 0.9990, 0.0, 1.0])
		"dig": _sfx.append([1.0, 0.9985, 0.0, 1.0])
		"fire": _sfx.append([1.0, 0.9995, 90.0, 0.8])

func _process(delta: float) -> void:
	if _pb == null:
		return
	# 目标参数（平滑过渡，避免咔哒声）
	var muffle: float = [1.0, 0.35, 0.18][clampi(shelter_level, 0, 2)]
	var target_cut := lerpf(350.0, 2600.0, exposure) * muffle
	var target_vol := (0.10 + 0.55 * exposure) * wind_strength * (1.0 if shelter_level == 0 else 0.45)
	_cut = lerpf(_cut, target_cut, clampf(delta * 2.0, 0.0, 1.0))
	_vol = lerpf(_vol, target_vol * master, clampf(delta * 2.0, 0.0, 1.0))
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = randf_range(0.8, 2.5) / maxf(gust_frequency, 0.05)
		_gust_target = randf_range(0.45, 1.25)
	if uses_loops():
		_update_loops(delta)
	_fill()

func _fill() -> void:
	var n := _pb.get_frames_available()
	var a := 1.0 - exp(-TAU * _cut / RATE)
	var step_interval := 0.0
	if speed > 0.3:
		step_interval = 0.95 / clampf(speed, 0.8, 4.0) * 1.1
	var step_cut := lerpf(1800.0, 600.0, clampf(snow_depth / 2.0, 0.0, 1.0))
	var sa := 1.0 - exp(-TAU * step_cut / RATE)
	var synth_wind := not uses_loops()
	for i in range(n):
		var s := 0.0
		if synth_wind:
			# 风：布朗噪声 → 两级低通 → 阵风包络
			_brown = clampf(_brown * 0.998 + randf_range(-1.0, 1.0) * 0.06, -1.0, 1.0)
			var white := randf_range(-1.0, 1.0)
			_lp += a * ((white * 0.35 + _brown) - _lp)
			_lp2 += a * (_lp - _lp2)
			_gust += (_gust_target - _gust) * 0.00004
			s = _lp2 * _vol * _gust * 2.2
		# 脚步咯吱
		if step_interval > 0.0:
			_step_t += 1.0 / RATE
			if _step_t >= step_interval:
				_step_t = 0.0
				_step_env = 1.0
		if _step_env > 0.001:
			_step_lp += sa * (randf_range(-1.0, 1.0) - _step_lp)
			s += _step_lp * _step_env * 0.55 * master
			_step_env *= 0.9992
		# 火：噼啪 + 低频
		if fire > 0.02:
			if randf() < fire * 9.0 / RATE:
				_crack_env = randf_range(0.4, 1.0)
			if _crack_env > 0.001:
				s += randf_range(-1.0, 1.0) * _crack_env * 0.35 * master
				_crack_env *= 0.985
			_rumble += 0.004 * (randf_range(-1.0, 1.0) - _rumble)
			s += _rumble * fire * 1.8 * master
		# 一次性音效
		if not _sfx.is_empty():
			_phase += 1.0 / RATE
			var i_sfx := 0
			while i_sfx < _sfx.size():
				var fx: Array = _sfx[i_sfx]
				var env: float = fx[0]
				var tone := sin(TAU * float(fx[2]) * _phase) if float(fx[2]) > 0.0 else 0.0
				s += (tone * (1.0 - float(fx[3])) + randf_range(-1.0, 1.0) * float(fx[3])) * env * 0.45 * master
				fx[0] = env * float(fx[1])
				if float(fx[0]) < 0.002:
					_sfx.remove_at(i_sfx)
				else:
					i_sfx += 1
		s = clampf(s, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))
