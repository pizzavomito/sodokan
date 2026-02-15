extends Node

const SAVE_FILE = "user://save_game.dat"

var last_level_reached = 0
var collected_lives = []  # ← NOUVEAU : liste des niveaux où les vies ont été collectées

func save_game():
	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file:
		file.store_var({
			"last_level": last_level_reached,
			"collected_lives": collected_lives
		})
		file.close()

func load_game():
	if FileAccess.file_exists(SAVE_FILE):
		var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
		if file:
			var save_data = file.get_var()
			last_level_reached = save_data.get("last_level", 0)
			collected_lives = save_data.get("collected_lives", [])
			file.close()

func update_level(level):
	if level > last_level_reached:
		last_level_reached = level
		save_game()

func collect_life(level_id: int):
	if not level_id in collected_lives:
		collected_lives.append(level_id)
		save_game()

func is_life_collected(level_id: int) -> bool:
	return level_id in collected_lives
