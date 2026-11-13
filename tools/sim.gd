extends Node

# Development helper: checks the menu -> raid -> menu scene flow, then measures
# how long a player who just stands in the open survives, and logs what the
# squads do meanwhile. Run headless:
#   godot --headless --path . res://tools/sim.tscn -- --test-profile

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _ready() -> void:
	# Survive the scene changes we're about to trigger.
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.reset_profile()
	get_tree().change_scene_to_file(GameManager.MENU_SCENE)
	await wait(0.5)
	print("FLOW menu: ", get_tree().current_scene.name)
	GameManager.start_raid()
	await wait(1.5)
	var raid := get_tree().current_scene as Raid
	print("FLOW raid: ", raid != null, " backpack ", GameManager.backpack, " weapons ", GameManager.raid_weapons())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := raid.player

	player.global_position = Vector3(0.0, 0.1, 9.0)
	var t := 0.0
	var first_hit := -1.0
	var total := player.health + player.shield
	while not player.is_dead and t < 60.0:
		await wait(0.5)
		t += 0.5
		if first_hit < 0.0 and player.health + player.shield < total:
			first_hit = t
		if int(t * 2) % 6 == 0:
			var modes := {}
			for squad in Squad.all:
				var key: String = Squad.Mode.keys()[squad.mode]
				modes[key] = modes.get(key, 0) + 1
			var seeing := 0
			var near := 0
			for node in get_tree().get_nodes_in_group("enemy"):
				var enemy := node as Enemy
				if enemy.is_dead:
					continue
				if enemy.get("_sees"):
					seeing += 1
				if enemy.global_position.distance_to(player.global_position) < 25.0:
					near += 1
			print("t=%.1f hp=%.0f sh=%.0f squads=%s seeing=%d within25m=%d" % [t, player.health, player.shield, modes, seeing, near])
	print("SIM standing in the open: first hit %.1fs, dead %s at %.1fs" % [first_hit, player.is_dead, t])
	await wait(1.0)
	print("FLOW result: ", GameManager.last_result.get("outcome", "none"), " over=", raid.over)
	GameManager.return_to_menu()
	await wait(0.5)
	print("FLOW back: ", get_tree().current_scene.name)
	get_tree().quit()
