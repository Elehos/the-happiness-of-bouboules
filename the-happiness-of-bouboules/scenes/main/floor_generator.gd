class_name FloorGenerator
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


# Random walk from the start room: each new room branches off an existing one
# in a random direction, so the layout is a simple connected tree.
static func generate(room_count: int) -> Dictionary:
	var rooms := {Vector2i.ZERO: {"doors": {}, "cleared": true}}
	var frontier: Array[Vector2i] = [Vector2i.ZERO]
	var attempts := 0

	while rooms.size() < room_count and attempts < room_count * 20:
		attempts += 1
		var from: Vector2i = frontier[randi() % frontier.size()]
		var dir: Vector2i = DIRECTIONS[randi() % DIRECTIONS.size()]
		var to: Vector2i = from + dir
		if rooms.has(to):
			continue

		rooms[to] = {"doors": {}, "cleared": false}
		rooms[from]["doors"][dir] = true
		rooms[to]["doors"][-dir] = true
		frontier.append(to)

	return rooms
