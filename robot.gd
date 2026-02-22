extends Node2D

var is_moving = false
var current_direction = Vector2.DOWN
const MOVE_DURATION = 0.18

func _ready():
	# Direction initiale aléatoire
	var dirs = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	current_direction = dirs[randi() % dirs.size()]
	$AnimatedSprite2D.play("walk_down")
	$AnimatedSprite2D.stop()
	# Délai initial aléatoire pour éviter que plusieurs robots bougent en sync
	await get_tree().create_timer(randf_range(0.2, 1.2)).timeout
	if is_inside_tree():
		pick_next_move()

func pick_next_move():
	if not is_inside_tree():
		return

	var forward_pos = position + current_direction * GameUtils.TILE_SIZE
	var can_go_forward = not has_wall_at(forward_pos) and not has_box_at(forward_pos)

	# 75% de chance de continuer tout droit si possible
	if can_go_forward and randf() < 0.75:
		move(current_direction)
		return

	# Construit les candidats : perpendiculaires en premier, demi-tour en dernier
	var all_dirs = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var perp = []
	for d in all_dirs:
		if d != current_direction and d != -current_direction:
			perp.append(d)
	perp.shuffle()

	var candidates = perp.duplicate()
	if can_go_forward:
		candidates.append(current_direction)
	candidates.append(-current_direction)  # demi-tour en dernier recours

	for d in candidates:
		var tp = position + d * GameUtils.TILE_SIZE
		if not has_wall_at(tp) and not has_box_at(tp):
			# Petite pause avant de tourner (l'animation s'arrête le temps de "réfléchir")
			if d != current_direction:
				$AnimatedSprite2D.frame = 0
				$AnimatedSprite2D.pause()
				await get_tree().create_timer(randf_range(0.1, 0.35)).timeout
				if not is_inside_tree():
					return
			current_direction = d
			move(d)
			return

	# Complètement bloqué : attend et réessaie
	$AnimatedSprite2D.frame = 0
	$AnimatedSprite2D.pause()
	await get_tree().create_timer(randf_range(0.3, 0.7)).timeout
	if not is_inside_tree():
		return
	pick_next_move()

func move(direction):
	if is_moving:
		return

	is_moving = true
	var target_pos = position + direction * GameUtils.TILE_SIZE

	var anim = "walk_down"
	var flip = false
	match direction:
		Vector2.RIGHT: anim = "walk";      flip = false
		Vector2.LEFT:  anim = "walk";      flip = true
		Vector2.UP:    anim = "walk_up"
		Vector2.DOWN:  anim = "walk_down"

	$AnimatedSprite2D.flip_h = flip
	$AnimatedSprite2D.play(anim)

	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, MOVE_DURATION)
	tween.finished.connect(func():
		if not is_inside_tree():
			return
		is_moving = false
		pick_next_move()
	)

func has_wall_at(pos) -> bool:
	var tile_pos = GameUtils.pos_to_tile(pos)

	for node in get_parent().get_children():
		if node.name.begins_with("Door"):
			var door_tile = GameUtils.pos_to_tile(node.position)
			if door_tile == tile_pos:
				return not node.is_open

	var wall_layer = get_parent().get_node_or_null("Wall")
	if wall_layer:
		if wall_layer.get_cell_tile_data(tile_pos):
			return true

	return false

func has_box_at(pos) -> bool:
	return GameUtils.get_object_at(get_parent(), pos, "push") != null
