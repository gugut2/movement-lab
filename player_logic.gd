extends Node3D

var max_speed: float = 12.0
var acceleration: float = 40.0
var friction: float = 25.0
var velocity: Vector3 = Vector3.ZERO

# Atributos de Jogo
var hp: int = 2
var forca_empurrao_ativo: float = 0.0
var caindo: bool = false

# Física do Pulo (Eixo Y)
var jump_force: float = 15.0
var gravity: float = 45.0
var vertical_velocity: float = 0.0
var is_jumping: bool = false

# Inércia Visual (Tilt)
var max_tilt_frente_tras: float = deg_to_rad(15.0)
var max_tilt_lateral: float = deg_to_rad(10.0)
var suavidade_tilt: float = 5.0
var velocidade_rotacao_y: float = 12.0

@onready var capsula = $PlayerCapsule
var angulo_alvo_y: float = 0.0
var cor_original: Color

func _ready() -> void:
	if capsula.get_active_material(0):
		capsula.material_override = capsula.get_active_material(0).duplicate()
		cor_original = capsula.material_override.albedo_color
	else:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLUE
		capsula.material_override = mat
		cor_original = mat.albedo_color

func _process(delta: float) -> void:
	# Se caiu no buraco, executa a animação de queda infinita para baixo
	if caindo:
		global_position.y -= 30.0 * delta
		return

	# Entrada do Comando de Pulo
	if Input.is_action_just_pressed("jump") and not is_jumping:
		vertical_velocity = jump_force
		is_jumping = true

	# Processamento da Gravidade do Pulo
	if is_jumping:
		vertical_velocity -= gravity * delta
		global_position.y += vertical_velocity * delta
		
		# Checa se tocou o chão novamente (altura padrão do Player é Y=1)
		if global_position.y <= 1.0:
			global_position.y = 1.0
			vertical_velocity = 0.0
			is_jumping = false

	# Captura de Movimento Horizontal (X/Z)
	var input_dir := Vector3.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.z = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	if input_dir != Vector3.ZERO:
		velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
		angulo_alvo_y = atan2(-input_dir.x, -input_dir.z)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, friction * delta)

	if forca_empurrao_ativo != 0.0:
		velocity.z = forca_empurrao_ativo
		forca_empurrao_ativo = move_toward(forca_empurrao_ativo, 0.0, friction * 2.0 * delta)

	# Rotação do Corpo
	var rot_atual_y = capsula.rotation.y
	capsula.rotation.y = lerp_angle(rot_atual_y, angulo_alvo_y, velocidade_rotacao_y * delta)

	# Aplicação de Tilts Estéticos de Curva
	var diferenca_angular = wrapf(angulo_alvo_y - rot_atual_y, -PI, PI)
	var intensidade = velocity.length() / max_speed
	var alvo_tilt_x = 0.0
	var alvo_tilt_z = 0.0

	if input_dir != Vector3.ZERO:
		alvo_tilt_x = max_tilt_frente_tras * intensidade
		alvo_tilt_z = clamp(diferenca_angular * 2.0, -1.0, 1.0) * max_tilt_lateral * intensidade

	capsula.rotation.x = lerp_angle(capsula.rotation.x, alvo_tilt_x, suavidade_tilt * delta)
	capsula.rotation.z = lerp_angle(capsula.rotation.z, alvo_tilt_z, suavidade_tilt * delta)

	# Translação e Trava Física de Borda de Pista
	global_position.x += velocity.x * delta
	global_position.z += velocity.z * delta
	global_position.x = clamp(global_position.x, -3.7, 3.7)

func tomar_dano_e_empurrante(dano: int, forca: float) -> void:
	hp -= dano
	forca_empurrao_ativo = forca
	if capsula.material_override:
		capsula.material_override.albedo_color = Color.RED
	if hp <= 0:
		morrer()

func cair_no_buraco() -> void:
	if caindo: return
	caindo = true
	print("JOGADOR CAIU NO BURACO! MORTE INSTANTÂNEA.")
	await get_tree().create_timer(0.4).timeout
	caindo = false
	global_position.y = 1.0
	if capsula.material_override:
		capsula.material_override.albedo_color = cor_original
	get_tree().reload_current_scene()

func morrer() -> void:
	print("JOGADOR MORREU SOTERRADO!")
	if capsula.material_override:
		capsula.material_override.albedo_color = cor_original
	get_tree().reload_current_scene()
