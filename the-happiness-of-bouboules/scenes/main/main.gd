extends Node2D

const PlayerScene := preload("res://scenes/player/player.tscn")
const ArenaScene := preload("res://scenes/main/arena.tscn")
const ROOM_COUNT := 6

@onready var room_holder: Node2D = $RoomHolder
@onready var hud: CanvasLayer = $HUD

var player: CharacterBody2D
var floor_layout: Dictionary
var current_coord := Vector2i.ZERO
var current_room: Node2D


func _ready() -> void:
	player = PlayerScene.instantiate()
	player.health_changed.connect(hud.set_health)
	player.gold_changed.connect(hud.set_gold)
	player.died.connect(_on_player_died)
	hud.set_health(player.health, player.MAX_HEALTH)
	hud.set_gold(player.gold)

	floor_layout = FloorGenerator.generate(ROOM_COUNT)
	_load_room(Vector2i.ZERO, Vector2i.ZERO)


func _load_room(coord: Vector2i, entry_direction: Vector2i) -> void:
	var previous_room := current_room
	var room_data: Dictionary = floor_layout[coord]

	var room: Node2D = ArenaScene.instantiate()
	room_holder.add_child(room)
	room.door_passed.connect(_on_door_passed)
	room.configure(coord, room_data["doors"].keys(), room_data["cleared"], player, entry_direction, room_data.get("coins", []))

	current_coord = coord
	current_room = room

	if previous_room:
		previous_room.queue_free()


func _on_door_passed(direction: Vector2i) -> void:
	floor_layout[current_coord]["cleared"] = current_room.cleared
	floor_layout[current_coord]["coins"] = current_room.get_coin_positions()
	_load_room(current_coord + direction, -direction)


func _on_player_died() -> void:
	hud.show_game_over()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		_toggle_fullscreen()


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
