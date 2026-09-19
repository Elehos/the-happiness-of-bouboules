extends CharacterBody2D

const SPEED := 90.0
const MAX_HEALTH := 3
const COIN_DROP_CHANCE := 0.5

const CoinScene := preload("res://scenes/items/coin.tscn")

signal died

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
		_drop_loot()
		died.emit()
		queue_free()
		return
	health_bar.set_health(health, MAX_HEALTH)


func _drop_loot() -> void:
	if randf() < COIN_DROP_CHANCE:
		var coin: Node2D = CoinScene.instantiate()
		get_parent().add_child(coin)
		coin.global_position = global_position
