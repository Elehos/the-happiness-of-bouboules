extends Node2D

const BasicEnemyScene := preload("res://scenes/enemies/basic_enemy.tscn")
const DoorScene := preload("res://scenes/environment/door.tscn")
const RockScene := preload("res://scenes/environment/rock.tscn")
const HoleScene := preload("res://scenes/environment/hole.tscn")

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

@onready var player: Node2D = $YSortLayer/Player
@onready var camera: Camera2D = $Camera2D
@onready var floor_layer: TileMapLayer = $FloorLayer
@onready var walls_layer: TileMapLayer = $WallsLayer
@onready var walls_body: StaticBody2D = $Walls
# Y-sorted so the player (and enemies) draw behind or in front of doors
# depending on which is higher on screen - e.g. walking through a door
# tucks the player under its frame instead of always drawing on top.
@onready var y_sort_layer: Node2D = $YSortLayer

var obstacle_positions: Array[Vector2] = []
var doors: Array[Node] = []
# Which of [top, bottom, left, right] got a door; the matching wall
# collider is split in two around a gap there instead of being solid,
# or an open door would still be blocked by the wall behind it.
var door_sides := [false, false, false, false]
# Per-door: the floor cell just inside it (with the wall-shadow tile) and
# the transform that tile uses, so it can be swapped to the no-shadow
# variant once the door opens.
var door_inner_floor_cells := {}
var enemies_alive := 0

# Center of the room and half-extent of its floor, in Arena-local pixels.
# Computed from the tile grid so an odd tile count still centers correctly.
var room_center := Vector2.ZERO
var room_half_size := Vector2.ZERO


func _ready() -> void:
	var origin := _build_room()
	_position_room(origin)
	_spawn_doors(origin)
	_build_wall_colliders()
	_spawn_rocks()
	_spawn_holes()

	var enemy_count := randi_range(MIN_ENEMIES, MAX_ENEMIES)
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


func _build_wall_colliders() -> void:
	var half_x := room_half_size.x
	var half_y := room_half_size.y
	var half_tile := TILE_SIZE / 2.0
	# The player's own collision box is small (just around the feet) compared
	# to its sprite, so hitting the wall right at the tile boundary still lets
	# the (taller) sprite visually poke into the wall above it. Push the wall
	# colliders this much further into the room - an invisible buffer - so
	# the player stops before that can happen. Doesn't affect door widths,
	# since only the solid segments grow, not the gap.
	var wall_margin := 14.0
	var thickness := TILE_SIZE + wall_margin
	var inward := wall_margin / 2.0

	# Top/bottom span the full outer width (including corners) when solid;
	# left/right only span the inner height between them. Same layout as
	# the wall tiles themselves, just as plain rectangles - except where a
	# door sits, where the collider is split around a tile-wide gap so an
	# open door actually lets you through instead of the wall still
	# blocking the space behind it.
	_add_side_collider(door_sides[0], Vector2(0.0, -half_y - half_tile + inward), true, half_x + TILE_SIZE, thickness)
	_add_side_collider(door_sides[1], Vector2(0.0, half_y + half_tile - inward), true, half_x + TILE_SIZE, thickness)
	_add_side_collider(door_sides[2], Vector2(-half_x - half_tile + inward, 0.0), false, half_y, thickness)
	_add_side_collider(door_sides[3], Vector2(half_x + half_tile - inward, 0.0), false, half_y, thickness)


func _add_side_collider(has_door: bool, center_offset: Vector2, horizontal: bool, half_length: float, thickness: float) -> void:
	if not has_door:
		var full_size := Vector2(half_length * 2.0, thickness) if horizontal else Vector2(thickness, half_length * 2.0)
		_add_wall_collider(room_center + center_offset, full_size)
		return

	# Doors always sit centered on their side, so the gap is centered too.
	var gap_half := TILE_SIZE / 2.0
	var segment_length := half_length - gap_half
	if segment_length <= 0.0:
		return
	var segment_center_dist := gap_half + segment_length / 2.0
	if horizontal:
		_add_wall_collider(room_center + center_offset + Vector2(-segment_center_dist, 0.0), Vector2(segment_length, thickness))
		_add_wall_collider(room_center + center_offset + Vector2(segment_center_dist, 0.0), Vector2(segment_length, thickness))
	else:
		_add_wall_collider(room_center + center_offset + Vector2(0.0, -segment_center_dist), Vector2(thickness, segment_length))
		_add_wall_collider(room_center + center_offset + Vector2(0.0, segment_center_dist), Vector2(thickness, segment_length))


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
	# The floor cell just inside each door, and the transform _place_floor_tile
	# used for its shadow there (see the elif chain there) - must match so the
	# no-shadow door variant lines up with the rest of the floor once swapped.
	var inner_cells := [
		origin + Vector2i(ROOM_WIDTH_TILES / 2, 0),                 # top
		origin + Vector2i(ROOM_WIDTH_TILES / 2, ROOM_HEIGHT_TILES - 1), # bottom
		origin + Vector2i(0, ROOM_HEIGHT_TILES / 2),                # left
		origin + Vector2i(ROOM_WIDTH_TILES - 1, ROOM_HEIGHT_TILES / 2), # right
	]
	var inner_transforms := [0, FLIP_V, TRANSPOSE, TRANSPOSE | FLIP_H]

	var order := range(cells.size())
	order.shuffle()

	var placed := 0
	for i in order.size():
		var index: int = order[i]
		var is_last_chance := i == order.size() - 1
		if randf() < DOOR_CHANCE or (placed == 0 and is_last_chance):
			_spawn_door(cells[index], rotations[index], inner_cells[index], inner_transforms[index])
			door_sides[index] = true
			placed += 1


func _spawn_door(cell: Vector2i, door_rotation: float, inner_cell: Vector2i, inner_transform: int) -> void:
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
	doors.append(door)
	door_inner_floor_cells[door] = {"cell": inner_cell, "transform": inner_transform}


func _spawn_rocks() -> void:
	var rock_count := randi_range(MIN_ROCKS, MAX_ROCKS)
	for i in rock_count:
		var pos := _random_room_position(OBSTACLE_MIN_DISTANCE_FROM_PLAYER)
		obstacle_positions.append(pos)
		var rock := RockScene.instantiate()
		y_sort_layer.add_child(rock)
		rock.global_position = pos


func _spawn_holes() -> void:
	var hole_count := randi_range(MIN_HOLES, MAX_HOLES)
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
		_open_doors()


func _open_doors() -> void:
	for door in doors:
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
			randf_range(-room_half_size.x + SPAWN_MARGIN, room_half_size.x - SPAWN_MARGIN),
			randf_range(-room_half_size.y + SPAWN_MARGIN, room_half_size.y - SPAWN_MARGIN)
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
