extends Node2D

# Préchargement des scènes
const BOX_SCENE = preload("res://box.tscn")
const TARGET_SCENE = preload("res://target.tscn")
const TELEPORTER_SCENE = preload("res://teleporter.tscn")
const DOOR_SCENE = preload("res://door.tscn")
const LIFE_PICKUP_SCENE = preload("res://life_pickup.tscn")
const UNDO_PICKUP_SCENE = preload("res://undo_pickup.tscn")

var current_level = 0
var levels_data = []
var checking_win = true
var lives = 3
var tutorial_completed = false

# Système Undo simplifié pour le tutoriel
var undo_history = []
var max_undo_steps = 10

func _ready():
	load_tutorial_levels()
	await get_tree().process_frame
	load_level(current_level)
	update_lives_display()
	update_level_display()

func load_tutorial_levels():
	var file = FileAccess.open("res://tutorial_levels.txt", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()

		var level_blocks = content.split("END")
		for block in level_blocks:
			if block.strip_edges() != "":
				var lines = block.split("\n")
				var level_lines = []
				var attributes = {}
				var reading_attributes = false

				for line in lines:
					var trimmed = line.strip_edges()

					if trimmed.begins_with("LEVEL_"):
						if trimmed.ends_with(":"):
							reading_attributes = true
						continue

					if reading_attributes:
						if trimmed == "" or line.begins_with("#"):
							reading_attributes = false
						else:
							if "=" in trimmed:
								var parts = trimmed.split("=", false, 1)
								if parts.size() == 2:
									var key = parts[0].strip_edges()
									var value = parts[1].strip_edges()
									attributes[key] = value
							continue

					if line.begins_with("#"):
						level_lines.append(line)

				if level_lines.size() > 0:
					levels_data.append({
						"elements": level_lines,
						"attributes": attributes
					})

func load_level(level_index):
	if level_index >= levels_data.size():
		# Tutoriel terminé !
		tutorial_completed = true
		show_completion_message()
		return

	checking_win = false
	undo_history.clear()
	clear_level()
	await get_tree().process_frame

	var level_data = levels_data[level_index]
	var element_grid = level_data["elements"]
	var attributes = level_data.get("attributes", {})
	var tutorial_text = attributes.get("tutorial_text", "")
	var container = get_node("LevelContainer")

	# Affiche le texte du tutoriel
	show_tutorial_text(tutorial_text)

	# Pose les sols
	var ground_layer = container.get_node_or_null("Ground")
	if ground_layer:
		for y in range(element_grid.size()):
			var line = element_grid[y]
			for x in range(line.length()):
				ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))

	# Place les éléments
	for y in range(element_grid.size()):
		var line = element_grid[y]
		for x in range(line.length()):
			var char = line[x]
			var pos = Vector2(x * GameUtils.TILE_SIZE, y * GameUtils.TILE_SIZE)

			match char:
				"!":
					spawn_undo_pickup(pos)
				"+":
					spawn_life_pickup(pos)
				"#":
					var wall_layer = container.get_node_or_null("Wall")
					if wall_layer:
						wall_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0), 0)
				"P":
					var player = container.get_node_or_null("Player")
					if player:
						player.position = pos
				"D":
					spawn_door(pos)
				"R":
					spawn_box(pos, "red")
				"G":
					spawn_box(pos, "green")
				"B":
					spawn_box(pos, "blue")
				"W":
					spawn_box(pos, "wood")
				"M":
					spawn_box(pos, "metal")
				"X":
					spawn_box(pos, "radioactive")
				"N":
					spawn_box(pos, "magnet")
				"r":
					spawn_target(pos, "red")
				"g":
					spawn_target(pos, "green")
				"b":
					spawn_target(pos, "blue")
				"w":
					spawn_target(pos, "wood")
				"m":
					spawn_target(pos, "metal")
				"x":
					spawn_target(pos, "radioactive")
				"n":
					spawn_target(pos, "magnet")
				"1":
					spawn_teleporter(pos, 1, 2)
				"2":
					spawn_teleporter(pos, 2, 1)

	center_level()
	await get_tree().process_frame
	save_state()
	checking_win = true

