extends Node2D

var is_pushing = false
var color = "red"
var is_radioactive = false  # ← NOUVEAU : marque les caisses radioactives
var radioactive_checked = false  # ← Flag pour éviter de vérifier deux fois
var is_magnet = false  # ← NOUVEAU : marque les caisses magnétiques
var attached_box = null  # ← NOUVEAU : caisse attachée (pour les caisses métal collées)
var attached_metals = []  # ← NOUVEAU : caisses métal attachées (pour les caisses magnétiques)

func push(direction):
	# Si la caisse est déjà en train de bouger, on ne fait rien
	if is_pushing:
		return

	# Marque la caisse comme "en train d'être poussée"
	is_pushing = true

	# Crée l'effet de poussière
	create_dust_effect(direction)

	# Calcule la position cible
	var target_pos = position + direction * GameUtils.TILE_SIZE

	# Anime le déplacement de la caisse
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, 0.15)
	tween.finished.connect(func():
		# Sécurité : vérifie que l'objet existe toujours
		if not is_inside_tree():
			return

		is_pushing = false

		# Vérifie s'il y a un téléporteur
		check_teleporter()
	)

func create_dust_effect(push_direction, movement_duration = 0.15):
	# Crée un effet de poussière continu pendant tout le déplacement
	# Émet des particules à intervalles réguliers pendant le mouvement

	var emit_count = 4  # Nombre d'émissions pendant le déplacement
	var emit_interval = movement_duration / emit_count

	for i in range(emit_count):
		emit_dust_burst(push_direction)
		if i < emit_count - 1:  # Pas de pause après la dernière émission
			await get_tree().create_timer(emit_interval).timeout

func emit_dust_burst(push_direction):
	# Crée une salve de particules de poussière
	var dust = CPUParticles2D.new()
	dust.name = "DustEffect"
	dust.one_shot = true
	dust.emitting = true
	dust.amount = 12  # Moins par salve, mais plusieurs salves
	dust.lifetime = 0.6
	dust.explosiveness = 0.8

	# Position en bas de la caisse
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		var texture_size = sprite.texture.get_size() if sprite.texture else Vector2(64, 64)
		if sprite.centered:
			dust.position = Vector2(0, texture_size.y / 2 - 8)  # En bas de la caisse
		else:
			dust.position = Vector2(texture_size.x / 2, texture_size.y - 8)
	else:
		dust.position = Vector2(0, 24)  # Valeur par défaut en bas

	# Direction opposée au mouvement de la caisse
	dust.direction = -push_direction
	dust.spread = 50.0

	# Vitesse des particules
	dust.initial_velocity_min = 50.0
	dust.initial_velocity_max = 100.0

	# Gravité légère vers le bas
	dust.gravity = Vector2(0, 30)

	# Couleur beige/marron plus visible
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.8, 0.7, 0.5, 0.9))
	gradient.add_point(0.4, Color(0.7, 0.6, 0.45, 0.6))
	gradient.add_point(1.0, Color(0.6, 0.5, 0.4, 0.0))
	dust.color_ramp = gradient

	# Taille des particules (un peu réduite)
	dust.scale_amount_min = 2.5
	dust.scale_amount_max = 5.0
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0, 0.6))
	scale_curve.add_point(Vector2(0.2, 1.0))
	scale_curve.add_point(Vector2(0.8, 0.8))
	scale_curve.add_point(Vector2(1, 0.1))
	dust.scale_amount_curve = scale_curve

	# Ajoute les particules à la scène
	add_child(dust)

	# Supprime les particules après qu'elles aient fini
	get_tree().create_timer(dust.lifetime + 0.1).timeout.connect(func():
		if dust and is_instance_valid(dust):
			dust.queue_free()
	)

func create_speed_effect(movement_duration = 0.15):
	# Crée un effet de vitesse avec des traînées fantômes (afterimages)
	var sprite = get_node_or_null("Sprite2D")
	if not sprite or not sprite.texture:
		return

	var ghost_count = 5  # Nombre de traînées
	var ghost_interval = movement_duration / (ghost_count + 1)

	for i in range(ghost_count):
		await get_tree().create_timer(ghost_interval).timeout
		create_ghost_sprite(sprite)

func create_ghost_sprite(original_sprite):
	# Crée une copie fantôme semi-transparente du sprite
	var ghost = Sprite2D.new()
	ghost.texture = original_sprite.texture
	ghost.centered = original_sprite.centered
	ghost.position = position  # Position actuelle de la caisse

	# Effet de transparence et teinte blanchâtre
	ghost.modulate = Color(1.2, 1.2, 1.2, 0.4)  # Blanc semi-transparent

	# Ajoute le fantôme à la scène parente
	get_parent().add_child(ghost)

	# Anime la disparition du fantôme
	var tween = create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.3)
	tween.finished.connect(func():
		ghost.queue_free()
	)

