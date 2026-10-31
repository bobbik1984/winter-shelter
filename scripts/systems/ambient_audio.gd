class_name AmbientAudio
extends AudioStreamPlayer

## 程序化音频灰盒（T3.8 / T1.5 风声部分）：不依赖任何音频资源，一个 AudioStreamGenerator 合成：
##   风：布朗噪声 + 低通。暴露越高越响、越"亮"；躲到挡风物后 / 进庇护所变闷（低通下移）。阵风按 WindData.gust_frequency。
##   脚步：移动时按步频触发短促"咯吱"噪声包；雪越深越低沉。
##   火：靠近燃烧的营火时随机噼啪声 + 低频呼呼声。
## GameDirector 每帧写入 exposure / shelter_level / fire / speed / snow_depth。

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

func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	stream = gen
	volume_db = -6.0
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback

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
	_fill()

func _fill() -> void:
	var n := _pb.get_frames_available()
	var a := 1.0 - exp(-TAU * _cut / RATE)
	var step_interval := 0.0
	if speed > 0.3:
		step_interval = 0.95 / clampf(speed, 0.8, 4.0) * 1.1
	var step_cut := lerpf(1800.0, 600.0, clampf(snow_depth / 2.0, 0.0, 1.0))
	var sa := 1.0 - exp(-TAU * step_cut / RATE)
	for i in range(n):
		# 风：布朗噪声 → 两级低通 → 阵风包络
		_brown = clampf(_brown * 0.998 + randf_range(-1.0, 1.0) * 0.06, -1.0, 1.0)
		var white := randf_range(-1.0, 1.0)
		_lp += a * ((white * 0.35 + _brown) - _lp)
		_lp2 += a * (_lp - _lp2)
		_gust += (_gust_target - _gust) * 0.00004
		var s := _lp2 * _vol * _gust * 2.2
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
		s = clampf(s, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))
