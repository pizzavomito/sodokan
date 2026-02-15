extends Node

const TILE_SIZE = 64
var recent_teleports = {}
var last_player_teleport_direction = Vector2.ZERO

# ========== CONVERSIONS ==========
static func pos_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / TILE_SIZE)),
		int(floor(pos.y / TILE_SIZE))
	)

static func tile_to_pos(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

# ========== DÉTECTION OBJETS ==========
static func is_box(node) -> bool:
	return node.has_method("push")

static func is_target(node) -> bool:
	# Utilise les groupes Godot pour identifier les targets
	# Tous les objets "target" doivent être ajoutés au groupe "targets"
	return node.is_in_group("targets")
	
static func get_object_at(parent: Node, pos: Vector2, method_name: String):
	var tile_pos = pos_to_tile(pos)
	
	for node in parent.get_children():
		if node.has_method(method_name):
			var node_tile = pos_to_tile(node.position)
			if node_tile == tile_pos:
				return node
	return null

# ========== TÉLÉPORTATION ==========
func set_teleporter_state(teleporter_node, is_active: bool):
	var active_sprite = teleporter_node.get_node_or_null("ActiveSprite")
	var cooldown_sprite = teleporter_node.get_node_or_null("CooldownSprite")
	
	if active_sprite:
		active_sprite.visible = is_active
	if cooldown_sprite:
		cooldown_sprite.visible = not is_active
		
func check_and_teleport(object: Node2D, direction: Vector2 = Vector2.ZERO):
	var tile_pos = pos_to_tile(object.position)
	
	# Si c'est le joueur, sauvegarde sa direction
	if object.name == "Player":
		last_player_teleport_direction = direction
	
	for node in object.get_parent().get_children():
		if node.name.begins_with("Teleporter_"):
			var tp_tile = pos_to_tile(node.position)
			
			if tp_tile == tile_pos:
				# Vérifie le cooldown
				var cooldown_key = str(object.get_instance_id())
				if recent_teleports.has(cooldown_key):
					var time_since = Time.get_ticks_msec() - recent_teleports[cooldown_key]
					if time_since < 500:
						return
				
				recent_teleports[cooldown_key] = Time.get_ticks_msec()
				
				# Désactive visuellement
				set_teleporter_state(node, false)
				
				# Bloque mouvements
				if object.name == "Player":
					object.is_moving = true
				elif object.has_method("push"):
					object.is_pushing = true
				
				# Son
				var sound = node.get_node_or_null("TeleportSound")
				if sound:
					sound.play()
				
				# Effet clignotement
				var sprite = null
				if object.has_node("AnimatedSprite2D"):
					sprite = object.get_node("AnimatedSprite2D")
				elif object.has_node("Sprite2D"):
					sprite = object.get_node("Sprite2D")
				
				if sprite:
					for i in range(3):
						sprite.modulate.a = 0.3
						await object.get_tree().create_timer(0.1).timeout
						sprite.modulate.a = 1.0
						await object.get_tree().create_timer(0.1).timeout
					sprite.modulate.a = 1.0
				else:
					await object.get_tree().create_timer(0.3).timeout
				
				# Téléporte (passe la direction)
				teleport_to(object, node.linked_teleporter_id, direction)  # ← Passe direction
				
				# Débloque
				if object.name == "Player":
					object.is_moving = false
				elif object.has_method("push"):
					object.is_pushing = false
				
				# Réactive après délai
				await object.get_tree().create_timer(0.5).timeout
				set_teleporter_state(node, true)
				
				return

func teleport_to(object: Node2D, target_id, direction: Vector2 = Vector2.ZERO):
	for node in object.get_parent().get_children():
		if node.name == "Teleporter_" + str(target_id):
			var destination_pos = node.position
			
			# Détermine la direction à utiliser
			var push_dir = direction  # Direction passée en paramètre
			
			# Si c'est une CAISSE et qu'on a pas de direction, utilise celle du joueur
			if is_box(object) and direction == Vector2.ZERO:
				push_dir = last_player_teleport_direction
			
			# Si on a une direction ET qu'il y a une caisse à destination
			if push_dir != Vector2.ZERO:
				var box_at_dest = get_object_at(object.get_parent(), destination_pos, "push")
				
				if box_at_dest:
					print("Caisse trouvée à destination, pousse avec direction ", push_dir)
					if push_box_chain(box_at_dest, push_dir, object.get_parent()):
						await object.get_tree().create_timer(0.2).timeout
			
			object.position = destination_pos
			return

func push_box_chain(box: Node2D, direction: Vector2, parent: Node) -> bool:
	print("push_box_chain appelée pour caisse à ", box.position, " direction ", direction)
	
	var box_target_pos = box.position + direction * TILE_SIZE
	print("Position cible : ", box_target_pos)
	
	# Vérifie mur
	var wall_layer = parent.get_node_or_null("Wall")
	if wall_layer:
		var box_target_tile = pos_to_tile(box_target_pos)
		if wall_layer.get_cell_tile_data(box_target_tile) != null:
			print("Bloqué par un mur")
			return false
	
	# Vérifie autre caisse
	var next_box = get_object_at(parent, box_target_pos, "push")
	if next_box:
		print("Autre caisse trouvée à ", next_box.position)
		if not push_box_chain(next_box, direction, parent):
			print("Chaîne bloquée plus loin")
			return false
	else:
		print("Pas d'autre caisse, espace libre")
	
	# Pousse la caisse
	print("Pousse la caisse de ", box.position, " vers ", box_target_pos)
	box.push(direction)
	return true
