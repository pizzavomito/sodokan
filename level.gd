extends Node2D

# Préchargement des scènes pour éviter de charger à chaque fois
const BOX_SCENE = preload("res://box.tscn")
const TARGET_SCENE = preload("res://target.tscn")
const TELEPORTER_SCENE = preload("res://teleporter.tscn")
const PARTICLES_SCENE = preload("res://victory_particles.tscn")
const DOOR_SCENE = preload("res://door.tscn")
const LIFE_PICKUP_SCENE = preload("res://life_pickup.tscn")

# Sons de sifflement aléatoires
var whistle_sounds = [
	preload("res://sounds/whistles/whistle1.mp3"),
	preload("res://sounds/whistles/whistle2.mp3"),
	preload("res://sounds/whistles/whistle3.mp3"),
	preload("res://sounds/whistles/whistle4.mp3"),
	preload("res://sounds/whistles/whistle5.mp3"),
	preload("res://sounds/whistles/whistle6.mp3"),
	preload("res://sounds/whistles/whistle7.mp3"),
	# Ajoute autant que tu veux
]

# Sons de voix aléatoires
var voice_sounds = [
	preload("res://sounds/voices/voice1.mp3"),
	preload("res://sounds/voices/voice2.mp3"),
	preload("res://sounds/voices/voice3.mp3"),
	preload("res://sounds/voices/voice4.mp3"),
	# Ajoute autant que tu veux
]

var background_musics = [
	preload("res://sounds/music_1.mp3"),  # Niveaux 1-10
	preload("res://sounds/music_2.mp3"),  # Niveaux 11-20
	#preload("res://sounds/music_3.mp3"),  # Niveaux 21-30
]

var previous_boxes_on_targets = 0

var lives = 3  # ← NOUVEAU : nombre de vies
var checkpoint_level = 0
# Système Undo
var undo_history = []  # ← NOUVEAU : historique des états
var max_undo = 20  # ← Limite d'undo

var whistle_timer = 0.0
var next_whistle_delay = 0.0

var current_level = 0  # Index du niveau actuel
var levels_data = []  # Tableau contenant tous les niveaux chargés
var checking_win = true  # Active/désactive la vérification de victoire

func _ready():
	load_levels()
	await get_tree().process_frame
	
	current_level = SaveManager.last_level_reached
	
	if current_level >= levels_data.size():
		current_level = 0
		SaveManager.last_level_reached = 0
		SaveManager.save_game()
	
	# Calcule le checkpoint (niveau 0, 10, 20, 30...)
	checkpoint_level = int(current_level / 10) * 10
	
	load_level(current_level)
	
	randomize()
	schedule_next_whistle()
	update_lives_display()
	
	# Fade in de la musique
	#fade_in_music()

func save_state():
	var container = get_node_or_null("LevelContainer")
	if not container:
		return
	
	var state = {
		"player_pos": Vector2.ZERO,
		"boxes": []
	}
	
	# Sauvegarde position du joueur
	var player = container.get_node_or_null("Player")
	if player:
		state["player_pos"] = player.position
	
	# Sauvegarde positions de toutes les caisses
	for node in container.get_children():
		if GameUtils.is_box(node):
			state["boxes"].append({
				"pos": node.position,
				"color": node.color
			})
	
	# Ajoute à l'historique
	undo_history.append(state)
	
	# Limite la taille de l'historique
	if undo_history.size() > max_undo:
		undo_history.pop_front()  # Supprime le plus ancien
	
	print("État sauvegardé - Undo disponibles : ", undo_history.size())

func undo_move():
	if undo_history.size() == 0:
		print("Pas d'undo disponible")
		return
	
	# Retire le dernier état (l'état actuel)
	if undo_history.size() > 0:
		undo_history.pop_back()
	
	# Si plus d'états, on ne peut pas undo
	if undo_history.size() == 0:
		print("Début du niveau, impossible d'undo")
		return
	
	# Récupère l'état précédent
	var state = undo_history[undo_history.size() - 1]
	
	var container = get_node_or_null("LevelContainer")
	if not container:
		return
	
	# Restaure position du joueur
	var player = container.get_node_or_null("Player")
	if player:
		player.position = state["player_pos"]
	
	# Restaure positions des caisses
	var box_index = 0
	for node in container.get_children():
		if GameUtils.is_box(node):
			if box_index < state["boxes"].size():
				node.position = state["boxes"][box_index]["pos"]
				box_index += 1
	
	print("Undo effectué - Undo restants : ", undo_history.size())
		
