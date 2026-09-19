extends Node2D

const BasicEnemyScene := preload("res://scenes/enemies/basic_enemy.tscn")
const DoorScene := preload("res://scenes/environment/door.tscn")
const RockScene := preload("res://scenes/environment/rock.tscn")
const HoleScene := preload("res://scenes/environment/hole.tscn")
const CoinScene := preload("res://scenes/items/coin.tscn")

const MIN_ENEMIES := 1
const MAX_ENEMIES := 3

# Rocks and holes are both solid, static obstacles placed the same way; they
# just avoid each other too, so they never spawn overlapping.
const MIN_ROCKS := 1
const MAX_ROCKS := 3
const MIN_HOLES := 1
const MAX_HOLES := 2
const OBSTACLE_MIN_DISTANCE_FROM_PLAYER := 80.0
const OBSTACLE_MIN_DISTANCE_BETWEEN := 60.0

const ENTRY_BUFFER := 56.0

const TILE_SIZE := 32
const ROOM_WIDTH_TILES := 15
const ROOM_HEIGHT_TILES := 7

const SPAWN_MARGIN := 60.0
const MIN_DISTANCE_FROM_PLAYER := 150.0

const FLOOR_SOURCE_ID := 0
const WALL_SOURCE_ID := 1
const WALL_CORNER_SOURCE_ID := 2
# Floor tile with a shadow along one edge (for the row/column that runs
# along a wall) and along two adjacent edges (for the room's 4 corners).
const FLOOR_EDGE_SOURCE_ID := 3
const FLOOR_CORNER_SOURCE_ID := 4
# Same as FLOOR_EDGE_SOURCE_ID, but with the shadow removed where a door
# opens onto it (there's no wall there anymore once it's open).
const FLOOR_EDGE_DOOR_SOURCE_ID := 5

# TileSetAtlasSource transform flags, combined to rotate/mirror a single tile
# onto each side of the room instead of drawing 4 separate sprites.
const FLIP_H := 4096
const FLIP_V := 8192
const TRANSPOSE := 16384

@onready var camera: Camera2D = $Camera2D
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var walls_layer: TileMapLayer = $WallsLayer
@onready var walls_body: StaticBody2D = $Walls
# Y-sorted so the player (and enemies) draw behind or in front of doors
# depending on which is higher on screen - e.g. walking through a door
# tucks the player under its frame instead of always drawing on top.
@onready var y_sort_layer: Node2D = $YSortLayer

signal door_passed(direction: Vector2i)

var obstacle_positions: Array[Vector2] = []
var player: Node2D
var doors: Dictionary = {}  # Vector2i direction -> Door node
# Per-door: the floor cell just inside it (with the wall-shadow tile) and
# the transform that tile uses, so it can be swapped to the no-shadow
# variant once the door opens.
var door_inner_floor_cells := {}
var enemies_alive := 0
var cleared := false

# Seeded per room coordinate so revisiting a room reproduces the exact same
# floor pattern and (while uncleared) the same enemies, instead of the room
# looking "regenerated" every time it's reloaded.
var rng := RandomNumberGenerator.new()

# Center of the room and half-extent of its floor, in Arena-local pixels.
# Computed from the tile grid so an odd tile count still centers correctly.
var room_center := Vector2.ZERO
var room_half_size := Vector2.ZERO


# Called by Main right after instancing this room. player_ref is the single,
# persistent Player instance that moves from room to room; entry_direction
# says which door it should appear next to (Vector2i.ZERO for the start room).
func configure(coord: Vector2i, door_directions: Array, is_cleared: bool, player_ref: Node2D, entry_direction: Vector2i, coin_positions: Array = []) -> void:
	player = player_ref
	cleared = is_cleared
	rng.seed = coord.x * 92821 + coord.y * 68917

	if player.is_inside_tree():
		player.reparent(self, false)
	else:
		add_child(player)

	var origin := _build_room()
	_position_room(origin)
	_spawn_doors(origin, door_directions)
	_build_wall_colliders(origin, door_directions)
	_place_player(entry_direction)
	_spawn_rocks()
	_spawn_holes()

	for coin_position in coin_positions:
		_spawn_coin(coin_position)

	if cleared:
		_open_doors()
	else:
		var enemy_count := rng.randi_range(MIN_ENEMIES, MAX_ENEMIES)
		enemies_alive = enemy_count
		for i in enemy_count:
			_spawn_enemy()


