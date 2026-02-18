extends Node

var whistle_sounds = [
	preload("res://sounds/whistles/whistle1.mp3"),
	preload("res://sounds/whistles/whistle2.mp3"),
	preload("res://sounds/whistles/whistle3.mp3"),
	preload("res://sounds/whistles/whistle4.mp3"),
	preload("res://sounds/whistles/whistle5.mp3"),
	preload("res://sounds/whistles/whistle6.mp3"),
	preload("res://sounds/whistles/whistle7.mp3"),
]

var voice_sounds = [
	preload("res://sounds/voices/voice1.mp3"),
	preload("res://sounds/voices/voice2.mp3"),
	preload("res://sounds/voices/voice3.mp3"),
	preload("res://sounds/voices/voice4.mp3"),
]

var background_musics = [
	preload("res://sounds/music_1.mp3"),
	preload("res://sounds/music_2.mp3"),
]

var whistle_timer = 0.0
var next_whistle_delay = 0.0

# Références aux nœuds audio, assignées par level.gd au démarrage
var _whistle_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer

func setup(whistle_player: AudioStreamPlayer, voice_player: AudioStreamPlayer, music_player: AudioStreamPlayer):
	_whistle_player = whistle_player
	_voice_player = voice_player
	_music_player = music_player
	randomize()
	schedule_next_whistle()

func _process(delta):
	if not _whistle_player:
		return
	whistle_timer += delta
	if whistle_timer >= next_whistle_delay:
		play_random_whistle()

func schedule_next_whistle():
	next_whistle_delay = randf_range(8.0, 20.0)
	whistle_timer = 0.0

func play_random_whistle():
	if not _whistle_player or not _voice_player:
		return
	if _voice_player.playing:
		schedule_next_whistle()
		return
	_whistle_player.stream = whistle_sounds[randi() % whistle_sounds.size()]
	_whistle_player.play()
	schedule_next_whistle()

func play_random_voice():
	if not _whistle_player or not _voice_player:
		return
	if _whistle_player.playing:
		_whistle_player.stop()
	_voice_player.stream = voice_sounds[randi() % voice_sounds.size()]
	_voice_player.play()
	schedule_next_whistle()

func change_music_for_level(level_index: int):
	if not _music_player:
		return
	var music_index = min(int(level_index / 10), background_musics.size() - 1)
	if _music_player.stream == background_musics[music_index]:
		return
	var tween = _music_player.create_tween()
	tween.tween_property(_music_player, "volume_db", -80, 1.0)
	await tween.finished
	_music_player.stream = background_musics[music_index]
	_music_player.play()
	tween = _music_player.create_tween()
	tween.tween_property(_music_player, "volume_db", -15, 1.0)