func fade_in_music():
	var music = get_node_or_null("BackgroundMusic")
	if music:
		music.volume_db = -80  # Commence silencieux
		var tween = create_tween()
		tween.tween_property(music, "volume_db", -10, 2.0)

func load_levels():
	# Ouvre le fichier levels.txt contenant les grilles de niveaux
	var file = FileAccess.open("res://levels.txt", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		
		# Découpe le fichier en blocs (séparés par "END")
		var level_blocks = content.split("END")
		for block in level_blocks:
			if block.strip_edges() != "":
				var lines = block.split("\n")
				var level_lines = []
				# Garde seulement les lignes qui commencent par # (la grille)
				for line in lines:
					if line.begins_with("#"):
						level_lines.append(line)
				if level_lines.size() > 0:
					levels_data.append(level_lines)
	
func load_level(level_index):
	if level_index >= levels_data.size():
		return
	
	checking_win = false
	previous_boxes_on_targets = 0
	undo_history.clear()  # ← NOUVEAU : vide l'historique
	
	clear_level()
	await get_tree().process_frame
	
	# Récupère la grille du niveau
	var level = levels_data[level_index]
	var container = get_node("LevelContainer")

	# Parse la grille
	for y in range(level.size()):
		var line = level[y]
		for x in range(line.length()):
			var char = line[x]
			var pos = Vector2(x * GameUtils.TILE_SIZE, y * GameUtils.TILE_SIZE)
			
			# Place les éléments selon le caractère
			match char:
				"+":  # Vie
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					
					# Ne spawn que si pas déjà collectée
					if not SaveManager.is_life_collected(current_level):
						spawn_life_pickup(pos)
				"#", "&", "@", "%":  # Murs variés
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					var wall_layer = container.get_node_or_null("Wall")
					if wall_layer:
						var source_id = 0
						if char == "&":
							source_id = 1
						elif char == "@":
							source_id = 2
						elif char == "%":
							source_id = 3
						wall_layer.set_cell(Vector2i(x, y), source_id, Vector2i(0, 0), 0)
				
				".":  # Sol vide
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
				
				"P":  # Joueur
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					var player = container.get_node_or_null("Player")
					if player:
						player.position = pos
				
				"D":  # Porte
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_door(pos)
				
				# === CAISSES ===
				"R":  # Caisse rouge
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_box(pos, "red")
				
				"G":  # Caisse verte
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_box(pos, "green")
				
				"B":  # Caisse bleue
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_box(pos, "blue")
				
				"W":  # Caisse bois
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_box(pos, "wood")
				
				"M":  # Caisse métal
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_box(pos, "metal")
				
				# === CIBLES ===
				"r":  # Cible rouge
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_target(pos, "red")
				
				"g":  # Cible verte
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_target(pos, "green")
				
				"b":  # Cible bleue
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_target(pos, "blue")
				
				"w":  # Cible bois
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_target(pos, "wood")
				
				"m":  # Cible métal
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_target(pos, "metal")
				
				# === TÉLÉPORTEURS ===
				"1":  # Téléporteur 1
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_teleporter(pos, 1, 2)
				
				"2":  # Téléporteur 2
					var ground_layer = container.get_node_or_null("Ground")
					if ground_layer:
						ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
					spawn_teleporter(pos, 2, 1)
				
		
	# Centre le niveau à l'écran
	center_level()
	# Change la musique tous les 10 niveaux
	change_music_for_level(level_index)
	
	# ATTEND une frame supplémentaire que tout soit bien en place
	await get_tree().process_frame
	
	# RÉACTIVE check_win
	checking_win = true

func center_level():
	# Décale le conteneur pour centrer le niveau
	var container = get_node_or_null("LevelContainer")
	if not container:
		return
	
	var level = levels_data[current_level]
	var level_width = level[0].length() * GameUtils.TILE_SIZE
	var level_height = level.size() * GameUtils.TILE_SIZE
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Décale juste le conteneur - tout le reste suit automatiquement !
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
	
	# Supprime caisses, cibles, téléporteurs ET porte
	for child in container.get_children():
		if GameUtils.is_box(child) or GameUtils.is_target(child) or child.name.begins_with("Teleporter") or child.name.begins_with("Door") or child.name == "LifePickup":  # ← Ajoute LifePickup
			child.queue_free()


func spawn_life_pickup(pos):
	var life = LIFE_PICKUP_SCENE.instantiate()
	life.name = "LifePickup"
	life.position = pos + Vector2(32, 32)  # ← Centre dans la case
	life.level_id = current_level
	get_node("LevelContainer").add_child(life)
	
func spawn_door(pos):
	var door = DOOR_SCENE.instantiate()
	door.position = pos
	get_node("LevelContainer").add_child(door)
	
	# Utilise un nom unique basé sur le niveau
	door.name = "Door_" + str(current_level)
	
	print("Porte créée avec le nom : ", door.name)
	
func spawn_box(pos, color = "red"):
	var box = BOX_SCENE.instantiate()
	box.name = "Box"
	box.position = pos
	get_node("LevelContainer").add_child(box)
	box.set_color(color)

func spawn_target(pos, color = "red"):
	var target = TARGET_SCENE.instantiate()
	target.name = "Target"
	target.position = pos
	get_node("LevelContainer").add_child(target)
	target.set_color(color)

func spawn_teleporter(pos, teleporter_id: int, linked_id: int):
	var teleporter = TELEPORTER_SCENE.instantiate()
	teleporter.position = pos
	get_node("LevelContainer").add_child(teleporter)
	teleporter.name = "Teleporter_" + str(teleporter_id)
	teleporter.initialize(teleporter_id, linked_id)

func _process(delta):
	# Vérifie à chaque frame si le niveau est gagné (seulement si activé)
	if checking_win:
		check_win()
		
	# Gère les sifflements aléatoires
	whistle_timer += delta
	if whistle_timer >= next_whistle_delay:
		play_random_whistle()

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
		play_random_voice()
	
	previous_boxes_on_targets = boxes_on_correct_targets
	
	# Trouve la porte
	var door = null
	for node in container.get_children():
		if node.name.begins_with("Door"):
			door = node
			break
	
	# Si toutes les cibles ont leur caisse → OUVRE LA PORTE
	if all_targets_filled and has_targets:
		# Si la porte n'est pas encore ouverte
		if door and not door.is_open:
			# Son de victoire
			var sound = get_node_or_null("NextLevelSound")
			if sound:
				sound.play()
			
			# Particules
			for target in container.get_children():
				if GameUtils.is_target(target) and "color" in target:
					var target_tile = GameUtils.pos_to_tile(target.position)
					spawn_victory_particles(target_tile)
			
			# Ouvre la porte
			door.open()
	else:
		# Sinon, si la porte était ouverte → REFERME-LA
		if door and door.is_open:
			print("Une caisse a bougé ! Fermeture de la porte")
			door.close()
		
				
func play_random_voice():
	# ARRÊTE le sifflement en cours si il y en a un
	var whistle_player = get_node_or_null("WhistlePlayer")
	if whistle_player and whistle_player.playing:
		whistle_player.stop()
	
	# Choisit une voix aléatoire
	var random_voice = voice_sounds[randi() % voice_sounds.size()]
	
	var voice_player = get_node_or_null("VoicePlayer")
	if voice_player:
		voice_player.stream = random_voice
		voice_player.play()
	
	# Reporte le prochain sifflement pour éviter le chevauchement
	schedule_next_whistle()
	
func spawn_victory_particles(tile_pos):
	# Crée des particules de victoire à la position donnée
	var particles = PARTICLES_SCENE.instantiate()
	
	# Convertit la position tile en position pixel
	var pixel_pos = GameUtils.tile_to_pos(tile_pos)
	particles.position = pixel_pos + Vector2(32, 32)  # Centre de la tile
	
	particles.one_shot = true
	get_node("LevelContainer").add_child(particles)
	particles.emitting = true
	
	# Les particules se détruisent automatiquement
	particles.finished.connect(particles.queue_free)

func player_entered_door():
	# Le joueur est entré dans la porte
	previous_boxes_on_targets = 0  # Reset
	await get_tree().create_timer(0.5).timeout
	next_level()
	
func update_lives_display():
	var lives_label = get_node_or_null("CanvasLayer/LivesLabel")
	if lives_label:
		var hearts = ""
		for i in range(lives):
			hearts += "❤️"
		lives_label.text = hearts
	
func next_level():
	current_level += 1
	SaveManager.update_level(current_level)
	
	# Si on passe à un nouveau palier de 10 niveaux → nouveau checkpoint
	var new_checkpoint = int(current_level / 10) * 10
	if new_checkpoint > checkpoint_level:
		checkpoint_level = new_checkpoint
		lives = 3  # Reset les vies au checkpoint
		print("Nouveau checkpoint au niveau ", checkpoint_level, " - Vies réinitialisées")
	
	load_level(current_level)
	update_lives_display()
	await get_tree().process_frame
	checking_win = true
	
func restart_level():
	# Perd une vie
	lives -= 1
	print("Vies restantes : ", lives)
	
	# Détermine le niveau cible
	var target_level = current_level
	
	if lives <= 0:
		# Plus de vies
		if current_level > checkpoint_level:
			# Pas au checkpoint → Recule d'un niveau et gagne 1 vie
			target_level = current_level - 1
			lives = 1
			print("Game Over ! Retour au niveau ", target_level, " avec 1 vie")
		else:
			# Au checkpoint → Reste au checkpoint et gagne 1 vie
			target_level = checkpoint_level
			lives = 1
			print("Game Over ! Bloqué au checkpoint niveau ", checkpoint_level, " avec 1 vie")
	else:
		# Encore des vies → Recommence le niveau actuel
		print("Recommence le niveau ", current_level)
	
	current_level = target_level
	SaveManager.last_level_reached = current_level
	SaveManager.save_game()
	undo_history.clear()
	checking_win = false
	previous_boxes_on_targets = 0
	
	update_lives_display()
	
	load_level(current_level)
	await get_tree().process_frame
	checking_win = true

func _input(event):
	# Touche Échap pour recommencer le niveau
	if event.is_action_pressed("ui_cancel"):
		restart_level()
	
	# Touche Z pour undo
	if event.is_action_pressed("ui_undo"):  # ← NOUVEAU
		undo_move()
		
func schedule_next_whistle():
	# Prochaine sifflement entre 8 et 20 secondes
	next_whistle_delay = randf_range(8.0, 20.0)
	whistle_timer = 0.0

func play_random_whistle():
	# Vérifie qu'aucune voix n'est en train de jouer
	var voice_player = get_node_or_null("VoicePlayer")
	if voice_player and voice_player.playing:
		# Reporte le sifflement
		schedule_next_whistle()
		return
	
	# Choisit un son aléatoire
	var random_sound = whistle_sounds[randi() % whistle_sounds.size()]
	
	var whistle_player = get_node_or_null("WhistlePlayer")
	if whistle_player:
		whistle_player.stream = random_sound
		whistle_player.play()
	
	# Programme le prochain
	schedule_next_whistle()
	
func change_music_for_level(level_index):
	var music_index = int(level_index / 10)  # 0-9 → 0, 10-19 → 1, etc.
	music_index = min(music_index, background_musics.size() - 1)
	
	var music_player = get_node_or_null("BackgroundMusic")
	if music_player and music_player.stream != background_musics[music_index]:
		# Fade out
		var tween = create_tween()
		tween.tween_property(music_player, "volume_db", -80, 1.0)
		await tween.finished
		
		# Change la musique
		music_player.stream = background_musics[music_index]
		music_player.play()
		
		# Fade in
		tween = create_tween()
		tween.tween_property(music_player, "volume_db", -15, 1.0)
