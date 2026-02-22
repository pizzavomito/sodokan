extends Node2D

var is_moving = false
var is_pushing = false
var is_locked = false
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
	# Bloque les inputs si le joueur bouge, pousse, en cooldown, ou sur une porte
	if is_moving or is_pushing or input_cooldown > 0 or is_locked:
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

		# ← NOUVEAU : Si la caisse est attachée (collée magnétiquement), on ne peut pas la pousser avec les flèches
		if box.attached_box != null or box.attached_metals.size() > 0:
			print("⚠️ Caisse collée ! Utilisez ESPACE pour la détacher et la pousser.")
			is_moving = false
			return

		# ← NOUVEAU : Si c'est une caisse magnétique adjacente à une caisse métal attachée, elle ne peut pas être poussée
		if box.is_magnet and is_magnet_blocked_by_attached_metal(box):
			print("⚠️ Caisse magnétique bloquée par une caisse métal attachée ! Utilisez ESPACE.")
			is_moving = false
			return

		# Vérifie si la caisse peut être poussée (pas de mur ou autre caisse derrière)
		var box_target = box.position + direction * GameUtils.TILE_SIZE
		if has_wall_at(box_target):
			is_moving = false
			return

		# Vérifie s'il y a une autre caisse derrière
		var next_box = GameUtils.get_object_at(get_parent(), box_target, "push")
		if next_box:
			# Si c'est une caisse magnétique qui pousse une autre caisse magnétique, c'est bloqué (répulsion)
			if box.is_magnet and next_box.is_magnet:
				print("🧲 Impossible ! Deux caisses magnétiques se repoussent !")
				is_moving = false
				return

			# Si c'est une caisse magnétique qui pousse une caisse normale
			elif box.is_magnet and not next_box.is_magnet:
				# Vérifie si la caisse normale peut être poussée
				var next_target = next_box.position + direction * GameUtils.TILE_SIZE
				if has_wall_at(next_target) or GameUtils.get_object_at(get_parent(), next_target, "push"):
					# La caisse normale ne peut pas être poussée, donc la caisse magnétique ne peut pas avancer
					is_moving = false
					return
				# Sinon, on pousse d'abord la caisse normale
				next_box.push(direction)

			# Pour toute autre combinaison (caisse normale -> n'importe quoi), c'est bloqué
			else:
				is_moving = false
				return

		# Pousse la caisse
		$PushSound.play()
		box.push(direction)

		# ← NOUVEAU : Vérifie si c'est une caisse radioactive
		if box.is_radioactive:
			var _level = get_parent().get_parent()
			var _gen = _level.level_generation if _level else 0
			await check_radioactive_hit()
			if not is_inside_tree():
				return
			if _level and _level.level_generation != _gen:
				is_moving = false
				return
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
		# Sécurité : vérifie que l'objet existe toujours
		if not is_inside_tree():
			return

		is_moving = false
		$AnimatedSprite2D.frame = 0
		$AnimatedSprite2D.pause()

		# Attends que tout soit en place (caisses, etc)
		await get_tree().process_frame

		# Vérifie à nouveau que l'objet existe
		if not is_inside_tree():
			return

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

		# Vérifie les attractions magnétiques après chaque mouvement
		await MagnetSystem.check_magnetic_attractions(get_parent())
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
				# Si la porte est ouverte, on peut passer
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
				# Si la porte est ouverte et qu'on peut entrer
				if node.is_open and node.can_enter:
					enter_door()
				return

func enter_door():
	# Entre dans la porte et passe au niveau suivant
	is_locked = true
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
		# ← NOUVEAU : Si la caisse est attachée, on la détache d'abord
		if box.attached_box != null or box.attached_metals.size() > 0:
			print("🧲 Détachement de la caisse collée !")
			detach_box(box)

		is_pushing = true
		$PushSound.play()
		# Lance la chaîne de poussée récursive
		await push_box_chain(box, direction)

		# Sécurité : vérifie que l'objet existe toujours
		if not is_inside_tree():
			return

		is_pushing = false

		# Vérifie les attractions magnétiques après la poussée avec espace
		await MagnetSystem.check_magnetic_attractions(get_parent())
		# Re-vérifie une deuxième fois pour gérer les cas où une caisse repoussée revient à sa position
		await MagnetSystem.check_magnetic_attractions(get_parent())

