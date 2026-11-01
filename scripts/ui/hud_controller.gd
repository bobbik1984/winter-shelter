class_name HUDController
extends Control

@onready var time_label: Label = $TopRightCard/VBox/TimeLabel
@onready var sunset_label: Label = $TopRightCard/VBox/SunsetLabel
@onready var temp_label: Label = $TopRightCard/VBox/TempLabel
@onready var wind_label: Label = $TopRightCard/VBox/WindLabel
@onready var probe_popup: PanelContainer = $ProbePopup
@onready var probe_text: Label = $ProbePopup/Margin/ProbeText

var popup_timer: float = 0.0
## 日落时刻字符串，由 MainLevel 从 WeatherController.sunset_clock() 注入。
var _sunset_clock: String = "16:18"

func set_sunset_clock(clock: String) -> void:
	_sunset_clock = clock

func _ready() -> void:
	if probe_popup:
		probe_popup.visible = false
	# 参考图的天气卡图标：日落 / 气温 / 风前各加一个小图标（运行时把 Label 包进 HBox）
	_add_icon(sunset_label, "sun", Color(0.96, 0.70, 0.30))
	_add_icon(temp_label, "thermo", Color(0.85, 0.88, 0.95))
	_add_icon(wind_label, "wind", Color(0.62, 0.78, 1.0))

func _add_icon(label: Label, kind: String, color: Color) -> void:
	if label == null:
		return
	var parent := label.get_parent()
	var idx := label.get_index()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	parent.move_child(row, idx)
	var icon := HudIcon.new()
	icon.kind = kind
	icon.color = color
	row.add_child(icon)
	label.reparent(row)

func _process(delta: float) -> void:
	if popup_timer > 0.0:
		popup_timer -= delta
		if popup_timer <= 0.0 and probe_popup:
			probe_popup.visible = false

func update_time(time_str: String, sunset_str: String) -> void:
	if time_label:
		time_label.text = Loc.t("Jan 14  ") + time_str
	if sunset_label:
		if sunset_str == "0h 00m":
			sunset_label.text = Loc.t("Sun set at %s — dusk") % _sunset_clock
		else:
			sunset_label.text = Loc.t("Sunset %s (%s left)") % [_sunset_clock, sunset_str]

func update_weather(temp: float, wind_str: String) -> void:
	if temp_label:
		temp_label.text = "%d°C" % int(temp)
	if wind_label:
		wind_label.text = wind_str

func show_probe_depth(screen_pos: Vector2, depth: float) -> void:
	if probe_popup and probe_text:
		var quality = Loc.t("Good depth") if depth >= 1.5 else Loc.t("Shallow snow")
		probe_text.text = "%s\n↓ %.2fm" % [quality, depth]
		probe_popup.position = screen_pos + Vector2(20, -40)
		probe_popup.visible = true
		popup_timer = 2.5
