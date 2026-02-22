extends Node2D

# ─────────────────────────────────────────────────────────────────────────────
# CHARS reconnus dans les niveaux
# ─────────────────────────────────────────────────────────────────────────────
# Valeur = source_id de fallback (utilisé si le TileSet n'a pas encore de
# resource_name configuré dans l'éditeur Godot).
# Quand les sources sont nommées, _build_source_map() prend le dessus.
const WALL_CHARS  = {"#": 0, "&": 1, "@": 2, "%": 3, "|": 4, "_": 6, "é": 5, "à": 5, "ù": 5, "è": 5, "[": 7, "]": 8, "(": 9, "-": 10, ")": 11, "<": 12, "=": 13, ">": 14}
const FLOOR_CHARS = {".": 0, ",": 1, ":": 9, "/": 10, "£": 11, "*": 12, "µ": 13}
const FLOOR_RANDOM_CHARS = [";"]  # sol aléatoire (pool de tiles, pas de source fixe)

# ─────────────────────────────────────────────────────────────────────────────
# SYSTÈME DE ROTATION DES TUILES
# ─────────────────────────────────────────────────────────────────────────────
#
# Deux systèmes coexistent, par ordre de priorité :
#
#   1. WALL_H_PATTERNS / WALL_V_PATTERNS  (priorité haute)
#      → Séquences explicites dans la grille → transform fixe.
#      → Idéal pour les "arches" ou cadres composés de plusieurs chars.
#
#   2. WALL_ROTATION_GROUPS               (fallback automatique)
#      → Si aucun pattern n'a matché, détecte l'orientation en comptant
#        les voisins qui appartiennent au même groupe.
#      → Idéal pour un char isolé qu'on veut orienter automatiquement.
#
# ─────────────────────────────────────────────────────────────────────────────

# ── 1. Transformations disponibles ───────────────────────────────────────────
# Godot 4 encode la rotation dans le paramètre `alternative_tile` de set_cell()
# via des bits : TRANSPOSE=16384, FLIP_H=4096, FLIP_V=8192.
#   ROT_0   = 0
#   ROT_90  = TRANSPOSE | FLIP_V  = 24576   (rotation horaire 90°)
#   ROT_180 = FLIP_H   | FLIP_V  = 12288   (demi-tour)
#   ROT_270 = TRANSPOSE | FLIP_H  = 20480   (rotation horaire 270°)
const TRANSFORM_NONE    = 0
const TRANSFORM_ROT_90  = 24576  # TRANSPOSE | FLIP_V
const TRANSFORM_ROT_180 = 12288  # FLIP_H | FLIP_V
const TRANSFORM_ROT_270 = 20480  # TRANSPOSE | FLIP_H

# Conversion angle (0/90/180/270) → valeur alternative_tile, pour rot=x,y,angle
const ANGLE_TO_TRANSFORM = {
	0:   0,
	90:  24576,
	180: 12288,
	270: 20480,
}

# ── 2. Patterns explicites (priorité haute) ───────────────────────────────────
# Chaque entrée décrit une séquence de chars contigus et la transform à appliquer
# à TOUTES les tuiles de cette séquence.
#
# WALL_H_PATTERNS : séquences lues de gauche → droite sur la même ligne.
#
#   Exemple :  )-(   →  rotation 180°
#              niveau : #)---(#
#                            ↑ le triplet )-( est détecté horizontalement,
#                              toutes ses tuiles reçoivent TRANSFORM_ROT_180.
#
const WALL_H_PATTERNS = [
	{"seq": [")", "-", "("], "transform": TRANSFORM_ROT_180},
	{"seq": [">", "=", "<"], "transform": TRANSFORM_ROT_180},
	# Ajouter ici d'autres séquences horizontales si nécessaire.
]

