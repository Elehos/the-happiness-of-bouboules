extends StaticBody2D

const CLOSED_TEXTURE := preload("res://assets/tileset/porte.png")
const OPEN_TEXTURE := preload("res://assets/tileset/porte ouvert.png")

signal player_passed(direction: Vector2i)

var is_open := false
var direction := Vector2i.ZERO
var passed := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var pass_area: Area2D = $PassArea


func _ready() -> void:
	sprite.texture = CLOSED_TEXTURE
	pass_area.body_entered.connect(_on_pass_area_body_entered)


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


func _on_pass_area_body_entered(body: Node) -> void:
	# The room swap that follows (reparenting the player, freeing the old
	# room) mutates the scene tree; doing that from inside this physics
	# callback corrupts the physics step, so defer the signal past it. The
	# reparenting also seems to make the physics server re-report the same
	# overlap several times in one step, so latch after the first pass to
	# avoid queuing several room swaps for a single crossing.
	if passed or not is_open or not body.is_in_group("player"):
		return
	# The player just arrived in this room and is still on their door
	# cooldown: don't consume this door's one-shot latch for what is really
	# still the entry crossing settling down (e.g. every door in a cleared
	# room is open, so walking straight in could otherwise carry them
	# straight out the far side).
	if body.door_cooldown_left > 0.0:
		return
	passed = true
	call_deferred("emit_signal", "player_passed", direction)
