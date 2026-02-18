extends Node2D

var color = "red"

func set_color(new_color: String):
	color = new_color
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		match color:
			"red":
				sprite.texture = load("res://assets/Crates/crate_28.png")
			"green":
				sprite.texture = load("res://assets/Crates/crate_30.png")
			"blue":
				sprite.texture = load("res://assets/Crates/crate_29.png")
			"wood":
				sprite.texture = load("res://assets/Crates/crate_27.png")
			"metal":
				sprite.texture = load("res://assets/Crates/crate_31.png")
			"radioactive":
				sprite.texture = load("res://assets/Crates/crate_48.png")
			"magnet":
				sprite.texture = load("res://assets/Crates/crate_50.png")
