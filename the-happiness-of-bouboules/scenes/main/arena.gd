extends Node2D

const BasicEnemyScene := preload("res://scenes/enemies/basic_enemy.tscn")

const MIN_ENEMIES := 1
const MAX_ENEMIES := 3
const ROOM_HALF_WIDTH := 400.0
const ROOM_HALF_HEIGHT := 300.0
const SPAWN_MARGIN := 60.0
const MIN_DISTANCE_FROM_PLAYER := 150.0

@onready var player: Node2D = $Player


func _ready() -> void:
	var enemy_count := randi_range(MIN_ENEMIES, MAX_ENEMIES)
	for i in enemy_count:
		_spawn_enemy()


func _spawn_enemy() -> void:
	var enemy := BasicEnemyScene.instantiate()
	add_child(enemy)
	enemy.global_position = _random_spawn_position()


func _random_spawn_position() -> Vector2:
	var pos := Vector2.ZERO
	var attempts := 0
	while attempts < 20:
		pos = Vector2(
			randf_range(-ROOM_HALF_WIDTH + SPAWN_MARGIN, ROOM_HALF_WIDTH - SPAWN_MARGIN),
			randf_range(-ROOM_HALF_HEIGHT + SPAWN_MARGIN, ROOM_HALF_HEIGHT - SPAWN_MARGIN)
		)
		if pos.distance_to(player.global_position) >= MIN_DISTANCE_FROM_PLAYER:
			break
		attempts += 1
	return pos
