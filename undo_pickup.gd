extends Node2D

var level_id : int = 0
var is_collected : bool = false

func _ready():
	# Animation de rotation continue
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property($Sprite2D, "rotation", TAU, 1.0).set_trans(Tween.TRANS_LINEAR)
	
	# Rebond vertical (optionnel)
	var bounce_tween = create_tween()
	bounce_tween.set_loops()
	bounce_tween.tween_property(self, "position:y", position.y - 5, 0.6).set_trans(Tween.TRANS_SINE)
	bounce_tween.tween_property(self, "position:y", position.y, 0.6).set_trans(Tween.TRANS_SINE)

func collect():
	if is_collected:
		return
	
	is_collected = true
	name = "UndoPickup_Collected"
	
	$Sprite2D.visible = false
	
	var sound = get_node_or_null("PickupSound")
	if sound:
		sound.play()
		await sound.finished
	
	queue_free()
