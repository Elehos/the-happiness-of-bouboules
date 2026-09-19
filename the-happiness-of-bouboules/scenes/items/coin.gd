extends Area2D

const VALUE := 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("add_gold"):
		body.add_gold(VALUE)
		queue_free()