func _build_room() -> Vector2i:
	var origin := Vector2i(-ROOM_WIDTH_TILES / 2, -ROOM_HEIGHT_TILES / 2)

	for y in ROOM_HEIGHT_TILES:
		for x in ROOM_WIDTH_TILES:
			_place_floor_tile(origin, x, y)

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


func _place_floor_tile(origin: Vector2i, x: int, y: int) -> void:
	# The default artwork for both shadowed tiles has its dark edge(s) on
	# the top (and, for the double one, also the left); flip/rotate it to
	# whichever wall(s) this cell actually touches.
	var at_top := y == 0
	var at_bottom := y == ROOM_HEIGHT_TILES - 1
	var at_left := x == 0
	var at_right := x == ROOM_WIDTH_TILES - 1

	var cell := origin + Vector2i(x, y)
	var source_id := FLOOR_SOURCE_ID
	var transform := _random_floor_transform()

	if at_top and at_left:
		source_id = FLOOR_CORNER_SOURCE_ID
		transform = 0
	elif at_top and at_right:
		source_id = FLOOR_CORNER_SOURCE_ID
		transform = FLIP_H
	elif at_bottom and at_left:
		source_id = FLOOR_CORNER_SOURCE_ID
		transform = FLIP_V
	elif at_bottom and at_right:
		source_id = FLOOR_CORNER_SOURCE_ID
		transform = FLIP_H | FLIP_V
	elif at_top:
		source_id = FLOOR_EDGE_SOURCE_ID
		transform = 0
	elif at_bottom:
		source_id = FLOOR_EDGE_SOURCE_ID
		transform = FLIP_V
	elif at_left:
		source_id = FLOOR_EDGE_SOURCE_ID
		transform = TRANSPOSE
	elif at_right:
		source_id = FLOOR_EDGE_SOURCE_ID
		transform = TRANSPOSE | FLIP_H

	floor_layer.set_cell(cell, source_id, Vector2i.ZERO, transform)


func _random_floor_transform() -> int:
	# The floor tile has no "up" direction, so any of the 8 flip/rotation
	# combinations looks fine; this just breaks up the visible repetition.
	var transform := 0
	if rng.randf() < 0.5:
		transform |= FLIP_H
	if rng.randf() < 0.5:
		transform |= FLIP_V
	if rng.randf() < 0.5:
		transform |= TRANSPOSE
	return transform


func _position_room(origin: Vector2i) -> void:
	room_center = Vector2(
		(origin.x + ROOM_WIDTH_TILES / 2.0) * TILE_SIZE,
		(origin.y + ROOM_HEIGHT_TILES / 2.0) * TILE_SIZE
	)
	room_half_size = Vector2(ROOM_WIDTH_TILES, ROOM_HEIGHT_TILES) * TILE_SIZE / 2.0

	camera.position = room_center


func _place_player(entry_direction: Vector2i) -> void:
	var pos := room_center
	if entry_direction == Vector2i(0, -1):
		pos += Vector2(0.0, -room_half_size.y + ENTRY_BUFFER)
	elif entry_direction == Vector2i(0, 1):
		pos += Vector2(0.0, room_half_size.y - ENTRY_BUFFER)
	elif entry_direction == Vector2i(-1, 0):
		pos += Vector2(-room_half_size.x + ENTRY_BUFFER, 0.0)
	elif entry_direction == Vector2i(1, 0):
		pos += Vector2(room_half_size.x - ENTRY_BUFFER, 0.0)
	else:
		pos += Vector2(0.0, room_half_size.y * 0.5)
	player.position = pos
	player.door_cooldown_left = player.DOOR_COOLDOWN


