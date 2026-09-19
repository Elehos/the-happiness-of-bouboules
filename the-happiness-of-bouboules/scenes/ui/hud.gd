extends CanvasLayer

@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel
@onready var gold_label: Label = $MarginContainer/VBoxContainer/GoldLabel


func set_health(current: int, max_health: int) -> void:
	health_label.text = "HP: %d/%d" % [current, max_health]


func set_gold(amount: int) -> void:
	gold_label.text = "Or: %d" % amount


func show_game_over() -> void:
	health_label.text = "GAME OVER"