func push_box_chain(box, direction, is_direct_push = true, has_moved = false):
	# Pousse une caisse et continue récursivement si elle rencontre une autre caisse
	# is_direct_push: true = poussée directe par le joueur, false = poussée indirecte
	# has_moved: true si la caisse a déjà glissé (pour déclencher le shake à l'impact)
	if box.is_pushing:
		return

	# Calcule la position cible
	var target_pos = box.position + direction * GameUtils.TILE_SIZE

	# Vérifie s'il y a un mur
	if has_wall_at(target_pos):
		if has_moved:
			if box.is_explosive:
				await box.explode()
			else:
				await box.shake_impact(direction)
		return

	# Vérifie s'il y a une autre caisse à la position cible
	var next_box = GameUtils.get_object_at(get_parent(), target_pos, "push")
	if next_box and not next_box.is_pushing:
		# ← NOUVEAU : Si les deux caisses sont magnétiques, elles se repoussent (bloqué)
		if box.is_magnet and next_box.is_magnet:
			print("🧲 Répulsion magnétique ! Impossible de pousser.")
			return

		# Il y a une caisse devant, elle prend la relève
		# Appel récursif avec is_direct_push = false (poussée indirecte)
		await push_box_chain(next_box, direction, false)
		# Cette caisse ne se déplace pas (elle s'arrête)
		if has_moved:
			if box.is_explosive:
				await box.explode()
			else:
				await box.shake_impact(direction)
		return

	# Marque la caisse comme poussée
	box.is_pushing = true

	# Crée l'effet adapté au type de caisse (poussière ou étincelles)
	box.create_push_effect(direction, 0.15)

	# Crée l'effet de vitesse (traînées fantômes)
	box.create_speed_effect(0.15)

	# Anime le déplacement
	var tween = create_tween()
	tween.tween_property(box, "position", target_pos, 0.15)
	await tween.finished

	# Sécurité : vérifie que l'objet existe toujours
	if not is_inside_tree() or not box or not box.is_inside_tree():
		return

	box.is_pushing = false

	# ← NOUVEAU : Vérifie si c'est une caisse radioactive (SEULEMENT si poussée directe)
	if is_direct_push and box.is_radioactive and not box.radioactive_checked:
		box.radioactive_checked = true
		await check_radioactive_hit()

	# Vérifie à nouveau que les objets existent
	if not is_inside_tree() or not box or not box.is_inside_tree():
		return

	# Vérifie les téléporteurs après le déplacement
	var pos_before_tp = box.position
	await GameUtils.check_and_teleport(box, last_direction)

	# Vérifie à nouveau que les objets existent
	if not is_inside_tree() or not box or not box.is_inside_tree():
		return

	# Si la caisse a été téléportée, arrête le glissement
	if box.position != pos_before_tp:
		return

	# Continue le glissement avec la même caisse (has_moved = true)
	await push_box_chain(box, direction, is_direct_push, true)

	# Sécurité finale
	if not is_inside_tree():
		return

	# Sauvegarde l'état après la poussée
	var level = get_parent().get_parent()
	if level and level.has_method("save_state"):
		level.save_state()

func check_radioactive_hit():
	# ← NOUVEAU : Perd 1 PV en poussant une caisse radioactive
	var level = get_parent().get_parent()
	if level:
		print("☢️ Contact avec caisse radioactive ! Perte de 1 PV")
		await level.player_lose_life()

func is_magnet_blocked_by_attached_metal(magnet_box):
	# Vérifie si une caisse magnétique est adjacente à une caisse métal qui est attachée à une autre caisse magnétique
	var magnet_tile = GameUtils.pos_to_tile(magnet_box.position)
	var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for dir in directions:
		var adjacent_tile = magnet_tile + dir
		var adjacent_pos = GameUtils.tile_to_pos(adjacent_tile)

		# Cherche une caisse à cette position
		for node in get_parent().get_children():
			if GameUtils.is_box(node) and node.color == "metal":
				var node_tile = GameUtils.pos_to_tile(node.position)
				if node_tile == adjacent_tile:
					# Vérifie si cette caisse métal est attachée à une autre caisse magnétique
					if node.attached_box != null and node.attached_box != magnet_box:
						return true

	return false

func detach_box(box):
	# Détache une caisse collée magnétiquement
	if box.attached_box == null and box.attached_metals.size() == 0:
		return

	# Si c'est une caisse métal attachée à une caisse magnétique
	if box.attached_box != null:
		var magnet = box.attached_box
		# Retire cette caisse métal de la liste des caisses attachées à la caisse magnétique
		if magnet and is_instance_valid(magnet):
			magnet.attached_metals.erase(box)

		# Réinitialise l'attachement
		box.attached_box = null

	# Si c'est une caisse magnétique avec des caisses métal attachées
	elif box.attached_metals.size() > 0:
		# Détache toutes les caisses métal
		for metal in box.attached_metals:
			if metal and is_instance_valid(metal):
				metal.attached_box = null

		# Vide la liste
		box.attached_metals.clear()

	print("✅ Caisse détachée !")
