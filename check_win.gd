extends Node2D

var current_level = 0
var tile_size = 64
var levels_data = []

func _ready():
	load_levels()
	load_level(current_level)

func load_levels():
	var file = FileAccess.open("res://levels.txt", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		
		var level_blocks = content.split("END")
		for block in level_blocks:
			if block.strip_edges() != "":
				var lines = block.split("\n")
				var level_lines = []
				for line in lines:
					if line.begins_with("#"):
						level_lines.append(line)
				if level_lines.size() > 0:
					levels_data.append(level_lines)
	
	print("Niveaux chargés: ", levels_data.size())

func load_level(level_index):
	if level_index >= levels_data.size():
		print("TOUS LES NIVEAUX TERMINÉS!")
		return
	
	# Nettoie le niveau actuel
	clear_level()
	
	var level = levels_data[level_index]
	print("=== Chargement niveau ", level_index + 1, " ===")
	
	# Parse la grille
	for y in range(level.size()):
		var line = level[y]
		for x in range(line.length()):
			var char = line[x]
			var pos = Vector2(x * tile_size, y * tile_size)
			
			match char:
				"#":
					# Dessine un mur sur le TileMap
					var wall_layer = get_node_or_null("Wall")
					if wall_layer:
						wall_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0), 0)
					var ground_layer = get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0), 0)
				".":
					# Dessine le sol
					var ground_layer = get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0), 0)
				"P":
					# Place le joueur
					var ground_layer = get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0), 0)
					var player = get_node_or_null("Player")
					if player:
						player.position = pos
				"B":
					# Place une caisse
					var ground_layer = get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0), 0)
					spawn_box(pos)
				"T":
					# Place une cible
					var ground_layer = get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0), 0)
					spawn_target(pos)

func clear_level():
	# Efface les TileMaps
	var wall_layer = get_node_or_null("Wall")
	if wall_layer:
		wall_layer.clear()
	var ground_layer = get_node_or_null("Ground")
	if ground_layer:
		ground_layer.clear()
	
	# Supprime les caisses et cibles existantes
	for child in get_children():
		if child.name.begins_with("Box") or child.name.begins_with("Target"):
			child.queue_free()

func spawn_box(pos):
	var box_scene = load("res://box.tscn")
	var box = box_scene.instantiate()
	box.position = pos
	add_child(box)

func spawn_target(pos):
	var target_scene = load("res://target.tscn")
	var target = target_scene.instantiate()
	target.position = pos
	add_child(target)

func _process(delta):
	check_win()

func check_win():
	var targets = []
	var boxes = []
	
	for node in get_children():
		if node.name.begins_with("Target"):
			targets.append(node.position)
		elif node.name.begins_with("Box"):
			boxes.append(node.position)
	
	var boxes_on_targets = 0
	for box_pos in boxes:
		for target_pos in targets:
			if box_pos.distance_to(target_pos) < 10:
				boxes_on_targets += 1
				break
	
	if boxes_on_targets == boxes.size() and boxes.size() > 0:
		print("NIVEAU TERMINÉ!")
		await get_tree().create_timer(1.0).timeout
		next_level()

func next_level():
	current_level += 1
	load_level(current_level)

func restart_level():
	load_level(current_level)

func _input(event):
	if event.is_action_pressed("ui_cancel"):  # Touche Échap
		restart_level()
