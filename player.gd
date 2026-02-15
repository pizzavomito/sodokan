extends Node2D

var is_moving = false
var is_pushing = false
var current_animation = "walk_down"
var input_cooldown = 0.0
var last_direction = Vector2.ZERO

func _ready():
	# Au démarrage, affiche la première frame de l'animation par défaut
	$AnimatedSprite2D.play(current_animation)
	$AnimatedSprite2D.stop()

func _process(delta):
	# Diminue le cooldown à chaque frame
	if input_cooldown > 0:
		input_cooldown -= delta

func _unhandled_input(event):
	# Bloque les inputs si le joueur bouge, pousse, ou en cooldown
	if is_moving or is_pushing or input_cooldown > 0:
		return

	# Détecte l'espace pour pousser une caisse
	if event.is_action_pressed("ui_accept"):
		if last_direction != Vector2.ZERO:
			await push_box_in_direction(last_direction)
		return

	# Détecte les touches de direction et lance le mouvement correspondant
	if event.is_action_pressed("ui_right"):
		attempt_move(Vector2.RIGHT, "walk_right")
	elif event.is_action_pressed("ui_left"):
		attempt_move(Vector2.LEFT, "walk_left")
	elif event.is_action_pressed("ui_up"):
		attempt_move(Vector2.UP, "walk_up")
	elif event.is_action_pressed("ui_down"):
		attempt_move(Vector2.DOWN, "walk_down")

func attempt_move(direction, animation_name):
	# Ajoute un petit délai pour éviter le spam
	input_cooldown = 0.05
	move(direction, animation_name)

func move(direction, animation_name):
	if is_moving:
		return

	last_direction = direction
	is_moving = true

	var target_pos = position + direction * GameUtils.TILE_SIZE

	# Vérifie s'il y a un mur à la position cible
	if has_wall_at(target_pos):
		is_moving = false
		return
	
	# Vérifie s'il y a une caisse à pousser
	var box = GameUtils.get_object_at(get_parent(), target_pos, "push")
	if box:
		# Si la caisse est déjà en train de bouger, on ne peut pas la pousser
		if box.is_pushing:
			is_moving = false
			return
		
		# Vérifie si la caisse peut être poussée (pas de mur ou autre caisse derrière)
		var box_target = box.position + direction * GameUtils.TILE_SIZE
		if has_wall_at(box_target) or GameUtils.get_object_at(get_parent(), box_target, "push"):
			is_moving = false
			return
		
		# Pousse la caisse
		$PushSound.play()
		box.push(direction)
	else:
		# Pas de caisse : joue le son de marche
		$WalkSound.play()
	
	# Lance l'animation de marche
	current_animation = animation_name
	$AnimatedSprite2D.play(current_animation)
	
	# Anime le déplacement du joueur avec un tween (interpolation)
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, 0.15)
	tween.finished.connect(func():
		is_moving = false
		$AnimatedSprite2D.frame = 0
		$AnimatedSprite2D.pause()

		# Attends que tout soit en place (caisses, etc)
		await get_tree().process_frame

		# Vérifie les interactions (téléportation est asynchrone !)
		await check_teleporter()
		check_door()
		check_life_pickup()
		check_undo_pickup()
		check_secret_wall()

		# ← SAUVEGARDE L'ÉTAT APRÈS TOUTES LES INTERACTIONS (notamment téléportation)
		var level = get_parent().get_parent()
		if level and level.has_method("save_state"):
			level.save_state()
	)

func check_life_pickup():
	var tile_pos = GameUtils.pos_to_tile(position)
	
	for node in get_parent().get_children():
		if node.name == "LifePickup":
			var life_tile = GameUtils.pos_to_tile(node.position)
			
			if life_tile == tile_pos:
				# Vérifie que la vie n'a pas déjà été collectée
				if not node.is_collected:
					collect_life(node)
				return

func collect_life(life_node):
	# Récupère le Level
	var level = get_parent().get_parent()
	if level:
		# Gagne 1 vie
		level.lives += 1
		level.update_lives_display()
		print("Vie collectée ! Total : ", level.lives)
		
		# Sauvegarde que cette vie a été collectée
		SaveManager.collect_life(life_node.level_id)
		
		# Effet de collecte
		life_node.collect()

