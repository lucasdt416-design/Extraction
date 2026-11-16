extends Node

# Development helper: loads a map headless and checks that it is playable --
# the player stands on something, every exit and high place can be walked to,
# loot can be reached, and the squads actually move.
#   godot --headless --path . res://tools/maptest.tscn -- <map id> --test-profile

const HIGH_PLACES: Dictionary = {
	"aster_city": [
		["spire deck", Vector3(-4.6, 5.2, 4.6)], ["west bridge, middle", Vector3(-66.0, 5.24, 0.0)], ["east bridge, middle", Vector3(66.0, 5.24, 0.0)],
		["north-west roof", Vector3(-66.0, 5.24, -31.0)], ["south-east roof", Vector3(66.0, 5.24, 31.0)], ["depot deck", Vector3(41.0, 3.3, 60.0)],
		["inside a north building", Vector3(-33.0, 0.0, -62.0)], ["inside a south building", Vector3(-33.0, 0.0, 62.0)], ["inside the depot", Vector3(30.0, 0.12, 50.0)],
		["north quarter, service lane", Vector3(-49.5, 0.0, -106.0)], ["south quarter, service lane", Vector3(49.5, 0.0, 106.0)],
	],
}

# Walks the real player body in a straight line, to catch kerbs, sills and
# stairs it cannot get over: [what, from, heading (x, z), seconds, test].
const WALKS: Dictionary = {
	"aster_city": [
		["over a kerb onto the pavement", Vector3(-30.0, 0.3, 8.0), Vector2(0, 1), 3.0, "z>17"],
		["through a south-side door", Vector3(-33.0, 0.3, 14.0), Vector2(0, 1), 4.0, "z>27"],
		["through a north-side door", Vector3(33.0, 0.3, -23.6), Vector2(0, -1), 2.5, "z<-27"],
		["up the roof stairs", Vector3(-56.0, 0.3, -24.0), Vector2(0, -1), 4.5, "y>4.6"],
		["up the spire ramp", Vector3(-24.0, 0.3, 0.0), Vector2(1, 0), 4.0, "y>4.6"],
		["into the depot", Vector3(33.0, 0.3, 14.0), Vector2(0, 1), 4.0, "z>30"],
		["through the north gate", Vector3(4.0, 0.3, -66.0), Vector2(0, -1), 5.0, "z<-86"],
		["through the south gate", Vector3(-2.0, 0.3, 70.0), Vector2(0, 1), 5.0, "z>86"],
	],
}

class Bot extends PlayerInputSource:
	var move := Vector2.ZERO
	func poll() -> InputFrame:
		var frame := InputFrame.new()
		frame.move = move
		return frame

