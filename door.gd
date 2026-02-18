extends Node2D

var is_open = false
var can_enter = false

func open():
	if is_open:
		return
	
	is_open = true
	update_visual()
	
	var sound = get_node_or_null("OpenSound")
	if sound:
		sound.play()
	
	await get_tree().create_timer(0.5).timeout
	can_enter = true

func close():
	if not is_open:
		return

	is_open = false
	can_enter = false
	update_visual()

	# Optionnel : son de fermeture
	var sound = get_node_or_null("CloseSound")
	if sound:
		sound.play()

func update_visual():
	var closed_sprite = get_node_or_null("ClosedSprite")
	var open_sprite = get_node_or_null("OpenSprite")

	if is_open:
		# Porte ouverte : affiche le sprite ouvert
		if closed_sprite:
			closed_sprite.visible = false
		if open_sprite:
			open_sprite.visible = true
	else:
		# Porte fermée : affiche le sprite fermé
		if closed_sprite:
			closed_sprite.visible = true
		if open_sprite:
			open_sprite.visible = false