# WALL_V_PATTERNS : séquences lues de haut → bas dans la même colonne.
#
#   Exemple :  (    →  rotation 270°
#              -
#              )
#              niveau :  #(#
#                        #-#   ← le triplet est détecté verticalement,
#                        #)#     toutes ses tuiles reçoivent TRANSFORM_ROT_270.
#
#   Note : (-) horizontal et (vertical avec - au milieu) sont deux patterns
#          DIFFÉRENTS → ils ont chacun leur liste (H ou V).
#
const WALL_V_PATTERNS = [
	{"seq": ["(", "-", ")"], "transform": TRANSFORM_ROT_270},
	{"seq": ["<", "-", ">"], "transform": TRANSFORM_ROT_270},
	# Ajouter ici d'autres séquences verticales si nécessaire.
]

# ── 3. Groupes de rotation automatique (fallback) ────────────────────────────
# Si aucun pattern explicite ne s'applique, get_wall_transform() compte combien
# de voisins du même groupe sont présents (haut/bas vs gauche/droite) pour
# deviner l'orientation de la tuile.
#
# Format : {char → [liste des chars considérés "du même groupe"]}
# Tous les chars d'un groupe doivent pointer vers la même liste.
#
#   Exemple : ( - ) forment un groupe "arche".
#     Si une tuile "-" a des voisins "(" à gauche et ")" à droite
#     → orientation horizontale → TRANSFORM_NONE (ou ROT_180 selon symétrie).
#
const WALL_ROTATION_GROUPS = {
	"(": ["(", "-", ")"],
	"-": ["(", "-", ")"],
	")": ["(", "-", ")"],
	"<": ["<", "=", ">"],
	"=": ["<", "=", ">"],
	">": ["<", "=", ">"],
}

const POP_SOUND = preload("res://sounds/pop.mp3")

signal _completion_continue
signal _name_entered

var previous_boxes_on_targets = 0
var move_count = 0
var level_start_time = 0

# Maps char → source_id, construites une fois par load_level()
# via _build_source_map() en lisant les resource_name du TileSet.
var wall_source_map: Dictionary = {}
var floor_source_map: Dictionary = {}

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

	_setup_stats_display()
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
		if undo_history.size() > 0:  # Ne pas compter l'état initial
			if move_count == 0:       # Premier move : démarre le chrono
				level_start_time = Time.get_ticks_msec()
			move_count += 1
			update_moves_display()
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

# Construit un dict {char → source_id} en lisant le resource_name de chaque
# source du TileSet. Il suffit de nommer les sources dans l'éditeur Godot
# avec le char correspondant ("#", "&", ".", etc.) pour que le mapping se fasse.
func _build_source_map(layer: TileMapLayer) -> Dictionary:
	var result: Dictionary = {}
	var ts = layer.tile_set
	for i in ts.get_source_count():
		var src_id = ts.get_source_id(i)
		var src_name: String = ts.get_source(src_id).resource_name
		if src_name != "":
			result[src_name] = src_id
	return result

func compute_wall_transforms(grid: Array) -> Dictionary:
	var map = {}

	# Patterns horizontaux
	for pattern in WALL_H_PATTERNS:
		var seq = pattern["seq"]
		var t = pattern["transform"]
		for y in range(grid.size()):
			for x in range(grid[y].length() - seq.size() + 1):
				var ok = true
				for i in range(seq.size()):
					if grid[y][x + i] != seq[i]:
						ok = false; break
				if ok:
					for i in range(seq.size()):
						map[Vector2i(x + i, y)] = t

	# Patterns verticaux
	for pattern in WALL_V_PATTERNS:
		var seq = pattern["seq"]
		var t = pattern["transform"]
		for y in range(grid.size() - seq.size() + 1):
			for x in range(grid[y].length()):
				var ok = true
				for i in range(seq.size()):
					if x >= grid[y + i].length() or grid[y + i][x] != seq[i]:
						ok = false; break
				if ok:
					for i in range(seq.size()):
						map[Vector2i(x, y + i)] = t

	return map

