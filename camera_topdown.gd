extends Camera3D

@onready var jogador = $"../Player"

# Configurações de posicionamento e atraso ajustadas para visão antecipada
var altura_camera: float = 14.0
var recuo_z: float = 14.0          # Aumentado para posicionar o player a 2/3 do topo
var velocidade_atraso: float = 6.0 

func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = 16.0
	rotation_degrees = Vector3(-60, 0, 0)

func _process(delta: float) -> void:
	if not jogador: return
	
	var posicao_alvo = Vector3(
		jogador.global_position.x,
		altura_camera,
		jogador.global_position.z + recuo_z
	)
	
	global_position = global_position.lerp(posicao_alvo, velocidade_atraso * delta)