func shake_impact(direction: Vector2 = Vector2.ZERO) -> void:
	var original_pos = position
	var shake_dir = direction if direction != Vector2.ZERO else Vector2(1, 0)
	var tween = create_tween()
	tween.tween_property(self, "position", original_pos + shake_dir * 4.0, 0.05)
	tween.tween_property(self, "position", original_pos - shake_dir * 2.5, 0.05)
	tween.tween_property(self, "position", original_pos + shake_dir * 1.0, 0.04)
	tween.tween_property(self, "position", original_pos, 0.03)
	await tween.finished

func check_teleporter():
	GameUtils.check_and_teleport(self, Vector2.ZERO)  # ← Pas de direction pour les caisses
	
func set_color(new_color: String):
	color = new_color
	# Détecte si c'est une caisse radioactive
	is_radioactive = new_color == "radioactive"
	# Détecte si c'est une caisse magnétique
	is_magnet = new_color == "magnet"

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
			"radioactive":
				sprite.texture = load("res://assets/Crates/crate_06_radio.png")
				add_radioactive_glow()
			"magnet":
				sprite.texture = load("res://assets/Crates/crate_49.png")
				add_magnet_glow()

func add_radioactive_glow():
	# Crée un halo jaune fluorescent autour de la caisse radioactive
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		# Annule l'animation précédente si elle existe
		sprite.set_meta("radioactive_tween", null)

		# Crée un PointLight2D pour le halo fluorescent
		var light = PointLight2D.new()
		light.name = "RadioactiveGlow"
		light.enabled = true
		light.color = Color(1.0, 1.0, 0.0, 1.0)  # Jaune pur
		light.energy = 1.5
		light.texture_scale = 2.0
		light.blend_mode = Light2D.BLEND_MODE_ADD

		# Ajoute la lumière au sprite
		sprite.add_child(light)

		# Animation pulsante du halo
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(light, "energy", 2.0, 0.8)
		tween.tween_property(light, "energy", 1.0, 0.8)

		# Animation de modulation de couleur du sprite
		var color_tween = create_tween()
		color_tween.set_loops()
		color_tween.tween_property(sprite, "self_modulate", Color(1.2, 1.2, 0.8), 0.5)
		color_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.5)

		# Crée des bulles vertes fluorescentes qui s'échappent
		var bubbles = CPUParticles2D.new()
		bubbles.name = "RadioactiveBubbles"
		bubbles.emitting = true
		bubbles.amount = 30
		bubbles.lifetime = 2.5
		bubbles.preprocess = 0.5

		# Position légèrement à gauche, vers le haut
		# Si le sprite est centré, (0,0) est au centre, sinon il faut calculer
		var texture_size = sprite.texture.get_size() if sprite.texture else Vector2(64, 64)
		if sprite.centered:
			bubbles.position = Vector2(-8, -10)
		else:
			bubbles.position = Vector2(texture_size.x / 2 - 8, texture_size.y / 2 - 10)

		# Z-index pour afficher les bulles au-dessus de la caisse
		bubbles.z_index = 10

		# Direction vers le haut
		bubbles.direction = Vector2(0, -1)
		bubbles.spread = 20.0

		# Vitesse lente pour les bulles
		bubbles.initial_velocity_min = 10.0
		bubbles.initial_velocity_max = 20.0
		bubbles.gravity = Vector2(0, -8)  # Bulles qui montent

		# Couleur verte fluorescente
		bubbles.color = Color(0.2, 1.0, 0.2, 0.9)  # Vert fluo
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(0.2, 1.0, 0.2, 0.9))  # Vert fluo opaque au début
		gradient.add_point(0.8, Color(0.3, 1.0, 0.3, 0.5))  # Commence à disparaître
		gradient.add_point(1.0, Color(0.2, 1.0, 0.2, 0.0))  # Transparent à la fin
		bubbles.color_ramp = gradient

		# Taille des bulles (petites et rondes)
		bubbles.scale_amount_min = 1.5
		bubbles.scale_amount_max = 3.0
		var scale_curve = Curve.new()
		scale_curve.add_point(Vector2(0, 0.3))
		scale_curve.add_point(Vector2(0.2, 1.0))  # Bulles qui gonflent
		scale_curve.add_point(Vector2(0.8, 1.1))
		scale_curve.add_point(Vector2(1, 0.5))  # Bulles qui éclatent
		bubbles.scale_amount_curve = scale_curve

		# Ajoute les bulles au sprite pour qu'elles soient au-dessus
		sprite.add_child(bubbles)

		# Crée un deuxième jet de bulles avec des paramètres différents
		var bubbles2 = CPUParticles2D.new()
		bubbles2.name = "RadioactiveBubbles2"
		bubbles2.emitting = true
		bubbles2.amount = 25
		bubbles2.lifetime = 2.8
		bubbles2.preprocess = 1.0  # Décalage temporel pour varier l'effet

		# Position décalée sur le côté
		if sprite.centered:
			bubbles2.position = Vector2(8, -8)
		else:
			bubbles2.position = Vector2(texture_size.x / 2 + 8, texture_size.y / 2 - 8)

		# Z-index pour afficher au-dessus
		bubbles2.z_index = 10

		# Direction vers le haut avec plus de spread
		bubbles2.direction = Vector2(0, -1)
		bubbles2.spread = 25.0

		# Vitesse similaire au premier jet
		bubbles2.initial_velocity_min = 9.0
		bubbles2.initial_velocity_max = 18.0
		bubbles2.gravity = Vector2(0, -7)

		# Couleur verte fluorescente plus visible
		bubbles2.color = Color(0.25, 1.0, 0.25, 0.85)
		var gradient2 = Gradient.new()
		gradient2.add_point(0.0, Color(0.25, 1.0, 0.25, 0.85))
		gradient2.add_point(0.75, Color(0.3, 1.0, 0.3, 0.5))
		gradient2.add_point(1.0, Color(0.2, 1.0, 0.2, 0.0))
		bubbles2.color_ramp = gradient2

		# Bulles de taille intermédiaire
		bubbles2.scale_amount_min = 1.3
		bubbles2.scale_amount_max = 2.5
		var scale_curve2 = Curve.new()
		scale_curve2.add_point(Vector2(0, 0.4))
		scale_curve2.add_point(Vector2(0.3, 1.0))
		scale_curve2.add_point(Vector2(0.9, 0.8))
		scale_curve2.add_point(Vector2(1, 0.3))
		bubbles2.scale_amount_curve = scale_curve2

		# Ajoute le deuxième jet de bulles
		sprite.add_child(bubbles2)

