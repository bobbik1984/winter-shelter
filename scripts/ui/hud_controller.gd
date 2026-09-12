class_name HUDController
extends Control

@onready var time_label: Label = $TopRightCard/VBox/TimeLabel
@onready var sunset_label: Label = $TopRightCard/VBox/SunsetLabel
@onready var temp_label: Label = $TopRightCard/VBox/TempLabel
@onready var wind_label: Label = $TopRightCard/VBox/WindLabel
@onready var probe_popup: PanelContainer = $ProbePopup
@onready var probe_text: Label = $ProbePopup/Margin/ProbeText

var popup_timer: float = 0.0

func _ready() -> void:
	if probe_popup:
		probe_popup.visible = false

func _process(delta: float) -> void:
	if popup_timer > 0.0:
		popup_timer -= delta
		if popup_timer <= 0.0 and probe_popup:
			probe_popup.visible = false

func update_time(time_str: String, sunset_str: String) -> void:
	if time_label:
		time_label.text = "Jan 14  " + time_str
	if sunset_label:
		sunset_label.text = "Sunset 16:18 (" + sunset_str + " left)"

func update_weather(temp: float, wind_str: String) -> void:
	if temp_label:
		temp_label.text = "%d°C" % int(temp)
	if wind_label:
		wind_label.text = wind_str

func show_probe_depth(screen_pos: Vector2, depth: float) -> void:
	if probe_popup and probe_text:
		var quality = "Good depth" if depth >= 1.5 else "Shallow snow"
		probe_text.text = "%s\n↓ %.2fm" % [quality, depth]
		probe_popup.position = screen_pos + Vector2(20, -40)
		probe_popup.visible = true
		popup_timer = 2.5