func _build_wall_colliders(origin: Vector2i, door_directions: Array) -> void:
	var half_x := room_half_size.x
	var half_y := room_half_size.y
	var half_tile := TILE_SIZE / 2.0
	var configs := _door_configs(origin)

	# World-space center of each door slot, if that side has one, so the
	# wall collider on that side can leave a gap there instead of sealing it.
	var door_centers := {}
	for direction in door_directions:
		var cell: Vector2i = configs[direction]["cell"]
		door_centers[direction] = Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE)

	# The player's own collision box is small (just around the feet) compared
	# to its sprite, so hitting the wall right at the tile boundary still lets
	# the (taller) sprite visually poke into the wall above it. Push the wall
	# colliders this much further into the room - an invisible buffer - so
	# the player stops before that can happen. Doesn't affect door widths,
	# since only the solid segments grow, not the gap.
	var wall_margin := 14.0
	var thickness := TILE_SIZE + wall_margin
	var inward := wall_margin / 2.0

	# Top/bottom colliders span the full outer width (including corners);
	# left/right only span the inner height between them. Same layout as
	# the wall tiles themselves, just as plain rectangles.
	_add_horizontal_wall(room_center.y - half_y - half_tile + inward, half_x, thickness, door_centers.get(Vector2i(0, -1)))
	_add_horizontal_wall(room_center.y + half_y + half_tile - inward, half_x, thickness, door_centers.get(Vector2i(0, 1)))
	_add_vertical_wall(room_center.x - half_x - half_tile + inward, half_y, thickness, door_centers.get(Vector2i(-1, 0)))
	_add_vertical_wall(room_center.x + half_x + half_tile - inward, half_y, thickness, door_centers.get(Vector2i(1, 0)))


func _add_horizontal_wall(y: float, half_x: float, thickness: float, door_center) -> void:
	var full_half_width := half_x + TILE_SIZE
	if door_center == null:
		_add_wall_collider(Vector2(room_center.x, y), Vector2(full_half_width * 2.0, thickness))
		return

	var gap_half := TILE_SIZE / 2.0
	var left_edge := room_center.x - full_half_width
	var right_edge := room_center.x + full_half_width
	var left_width: float = door_center.x - gap_half - left_edge
	var right_width: float = right_edge - (door_center.x + gap_half)
	_add_wall_collider(Vector2(left_edge + left_width / 2.0, y), Vector2(left_width, thickness))
	_add_wall_collider(Vector2(right_edge - right_width / 2.0, y), Vector2(right_width, thickness))


func _add_vertical_wall(x: float, half_y: float, thickness: float, door_center) -> void:
	if door_center == null:
		_add_wall_collider(Vector2(x, room_center.y), Vector2(thickness, half_y * 2.0))
		return

	var gap_half := TILE_SIZE / 2.0
	var top_edge := room_center.y - half_y
	var bottom_edge := room_center.y + half_y
	var top_height: float = door_center.y - gap_half - top_edge
	var bottom_height: float = bottom_edge - (door_center.y + gap_half)
	_add_wall_collider(Vector2(x, top_edge + top_height / 2.0), Vector2(thickness, top_height))
	_add_wall_collider(Vector2(x, bottom_edge - bottom_height / 2.0), Vector2(thickness, bottom_height))


func _add_wall_collider(local_position: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = local_position
	walls_body.add_child(collision)


func _door_configs(origin: Vector2i) -> Dictionary:
	# One slot at the middle of each side; matches where a straight wall
	# tile would otherwise sit, so the door drops in place of it. Top/right
	# use rotation 0/PI-2; bottom/left face the opposite way and need the
	# mirrored rotation instead of reusing top/right's.
	# "inner_cell"/"inner_transform": the floor cell just inside the door,
	# and the transform _place_floor_tile used for its shadow there (see the
	# elif chain there) - must match so the no-shadow door variant lines up
	# with the rest of the floor once the door opens.
	return {
		Vector2i(0, -1): {
			"cell": origin + Vector2i(ROOM_WIDTH_TILES / 2, -1), "rotation": 0.0,
			"inner_cell": origin + Vector2i(ROOM_WIDTH_TILES / 2, 0), "inner_transform": 0,
		},
		Vector2i(0, 1): {
			"cell": origin + Vector2i(ROOM_WIDTH_TILES / 2, ROOM_HEIGHT_TILES), "rotation": PI,
			"inner_cell": origin + Vector2i(ROOM_WIDTH_TILES / 2, ROOM_HEIGHT_TILES - 1), "inner_transform": FLIP_V,
		},
		Vector2i(-1, 0): {
			"cell": origin + Vector2i(-1, ROOM_HEIGHT_TILES / 2), "rotation": -PI / 2.0,
			"inner_cell": origin + Vector2i(0, ROOM_HEIGHT_TILES / 2), "inner_transform": TRANSPOSE,
		},
		Vector2i(1, 0): {
			"cell": origin + Vector2i(ROOM_WIDTH_TILES, ROOM_HEIGHT_TILES / 2), "rotation": PI / 2.0,
			"inner_cell": origin + Vector2i(ROOM_WIDTH_TILES - 1, ROOM_HEIGHT_TILES / 2), "inner_transform": TRANSPOSE | FLIP_H,
		},
	}


func _spawn_doors(origin: Vector2i, door_directions: Array) -> void:
	var configs := _door_configs(origin)
	for direction in door_directions:
		var config: Dictionary = configs[direction]
		_spawn_door(direction, config["cell"], config["rotation"], config["inner_cell"], config["inner_transform"])


func _spawn_door(direction: Vector2i, cell: Vector2i, door_rotation: float, inner_cell: Vector2i, inner_transform: int) -> void:
	# The door cell sits in the wall ring, past the floor's edge, so it has
	# no floor tile under it by default; add one so there's ground to walk
	# on (visible once the door opens) instead of the bare background. The
	# straight wall tile placed there by _build_room() is still on top of
	# it in the walls layer, so clear that too, or it's what shows through.
	floor_layer.set_cell(cell, FLOOR_SOURCE_ID, Vector2i.ZERO, _random_floor_transform())
	walls_layer.erase_cell(cell)

	var door: Node2D = DoorScene.instantiate()
	y_sort_layer.add_child(door)
	door.position = Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE)
	door.rotation = door_rotation
	door.direction = direction
	door.player_passed.connect(_on_door_passed)
	doors[direction] = door
	door_inner_floor_cells[door] = {"cell": inner_cell, "transform": inner_transform}