func add_magnet_glow():
	# Crée un halo bleu/rouge magnétique autour de la caisse
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		# Crée un PointLight2D pour le halo magnétique
		var light = PointLight2D.new()
		light.name = "MagnetGlow"
		light.enabled = true
		light.color = Color(1.0, 0.2, 0.2, 1.0)  # Rouge magnétique
		light.energy = 1.8
		light.texture_scale = 2.5
		light.blend_mode = Light2D.BLEND_MODE_ADD

		# Ajoute la lumière au sprite
		sprite.add_child(light)

		# Animation pulsante du halo (rouge -> bleu -> rouge)
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(light, "color", Color(0.2, 0.2, 1.0), 1.2)  # Bleu
		tween.tween_property(light, "color", Color(1.0, 0.2, 0.2), 1.2)  # Rouge

		# Animation d'intensité
		var energy_tween = create_tween()
		energy_tween.set_loops()
		energy_tween.tween_property(light, "energy", 2.5, 0.6)
		energy_tween.tween_property(light, "energy", 1.2, 0.6)

		# Animation de modulation de couleur du sprite
		var color_tween = create_tween()
		color_tween.set_loops()
		color_tween.tween_property(sprite, "self_modulate", Color(1.2, 0.9, 0.9), 0.6)  # Légèrement rouge
		color_tween.tween_property(sprite, "self_modulate", Color(0.9, 0.9, 1.2), 0.6)  # Légèrement bleu
		color_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.6)

		# Crée des particules magnétiques (lignes d'énergie)
		var particles = CPUParticles2D.new()
		particles.name = "MagnetParticles"
		particles.emitting = true
		particles.amount = 20
		particles.lifetime = 1.5
		particles.preprocess = 0.5

		# Position au centre de la caisse
		var texture_size = sprite.texture.get_size() if sprite.texture else Vector2(64, 64)
		if sprite.centered:
			particles.position = Vector2(0, 0)
		else:
			particles.position = Vector2(texture_size.x / 2, texture_size.y / 2)

		# Z-index pour afficher au-dessus
		particles.z_index = 5

		# Émission circulaire
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		particles.emission_sphere_radius = 20.0

		# Direction radiale (vers l'extérieur)
		particles.direction = Vector2(0, -1)
		particles.spread = 180.0

		# Vitesse
		particles.initial_velocity_min = 15.0
		particles.initial_velocity_max = 30.0
		particles.gravity = Vector2.ZERO  # Pas de gravité pour effet magnétique

		# Couleur alternée rouge/bleu
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1.0, 0.2, 0.2, 0.8))  # Rouge opaque
		gradient.add_point(0.5, Color(0.5, 0.2, 0.8, 0.6))  # Violet
		gradient.add_point(1.0, Color(0.2, 0.2, 1.0, 0.0))  # Bleu transparent
		particles.color_ramp = gradient

		# Taille des particules (petites)
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 4.0
		var scale_curve = Curve.new()
		scale_curve.add_point(Vector2(0, 0.8))
		scale_curve.add_point(Vector2(0.5, 1.0))
		scale_curve.add_point(Vector2(1, 0.0))
		particles.scale_amount_curve = scale_curve

		# Ajoute les particules au sprite
		sprite.add_child(particles)
