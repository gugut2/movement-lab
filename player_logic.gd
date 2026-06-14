extends Node3D

var max_speed: float = 12.0
var acceleration: float = 40.0
var friction: float = 25.0
var velocity: Vector3 = Vector3.ZERO

# Atributos de Jogo
var hp: int = 2
var forca_empurrao_ativo: float = 0.0
var caindo: bool = false
var is_dead: bool = false

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

@onready var dust_particles = $DustParticles
@onready var capsula = $PlayerCapsule
var angulo_alvo_y: float = 0.0
var cor_original: Color

func _ready() -> void:
	global_position.y = 1.0
	
	if capsula.get_active_material(0):
		capsula.material_override = capsula.get_active_material(0).duplicate()
		cor_original = capsula.material_override.albedo_color
	else:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLUE
		capsula.material_override = mat
		cor_original = mat.albedo_color

func _process(delta: float) -> void:
	if is_dead:
		return
	
	if caindo:
		global_position.y -= 30.0 * delta
		return

	if Input.is_action_just_pressed("jump") and not is_jumping:
		vertical_velocity = jump_force
		is_jumping = true

	if is_jumping:
		vertical_velocity -= gravity * delta
		global_position.y += vertical_velocity * delta
		
		if global_position.y <= 1.0 and vertical_velocity <= 0.0:
			global_position.y = 1.0
			vertical_velocity = 0.0
			is_jumping = false

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

	var rot_atual_y = capsula.rotation.y
	capsula.rotation.y = lerp_angle(rot_atual_y, angulo_alvo_y, velocidade_rotacao_y * delta)

	var diferenca_angular = wrapf(angulo_alvo_y - rot_atual_y, -PI, PI)
	var intensidade = velocity.length() / max_speed
	var alvo_tilt_x = 0.0
	var alvo_tilt_z = 0.0

	if input_dir != Vector3.ZERO:
		alvo_tilt_x = max_tilt_frente_tras * intensidade
		alvo_tilt_z = clamp(diferenca_angular * 2.0, -1.0, 1.0) * max_tilt_lateral * intensidade

	capsula.rotation.x = lerp_angle(capsula.rotation.x, alvo_tilt_x, suavidade_tilt * delta)
	capsula.rotation.z = lerp_angle(capsula.rotation.z, alvo_tilt_z, suavidade_tilt * delta)

	global_position.x += velocity.x * delta
	global_position.z += velocity.z * delta
	global_position.x = clamp(global_position.x, -3.7, 3.7)
	
	if velocity.length() > 1.0 and not is_jumping and not caindo:
		dust_particles.emitting = true
	else:
		dust_particles.emitting = false

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
	print("JOGADOR CAIU NO BURACO!")
	
	await get_tree().create_timer(0.2).timeout
	morrer("buraco")

func morrer(causa: String) -> void:
	if is_dead: return
	is_dead = true
	dust_particles.emitting = false
	
	# CORREÇÃO CRÍTICA: Chamamos o Ragdoll ANTES de apagar a velocidade, preservando a inércia
	if causa == "avalanche":
		gerar_ragdoll_explosion()
	else:
		gerar_ragdoll_tombamento(causa)
		
	# Agora sim, zeramos o nó original com segurança
	velocity = Vector3.ZERO
	
	await get_tree().create_timer(3.0).timeout
	
	caindo = false
	is_dead = false
	capsula.visible = true
	if capsula.material_override:
		capsula.material_override.albedo_color = cor_original
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
		
		var forca_explosao = Vector3(
			randf_range(-6.0, 6.0),
			randf_range(10.0, 16.0),
			randf_range(-6.0, 6.0)
		)
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

	# Cálculo da física vetorial com dados de velocidade reais recuperados!
	var direcao_movimento = velocity.normalized()
	var velocidade_impacto = velocity.length()
	
	# CORREÇÃO: Inversão do Produto Vetorial para projetar a rotação para frente
	var eixo_alavanca = Vector3.UP.cross(direcao_movimento).normalized()
	
	# Torque de rotação acentuado para chicotear o topo para frente
	var magnitude_alavanca = velocidade_impacto * 1.35
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
