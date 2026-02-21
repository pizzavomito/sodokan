extends Node2D

# Son de perte de vie
const POP_SOUND = preload("res://sounds/pop.mp3")

var previous_boxes_on_targets = 0

var lives = 3  # nombre de vies
# Système Undo
var undo_history = []  # Array pour stocker l'historique
var max_undo_steps = 30  # Max 10 étapes
var currently_saving = false

var current_level = 0  # Index du niveau actuel
var levels_data = []  # Tableau contenant tous les niveaux chargés
var checking_win = true  # Active/désactive la vérification de victoire
var is_tutorial = false  # Mode tutoriel
var dialog_texts = []    # File des textes à afficher
var dialog_generation = 0
var is_paused = false  # Menu pause actif
var level_generation: int = 0  # Incrémenté à chaque load_level

# Mode dev : saut de niveau
var level_jump_input = ""  # Numéro en cours de saisie

func _ready():
	# Récupère le mode depuis le singleton
	is_tutorial = GameMode.is_tutorial_mode

	load_levels()
	await get_tree().process_frame

	# En mode tutoriel, on commence toujours au niveau 0
	if is_tutorial:
		current_level = 0
	else:
		current_level = SaveManager.last_level_reached

		if current_level >= levels_data.size():
			current_level = 0
			SaveManager.last_level_reached = 0
			SaveManager.save_game()

	# Initialise le système audio
	LevelAudio.setup(
		get_node_or_null("WhistlePlayer"),
		get_node_or_null("VoicePlayer"),
		get_node_or_null("BackgroundMusic")
	)

	load_level(current_level)
	update_undos_display()
	update_lives_display()
	update_level_display()

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

	# Vérifie que l'état est DIFFÉRENT du précédent
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

		print("État sauvegardé - Total steps: ", undo_history.size())
		update_undos_display()
	else:
		print("État identique au précédent, pas sauvegardé")

func undo_move():
	if SaveManager.current_undos <= 0:
		print("❌ Pas d'undo disponible !")
		return

	if undo_history.size() <= 1:
		print("❌ Début du niveau, impossible d'undo")
		return

	# Utilise un undo
	SaveManager.use_undo()

	# Retire le dernier état (état actuel)
	undo_history.pop_back()

	# Récupère l'état précédent
	var state = undo_history[undo_history.size() - 1]
	print("🔙 Undo - Retour à l'état ", undo_history.size() - 1)

	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	# Restaure joueur
	var player = container.get_node_or_null("Player")
	if player:
		print("   Joueur: ", state["player_pos"])
		player.position = state["player_pos"]

	# Restaure caisses dans le bon ordre
	var box_index = 0
	for node in container.get_children():
		if GameUtils.is_box(node):
			if box_index < state["boxes"].size():
				print("   Caisse ", box_index, ": ", state["boxes"][box_index]["pos"])
				node.position = state["boxes"][box_index]["pos"]
				box_index += 1

	await animate_undo()

	update_undos_display()

	# Force check_win après undo
	checking_win = false
	await get_tree().process_frame
	checking_win = true

	print("✅ Undo effectué - Undos restants : ", SaveManager.current_undos)

