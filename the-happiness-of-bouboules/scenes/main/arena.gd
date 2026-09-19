extends Node2D

const BasicEnemyScene := preload("res://scenes/enemies/basic_enemy.tscn")
const DoorScene := preload("res://scenes/environment/door.tscn")

const MIN_ENEMIES := 1
const MAX_ENEMIES := 3

# Chance for a door to appear at each cardinal point; at least one door is
# always placed so the room is never fully sealed.
const DOOR_CHANCE := 0.5

const TILE_SIZE := 32
const ROOM_WIDTH_TILES := 16
const ROOM_HEIGHT_TILES := 8
const ROOM_HALF_WIDTH := ROOM_WIDTH_TILES * TILE_SIZE / 2.0
const ROOM_HALF_HEIGHT := ROOM_HEIGHT_TILES * TILE_SIZE / 2.0

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
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var walls_layer: TileMapLayer = $WallsLayer

var doors: Array[Node] = []
var enemies_alive := 0


func _ready() -> void:
	var origin := _build_room()
	_spawn_doors(origin)

	var enemy_count := randi_range(MIN_ENEMIES, MAX_ENEMIES)
	enemies_alive = enemy_count
	for i in enemy_count:
		_spawn_enemy()


func _build_room() -> Vector2i:
	var origin := Vector2i(-ROOM_WIDTH_TILES / 2, -ROOM_HEIGHT_TILES / 2)

	for y in ROOM_HEIGHT_TILES:
		for x in ROOM_WIDTH_TILES:
			floor_layer.set_cell(origin + Vector2i(x, y), FLOOR_SOURCE_ID, Vector2i.ZERO)

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


func _spawn_doors(origin: Vector2i) -> void:
	# One slot at the middle of each side; matches where a straight wall
	# tile would otherwise sit, so the door drops in place of it.
	var cells := [
		origin + Vector2i(ROOM_WIDTH_TILES / 2, -1),                # top
		origin + Vector2i(ROOM_WIDTH_TILES / 2, ROOM_HEIGHT_TILES), # bottom
		origin + Vector2i(-1, ROOM_HEIGHT_TILES / 2),               # left
		origin + Vector2i(ROOM_WIDTH_TILES, ROOM_HEIGHT_TILES / 2), # right
	]
	var rotations := [0.0, 0.0, PI / 2.0, PI / 2.0]

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
