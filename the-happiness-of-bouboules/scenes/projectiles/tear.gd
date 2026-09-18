extends Area2D

const SPEED := 420.0
const LIFETIME := 1.2
const DAMAGE := 1
const FRAME_COUNT := 3
const FRAME_DURATION := 0.08

var velocity := Vector2.ZERO
var life_left := LIFETIME
var frame_time := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(direction: Vector2) -> void:
	velocity = direction * SPEED
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life_left -= delta
	if life_left <= 0.0:
		queue_free()
		return
	_animate(delta)


func _animate(delta: float) -> void:
	frame_time += delta
	if frame_time >= FRAME_DURATION:
		frame_time -= FRAME_DURATION
		sprite.frame = (sprite.frame + 1) % FRAME_COUNT


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(DAMAGE)
	queue_free()
