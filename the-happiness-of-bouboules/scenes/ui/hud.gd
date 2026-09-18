extends CanvasLayer

@onready var health_label: Label = $MarginContainer/HealthLabel


func set_health(current: int, max_health: int) -> void:
	health_label.text = "HP: %d/%d" % [current, max_health]


func show_game_over() -> void:
	health_label.text = "GAME OVER"