func show_tutorial_text(text: String):
	var label = get_node_or_null("CanvasLayer/TutorialLabel")
	if label:
		label.text = text

		# Animation d'apparition
		label.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(label, "modulate:a", 1.0, 0.5)

func show_completion_message():
	var label = get_node_or_null("CanvasLayer/TutorialLabel")
	if label:
		label.text = "🎉 TUTORIEL TERMINÉ ! 🎉\n\nAppuie sur ENTRÉE pour retourner au menu"

		var tween = create_tween()
		tween.tween_property(label, "modulate:a", 1.0, 0.5)

func center_level():
	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	var level_data = levels_data[current_level]
	var element_grid = level_data["elements"]
	var level_width = element_grid[0].length() * GameUtils.TILE_SIZE
	var level_height = element_grid.size() * GameUtils.TILE_SIZE
	var viewport_size = get_viewport().get_visible_rect().size

	container.position = Vector2(
		(viewport_size.x - level_width) / 2.0,
		(viewport_size.y - level_height) / 2.0
	)

func clear_level():
	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	container.position = Vector2.ZERO

	var wall_layer = container.get_node_or_null("Wall")
	if wall_layer:
		wall_layer.clear()

	var ground_layer = container.get_node_or_null("Ground")
	if ground_layer:
		ground_layer.clear()

	for child in container.get_children():
		if child.is_in_group("level_objects"):
			child.queue_free()

func spawn_box(pos, color = "red"):
	var box = BOX_SCENE.instantiate()
	box.name = "Box"
	box.position = pos
	box.add_to_group("level_objects")
	get_node("LevelContainer").add_child(box)
	box.set_color(color)

func spawn_target(pos, color = "red"):
	var target = TARGET_SCENE.instantiate()
	target.name = "Target"
	target.position = pos
	target.add_to_group("targets")
	target.add_to_group("level_objects")
	get_node("LevelContainer").add_child(target)
	target.set_color(color)

func spawn_door(pos):
	var door = DOOR_SCENE.instantiate()
	door.position = pos
	door.add_to_group("level_objects")
	get_node("LevelContainer").add_child(door)
	door.name = "Door_" + str(current_level)

func spawn_teleporter(pos, teleporter_id: int, linked_id: int):
	var teleporter = TELEPORTER_SCENE.instantiate()
	teleporter.position = pos
	teleporter.add_to_group("level_objects")
	get_node("LevelContainer").add_child(teleporter)
	teleporter.name = "Teleporter_" + str(teleporter_id)
	teleporter.initialize(teleporter_id, linked_id)

func spawn_life_pickup(pos):
	var life = LIFE_PICKUP_SCENE.instantiate()
	life.name = "LifePickup"
	life.position = pos + Vector2(32, 32)
	life.level_id = current_level
	life.add_to_group("level_objects")
	get_node("LevelContainer").add_child(life)

func spawn_undo_pickup(pos):
	var undo_pickup = UNDO_PICKUP_SCENE.instantiate()
	undo_pickup.name = "UndoPickup"
	undo_pickup.position = pos + Vector2(32, 32)
	undo_pickup.level_id = current_level
	undo_pickup.add_to_group("level_objects")
	get_node("LevelContainer").add_child(undo_pickup)

func _process(_delta):
	if checking_win and not tutorial_completed:
		check_win()

func check_win():
	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	var all_targets_filled = true
	var has_targets = false

	for target in container.get_children():
		if not GameUtils.is_target(target):
			continue

		if not "color" in target:
			continue

		has_targets = true
		var target_tile = GameUtils.pos_to_tile(target.position)
		var box_found = false

		for box in container.get_children():
			if not GameUtils.is_box(box):
				continue

			if not "color" in box:
				continue

			var box_tile = GameUtils.pos_to_tile(box.position)

			if box_tile == target_tile and box.color == target.color:
				box_found = true
				break

		if not box_found:
			all_targets_filled = false

	var door = null
	for node in container.get_children():
		if node.name.begins_with("Door"):
			door = node
			break

	if all_targets_filled and has_targets:
		if door and not door.is_open:
			var sound = get_node_or_null("NextLevelSound")
			if sound:
				sound.play()
			door.open()
	else:
		if door and door.is_open:
			door.close()

