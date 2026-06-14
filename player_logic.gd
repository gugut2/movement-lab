extends Area3D

var max_speed: float = 12.0
var acceleration: float = 40.0
var friction: float = 25.0
var velocity: Vector3 = Vector3.ZERO

# Atributos de Jogo
var hp: int = 2
var forca_empurrao_ativo: float = 0.0
var caindo: bool = false
var is_dead: bool = false

# Mecânica de Gelo Modular (Funciona em qualquer fase)
enum EixoGelo { NENHUM, X, Z }
var eixo_travado: EixoGelo = EixoGelo.NENHUM
var sinal_eixo_travado: float = 1.0
var fixed_sliding_speed: float = 14.0
var fase_1_ativa: bool = true

# Física do Pulo (Eixo Y)
var jump_force: float = 15.0
var pulo_gravidade: float = 45.0 # CORRIGIDO: Nome alterado para evitar conflito com a classe Area3D
var vertical_velocity: float = 0.0
var is_jumping: bool = false

# Inércia Visual (Tilt)
var max_tilt_frente_tras: float = deg_to_rad(15.0)
var max_tilt_lateral: float = deg_to_rad(10.0)
var suavidade_tilt: float = 5.0
var velocidade_rotacao_y: float = 12.0

var centro_pista_atual: Vector3 = Vector3.ZERO

@onready var dust_particles = $DustParticles
@onready var capsula = $PlayerCapsule
var angulo_alvo_y: float = 0.0
var cor_original: Color

func _ready() -> void:
	global_position.y = 1.0
	
	# Auto-detecta a fase para desativar a trava lateral de borda fixa na Fase 2
	if "World2" in get_tree().current_scene.name or "Fase2" in get_tree().current_scene.name:
		fase_1_ativa = false
	
	if capsula.get_active_material(0):
		capsula.material_override = capsula.get_active_material(0).duplicate()
		cor_original = capsula.material_override.albedo_color
	else:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLUE
		capsula.material_override = mat
		cor_original = mat.albedo_color

func _physics_process(delta: float) -> void:
	if is_dead: return
	if caindo:
		global_position.y -= 30.0 * delta
		return

	# Entrada do Comando de Pulo
	if Input.is_action_just_pressed("jump") and not is_jumping:
		vertical_velocity = jump_force
		is_jumping = true

	# Processamento da Gravidade do Pulo
	if is_jumping:
		vertical_velocity -= pulo_gravidade * delta # CORRIGIDO
		global_position.y += vertical_velocity * delta
		
		if global_position.y <= 1.0 and vertical_velocity <= 0.0:
			global_position.y = 1.0
			vertical_velocity = 0.0
			is_jumping = false

	# Captura de Movimento Horizontal
	var input_x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var input_z = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	# CONTROLE DE TRÁFEGO (NORMAL VS GELO)
	if eixo_travado == EixoGelo.NENHUM:
		var input_dir = Vector3(input_x, 0, input_z)
		if input_dir.length() > 1.0: input_dir = input_dir.normalized()
		
		if input_dir != Vector3.ZERO:
			velocity = velocity.move_toward(input_dir * max_speed, acceleration * delta)
			angulo_alvo_y = atan2(-input_dir.x, -input_dir.z)
		else:
			velocity = velocity.move_toward(Vector3.ZERO, friction * delta)
	else:
		# MODULARIDADE: Se pisar no gelo em QUALQUER fase, essa lógica assume o controle
		if eixo_travado == EixoGelo.Z:
			velocity.z = fixed_sliding_speed * sinal_eixo_travado
			if input_x != 0:
				velocity.x = move_toward(velocity.x, input_x * max_speed, acceleration * 1.5 * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, friction * 0.3 * delta)
			angulo_alvo_y = atan2(-velocity.x, -velocity.z)
			
		elif eixo_travado == EixoGelo.X:
			velocity.x = fixed_sliding_speed * sinal_eixo_travado
			if input_z != 0:
				velocity.z = move_toward(velocity.z, input_z * max_speed, acceleration * 1.5 * delta)
			else:
				velocity.z = move_toward(velocity.z, 0.0, friction * 0.3 * delta)
			angulo_alvo_y = atan2(-velocity.x, -velocity.z)

	# Cooldown de Empurrão de Impacto (Fase 1)
	if forca_empurrao_ativo != 0.0:
		velocity.z = forca_empurrao_ativo
		forca_empurrao_ativo = move_toward(forca_empurrao_ativo, 0.0, friction * 2.0 * delta)

	# Rotação do Corpo
	var rot_atual_y = capsula.rotation.y
	capsula.rotation.y = lerp_angle(rot_atual_y, angulo_alvo_y, velocidade_rotacao_y * delta)

	# Tilts Estéticos
	var diferenca_angular = wrapf(angulo_alvo_y - rot_atual_y, -PI, PI)
	var intensidade = velocity.length() / max_speed
	var alvo_tilt_x = max_tilt_frente_tras * intensidade if velocity.length() > 1.0 else 0.0
	var alvo_tilt_z = clamp(diferenca_angular * 2.0, -1.0, 1.0) * max_tilt_lateral * intensidade

	capsula.rotation.x = lerp_angle(capsula.rotation.x, alvo_tilt_x, suavidade_tilt * delta)
	capsula.rotation.z = lerp_angle(capsula.rotation.z, alvo_tilt_z, suavidade_tilt * delta)

	# Translação física global
	global_position.x += velocity.x * delta
	global_position.z += velocity.z * delta
	
	if fase_1_ativa:
		global_position.x = clamp(global_position.x, -3.7, 3.7)
	else:
		# RESOLUÇÃO DE GEOMETRIA FÍSICA DA FASE 2
		# Se a cápsula interceptar qualquer parede invisível, ela é travada milimetricamente
		for area in get_overlapping_areas():
			if area.is_in_group("paredes_invisiveis"):
				var eixo = area.get_meta("eixo")
				var sinal = area.get_meta("sinal")
				
				if eixo == "X":
					if sinal == 1.0 and global_position.x > area.global_position.x - 0.5:
						global_position.x = area.global_position.x - 0.5
						velocity.x = 0
					elif sinal == -1.0 and global_position.x < area.global_position.x + 0.5:
						global_position.x = area.global_position.x + 0.5
						velocity.x = 0
				elif eixo == "Z":
					if sinal == 1.0 and global_position.z > area.global_position.z - 0.5:
						global_position.z = area.global_position.z - 0.5
						velocity.z = 0
					elif sinal == -1.0 and global_position.z < area.global_position.z + 0.5:
						global_position.z = area.global_position.z + 0.5
						velocity.z = 0
	
	dust_particles.emitting = velocity.length() > 1.0 and not is_jumping and not caindo

