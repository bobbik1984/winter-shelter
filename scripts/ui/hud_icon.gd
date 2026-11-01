class_name HudIcon
extends Control

## 天气卡的小线性图标（参考图：太阳 / 温度计 / 风）。纯 _draw，无贴图。

@export_enum("sun", "thermo", "wind") var kind: String = "sun"
@export var color: Color = Color(0.96, 0.78, 0.40)

func _ready() -> void:
	custom_minimum_size = Vector2(22, 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	match kind:
		"sun":
			draw_circle(c, 4.5, color)
			for i in range(8):
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * 6.5, c + d * 9.0, color, 1.6, true)
		"thermo":
			draw_line(c + Vector2(0, -7), c + Vector2(0, 3), color, 3.0, true)
			draw_circle(c + Vector2(0, 5), 3.6, color)
			draw_arc(c + Vector2(0, -7), 1.5, PI, TAU, 8, color, 1.2, true)
		"wind":
			for k in range(3):
				var y := -5.0 + k * 5.0
				var w := 14.0 - absf(k - 1) * 3.0
				draw_line(c + Vector2(-8, y), c + Vector2(-8 + w, y), color, 1.6, true)
				draw_arc(c + Vector2(-8 + w, y - 2.0), 2.0, -PI * 0.5, PI * 0.5, 6, color, 1.4, true)