func check_undo_pickup():
	var tile_pos = GameUtils.pos_to_tile(position)
	
	for node in get_parent().get_children():
		if node.name == "UndoPickup":
			var undo_tile = GameUtils.pos_to_tile(node.position)
			
			if undo_tile == tile_pos:
				if not node.is_collected:
					collect_undo(node)
				return

func collect_undo(undo_node):
	var level = get_parent().get_parent()
	if level:
		SaveManager.collect_undo(undo_node.level_id)
		level.update_undos_display()
		print("Undo collecté ! Total : ", SaveManager.current_undos)
		
		undo_node.collect()
		
func has_wall_at(pos):
	var tile_pos = GameUtils.pos_to_tile(pos)

	# Vérifie d'abord les portes (priorité sur les murs)
	for node in get_parent().get_children():
		if node.name.begins_with("Door"):
			var door_tile = GameUtils.pos_to_tile(node.position)
			if door_tile == tile_pos:
				# Si la porte est ouverte, on peut passer (ignore le mur dessous)
				if node.is_open:
					return false
				# Si la porte est fermée, on ne peut pas passer
				else:
					return true

	# Puis vérifie les murs normaux
	var wall_layer = get_parent().get_node_or_null("Wall")
	if wall_layer:
		var tile_data = wall_layer.get_cell_tile_data(tile_pos)
		if tile_data:
			return true

	return false

func check_teleporter():
	# Utilise le système de téléportation factorisé (fonction asynchrone)
	await GameUtils.check_and_teleport(self, last_direction)
	
func check_door():
	var tile_pos = GameUtils.pos_to_tile(position)
	
	for node in get_parent().get_children():
		if node.name.begins_with("Door"):
			var door_tile = GameUtils.pos_to_tile(node.position)
			
			if door_tile == tile_pos:
				if node.is_open and node.can_enter:
					enter_door()
				return

func enter_door():
	# Entre dans la porte et passe au niveau suivant
	var level = get_parent().get_parent()
	if level:
		level.player_entered_door()

func check_secret_wall():
	var tile_pos = GameUtils.pos_to_tile(position)

	for node in get_parent().get_children():
		if node.name.begins_with("SecretWall"):
			var wall_tile = GameUtils.pos_to_tile(node.position)

			if wall_tile == tile_pos:
				if not node.is_revealed:
					node.reveal()
				return

func push_box_in_direction(direction):
	# Vérifie qu'il y a une caisse à côté du joueur dans cette direction
	var box_pos = position + direction * GameUtils.TILE_SIZE
	var box = GameUtils.get_object_at(get_parent(), box_pos, "push")

	if box and not box.is_pushing:
		is_pushing = true
		$PushSound.play()
		# Lance la chaîne de poussée récursive
		await push_box_chain(box, direction)
		is_pushing = false

func push_box_chain(box, direction):
	# Pousse une caisse et continue récursivement si elle rencontre une autre caisse
	if box.is_pushing:
		return

	# Calcule la position cible
	var target_pos = box.position + direction * GameUtils.TILE_SIZE

	# Vérifie s'il y a un mur
	if has_wall_at(target_pos):
		return

	# Vérifie s'il y a une autre caisse à la position cible
	var next_box = GameUtils.get_object_at(get_parent(), target_pos, "push")
	if next_box and not next_box.is_pushing:
		# Il y a une caisse devant, elle prend la relève
		await push_box_chain(next_box, direction)
		# Cette caisse ne se déplace pas (elle s'arrête)
		return

	# Marque la caisse comme poussée
	box.is_pushing = true

	# Anime le déplacement
	var tween = create_tween()
	tween.tween_property(box, "position", target_pos, 0.15)
	await tween.finished

	box.is_pushing = false

	# Continue le glissement avec la même caisse
	await push_box_chain(box, direction)

	# Sauvegarde l'état après la poussée
	var level = get_parent().get_parent()
	if level and level.has_method("save_state"):
		level.save_state()