func aplicar_mecanica_gelo(direcao_pista: Vector3, centro_bloco: Vector3) -> void:
	centro_pista_atual = centro_bloco
	if abs(direcao_pista.x) > abs(direcao_pista.z):
		eixo_travado = EixoGelo.X
		sinal_eixo_travado = sign(direcao_pista.x)
	else:
		eixo_travado = EixoGelo.Z
		sinal_eixo_travado = sign(direcao_pista.z)

func desativar_mecanica_gelo(centro_bloco: Vector3) -> void:
	eixo_travado = EixoGelo.NENHUM
	centro_pista_atual = centro_bloco

func tomar_dano_e_empurrante(dano: int, forca: float, causa: String = "barreira") -> void:
	if is_dead: return
	hp -= dano
	if hp <= 0:
		morrer(causa)
		return
	forca_empurrao_ativo = forca
	if capsula.material_override:
		capsula.material_override.albedo_color = Color.RED

func cair_no_buraco() -> void:
	if caindo or is_dead: return
	caindo = true
	await get_tree().create_timer(0.2).timeout
	morrer("buraco")

func morrer(causa: String) -> void:
	if is_dead: return
	is_dead = true
	dust_particles.emitting = false
	
	if causa == "avalanche":
		gerar_ragdoll_explosion()
	else:
		gerar_ragdoll_tombamento(causa)
		
	velocity = Vector3.ZERO
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()

func gerar_ragdoll_explosion() -> void:
	capsula.visible = false
	for i in range(6):
		var corpo_fisico = RigidBody3D.new()
		var mesh_pedaço = MeshInstance3D.new()
		var cubo_mesh = BoxMesh.new()
		var colisor = CollisionShape3D.new()
		var formato_caixa = BoxShape3D.new()
		
		var dimensoes = Vector3(0.5, 0.5, 0.5)
		cubo_mesh.size = dimensoes
		formato_caixa.size = dimensoes
		mesh_pedaço.mesh = cubo_mesh
		colisor.shape = formato_caixa
		corpo_fisico.add_child(mesh_pedaço)
		corpo_fisico.add_child(colisor)
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = cor_original
		mesh_pedaço.material_override = mat
		get_parent().add_child(corpo_fisico)
		
		corpo_fisico.global_position = global_position + Vector3(randf_range(-0.2, 0.2), randf_range(0.2, 1.2), randf_range(-0.2, 0.2))
		var forca_explosao = Vector3(randf_range(-6.0, 6.0), randf_range(10.0, 16.0), randf_range(-6.0, 6.0))
		corpo_fisico.apply_central_impulse(forca_explosao)
		corpo_fisico.apply_torque_impulse(Vector3(randf_range(-15, 15), randf_range(-15, 15), randf_range(-15, 15)))

func gerar_ragdoll_tombamento(causa: String) -> void:
	capsula.visible = false
	var boneco_fisico = RigidBody3D.new()
	var mesh_capsula = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	var colisor = CollisionShape3D.new()
	var formato_capsula = CapsuleShape3D.new()
	
	mesh_capsula.mesh = capsule_mesh
	colisor.shape = formato_capsula
	boneco_fisico.add_child(mesh_capsula)
	boneco_fisico.add_child(colisor)
	mesh_capsula.material_override = capsula.material_override
	
	var mat_fisico = PhysicsMaterial.new()
	mat_fisico.friction = 0.4
	mat_fisico.bounce = 0.02
	boneco_fisico.physics_material_override = mat_fisico
	get_parent().add_child(boneco_fisico)
	
	boneco_fisico.global_transform = capsula.global_transform
	boneco_fisico.global_position.y += 0.05 

	var dir_mov = velocity.normalized() if velocity.length() > 0.1 else Vector3.FORWARD
	var velocidade_impacto = velocity.length()
	var eixo_alavanca = Vector3.UP.cross(dir_mov).normalized()
	
	var magnitude_alavanca = velocidade_impacto * 1.35 if velocidade_impacto > 0.1 else 5.0
	boneco_fisico.angular_velocity = eixo_alavanca * magnitude_alavanca
	boneco_fisico.angular_velocity.y = randf_range(-0.4, 0.4)

	if causa == "low":
		boneco_fisico.linear_velocity = velocity * 0.8
		boneco_fisico.linear_velocity.y = 3.0 
	elif causa == "high":
		boneco_fisico.linear_velocity = velocity * 0.35
		boneco_fisico.linear_velocity.y = 0.5
	else:
		boneco_fisico.linear_velocity = velocity
