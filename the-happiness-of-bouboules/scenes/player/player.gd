extends CharacterBody2D

const SPEED := 220.0
const SHOOT_COOLDOWN := 0.25
const INVINCIBILITY_TIME := 0.5
const MAX_HEALTH := 3

const TearScene := preload("res://scenes/projectiles/tear.tscn")

signal health_changed(current: int, max_health: int)
signal died

var health := MAX_HEALTH
var shoot_cooldown_left := 0.0
var invincible_left := 0.0

@onready var hurt_area: Area2D = $HurtArea
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	hurt_area.body_entered.connect(_on_hurt_area_body_entered)


func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_shooting(delta)
	_handle_invincibility(delta)
	_update_facing()


func _update_facing() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse == Vector2.ZERO:
		return
	if absf(to_mouse.y) > absf(to_mouse.x):
		sprite.frame = 2 if to_mouse.y < 0.0 else 0
		sprite.flip_h = false
	else:
		sprite.frame = 1
		sprite.flip_h = to_mouse.x < 0.0


func _handle_movement() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * SPEED
	move_and_slide()


func _handle_shooting(delta: float) -> void:
	if shoot_cooldown_left > 0.0:
		shoot_cooldown_left -= delta

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and shoot_cooldown_left <= 0.0:
		var aim_dir := (get_global_mouse_position() - global_position)
		if aim_dir != Vector2.ZERO:
			_shoot(aim_dir.normalized())
			shoot_cooldown_left = SHOOT_COOLDOWN


func _shoot(direction: Vector2) -> void:
	var tear: Node2D = TearScene.instantiate()
	get_parent().add_child(tear)
	tear.global_position = global_position
	tear.launch(direction)


func _handle_invincibility(delta: float) -> void:
	if invincible_left <= 0.0:
		modulate.a = 1.0
		return
	invincible_left -= delta
	modulate.a = 0.5 if int(invincible_left * 10) % 2 == 0 else 1.0


func _on_hurt_area_body_entered(body: Node) -> void:
	if invincible_left > 0.0:
		return
	if body.is_in_group("enemies"):
		take_damage(1)


func take_damage(amount: int) -> void:
	health -= amount
	invincible_left = INVINCIBILITY_TIME
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0:
		died.emit()
		queue_free()
