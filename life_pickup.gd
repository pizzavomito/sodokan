extends Node2D

var level_id : int = 0
var is_collected : bool = false  # ← NOUVEAU flag
var color = ""

func _ready():
	# Animation de rotation pièce SANS déplacement
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property($Sprite2D, "scale:x", -1.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property($Sprite2D, "scale:x", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	# Rebond vertical (optionnel)
	var bounce_tween = create_tween()
	bounce_tween.set_loops()
	bounce_tween.tween_property(self, "position:y", position.y - 5, 0.6).set_trans(Tween.TRANS_SINE)
	bounce_tween.tween_property(self, "position:y", position.y, 0.6).set_trans(Tween.TRANS_SINE)

func collect():
	if is_collected:
		return
	
	is_collected = true
	
	# Change le nom pour empêcher re-collecte
	name = "LifePickup_Collected"
	
	# Cache le sprite
	$Sprite2D.visible = false
	
	# Son
	var sound = get_node_or_null("PickupSound")
	if sound:
		sound.play()
		await sound.finished
	
	queue_free()