func get_wall_transform(char: String, grid: Array, x: int, y: int) -> int:
	if not (char in WALL_ROTATION_GROUPS):
		return TRANSFORM_NONE
	var group = WALL_ROTATION_GROUPS[char]
	var v = 0  # voisins verticaux
	var h = 0  # voisins horizontaux
	if y > 0 and x < grid[y - 1].length() and grid[y - 1][x] in group:
		v += 1
	if y < grid.size() - 1 and x < grid[y + 1].length() and grid[y + 1][x] in group:
		v += 1
	if x > 0 and grid[y][x - 1] in group:
		h += 1
	if x < grid[y].length() - 1 and grid[y][x + 1] in group:
		h += 1
	if v > h:
		return TRANSFORM_ROT_90
	return TRANSFORM_NONE

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
						if trimmed == "" or (line.length() > 0 and line[0] in WALL_CHARS):
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
									elif key == "rot":
										# Format : rot=x,y,angle  (angle = 0/90/180/270)
										if not attributes.has("rots"):
											attributes["rots"] = []
										var rparts = value.split(",")
										if rparts.size() == 3:
											attributes["rots"].append({
												"x": int(rparts[0].strip_edges()),
												"y": int(rparts[1].strip_edges()),
												"angle": int(rparts[2].strip_edges()),
											})
									else:
										attributes[key] = value
							continue
					# Détecte le début de la section FLOORS
					if trimmed == "FLOORS" or trimmed == "FLOORS:":
						reading_floors = true
						continue

					# Garde seulement les lignes de grille (mur ou sol pour FLOORS)
					if line.length() > 0 and (line[0] in WALL_CHARS or (reading_floors and (line[0] in FLOOR_CHARS or line[0] in FLOOR_RANDOM_CHARS))):
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
	move_count = 0
	level_start_time = Time.get_ticks_msec()
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

	print(floor_grid)
	# Lance le dialogue si des textes sont définis
	var texts = attributes.get("texts", [])
	if texts.size() > 0:
		print("text ", texts.size)
		start_dialog(texts)

	# Réinitialise les flags des caisses radioactives
	for node in container.get_children():
		if GameUtils.is_box(node):
			node.radioactive_checked = false

	# Construit les maps char→source_id depuis les noms des sources TileSet
	var ground_layer = container.get_node_or_null("Ground")
	var wall_layer_for_map = container.get_node_or_null("Wall")
	if ground_layer:
		floor_source_map = _build_source_map(ground_layer)
	if wall_layer_for_map:
		wall_source_map = _build_source_map(wall_layer_for_map)

	# === PASSE 1 : POSER TOUS LES SOLS ===
	if ground_layer:
		for y in range(element_grid.size()):
			var line = element_grid[y]
			for x in range(line.length()):
				var element_char = line[x]
				var floor_char = default_ground  # Sol par défaut

				# Priorité 1 : Grille FLOORS (priorité maximale)
				if floor_grid and y < floor_grid.size() and x < floor_grid[y].length():
					print("floor ", floor_grid[y][x])
					floor_char = floor_grid[y][x]
				# Priorité 2 : override_ground (force ce sol partout)
				elif override_ground:
					floor_char = override_ground
				# Priorité 3 : Caractère de sol explicite dans la grille
				elif element_char in FLOOR_CHARS or element_char in FLOOR_RANDOM_CHARS:
					floor_char = element_char

				# Détermine le source_id du sol
				var source_id: int
				if floor_char in FLOOR_RANDOM_CHARS:
					source_id = randi_range(5, 8)  # pool aléatoire tile_01-04
				else:
					source_id = floor_source_map.get(floor_char, FLOOR_CHARS.get(floor_char, 0))

				# Pose le sol
				ground_layer.set_cell(Vector2i(x, y), source_id, Vector2i(0, 0))

	# Précompute les transforms de patterns explicites
	var wall_transform_map = compute_wall_transforms(element_grid)

	# Rotations manuelles (rot=x,y,angle) — écrasent le résultat automatique
	for r in attributes.get("rots", []):
		wall_transform_map[Vector2i(r["x"], r["y"])] = ANGLE_TO_TRANSFORM.get(r["angle"], TRANSFORM_NONE)

	# === PASSE 2 : PLACER LES ÉLÉMENTS ===
	for y in range(element_grid.size()):
		var line = element_grid[y]
		for x in range(line.length()):
			var char = line[x]
			var pos = Vector2(x * GameUtils.TILE_SIZE, y * GameUtils.TILE_SIZE)

			# Murs
			if char in WALL_CHARS:
				var wall_layer = container.get_node_or_null("Wall")
				if wall_layer:
					var wall_char = override_wall if override_wall else char
					wall_layer.set_cell(Vector2i(x, y), wall_source_map.get(wall_char, WALL_CHARS.get(wall_char, 0)), Vector2i(0, 0), wall_transform_map.get(Vector2i(x, y), get_wall_transform(char, element_grid, x, y)))
				continue

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
				"€":  # Robot
					LevelSpawner.spawn_robot(container, pos)

				"P":  # Joueur
					var player = container.get_node_or_null("Player")
					if player:
						player.position = pos
						player.is_moving = false
						player.is_pushing = false
						player.is_locked = false
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

	update_moves_display()
	_update_timer_display()
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
		_update_timer_display()
		
		

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
	var elapsed_ms = (Time.get_ticks_msec() - level_start_time) if move_count > 0 else 0
	await get_tree().create_timer(0.5).timeout
	if not is_tutorial:
		checking_win = false
		await show_completion_screen(current_level, move_count, elapsed_ms)
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

