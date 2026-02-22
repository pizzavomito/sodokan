class_name LevelSpawner

const BOX_SCENE = preload("res://box.tscn")
const ROBOT_SCENE = preload("res://robot.tscn")
const TARGET_SCENE = preload("res://target.tscn")
const TELEPORTER_SCENE = preload("res://teleporter.tscn")
const PARTICLES_SCENE = preload("res://victory_particles.tscn")
const DOOR_SCENE = preload("res://door.tscn")
const LIFE_PICKUP_SCENE = preload("res://life_pickup.tscn")
const UNDO_PICKUP_SCENE = preload("res://undo_pickup.tscn")
const SECRET_WALL_SCENE = preload("res://secret_wall.tscn")

static func spawn_robot(container: Node, pos: Vector2):
	var robot = ROBOT_SCENE.instantiate()
	robot.name = "Robot"
	robot.position = pos
	robot.add_to_group("level_objects")
	container.add_child(robot)

static func spawn_box(container: Node, pos: Vector2, color: String = "red"):
	var box = BOX_SCENE.instantiate()
	box.name = "Box"
	box.position = pos
	box.add_to_group("level_objects")
	container.add_child(box)
	box.set_color(color)

static func spawn_target(container: Node, pos: Vector2, color: String = "red"):
	var target = TARGET_SCENE.instantiate()
	target.name = "Target"
	target.position = pos
	target.add_to_group("targets")
	target.add_to_group("level_objects")
	container.add_child(target)
	target.set_color(color)

static func spawn_door(container: Node, pos: Vector2, current_level: int):
	var door = DOOR_SCENE.instantiate()
	door.position = pos
	door.add_to_group("level_objects")
	container.add_child(door)
	door.name = "Door_" + str(current_level)
	print("Porte créée avec le nom : ", door.name)

static func spawn_teleporter(container: Node, pos: Vector2, teleporter_id: int, linked_id: int):
	var teleporter = TELEPORTER_SCENE.instantiate()
	teleporter.position = pos
	teleporter.add_to_group("level_objects")
	container.add_child(teleporter)
	teleporter.name = "Teleporter_" + str(teleporter_id)
	teleporter.initialize(teleporter_id, linked_id)

static func spawn_undo_pickup(container: Node, pos: Vector2, current_level: int):
	var undo_pickup = UNDO_PICKUP_SCENE.instantiate()
	undo_pickup.name = "UndoPickup"
	undo_pickup.position = pos + Vector2(32, 32)
	undo_pickup.level_id = current_level
	undo_pickup.add_to_group("level_objects")
	container.add_child(undo_pickup)

static func spawn_hidden_undo_pickup(container: Node, pos: Vector2, current_level: int, zone_id: int = 0):
	var undo_pickup = UNDO_PICKUP_SCENE.instantiate()
	undo_pickup.name = "UndoPickup"
	undo_pickup.position = pos + Vector2(32, 32)
	undo_pickup.level_id = current_level

	var fake_wall = Sprite2D.new()
	fake_wall.texture = preload("res://assets/Blocks/block_02.png")
	fake_wall.centered = false
	fake_wall.position = Vector2(-32, -32)
	fake_wall.z_index = 20
	fake_wall.name = "FakeWall"
	undo_pickup.add_child(fake_wall)

	var sprite = undo_pickup.get_node_or_null("Sprite2D")
	if sprite:
		sprite.visible = false

	undo_pickup.set_meta("hidden", true)
	undo_pickup.set_meta("secret_zone_id", zone_id)
	undo_pickup.add_to_group("level_objects")
	container.add_child(undo_pickup)
	print("Undo caché créé dans la zone ", zone_id)

static func spawn_life_pickup(container: Node, pos: Vector2, current_level: int):
	var life = LIFE_PICKUP_SCENE.instantiate()
	life.name = "LifePickup"
	life.position = pos + Vector2(32, 32)
	life.level_id = current_level
	life.add_to_group("level_objects")
	container.add_child(life)

static func spawn_hidden_life_pickup(container: Node, pos: Vector2, current_level: int, zone_id: int = 0):
	var life = LIFE_PICKUP_SCENE.instantiate()
	life.name = "LifePickup"
	life.position = pos + Vector2(32, 32)
	life.level_id = current_level

	var fake_wall = Sprite2D.new()
	fake_wall.texture = preload("res://assets/Blocks/block_02.png")
	fake_wall.centered = false
	fake_wall.position = Vector2(-32, -32)
	fake_wall.z_index = 10
	fake_wall.name = "FakeWall"
	life.add_child(fake_wall)

	var sprite = life.get_node_or_null("Sprite2D")
	if sprite:
		sprite.visible = false

	life.set_meta("hidden", true)
	life.set_meta("secret_zone_id", zone_id)
	life.add_to_group("level_objects")
	container.add_child(life)
	print("Vie cachée créée dans la zone ", zone_id)

static func spawn_secret_wall(container: Node, pos: Vector2, zone_id: int = 0):
	var secret_wall = SECRET_WALL_SCENE.instantiate()
	secret_wall.position = pos
	secret_wall.secret_zone_id = zone_id
	secret_wall.name = "SecretWall_" + str(zone_id)
	secret_wall.add_to_group("level_objects")
	container.add_child(secret_wall)

static func spawn_victory_particles(container: Node, tile_pos: Vector2i):
	var particles = PARTICLES_SCENE.instantiate()
	var pixel_pos = GameUtils.tile_to_pos(tile_pos)
	particles.position = pixel_pos + Vector2(32, 32)
	particles.one_shot = true
	container.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)

static func reveal_secret_zone(container: Node, zone_id: int):
	for node in container.get_children():
		if node.has_meta("hidden") and node.get_meta("hidden"):
			if node.has_meta("secret_zone_id") and node.get_meta("secret_zone_id") == zone_id:
				var fake_wall = node.get_node_or_null("FakeWall")
				if fake_wall:
					var tween = node.create_tween()
					tween.tween_property(fake_wall, "modulate:a", 0.0, 0.5)
					tween.finished.connect(fake_wall.queue_free)

				var sprite = node.get_node_or_null("Sprite2D")
				if sprite:
					sprite.visible = true
					node.start_animation()

				node.set_meta("hidden", false)
				print("   Révélé : ", node.name)