var failed: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failed += 1

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	GameManager.map_id = args[0]
	GameManager.in_raid = true
	var started := Time.get_ticks_msec()
	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	check("builds and bakes", true, "%d ms" % (Time.get_ticks_msec() - started))
	var before: Dictionary = {}
	await get_tree().create_timer(1.5).timeout
	var player := raid.player
	player.max_shield = 1.0e9
	player.shield = 1.0e9
	check("player lands on the ground", player.is_on_floor(), str(player.global_position))
	var map := raid.get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map, player.global_position)
	check("spawn is on the navmesh", start.distance_to(player.global_position) < 1.5, "%.2f m off" % start.distance_to(player.global_position))
	var targets: Array = []
	for point in raid.extract_points:
		targets.append([point.label, point.global_position])
	targets.append_array(HIGH_PLACES.get(args[0], []))
	if raid.level is AsterLevel:
		for column in AsterLevel.COLUMNS:
			for row in AsterLevel.ROWS:
				if not AsterLevel.DEPOT.grow(3.0).has_point(Vector2(column, row)):
					targets.append(["building at %d, %d" % [column, row], Vector3(column, 0.0, row + (2.5 if row < 0.0 else -2.5))])
	for target: Array in targets:
		var path := NavigationServer3D.map_get_path(map, start, target[1], true)
		var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.INF
		check("walkable: " + str(target[0]), end.distance_to(target[1]) < 1.6, "ends %.1f m away" % end.distance_to(target[1]))
	var unreachable := 0
	for mark: Dictionary in raid.level.containers:
		var at: Vector3 = mark["position"]
		var path := NavigationServer3D.map_get_path(map, start, at, true)
		if path.is_empty() or path[path.size() - 1].distance_to(at) > 1.5:
			unreachable += 1
			print("      container out of reach: ", at, " ", mark["kind"])
	check("every container can be reached", unreachable == 0, "%d of %d out of reach" % [unreachable, raid.level.containers.size()])
	for point: Vector3 in raid.level.reinforce_points:
		var snapped := NavigationServer3D.map_get_closest_point(map, point)
		if snapped.distance_to(point) > 1.5:
			check("reinforcement point on the navmesh", false, str(point))
	for node in get_tree().get_nodes_in_group("enemy"):
		before[node] = (node as Enemy).global_position
	await get_tree().create_timer(10.0).timeout
	var moved := 0
	var fell := 0
	for node: Node in before:
		if not is_instance_valid(node):
			continue
		var enemy := node as Enemy
		if enemy.global_position.distance_to(before[node]) > 1.0:
			moved += 1
		if enemy.global_position.y < -3.0:
			fell += 1
	check("squads patrol", moved >= before.size() * 0.6, "%d of %d moved" % [moved, before.size()])
	check("nobody fell through the world", fell == 0, str(fell))
	for node in get_tree().get_nodes_in_group("enemy"):
		node.queue_free()
	var bot := Bot.new()
	player.add_child(bot)
	player.input_source = bot
	# Doors: shut ones stop the player, their button opens them, and the rest
	# of the walks are done with everything open.
	var doors := get_tree().get_nodes_in_group("door")
	if not doors.is_empty():
		for door: Door in doors:
			door.close()
		await get_tree().create_timer(4.0).timeout
		for trial: Array in [["a shut door", Vector3(-33.0, 0.3, 16.0), 25.6, 27.0], ["the shut south gate", Vector3(-2.0, 0.3, 70.0), 80.0, 86.0]]:
			var from: Vector3 = trial[1]
			for pressed in 2:
				player.global_position = from
				player.velocity = Vector3.ZERO
				player.set("_yaw", atan2(0.0, -1.0))
				if pressed == 1:
					var nearest: DoorSwitch = null
					for node in raid.level.find_children("*", "StaticBody3D", false, false):
						var button := node as DoorSwitch
						if button != null and (nearest == null or button.global_position.distance_to(from) < nearest.global_position.distance_to(from)):
							nearest = button
					check("%s has a button the player can use" % trial[0], nearest != null and nearest.can_interact(), nearest.interact_label() if nearest != null else "")
					nearest.interact(player)
					await get_tree().create_timer(3.6).timeout
				bot.move = Vector2(0, 1)
				await get_tree().create_timer(4.5).timeout
				bot.move = Vector2.ZERO
				var z := player.global_position.z
				if pressed == 0:
					check("%s stops the player" % trial[0], z < trial[2], "ended at z %.1f" % z)
				else:
					check("%s lets the player through once opened" % trial[0], z > trial[3], "ended at z %.1f" % z)
		for door: Door in doors:
			door.open()
		await get_tree().create_timer(4.0).timeout
	var grass := raid.level.get_node_or_null("Grass") as Grass
	if grass != null:
		check("grass found bare ground to grow on", grass.planted > 2000, "%d tufts" % grass.planted)
	for walk: Array in WALKS.get(args[0], []):
		var heading: Vector2 = walk[2]
		player.global_position = walk[1]
		player.velocity = Vector3.ZERO
		player.set("_yaw", atan2(-heading.x, -heading.y))
		bot.move = Vector2(0, 1)
		await get_tree().create_timer(walk[3]).timeout
		bot.move = Vector2.ZERO
		var at := player.global_position
		var rule: String = walk[4]
		var value: float = at.y if rule[0] == "y" else (at.z if rule[0] == "z" else at.x)
		var limit := float(rule.substr(2))
		check("walk: " + str(walk[0]), value > limit if rule[1] == ">" else value < limit, "ended at %s" % at.snappedf(0.1))
	print("MAPTEST %s (%d failed)" % ["OK" if failed == 0 else "FAILED", failed])
	get_tree().quit(failed)
