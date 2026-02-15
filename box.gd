extends Node2D

var is_pushing = false
var color = "red"

func push(direction):
	# Si la caisse est déjà en train de bouger, on ne fait rien
	if is_pushing:
		return
		
	# Marque la caisse comme "en train d'être poussée"
	is_pushing = true
	
	# Calcule la position cible
	var target_pos = position + direction * GameUtils.TILE_SIZE
	
	# Anime le déplacement de la caisse
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, 0.15)
	tween.finished.connect(func(): 
		is_pushing = false
		
		# Vérifie s'il y a un téléporteur
		check_teleporter()
	)

func check_teleporter():
	GameUtils.check_and_teleport(self, Vector2.ZERO)  # ← Pas de direction pour les caisses
	
func set_color(new_color: String):
	color = new_color
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		match color:
			"red":
				sprite.texture = load("res://assets/Crates/crate_03.png")
			"green":
				sprite.texture = load("res://assets/Crates/crate_05.png")
			"blue":
				sprite.texture = load("res://assets/Crates/crate_04.png")
			"wood":
				sprite.texture = load("res://assets/Crates/crate_02.png")
			"metal":
				sprite.texture = load("res://assets/Crates/crate_06.png")
