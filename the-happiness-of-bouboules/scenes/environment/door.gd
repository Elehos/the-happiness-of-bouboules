extends StaticBody2D

const CLOSED_TEXTURE := preload("res://assets/tileset/porte.png")
const OPEN_TEXTURE := preload("res://assets/tileset/porte ouvert.png")

var is_open := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	sprite.texture = CLOSED_TEXTURE


func open() -> void:
	if is_open:
		return
	is_open = true
	sprite.texture = OPEN_TEXTURE
	collision_shape.set_deferred("disabled", true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	sprite.texture = CLOSED_TEXTURE
	collision_shape.set_deferred("disabled", false)
