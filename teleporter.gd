extends Node2D

var teleporter_id : int = 0
var linked_teleporter_id : int = 0

func _ready():
	# Animation de flottement pour le sprite
	var floating_sprite = get_node_or_null("FloatingSprite")
	if floating_sprite:
		start_floating_animation(floating_sprite)

func start_floating_animation(sprite: Sprite2D):
	# Crée une animation continue de flottement
	var tween = create_tween()
	tween.set_loops()  # Boucle infinie

	# Anime vers le haut
	tween.tween_property(sprite, "position:y", -20, 1.5)
	# Anime vers le bas
	tween.tween_property(sprite, "position:y", 0, 1.5)

func initialize(tp_id: int, linked_id: int):
	teleporter_id = tp_id
	linked_teleporter_id = linked_id