# ========== AFFICHAGE MOVES / TIMER EN JEU ==========

func _setup_stats_display() -> void:
	var canvas = get_node_or_null("CanvasLayer")
	if not canvas:
		return

	var moves_label = Label.new()
	moves_label.name = "MovesLabel"
	moves_label.position = Vector2(5, 120)
	moves_label.text = "🎯 0"
	canvas.add_child(moves_label)

	var timer_label = Label.new()
	timer_label.name = "TimerLabel"
	timer_label.position = Vector2(5, 160)
	timer_label.text = "⏱ 0.00s"
	canvas.add_child(timer_label)

func update_moves_display() -> void:
	var lbl = get_node_or_null("CanvasLayer/MovesLabel")
	if lbl:
		lbl.text = "🎯 %d" % move_count

func _update_timer_display() -> void:
	var lbl = get_node_or_null("CanvasLayer/TimerLabel")
	if lbl:
		if move_count == 0:
			lbl.text = "⏱ 0.00s"
		else:
			lbl.text = "⏱ " + _format_time(Time.get_ticks_msec() - level_start_time)

# ========== ÉCRAN DE FIN DE NIVEAU + LEADERBOARD ==========

func show_completion_screen(level_idx: int, moves: int, time_ms: int) -> void:
	var canvas = get_node_or_null("CanvasLayer")
	if not canvas:
		return

	# ── Fond semi-transparent ───────────────────────────────────────────────
	var overlay = ColorRect.new()
	overlay.color = Color(0.05, 0.05, 0.1, 0.88)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	# ── Conteneur centré ────────────────────────────────────────────────────
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# ── Titre ───────────────────────────────────────────────────────────────
	var title = Label.new()
	title.text = "🎉  Niveau terminé !"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# ── Stats ────────────────────────────────────────────────────────────────
	var stats_box = HBoxContainer.new()
	stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_box.add_theme_constant_override("separation", 32)
	vbox.add_child(stats_box)

	var moves_lbl = Label.new()
	moves_lbl.text = "🎯  %d moves" % moves
	moves_lbl.add_theme_font_size_override("font_size", 17)
	stats_box.add_child(moves_lbl)

	var time_lbl = Label.new()
	time_lbl.text = "⏱  " + _format_time(time_ms)
	time_lbl.add_theme_font_size_override("font_size", 17)
	stats_box.add_child(time_lbl)

	vbox.add_child(HSeparator.new())

	# ── Saisie du nom (seulement si pas encore défini) ───────────────────────
	if SaveManager.player_name == "":
		var name_box = HBoxContainer.new()
		name_box.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(name_box)

		var prompt_lbl = Label.new()
		prompt_lbl.text = "Ton nom : "
		name_box.add_child(prompt_lbl)

		var name_input = LineEdit.new()
		name_input.placeholder_text = "Joueur"
		name_input.custom_minimum_size = Vector2(140, 0)
		name_box.add_child(name_input)

		var ok_btn = Button.new()
		ok_btn.text = "OK"
		name_box.add_child(ok_btn)

		var _validate_name = func():
			var n = name_input.text.strip_edges()
			if n != "":
				SaveManager.player_name = n
				SaveManager.save_game()
				name_box.visible = false
				_name_entered.emit()

		ok_btn.pressed.connect(_validate_name)
		name_input.text_submitted.connect(func(_t): _validate_name.call())

		await _name_entered

	# ── Soumission + leaderboard ─────────────────────────────────────────────
	var lb_title = Label.new()
	lb_title.text = "Leaderboard"
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(lb_title)

	var lb_box = VBoxContainer.new()
	lb_box.add_theme_constant_override("separation", 3)
	vbox.add_child(lb_box)

	var status_lbl = Label.new()
	status_lbl.text = "Envoi du score..."
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_box.add_child(status_lbl)

	if SupabaseManager.is_configured():
		var level_name = levels_data[level_idx].get("attributes", {}).get("level_name", "")
		SupabaseManager.submit_score(level_idx, level_name, moves, time_ms, SaveManager.player_name, SaveManager.player_id)
		var ok = await SupabaseManager.score_submitted
		if ok:
			status_lbl.text = "Récupération du classement..."
			SupabaseManager.get_leaderboard(level_idx)
			var lb_data = await SupabaseManager.leaderboard_received
			status_lbl.queue_free()
			_populate_leaderboard(lb_box, lb_data, "")
		else:
			status_lbl.text = "⚠️ Échec de l'envoi (pas de réseau ?)"
	else:
		status_lbl.text = "⚙️ Supabase non configuré (voir supabase_manager.gd)"

	vbox.add_child(HSeparator.new())

	# ── Bouton Continuer ─────────────────────────────────────────────────────
	var continue_btn = Button.new()
	continue_btn.text = "Continuer →"
	continue_btn.custom_minimum_size = Vector2(160, 38)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_btn.pressed.connect(func(): _completion_continue.emit())
	vbox.add_child(continue_btn)

	await _completion_continue
	overlay.queue_free()


func _populate_leaderboard(container: VBoxContainer, entries: Array, _my_name: String) -> void:
	if entries.is_empty():
		var lbl = Label.new()
		lbl.text = "(aucune entrée)"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(lbl)
		return

	for i in entries.size():
		var e = entries[i]
		var is_me = e.get("player_id", "") == SaveManager.player_id
		var lbl = Label.new()
		lbl.text = "#%d  %s  —  %d mvs  —  %s%s" % [
			i + 1,
			e.get("player_name", "?"),
			e.get("moves", 0),
			_format_time(e.get("time_ms", 0)),
			"  ←" if is_me else "",
		]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if is_me:
			lbl.modulate = Color(1.0, 0.9, 0.2)
		container.add_child(lbl)


func _format_time(ms: int) -> String:
	var total_s = ms / 1000
	var minutes = total_s / 60
	var secs    = total_s % 60
	var centis  = (ms % 1000) / 10
	if minutes > 0:
		return "%dm %02ds" % [minutes, secs]
	return "%d.%02ds" % [secs, centis]