func _on_door_passed(direction: Vector2i) -> void:
	door_passed.emit(direction)


func _spawn_rocks() -> void:
	var rock_count := rng.randi_range(MIN_ROCKS, MAX_ROCKS)
	for i in rock_count:
		var pos := _random_room_position(OBSTACLE_MIN_DISTANCE_FROM_PLAYER)
		obstacle_positions.append(pos)
		var rock := RockScene.instantiate()
		y_sort_layer.add_child(rock)
		rock.global_position = pos


func _spawn_holes() -> void:
	var hole_count := rng.randi_range(MIN_HOLES, MAX_HOLES)
	for i in hole_count:
		var pos := _random_room_position(OBSTACLE_MIN_DISTANCE_FROM_PLAYER)
		obstacle_positions.append(pos)
		var hole := HoleScene.instantiate()
		y_sort_layer.add_child(hole)
		hole.global_position = pos


func _spawn_enemy() -> void:
	var enemy := BasicEnemyScene.instantiate()
	y_sort_layer.add_child(enemy)
	enemy.global_position = _random_room_position(MIN_DISTANCE_FROM_PLAYER)
	enemy.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	enemies_alive -= 1
	if enemies_alive <= 0:
		cleared = true
		_open_doors()


func _spawn_coin(position: Vector2) -> void:
	var coin: Node2D = CoinScene.instantiate()
	add_child(coin)
	coin.position = position


# Read by Main before this room is torn down, so any coins the player left
# behind can be respawned at the same spot next time this room is loaded.
func get_coin_positions() -> Array:
	var positions := []
	for child in get_children():
		if child.is_in_group("coins"):
			positions.append(child.position)
	return positions


func _open_doors() -> void:
	for door in doors.values():
		if not is_instance_valid(door):
			continue
		door.open()
		var info: Dictionary = door_inner_floor_cells.get(door, {})
		if info.is_empty():
			continue
		floor_layer.set_cell(info["cell"], FLOOR_EDGE_DOOR_SOURCE_ID, Vector2i.ZERO, info["transform"])


func _random_room_position(min_distance_from_player: float) -> Vector2:
	var pos := room_center
	var attempts := 0
	while attempts < 20:
		pos = room_center + Vector2(
			rng.randf_range(-room_half_size.x + SPAWN_MARGIN, room_half_size.x - SPAWN_MARGIN),
			rng.randf_range(-room_half_size.y + SPAWN_MARGIN, room_half_size.y - SPAWN_MARGIN)
		)
		var far_from_player := pos.distance_to(player.global_position) >= min_distance_from_player
		var far_from_obstacles := true
		for obstacle_pos in obstacle_positions:
			if pos.distance_to(obstacle_pos) < OBSTACLE_MIN_DISTANCE_BETWEEN:
				far_from_obstacles = false
				break
		if far_from_player and far_from_obstacles:
			break
		attempts += 1
	return pos
