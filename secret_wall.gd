extends Node2D

var is_revealed = false
var secret_zone_id = 0  # ID de la zone secrète associée

func _ready():
	pass

func reveal():
	if is_revealed:
		return

	is_revealed = true

	# Effet visuel de révélation (fade out du mur secret)
	var tween = create_tween()
	tween.tween_property($Sprite2D, "modulate:a", 0.3, 0.5)

	# Révèle tous les éléments cachés de la même zone
	LevelSpawner.reveal_secret_zone(get_parent(), secret_zone_id)

	print("🎉 Easter egg découvert ! Zone secrète ", secret_zone_id, " révélée !")
