extends Node2D

const WIDTH := 32.0

@onready var fill: ColorRect = $Fill


func set_health(current: int, max_health: int) -> void:
	var fraction := clampf(float(current) / float(max_health), 0.0, 1.0)
	fill.offset_right = fill.offset_left + WIDTH * fraction