func player_entered_door():
	await get_tree().create_timer(0.5).timeout
	next_level()

func next_level():
	current_level += 1

	# Fade out
	await fade_out_level(0.1)

	load_level(current_level)
	update_lives_display()
	update_level_display()
	await get_tree().process_frame

	# Fade in
	await fade_in_level(0.3)

	checking_win = true

func fade_out_level(duration: float) -> void:
	var level_container = get_node_or_null("LevelContainer")
	if level_container:
		var tween = create_tween()
		tween.tween_property(level_container, "modulate:a", 0.0, duration)
		await tween.finished

func fade_in_level(duration: float) -> void:
	var level_container = get_node_or_null("LevelContainer")
	if level_container:
		var tween = create_tween()
		tween.tween_property(level_container, "modulate:a", 1.0, duration)
		await tween.finished

func update_lives_display():
	var lives_label = get_node_or_null("CanvasLayer/LivesLabel")
	if lives_label:
		var hearts = ""
		for i in range(lives):
			hearts += "❤️"
		lives_label.text = hearts

func update_level_display():
	var level_label = get_node_or_null("CanvasLayer/LevelLabel")
	if level_label:
		level_label.text = "Tutoriel " + str(current_level + 1) + "/" + str(levels_data.size())

func save_state():
	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	var state = {
		"player_pos": Vector2.ZERO,
		"boxes": []
	}

	var player = container.get_node_or_null("Player")
	if player:
		state["player_pos"] = player.position

	for node in container.get_children():
		if GameUtils.is_box(node):
			state["boxes"].append({
				"pos": node.position,
				"color": node.color
			})

	var is_different = true
	if undo_history.size() > 0:
		var prev_state = undo_history[undo_history.size() - 1]
		if prev_state["player_pos"] == state["player_pos"] and prev_state["boxes"].size() == state["boxes"].size():
			var boxes_same = true
			for i in range(state["boxes"].size()):
				if state["boxes"][i]["pos"] != prev_state["boxes"][i]["pos"]:
					boxes_same = false
					break
			is_different = not boxes_same

	if is_different:
		undo_history.append(state)
		if undo_history.size() > max_undo_steps:
			undo_history.pop_front()

func undo_move():
	if undo_history.size() <= 1:
		print("❌ Début du niveau, impossible d'undo")
		return

	undo_history.pop_back()
	var state = undo_history[undo_history.size() - 1]

	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	var player = container.get_node_or_null("Player")
	if player:
		player.position = state["player_pos"]

	var box_index = 0
	for node in container.get_children():
		if GameUtils.is_box(node):
			if box_index < state["boxes"].size():
				node.position = state["boxes"][box_index]["pos"]
				box_index += 1

	checking_win = false
	await get_tree().process_frame
	checking_win = true

func player_lose_life():
	lives -= 1
	update_lives_display()

	if lives > 0:
		return

	# Game over dans le tutoriel = restart niveau
	lives = 3
	await fade_out_level(0.1)
	load_level(current_level)
	await get_tree().process_frame
	await fade_in_level(0.3)
	checking_win = true

func check_magnetic_attractions():
	# Copie simplifiée de la fonction du level normal
	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	var magnet_boxes = []
	var metal_boxes = []

	for node in container.get_children():
		if GameUtils.is_box(node):
			if node.is_pushing:
				continue
			if node.is_magnet:
				magnet_boxes.append(node)
			elif node.color == "metal":
				metal_boxes.append(node)

	# Simplifié : pas d'attractions magnétiques complexes dans le tutoriel
	# On laisse juste la détection pour ne pas avoir d'erreurs

func _input(event):
	if event.is_action_pressed("ui_undo"):
		undo_move()

	# Retour au menu si tutoriel terminé
	if tutorial_completed and event.is_action_pressed("ui_accept"):
		get_tree().change_scene_to_file("res://main_menu.tscn")

	# Restart niveau
	if event.is_action_pressed("ui_cancel"):
		await fade_out_level(0.1)
		load_level(current_level)
		await get_tree().process_frame
		await fade_in_level(0.3)
		checking_win = true