func load_levels():
	# Ouvre le fichier levels.txt ou tutorial_levels.txt selon le mode
	var filename = "res://tutorial_levels.txt" if is_tutorial else "res://levels.txt"
	var file = FileAccess.open(filename, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()

		# Découpe le fichier en blocs (séparés par "END")
		var level_blocks = content.split("END")
		for block in level_blocks:
			if block.strip_edges() != "":
				var lines = block.split("\n")
				var level_lines = []
				var floor_lines = []
				var attributes = {}
				var reading_floors = false
				var reading_attributes = false

				# Parse les lignes
				for line in lines:
					var trimmed = line.strip_edges()

					# Détecte le début d'un niveau
					if trimmed.begins_with("LEVEL_"):
						# Si la ligne se termine par ":", on lit les attributs
						if trimmed.ends_with(":"):
							reading_attributes = true
						continue

					# Si on lit les attributs
					if reading_attributes:
						# Si la ligne est vide ou commence par #, fin des attributs
						if trimmed == "" or line.begins_with("#"):
							reading_attributes = false
						else:
							# Parse les attributs (format: key=value)
							if "=" in trimmed:
								var parts = trimmed.split("=", false, 1)
								if parts.size() == 2:
									var key = parts[0].strip_edges()
									var value = parts[1].strip_edges()
									if key == "text":
										if not attributes.has("texts"):
											attributes["texts"] = []
										attributes["texts"].append(value)
									elif key == "glitch":
										if not attributes.has("glitchs"):
											attributes["glitchs"] = []
										attributes["glitchs"].append(_parse_glitch_config(value))
									else:
										attributes[key] = value
							continue
					# Garde seulement les lignes qui commencent par #
					if line.begins_with("#") or line.begins_with("_"):
						if reading_floors:
							floor_lines.append(line)
						else:
							level_lines.append(line)

				if level_lines.size() > 0:
					# Stocke les éléments, les sols et les attributs
					levels_data.append({
						"elements": level_lines,
						"floors": floor_lines if floor_lines.size() > 0 else null,
						"attributes": attributes
					})

func load_level(level_index):
	if level_index >= levels_data.size():
		return

	checking_win = false
	previous_boxes_on_targets = 0
	level_generation += 1

	# Réinitialise correctement
	undo_history.clear()
	currently_saving = false

	clear_level()
	await get_tree().process_frame

	# Récupère les grilles du niveau
	var level_data = levels_data[level_index]
	var element_grid = level_data["elements"]
	var floor_grid = level_data["floors"]
	var attributes = level_data.get("attributes", {})
	var override_ground = attributes.get("override_ground", null)
	var default_ground = attributes.get("default_ground", ".")
	var override_wall = attributes.get("override_wall", null)
	var container = get_node("LevelContainer")
	var levelName = attributes.get("level_name", "")
	update_level_name(levelName)

	# Lance le dialogue si des textes sont définis
	var texts = attributes.get("texts", [])
	if texts.size() > 0:
		start_dialog(texts)

	# Réinitialise les flags des caisses radioactives
	for node in container.get_children():
		if GameUtils.is_box(node):
			node.radioactive_checked = false

	# === PASSE 1 : POSER TOUS LES SOLS ===
	var ground_layer = container.get_node_or_null("Ground")
	if ground_layer:
		for y in range(element_grid.size()):
			var line = element_grid[y]
			for x in range(line.length()):
				var element_char = line[x]
				var floor_char = default_ground  # Sol par défaut

				# Priorité 1 : Grille FLOORS (priorité maximale)
				if floor_grid and y < floor_grid.size() and x < floor_grid[y].length():
					floor_char = floor_grid[y][x]
				# Priorité 2 : override_ground (force ce sol partout)
				elif override_ground:
					floor_char = override_ground
				# Priorité 3 : Caractère de sol explicite dans la grille
				elif element_char in [".", ",", ";", ":", "/"]:
					floor_char = element_char

				# Détermine le source_id du sol
				var source_id = 0
				if floor_char == ",":
					source_id = 1
				elif floor_char == ";":
					source_id = 2
				elif floor_char == ":":
					source_id = 3
				elif floor_char == "/":
					source_id = 4

				# Pose le sol
				ground_layer.set_cell(Vector2i(x, y), source_id, Vector2i(0, 0))

	# === PASSE 2 : PLACER LES ÉLÉMENTS ===
	for y in range(element_grid.size()):
		var line = element_grid[y]
		for x in range(line.length()):
			var char = line[x]
			var pos = Vector2(x * GameUtils.TILE_SIZE, y * GameUtils.TILE_SIZE)

			match char:
				"!":  # Undo
					if not SaveManager.is_undo_collected(current_level):
						LevelSpawner.spawn_undo_pickup(container, pos, current_level)

				"~":  # Undo caché (easter egg)
					if not SaveManager.is_undo_collected(current_level):
						LevelSpawner.spawn_hidden_undo_pickup(container, pos, current_level, 0)

				"+":  # Vie
					if not SaveManager.is_life_collected(current_level):
						LevelSpawner.spawn_life_pickup(container, pos, current_level)

				"^":  # Vie cachée (easter egg)
					if not SaveManager.is_life_collected(current_level):
						LevelSpawner.spawn_hidden_life_pickup(container, pos, current_level, 0)

				"#", "&", "@", "%", "|", "_":  # Murs variés
					var wall_layer = container.get_node_or_null("Wall")
					if wall_layer:
						var wall_char = override_wall if override_wall else char
						var source_id = 0
						if wall_char == "&":
							source_id = 1
						elif wall_char == "@":
							source_id = 2
						elif wall_char == "%":
							source_id = 3
						elif wall_char == "|":
							source_id = 4
						elif wall_char == "_":
							source_id = 6
						wall_layer.set_cell(Vector2i(x, y), source_id, Vector2i(0, 0), 0)

				"P":  # Joueur
					var player = container.get_node_or_null("Player")
					if player:
						player.position = pos
						player.is_moving = false
						player.is_pushing = false
						player.input_cooldown = 0.0

				"D":  # Porte
					LevelSpawner.spawn_door(container, pos, current_level)

				"$":  # Mur secret (easter egg)
					LevelSpawner.spawn_secret_wall(container, pos, 0)

				# === CAISSES ===
				"R":  LevelSpawner.spawn_box(container, pos, "red")
				"G":  LevelSpawner.spawn_box(container, pos, "green")
				"B":  LevelSpawner.spawn_box(container, pos, "blue")
				"W":  LevelSpawner.spawn_box(container, pos, "wood")
				"M":  LevelSpawner.spawn_box(container, pos, "metal")
				"X":  LevelSpawner.spawn_box(container, pos, "radioactive")
				"N":  LevelSpawner.spawn_box(container, pos, "magnet")
				"E":  LevelSpawner.spawn_box(container, pos, "explosive")

				# === CIBLES ===
				"r":  LevelSpawner.spawn_target(container, pos, "red")
				"g":  LevelSpawner.spawn_target(container, pos, "green")
				"b":  LevelSpawner.spawn_target(container, pos, "blue")
				"w":  LevelSpawner.spawn_target(container, pos, "wood")
				"m":  LevelSpawner.spawn_target(container, pos, "metal")
				"x":  LevelSpawner.spawn_target(container, pos, "radioactive")
				"n":  LevelSpawner.spawn_target(container, pos, "magnet")

				# === TÉLÉPORTEURS ===
				"1":  LevelSpawner.spawn_teleporter(container, pos, 1, 2)
				"2":  LevelSpawner.spawn_teleporter(container, pos, 2, 1)

	center_level()
	LevelAudio.change_music_for_level(level_index)

	# Configure les effets glitch
	#var glitch_rect = get_node_or_null("LevelContainer/GlitchRect")
	#if glitch_rect:
		#var glitchs = attributes.get("glitchs", [])
		#glitch_rect.setup(glitchs)

	await get_tree().process_frame

	# Sauvegarde l'ÉTAT INITIAL du niveau
	save_state()

	checking_win = true

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
	# Stoppe les glitchs
	#var glitch_rect = get_node_or_null("CanvasLayer/GlitchRect")
	#if glitch_rect:
		#glitch_rect.stop_all()

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

	print("dialog_generation :", dialog_generation)
	dialog_generation += 1

func _process(delta):
	if is_paused:
		var label = get_node_or_null("CanvasLayer/PauseMenu/ClaudeTextLabel")
		if label:
			var scrollbar = label.get_v_scroll_bar()
			if Input.is_action_pressed("ui_down"):
				scrollbar.value += 200 * delta
			if Input.is_action_pressed("ui_up"):
				scrollbar.value -= 200 * delta
		return
	# Vérifie à chaque frame si le niveau est gagné (seulement si activé)
	if checking_win:
		check_win()
		
		

func toggle_pause():
	is_paused = not is_paused
	get_tree().paused = is_paused
	var pause_menu = get_node_or_null("CanvasLayer/PauseMenu")
	if pause_menu:
		pause_menu.visible = is_paused

func check_win():
	var container = get_node_or_null("LevelContainer")
	if not container:
		return

	var all_targets_filled = true
	var has_targets = false
	var boxes_on_correct_targets = 0

	# Pour chaque cible
	for target in container.get_children():
		if not GameUtils.is_target(target):
			continue

		if not "color" in target:
			continue

		has_targets = true
		var target_tile = GameUtils.pos_to_tile(target.position)
		var box_found = false

		# Cherche une caisse
		for box in container.get_children():
			if not GameUtils.is_box(box):
				continue

			if not "color" in box:
				continue

			var box_tile = GameUtils.pos_to_tile(box.position)

			if box_tile == target_tile and box.color == target.color:
				box_found = true
				boxes_on_correct_targets += 1
				break

		if not box_found:
			all_targets_filled = false

	# Si progression, joue une voix
	if boxes_on_correct_targets > previous_boxes_on_targets:
		LevelAudio.play_random_voice()

	previous_boxes_on_targets = boxes_on_correct_targets

	# Trouve la porte
	var door = null
	for node in container.get_children():
		if node.name.begins_with("Door"):
			door = node
			break

	# Si toutes les cibles ont leur caisse → OUVRE LA PORTE
	if all_targets_filled and has_targets:
		if door and not door.is_open:
			var sound = get_node_or_null("NextLevelSound")
			if sound:
				sound.play()
			door.open()
	else:
		if door and door.is_open:
			print("Une caisse a bougé ! Fermeture de la porte")
			door.close()

func player_entered_door():
	previous_boxes_on_targets = 0
	await get_tree().create_timer(0.5).timeout
	next_level()

func update_undos_display():
	var undos_label = get_node_or_null("CanvasLayer/UndosLabel")
	if undos_label:
		undos_label.text = "🔋x " + str(SaveManager.current_undos)

func update_lives_display():
	var lives_label = get_node_or_null("CanvasLayer/LivesLabel")
	if lives_label:
		lives_label.text = "❤️x " + str(lives)
		
func update_level_name(name):
	var level_name = get_node_or_null("CanvasLayer/LevelNameLabel")
	if level_name:
		if is_tutorial:
			level_name.text = "Tutoriel " +name
		else:
			level_name.text = name
			
func update_level_display():
	var level_label = get_node_or_null("CanvasLayer/LevelLabel")
	if level_label:
		if is_tutorial:
			level_label.text = "Tutoriel " + str(current_level + 1) + "/" + str(levels_data.size())
		else:
			level_label.text = "Level " + str(current_level)

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

func animate_heart_loss():
	var pop_player = get_node_or_null("PopPlayer")
	if pop_player:
		pop_player.stream = POP_SOUND
		pop_player.play()

	var lives_label = get_node_or_null("CanvasLayer/LivesLabel")
	if lives_label:
		var original_y = lives_label.position.y

		var tween = create_tween()

		tween.tween_property(lives_label, "position:y", original_y + 10, 0.1)
		tween.tween_property(lives_label, "position:y", original_y - 10, 0.1)
		tween.tween_property(lives_label, "position:y", original_y, 0.1)

		tween.parallel().tween_property(lives_label, "modulate", Color.WHITE, 0.15)
		tween.tween_property(lives_label, "modulate", Color.RED, 0.15)
		tween.tween_property(lives_label, "modulate", Color.WHITE, 0.15)

		tween.parallel().tween_property(lives_label, "scale", Vector2(1.2, 1.2), 0.1)
		tween.tween_property(lives_label, "scale", Vector2(1.0, 1.0), 0.1)

		await tween.finished

func animate_life_loss(with_fade_in: bool = true) -> void:
	var pop_player = get_node_or_null("PopPlayer")
	if pop_player:
		pop_player.stream = POP_SOUND
		pop_player.play()

	await fade_out_level(0.1)

	var undos_label = get_node_or_null("CanvasLayer/UndosLabel")
	if undos_label:
		var original_y = undos_label.position.y

		var tween = create_tween()

		tween.tween_property(undos_label, "position:y", original_y + 10, 0.1)
		tween.tween_property(undos_label, "position:y", original_y - 10, 0.1)
		tween.tween_property(undos_label, "position:y", original_y, 0.1)

		tween.parallel().tween_property(undos_label, "modulate", Color.WHITE, 0.15)
		tween.tween_property(undos_label, "modulate", Color.RED, 0.15)
		tween.tween_property(undos_label, "modulate", Color.WHITE, 0.15)

		tween.parallel().tween_property(undos_label, "scale", Vector2(1.2, 1.2), 0.1)
		tween.tween_property(undos_label, "scale", Vector2(1.0, 1.0), 0.1)

		await tween.finished

	if with_fade_in:
		await fade_in_level(0.3)

func animate_undo():
	var pop_player = get_node_or_null("PopPlayer")
	if pop_player:
		pop_player.stream = POP_SOUND
		pop_player.play()

	var level_container = get_node_or_null("LevelContainer")
	if level_container:
		var tween_level = create_tween()
		tween_level.tween_property(level_container, "modulate", Color.WHITE, 0.1)
		tween_level.tween_property(level_container, "modulate", Color(0.8, 0.9, 1.0), 0.1)
		tween_level.tween_property(level_container, "modulate", Color.WHITE, 0.1)
		tween_level.parallel().tween_property(level_container, "position:x", level_container.position.x - 5, 0.05)
		tween_level.tween_property(level_container, "position:x", level_container.position.x + 5, 0.05)
		tween_level.tween_property(level_container, "position:x", level_container.position.x, 0.05)

	var undos_label = get_node_or_null("CanvasLayer/UndosLabel")
	if undos_label:
		var tween = create_tween()

		tween.tween_property(undos_label, "position:y", undos_label.position.y - 10, 0.1)
		tween.tween_property(undos_label, "position:y", undos_label.position.y + 10, 0.1)
		tween.tween_property(undos_label, "position:y", undos_label.position.y, 0.1)

		tween.parallel().tween_property(undos_label, "modulate", Color.WHITE, 0.15)
		tween.tween_property(undos_label, "modulate", Color(0.6, 0.8, 1.0), 0.15)
		tween.tween_property(undos_label, "modulate", Color.WHITE, 0.15)

		await tween.finished

func next_level():
	current_level += 1

	# En mode tutoriel, ne pas sauvegarder la progression
	if not is_tutorial:
		SaveManager.update_level(current_level)
		# +1 undo quand on passe un niveau
		SaveManager.add_undo()

	# Vérifie si le tutoriel est terminé
	if is_tutorial and current_level >= levels_data.size():
		checking_win = false
		check_tutorial_completion()
		return

	# Fade out avant de charger le nouveau niveau
	await fade_out_level(0.1)

	load_level(current_level)
	update_lives_display()
	update_undos_display()
	update_level_display()
	await get_tree().process_frame

	# Fade in après chargement du nouveau niveau
	await fade_in_level(0.3)

	checking_win = true

func restart_level():
	if SaveManager.current_undos >= 5:
		# Assez d'undos : perd 5 et recommence le niveau actuel
		for i in range(5):
			SaveManager.use_undo()

		await animate_life_loss(false)

		print("Restart niveau ", current_level, " (-5 undos)")

		SaveManager.last_level_reached = current_level
		SaveManager.save_game()
		undo_history.clear()
		checking_win = false
		previous_boxes_on_targets = 0
		currently_saving = false

		update_undos_display()
		update_level_display()

		load_level(current_level)
		await get_tree().process_frame
		checking_win = true
		await fade_in_level(0.3)
	else:
		# Pas assez d'undos : va au niveau précédent et gagne 1 undo
		if current_level > 0:
			current_level -= 1
		SaveManager.add_undo()

		await animate_life_loss(false)

		print("Pas assez d'undos ! Retour au niveau ", current_level, " (+1 undo)")

		SaveManager.last_level_reached = current_level
		SaveManager.save_game()
		undo_history.clear()
		checking_win = false
		previous_boxes_on_targets = 0
		currently_saving = false

		update_undos_display()
		update_level_display()

		load_level(current_level)
		await get_tree().process_frame
		checking_win = true
		await fade_in_level(0.3)

func player_lose_life():
	lives -= 1
	print("☢️ Perte de vie ! Vies restantes : ", lives)

	update_lives_display()

	if lives > 0:
		print("Continue le niveau avec ", lives, " vie(s)")
		animate_heart_loss()
		return

	print("Game Over ! Perte de toutes les vies")
	await animate_heart_loss()

	if SaveManager.current_undos >= 5:
		# Assez d'undos : perd 5 et recommence le niveau actuel
		for i in range(5):
			SaveManager.use_undo()
		lives = 1
		print("Retour au début du niveau ", current_level, " (-5 undos)")
	else:
		# Pas assez d'undos : va au niveau précédent et gagne 1 undo
		if current_level > 0:
			current_level -= 1
		SaveManager.add_undo()
		lives = 1
		print("Pas assez d'undos ! Retour au niveau ", current_level, " (+1 undo)")

	await fade_out_level(0.1)

	SaveManager.last_level_reached = current_level
	SaveManager.save_game()
	undo_history.clear()
	checking_win = false
	previous_boxes_on_targets = 0
	currently_saving = false

	update_lives_display()
	update_undos_display()
	update_level_display()

	load_level(current_level)
	await get_tree().process_frame
	checking_win = true
	await fade_in_level(0.3)

func _input(event):
	# Touche Entrée pour ouvrir/fermer le menu pause (hors dialogue et hors saisie de niveau)
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and level_jump_input == "":
			toggle_pause()
			get_viewport().set_input_as_handled()
			return

	# Si en pause, on bloque tout le reste
	if is_paused:
		get_viewport().set_input_as_handled()
		return

	# Retour au menu si tutoriel terminé
	if is_tutorial and current_level >= levels_data.size() and event.is_action_pressed("ui_accept"):
		GameMode.is_tutorial_mode = false
		get_tree().change_scene_to_file("res://main_menu.tscn")
		return

	# Touche Échap pour recommencer le niveau (ou retour au menu en mode tutoriel)
	if event.is_action_pressed("ui_cancel"):
		if is_tutorial:
			GameMode.is_tutorial_mode = false
			get_tree().change_scene_to_file("res://main_menu.tscn")
		else:
			restart_level()

	# Touche Z pour undo
	if event.is_action_pressed("ui_undo"):
		undo_move()

	# Touche U pour ajouter un undo (debug/cheat)
	if event is InputEventKey and event.pressed and event.keycode == KEY_U and not event.echo:
		SaveManager.add_undo()
		update_undos_display()
		print("➕ Undo ajouté ! Total : ", SaveManager.current_undos)

	# MODE DEV : Saut de niveau
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var digit = str(event.keycode - KEY_0)
			level_jump_input += digit
			update_level_jump_display()
			print("Saisie niveau : ", level_jump_input)

		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if level_jump_input != "":
				jump_to_level(int(level_jump_input))
				level_jump_input = ""
				update_level_jump_display()

		elif event.keycode == KEY_BACKSPACE:
			if level_jump_input.length() > 0:
				level_jump_input = level_jump_input.substr(0, level_jump_input.length() - 1)
				update_level_jump_display()
				print("Saisie niveau : ", level_jump_input if level_jump_input != "" else "(vide)")

func update_level_jump_display():
	var label = get_node_or_null("CanvasLayer/LevelJumpLabel")
	if label:
		if level_jump_input == "":
			label.text = ""
		else:
			label.text = "Niveau : " + level_jump_input

func jump_to_level(level_number: int):
	if level_number < 0 or level_number >= levels_data.size():
		print("❌ Niveau ", level_number, " n'existe pas ! (0-", levels_data.size() - 1, ")")
		return

	var container = get_node_or_null("LevelContainer")
	if container:
		var player = container.get_node_or_null("Player")
		if player and (player.is_moving or player.is_pushing):
			print("⏳ Joueur occupé, réessayez dans un instant...")
			return

	print("🚀 Saut vers le niveau ", level_number)

	checking_win = false

	current_level = level_number
	SaveManager.last_level_reached = current_level
	SaveManager.save_game()

	undo_history.clear()
	previous_boxes_on_targets = 0
	currently_saving = false

	_load_level_deferred.call_deferred(current_level)

func _load_level_deferred(level_index: int):
	load_level(level_index)
	update_level_display()
	await get_tree().process_frame
	checking_win = true
	print("✅ Niveau ", level_index, " chargé")

func _parse_glitch_config(value: String) -> Dictionary:
	# Parse le format [type=1, count=3, delay=2.0, duration=0.3]
	var config = {}
	var cleaned = value.strip_edges()
	if cleaned.begins_with("[") and cleaned.ends_with("]"):
		cleaned = cleaned.substr(1, cleaned.length() - 2)
	var pairs = cleaned.split(",")
	for pair in pairs:
		pair = pair.strip_edges()
		if "=" in pair:
			var kv = pair.split("=", false, 1)
			if kv.size() == 2:
				var k = kv[0].strip_edges()
				var v = kv[1].strip_edges()
				if k == "type":
					config["type"] = int(v)
				elif k == "count":
					config["count"] = int(v)
				elif k == "delay":
					config["delay"] = float(v)
				elif k == "duration":
					config["duration"] = float(v)
	return config
# ========== FONCTIONS TUTORIEL ==========

func start_dialog(texts: Array):
	dialog_texts = texts.duplicate()
	show_dialog_page()

func show_dialog_page():
	var my_generation = dialog_generation

	var label = get_node_or_null("CanvasLayer/PauseMenu/ClaudeTextLabel")

	if not label:
		return

	toggle_pause()
	label.visible = true
	label.text = ""
	label.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)

	for text in dialog_texts:
		if my_generation != dialog_generation:
			return
		label.text += " >: " + text + "\n"
		await get_tree().create_timer(randf_range(2.0, 5.0)).timeout
		if my_generation != dialog_generation:
			return

func check_tutorial_completion():
	if is_tutorial and current_level >= levels_data.size():
		start_dialog(["🎉 TUTORIEL TERMINÉ ! 🎉", "Appuie sur ENTRÉE pour retourner au menu."])
