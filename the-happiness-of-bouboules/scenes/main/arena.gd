extends Node2D

const BasicEnemyScene := preload("res://scenes/enemies/basic_enemy.tscn")
const DoorScene := preload("res://scenes/environment/door.tscn")

const MIN_ENEMIES := 1
const MAX_ENEMIES := 3

# Chance for a door to appear at each cardinal point; at least one door is
# always placed so the room is never fully sealed.
const DOOR_CHANCE := 0.5

const TILE_SIZE := 32
const ROOM_WIDTH_TILES := 15
const ROOM_HEIGHT_TILES := 7

const SPAWN_MARGIN := 60.0
const MIN_DISTANCE_FROM_PLAYER := 150.0

const FLOOR_SOURCE_ID := 0
const WALL_SOURCE_ID := 1
const WALL_CORNER_SOURCE_ID := 2

# TileSetAtlasSource transform flags, combined to rotate/mirror a single tile
# onto each side of the room instead of drawing 4 separate sprites.
const FLIP_H := 4096
const FLIP_V := 8192
const TRANSPOSE := 16384

@onready var player: Node2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var walls_layer: TileMapLayer = $WallsLayer
@onready var walls_body: StaticBody2D = $Walls

var doors: Array[Node] = []
var enemies_alive := 0

# Center of the room and half-extent of its floor, in Arena-local pixels.
# Computed from the tile grid so an odd tile count still centers correctly.
var room_center := Vector2.ZERO
var room_half_size := Vector2.ZERO


func _ready() -> void:
	var origin := _build_room()
	_position_room(origin)
	_spawn_doors(origin)

	var enemy_count := randi_range(MIN_ENEMIES, MAX_ENEMIES)
	enemies_alive = enemy_count
	for i in enemy_count:
		_spawn_enemy()


func _build_room() -> Vector2i:
	var origin := Vector2i(-ROOM_WIDTH_TILES / 2, -ROOM_HEIGHT_TILES / 2)

	for y in ROOM_HEIGHT_TILES:
		for x in ROOM_WIDTH_TILES:
			floor_layer.set_cell(origin + Vector2i(x, y), FLOOR_SOURCE_ID, Vector2i.ZERO, _random_floor_transform())

	for x in ROOM_WIDTH_TILES:
		walls_layer.set_cell(origin + Vector2i(x, -1), WALL_SOURCE_ID, Vector2i.ZERO)
		walls_layer.set_cell(origin + Vector2i(x, ROOM_HEIGHT_TILES), WALL_SOURCE_ID, Vector2i.ZERO, FLIP_V)

	for y in ROOM_HEIGHT_TILES:
		walls_layer.set_cell(origin + Vector2i(-1, y), WALL_SOURCE_ID, Vector2i.ZERO, TRANSPOSE | FLIP_V)
		walls_layer.set_cell(origin + Vector2i(ROOM_WIDTH_TILES, y), WALL_SOURCE_ID, Vector2i.ZERO, TRANSPOSE | FLIP_H)

	walls_layer.set_cell(origin + Vector2i(-1, -1), WALL_CORNER_SOURCE_ID, Vector2i.ZERO)
	walls_layer.set_cell(origin + Vector2i(ROOM_WIDTH_TILES, -1), WALL_CORNER_SOURCE_ID, Vector2i.ZERO, FLIP_H)
	walls_layer.set_cell(origin + Vector2i(-1, ROOM_HEIGHT_TILES), WALL_CORNER_SOURCE_ID, Vector2i.ZERO, FLIP_V)
	walls_layer.set_cell(origin + Vector2i(ROOM_WIDTH_TILES, ROOM_HEIGHT_TILES), WALL_CORNER_SOURCE_ID, Vector2i.ZERO, FLIP_H | FLIP_V)

	return origin


func _random_floor_transform() -> int:
	# The floor tile has no "up" direction, so any of the 8 flip/rotation
	# combinations looks fine; this just breaks up the visible repetition.
	var transform := 0
	if randf() < 0.5:
		transform |= FLIP_H
	if randf() < 0.5:
		transform |= FLIP_V
	if randf() < 0.5:
		transform |= TRANSPOSE
	return transform


