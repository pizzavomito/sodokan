extends Node

func check_magnetic_attractions(container: Node) -> void:
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

	# Vérifie les détachements automatiques
	for metal in metal_boxes:
		if metal.attached_box != null:
			var magnet = metal.attached_box
			if not are_boxes_adjacent(metal, magnet):
				print("🧲 Détachement automatique : caisse métal éloignée de la caisse magnétique")
				detach_metal_from_magnet(metal, magnet)

	for magnet in magnet_boxes:
		if magnet.attached_metals.size() > 0:
			var to_detach = []
			for metal in magnet.attached_metals:
				if metal and is_instance_valid(metal):
					if not are_boxes_adjacent(metal, magnet):
						to_detach.append(metal)
			for metal in to_detach:
				print("🧲 Détachement automatique : caisse métal éloignée de la caisse magnétique")
				detach_metal_from_magnet(metal, magnet)

	# Pour chaque caisse magnétique, vérifie les attractions
	for magnet in magnet_boxes:
		var magnet_tile = GameUtils.pos_to_tile(magnet.position)
		var directions = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		for direction in directions:
			for distance in [1, 2]:
				var target_tile = magnet_tile + (direction * distance)
				for metal in metal_boxes:
					var metal_tile = GameUtils.pos_to_tile(metal.position)
					if metal_tile == target_tile:
						if metal.attached_box == null:
							if can_attract(container, metal, magnet, direction, distance):
								await attract_metal_to_magnet(metal, magnet, direction, distance)
						

	# Vérifie les répulsions entre caisses magnétiques
	for i in range(magnet_boxes.size()):
		for j in range(i + 1, magnet_boxes.size()):
			var magnet1 = magnet_boxes[i]
			var magnet2 = magnet_boxes[j]
			var tile1 = GameUtils.pos_to_tile(magnet1.position)
			var tile2 = GameUtils.pos_to_tile(magnet2.position)
			var diff = tile2 - tile1
			var manhattan_distance = abs(diff.x) + abs(diff.y)
			if manhattan_distance == 1:
				print("🧲 Répulsion magnétique détectée !")
				await repel_magnets(container, magnet1, magnet2, diff)

func can_attract(container: Node, metal_box, magnet_box, direction, distance) -> bool:
	if not container:
		return false

	var metal_tile = GameUtils.pos_to_tile(metal_box.position)

	for i in range(1, distance + 1):
		var check_tile = metal_tile + (-direction * i)

		if i == distance:
			var magnet_tile = GameUtils.pos_to_tile(magnet_box.position)
			if check_tile != magnet_tile:
				return false
			continue

		var wall_layer = container.get_node_or_null("Wall")
		if wall_layer:
			var tile_data = wall_layer.get_cell_tile_data(check_tile)
			if tile_data:
				return false

		for node in container.get_children():
			if GameUtils.is_box(node) and node != metal_box and node != magnet_box:
				var node_tile = GameUtils.pos_to_tile(node.position)
				if node_tile == check_tile:
					return false

	return true

func attract_metal_to_magnet(metal_box, magnet_box, direction, distance) -> void:
	print("🧲 Attraction magnétique à ", distance, " case(s) ! Caisse métal attirée...")

	await shake_metal_box(metal_box)

	var dir_vec2 = Vector2(direction)

	if distance == 2:
		metal_box.is_pushing = true
		var tween = create_tween()
		var intermediate_pos = metal_box.position + (-dir_vec2 * GameUtils.TILE_SIZE)
		tween.tween_property(metal_box, "position", intermediate_pos, 0.25)
		await tween.finished
		metal_box.is_pushing = false

	metal_box.attached_box = magnet_box

	if not magnet_box.attached_metals.has(metal_box):
		magnet_box.attached_metals.append(metal_box)

	print("✅ Caisse métal collée à la caisse magnétique !")

func shake_metal_box(metal_box) -> void:
	var original_pos = metal_box.position
	var shake_amount = 3.0
	var shake_duration = 0.4

	var tween = create_tween()
	tween.set_parallel(true)

	for i in range(6):
		var offset_x = shake_amount if i % 2 == 0 else -shake_amount
		tween.tween_property(metal_box, "position:x", original_pos.x + offset_x, shake_duration / 12.0)

	for i in range(6):
		var offset_y = shake_amount * 0.7 if i % 2 == 0 else -shake_amount * 0.7
		tween.tween_property(metal_box, "position:y", original_pos.y + offset_y, shake_duration / 12.0)

	await tween.finished
	metal_box.position = original_pos


