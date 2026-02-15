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

func close():  # ← NOUVELLE FONCTION
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
	var hole_sprite = get_node_or_null("HoleSprite")

	if closed_sprite:
		closed_sprite.visible = not is_open
	if open_sprite:
		open_sprite.visible = false  # Toujours caché
	if hole_sprite:
		hole_sprite.visible = false  # Toujours caché