func _position_room(origin: Vector2i) -> void:
	room_center = Vector2(
		(origin.x + ROOM_WIDTH_TILES / 2.0) * TILE_SIZE,
		(origin.y + ROOM_HEIGHT_TILES / 2.0) * TILE_SIZE
	)
	room_half_size = Vector2(ROOM_WIDTH_TILES, ROOM_HEIGHT_TILES) * TILE_SIZE / 2.0

	camera.position = room_center
	player.position = room_center + Vector2(0.0, room_half_size.y * 0.5)

	_build_wall_colliders()


func _build_wall_colliders() -> void:
	var half_x := room_half_size.x
	var half_y := room_half_size.y
	var half_tile := TILE_SIZE / 2.0

	# Top/bottom colliders span the full outer width (including corners);
	# left/right only span the inner height between them. Same layout as
	# the wall tiles themselves, just as plain rectangles.
	_add_wall_collider(
		room_center + Vector2(0.0, -half_y - half_tile),
		Vector2(half_x * 2.0 + TILE_SIZE * 2.0, TILE_SIZE)
	)
	_add_wall_collider(
		room_center + Vector2(0.0, half_y + half_tile),
		Vector2(half_x * 2.0 + TILE_SIZE * 2.0, TILE_SIZE)
	)
	_add_wall_collider(
		room_center + Vector2(-half_x - half_tile, 0.0),
		Vector2(TILE_SIZE, half_y * 2.0)
	)
	_add_wall_collider(
		room_center + Vector2(half_x + half_tile, 0.0),
		Vector2(TILE_SIZE, half_y * 2.0)
	)


func _add_wall_collider(local_position: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = local_position
	walls_body.add_child(collision)


func _spawn_doors(origin: Vector2i) -> void:
	# One slot at the middle of each side; matches where a straight wall
	# tile would otherwise sit, so the door drops in place of it.
	var cells := [
		origin + Vector2i(ROOM_WIDTH_TILES / 2, -1),                # top
		origin + Vector2i(ROOM_WIDTH_TILES / 2, ROOM_HEIGHT_TILES), # bottom
		origin + Vector2i(-1, ROOM_HEIGHT_TILES / 2),               # left
		origin + Vector2i(ROOM_WIDTH_TILES, ROOM_HEIGHT_TILES / 2), # right
	]
	# Top/right were correct; bottom and left face the opposite way, so they
	# need the mirrored rotation instead of reusing top/right's.
	var rotations := [0.0, PI, -PI / 2.0, PI / 2.0]

	var order := range(cells.size())
	order.shuffle()

	var placed := 0
	for i in order.size():
		var index: int = order[i]
		var is_last_chance := i == order.size() - 1
		if randf() < DOOR_CHANCE or (placed == 0 and is_last_chance):
			_spawn_door(cells[index], rotations[index])
			placed += 1


func _spawn_door(cell: Vector2i, door_rotation: float) -> void:
	var door: Node2D = DoorScene.instantiate()
	add_child(door)
	door.position = Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE)
	door.rotation = door_rotation
	doors.append(door)


func _spawn_enemy() -> void:
	var enemy := BasicEnemyScene.instantiate()
	add_child(enemy)
	enemy.global_position = _random_spawn_position()
	enemy.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	enemies_alive -= 1
	if enemies_alive <= 0:
		_open_doors()


func _open_doors() -> void:
	for door in doors:
		if is_instance_valid(door):
			door.open()


func _random_spawn_position() -> Vector2:
	var pos := room_center
	var attempts := 0
	while attempts < 20:
		pos = room_center + Vector2(
			randf_range(-room_half_size.x + SPAWN_MARGIN, room_half_size.x - SPAWN_MARGIN),
			randf_range(-room_half_size.y + SPAWN_MARGIN, room_half_size.y - SPAWN_MARGIN)
		)
		if pos.distance_to(player.global_position) >= MIN_DISTANCE_FROM_PLAYER:
			break
		attempts += 1
	return pos