func update_all_magnetic_links(container: Node) -> void:
	if not container:
		return

	for node in container.get_children():
		if GameUtils.is_box(node) and node.color == "metal":
			if node.attached_box != null:
				var link = node.get_meta("magnetic_link", null)
				var magnet = node.attached_box
				if link and is_instance_valid(link) and is_instance_valid(magnet):
					link.clear_points()
					link.add_point(node.position + Vector2(32, 32))
					link.add_point(magnet.position + Vector2(32, 32))

func repel_magnets(container: Node, magnet1, magnet2, direction) -> void:
	if not container:
		return

	var dir1 = -Vector2(direction)
	var dir2 = Vector2(direction)

	var can_move1 = can_magnet_move(container, magnet1, dir1)
	var can_move2 = can_magnet_move(container, magnet2, dir2)

	if can_move1 and can_move2:
		print("🧲 Les deux caisses magnétiques se repoussent !")
		magnet1.is_pushing = true
		magnet2.is_pushing = true

		var tween1 = create_tween()
		var tween2 = create_tween()

		var new_pos1 = magnet1.position + dir1.normalized() * GameUtils.TILE_SIZE
		var new_pos2 = magnet2.position + dir2.normalized() * GameUtils.TILE_SIZE

		tween1.tween_property(magnet1, "position", new_pos1, 0.2)
		tween2.tween_property(magnet2, "position", new_pos2, 0.2)

		await tween1.finished
		await tween2.finished

		magnet1.is_pushing = false
		magnet2.is_pushing = false

		var magnet_movements = {magnet1: dir1, magnet2: dir2}
		await check_and_move_player_from_magnets(container, magnet_movements)

	elif can_move1:
		print("🧲 Caisse magnétique 1 repoussée !")
		magnet1.is_pushing = true
		var tween = create_tween()
		var new_pos = magnet1.position + dir1.normalized() * GameUtils.TILE_SIZE
		tween.tween_property(magnet1, "position", new_pos, 0.2)
		await tween.finished
		magnet1.is_pushing = false

		var magnet_movements = {magnet1: dir1}
		await check_and_move_player_from_magnets(container, magnet_movements)

	elif can_move2:
		print("🧲 Caisse magnétique 2 repoussée !")
		magnet2.is_pushing = true
		var tween = create_tween()
		var new_pos = magnet2.position + dir2.normalized() * GameUtils.TILE_SIZE
		tween.tween_property(magnet2, "position", new_pos, 0.2)
		await tween.finished
		magnet2.is_pushing = false

		var magnet_movements = {magnet2: dir2}
		await check_and_move_player_from_magnets(container, magnet_movements)

	else:
		print("🧲 Caisses magnétiques bloquées ! Impossible de se repousser.")

func can_magnet_move(container: Node, magnet, direction) -> bool:
	if not container:
		return false

	var target_pos = magnet.position + direction.normalized() * GameUtils.TILE_SIZE
	var target_tile = GameUtils.pos_to_tile(target_pos)

	var wall_layer = container.get_node_or_null("Wall")
	if wall_layer:
		var tile_data = wall_layer.get_cell_tile_data(target_tile)
		if tile_data:
			return false

	for node in container.get_children():
		if GameUtils.is_box(node) and node != magnet:
			var node_tile = GameUtils.pos_to_tile(node.position)
			if node_tile == target_tile:
				return false

	return true

func check_and_move_player_from_magnets(container, magnet_movements) -> void:
	var player = container.get_node_or_null("Player")
	if not player:
		return

	var player_tile = GameUtils.pos_to_tile(player.position)

	for magnet in magnet_movements.keys():
		var magnet_tile = GameUtils.pos_to_tile(magnet.position)
		if player_tile == magnet_tile:
			print("⚠️ Le joueur est sur une caisse magnétique ! Poussée automatique...")
			var push_direction = magnet_movements[magnet]
			var target_tile = player_tile + Vector2i(push_direction.normalized())
			var target_pos = GameUtils.tile_to_pos(target_tile)
			print("✅ Déplacement du joueur dans la direction de la répulsion")
			var tween = create_tween()
			tween.tween_property(player, "position", target_pos, 0.15)
			await tween.finished
			return

func are_boxes_adjacent(box1, box2) -> bool:
	var tile1 = GameUtils.pos_to_tile(box1.position)
	var tile2 = GameUtils.pos_to_tile(box2.position)
	var diff = tile2 - tile1
	var manhattan_distance = abs(diff.x) + abs(diff.y)
	return manhattan_distance == 1

func detach_metal_from_magnet(metal, magnet) -> void:
	if not metal or not is_instance_valid(metal) or not magnet or not is_instance_valid(magnet):
		return
	magnet.attached_metals.erase(metal)
	metal.attached_box = null
