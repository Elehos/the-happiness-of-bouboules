extends CharacterBody2D

const SPEED := 90.0
const MAX_HEALTH := 3

var health := MAX_HEALTH
var target: Node2D

@onready var health_bar: Node2D = $HealthBar


func _ready() -> void:
	target = get_tree().get_first_node_in_group("player")
	health_bar.set_health(health, MAX_HEALTH)


func _physics_process(_delta: float) -> void:
	if target:
		velocity = (target.global_position - global_position).normalized() * SPEED
		move_and_slide()


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()
		return
	health_bar.set_health(health, MAX_HEALTH)
