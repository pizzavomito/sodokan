extends ColorRect

# Liste des configs glitch actives
var glitch_configs: Array = []
# Timers et état pour chaque glitch
var glitch_states: Array = []

const INTERVAL_MIN = 3.0
const INTERVAL_MAX = 8.0

# @onready var glitch_shader = preload("res://glitch_effect.gdshader")
#@onready var glitch_shader = preload("res://test_shader.gdshader")

func _ready():
	# Invisible par défaut
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	#if material and material is ShaderMaterial:
	#	material = material.duplicate(true)

func setup(configs: Array):

	stop_all()
	glitch_configs = configs
	glitch_states.clear()

	if configs.size() == 0:
		visible = false
		return

	visible = false
	# Intensité à 0 par défaut (pas de glitch visible)
	material.set_shader_parameter("glitch_intensity", 0.0)

	for i in range(configs.size()):
		var config = configs[i]
		var state = {
			"type": config.get("type", 1),
			"count": config.get("count", -1),
			"remaining": config.get("count", -1),
			"delay": config.get("delay", 0.0),
			"duration": config.get("duration", 0.3),
			"waiting_delay": true,
			"active": false,
			"timer": 0.0,
		}
		glitch_states.append(state)

		# Démarre le délai initial
		if state.delay > 0.0:
			state.timer = state.delay
		else:
			state.waiting_delay = false
			state.timer = randf_range(INTERVAL_MIN, INTERVAL_MAX)

func _process(delta):
	if glitch_states.size() == 0:
		return

	var any_active = false

	for state in glitch_states:
		# Si le glitch a épuisé ses déclenchements
		if state.remaining == 0:
			continue

		state.timer -= delta

		if state.active:
			# Le glitch est en cours d'affichage
			any_active = true
			if state.timer <= 0.0:
				# Fin du glitch
				state.active = false
				# Décompte
				if state.remaining > 0:
					state.remaining -= 1
				# Prochain intervalle
				if state.remaining != 0:
					state.timer = randf_range(INTERVAL_MIN, INTERVAL_MAX)
		else:
			# En attente
			if state.timer <= 0.0:
				if state.waiting_delay:
					# Le délai initial est fini
					state.waiting_delay = false
					state.timer = randf_range(INTERVAL_MIN, INTERVAL_MAX)
				else:
					print('Glitch !')
					# Déclenche le glitch
					state.active = true
					state.timer = state.duration
					any_active = true

	# Applique l'état au shader
	if any_active:
		# Trouve le premier glitch actif pour le type
		for state in glitch_states:
			if state.active:
				print('Glitch active !')
				material.set_shader_parameter("glitch_type", state.type)
				material.set_shader_parameter("glitch_intensity", 1.0)
				material.set_shader_parameter("time_offset", randf() * 100.0)
				break
	else:
		material.set_shader_parameter("glitch_intensity", 0.0)

func stop_all():
	glitch_states.clear()
	glitch_configs.clear()
	if material:
		material.set_shader_parameter("glitch_intensity", 0.0)
	visible = false
