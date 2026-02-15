extends Control

func _ready():
	# Connecte les signaux des boutons
	$ButtonsContainer/PlayButton.pressed.connect(_on_play_pressed)
	$ButtonsContainer/ResetButton.pressed.connect(_on_reset_pressed) 
	$ButtonsContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _on_play_pressed():
	# Lance le jeu (charge la scène Level)
	get_tree().change_scene_to_file("res://level.tscn")

func _on_reset_pressed():
	# Remet toute la progression à zéro
	SaveManager.last_level_reached = 0
	SaveManager.collected_lives = []
	SaveManager.collected_undos = []
	SaveManager.current_undos = 1
	SaveManager.save_game()
	# Lance depuis le niveau 1
	get_tree().change_scene_to_file("res://level.tscn")
	
func _on_quit_pressed():
	# Quitte le jeu
	get_tree().quit()
