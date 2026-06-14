extends Camera3D

@onready var jogador = $"../Player"

# Configurações de posicionamento e atraso ajustadas para visão antecipada
var altura_camera: float
var recuo_z: float
var velocidade_atraso: float = 6.0

func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = 16.0
	
	# DETECÇÃO AUTOMÁTICA DE FASE
	if "World2" in get_tree().current_scene.name or "Mundo2" in get_tree().current_scene.name or "Fase2" in get_tree().current_scene.name:		# Configuração para a Pista de Gelo (Fase 2) - Suave inclinação de 75º
			altura_camera = 18.0
			recuo_z = 4.5 # Compensação angular para manter o player centralizado
			rotation_degrees = Vector3(-75, 0, 0)
	else:
		# Configuração para A Ladeira (Fase 1) - Visão com Recuo Cinematográfico
		altura_camera = 14.0
		recuo_z = 14.0
		rotation_degrees = Vector3(-60, 0, 0)

func _process(delta: float) -> void:
	if not jogador: return
	
	var posicao_alvo = Vector3(
		jogador.global_position.x,
		altura_camera,
		jogador.global_position.z + recuo_z # Somando o recuo dinâmico aqui
	)
	
	global_position = global_position.lerp(posicao_alvo, velocidade_atraso * delta)
