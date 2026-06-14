extends Node3D

@onready var jogador = $Player
@onready var container = $ChunksContainer

var tamanho_chunk: float = 20.0
var proxima_posicao_z: float = 0.0
var chunks_visiveis: int = 5
var distancia_vitoria: float = 480.0
var jogo_finalizado: bool = false

# Avalanche
var avalanche_mesh: MeshInstance3D
var avalanche_z: float = -15.0
var velocidade_base_avalanche: float = 9.5
var cooldown_ataque: float = 0.0

# Grid e Balanço Separado
var colunas_x: Array = [-2.5, 0.0, 2.5]
var posicoes_obstaculos_ativos: Array[Dictionary] = []
var posicoes_buracos_ativos: Array[Dictionary] = []

func _ready() -> void:
	for i in range(chunks_visiveis):
		criar_chunk(i == 0)
	criar_objeto_avalanche()
	criar_portal_de_ouro()

func _process(delta: float) -> void:
	if jogo_finalizado or jogador.is_dead: return
	
	if jogador.global_position.z >= distancia_vitoria:
		vitoria()
		return

	if jogador.global_position.z > proxima_posicao_z - (chunks_visiveis * tamanho_chunk):
		criar_chunk(false)
		limpar_chunks_antigos()

	processar_avalanche(delta)
	processar_colisao_obstaculos()
	processar_queda_buracos()

func criar_chunk(vazio: bool) -> void:
	var chunk_node = Node3D.new()
	chunk_node.position = Vector3(0, 0, proxima_posicao_z)
	container.add_child(chunk_node)

	# 1. PARTE VISUAL DO CHÃO
	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(8, tamanho_chunk)
	mesh_instance.mesh = plane_mesh
	mesh_instance.position = Vector3(0, 0, tamanho_chunk / 2)
	chunk_node.add_child(mesh_instance)
	
	# 2. PARTE FÍSICA DO CHÃO
	var corpo_estatico = StaticBody3D.new()
	var colisor_chao = CollisionShape3D.new()
	var formato_caixa = BoxShape3D.new()
	
	formato_caixa.size = Vector3(8.0, 0.2, tamanho_chunk)
	colisor_chao.shape = formato_caixa

	corpo_estatico.add_child(colisor_chao)
	chunk_node.add_child(corpo_estatico)
	corpo_estatico.position = Vector3(0, -0.1, tamanho_chunk / 2)

	# 3. GERAÇÃO DE PERIGOS DESACOPLADOS
	if not vazio:
		processar_tokens_e_spawn(chunk_node)

	proxima_posicao_z += tamanho_chunk

func processar_tokens_e_spawn(chunk_node: Node3D) -> void:
	var progresso = clamp(proxima_posicao_z / distancia_vitoria, 0.0, 1.0)

	# ==========================================
	# 1. SISTEMA DE TOKENS: BARREIRAS (CUBOS)
	# ==========================================
	var max_barreiras_chunk = 2 if progresso < 0.5 else 3
	var qtd_barreiras = randi_range(1, max_barreiras_chunk)
	
	var lista_barreiras_definidas = []
	for i in range(qtd_barreiras):
		var type = "high" if randf() < 0.5 else "low"
		lista_barreiras_definidas.append(type)
		
	if lista_barreiras_definidas.size() == 3:
		if not "low" in lista_barreiras_definidas:
			lista_barreiras_definidas[randi() % 3] = "low"

	# CORREÇÃO: Linhas fixas de barreiras recuadas para abrir espaço para os abismos
	var cubos_linha_front = []
	var cubos_linha_back = []
	var colunas_b = colunas_x.duplicate()
	colunas_b.shuffle()

	for b_type in lista_barreiras_definidas:
		var cx = colunas_b.pop_front()
		if cubos_linha_front.size() <= cubos_linha_back.size():
			cubos_linha_front.append({"x": cx, "type": b_type})
		else:
			cubos_linha_back.append({"x": cx, "type": b_type})

	processar_cubos_linha(chunk_node, cubos_linha_front, 4.0)
	processar_cubos_linha(chunk_node, cubos_linha_back, 13.0)

	# ==========================================
	# 2. SISTEMA DE TOKENS: BURACOS (ORGANICOS)
	# ==========================================
	var max_buracos_chunk = 2 if progresso < 0.3 else (4 if progresso < 0.7 else 5)
	var qtd_buracos = randi_range(2, max_buracos_chunk)

	# CORREÇÃO: Faixas Z alteradas para que NUNCA entrem no perímetro das barreiras (4.0 e 13.0)
	var hole_z1 = randf_range(8.5, 10.5)
	var hole_z2 = randf_range(17.0, 19.0)
	
	var buracos_linha_a = []
	var buracos_linha_b = []
	var colunas_h = colunas_x.duplicate()
	colunas_h.shuffle()

	for i in range(qtd_buracos):
		if colunas_h.is_empty():
			colunas_h = colunas_x.duplicate()
			colunas_h.shuffle()
		
		var cx = colunas_h.pop_front()
		if buracos_linha_a.size() <= buracos_linha_b.size():
			buracos_linha_a.append(cx)
		else:
			buracos_linha_b.append(cx)

	var buracos_criados_no_chunk = []
	processar_buracos_linha(chunk_node, buracos_linha_a, hole_z1, buracos_criados_no_chunk)
	processar_buracos_linha(chunk_node, buracos_linha_b, hole_z2, buracos_criados_no_chunk)

	processar_uniao_diagonal_buracos(chunk_node, buracos_criados_no_chunk)

func processar_cubos_linha(chunk_node: Node3D, lista_cubos: Array, linha_z: float) -> void:
	if lista_cubos.size() == 0: return
	lista_cubos.sort_custom(func(a, b): return a["x"] < b["x"])

	if lista_cubos.size() == 2:
		var c1 = lista_cubos[0]
		var c2 = lista_cubos[1]
		if c1["type"] == "c2[type]" or (c1["type"] == c2["type"] and abs(c1["x"] - c2["x"]) == 2.5):
			var mid_x = (c1["x"] + c2["x"]) / 2.0
			criar_cubo_fisico(chunk_node, mid_x, linha_z, 4.3, c1["type"])
		else:
			criar_cubo_fisico(chunk_node, c1["x"], linha_z, 1.8, c1["type"])
			criar_cubo_fisico(chunk_node, c2["x"], linha_z, 1.8, c2["type"])
			
	elif lista_cubos.size() == 3:
		var le = lista_cubos[0]
		var ce = lista_cubos[1]
		var di = lista_cubos[2]
		
		if le["type"] == ce["type"]:
			criar_cubo_fisico(chunk_node, -1.25, linha_z, 4.3, le["type"])
			criar_cubo_fisico(chunk_node, di["x"], linha_z, 1.8, di["type"])
		elif ce["type"] == di["type"]:
			criar_cubo_fisico(chunk_node, le["x"], linha_z, 1.8, le["type"])
			criar_cubo_fisico(chunk_node, 1.25, linha_z, 4.3, ce["type"])
		else:
			for c in lista_cubos:
				criar_cubo_fisico(chunk_node, c["x"], linha_z, 1.8, c["type"])
	else:
		criar_cubo_fisico(chunk_node, lista_cubos[0]["x"], linha_z, 1.8, lista_cubos[0]["type"])

func processar_buracos_linha(chunk_node: Node3D, lista_x: Array, linha_z: float, acumulador_global: Array) -> void:
	if lista_x.size() == 0: return
	lista_x.sort()

	if lista_x.size() == 2 and abs(lista_x[0] - lista_x[1]) == 2.5:
		var mid_x = (lista_x[0] + lista_x[1]) / 2.0
		criar_visual_buraco(chunk_node, mid_x, linha_z, 4.5, 2.2)
		acumulador_global.append(Vector3(mid_x, 0, linha_z))
	elif lista_x.size() == 3:
		criar_visual_buraco(chunk_node, 0.0, linha_z, 7.2, 2.2)
		acumulador_global.append(Vector3(0.0, 0, linha_z))
	else:
		for hx in lista_x:
			criar_visual_buraco(chunk_node, hx, linha_z, 2.2, 2.2)
			acumulador_global.append(Vector3(hx, 0, linha_z))

func criar_cubo_fisico(chunk_node: Node3D, x: float, z: float, tam_x: float, type: String) -> void:
	# CORREÇÃO: Agora cria um corpo estático com física real para o Ragdoll bater
	var corpo_estatico = StaticBody3D.new()
	var cubo_mesh = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	var colisor = CollisionShape3D.new()
	var formato_caixa = BoxShape3D.new()
	var mat = StandardMaterial3D.new()
	
	# Configura dimensões e cores dinâmicas baseadas no tipo de barreira
	var tam_y = 3.0 if type == "high" else 0.6
	var pos_y = 1.5 if type == "high" else 0.3
	mat.albedo_color = Color(0.1, 0.8, 0.1) if type == "high" else Color(1.0, 0.5, 0.0)
	
	box_mesh.size = Vector3(tam_x, tam_y, 1.8)
	formato_caixa.size = Vector3(tam_x, tam_y, 1.8)
	
	cubo_mesh.mesh = box_mesh
	cubo_mesh.material_override = mat
	colisor.shape = formato_caixa
	
	# Monta a estrutura de nós físicos
	corpo_estatico.add_child(cubo_mesh)
	corpo_estatico.add_child(colisor)
	chunk_node.add_child(corpo_estatico)
	
	# Posiciona o corpo físico no grid do cenário
	corpo_estatico.position = Vector3(x, pos_y, z)
	
	# Registra a posição global para a lógica de dano do Player
	posicoes_obstaculos_ativos.append({
		"pos": corpo_estatico.global_position, 
		"tamanho_x": tam_x, 
		"type": type
	})

func criar_visual_buraco(chunk_node: Node3D, x: float, z: float, tam_x: float, tam_z: float) -> void:
	var buraco = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(tam_x, 0.1, tam_z)
	buraco.mesh = box_mesh
	
	var mat_preto = StandardMaterial3D.new()
	mat_preto.albedo_color = Color(0.0, 0.0, 0.0)
	buraco.material_override = mat_preto
	
	chunk_node.add_child(buraco)
	buraco.position = Vector3(x, 0.01, z)
	posicoes_buracos_ativos.append({"pos": buraco.global_position, "tamanho_x": tam_x, "tamanho_z": tam_z})

func processar_uniao_diagonal_buracos(chunk_node: Node3D, lista_buracos: Array) -> void:
	if lista_buracos.size() < 2: return
	
	for i in range(lista_buracos.size()):
		for j in range(i + 1, lista_buracos.size()):
			var b1 = lista_buracos[i]
			var b2 = lista_buracos[j]
			
			if abs(b1.z - b2.z) > 3.0 and abs(b1.x - b2.x) >= 1.25:
				var conexao = MeshInstance3D.new()
				var box_mesh = BoxMesh.new()
				var dist_z = abs(b1.z - b2.z)
				box_mesh.size = Vector3(2.2, 0.1, dist_z + 2.0)
				conexao.mesh = box_mesh
				
				var mat_preto = StandardMaterial3D.new()
				mat_preto.albedo_color = Color(0.0, 0.0, 0.0)
				conexao.material_override = mat_preto
				
				chunk_node.add_child(conexao)
				var pos_media_local = (b1 + b2) / 2.0
				conexao.position = Vector3(pos_media_local.x, 0.01, pos_media_local.z)
				
				var direcao = (b2 - b1).normalized()
				var angulo_y = atan2(-direcao.x, -direcao.z)
				conexao.rotation.y = angulo_y
				
				var pos_global_media = conexao.global_position
				posicoes_buracos_ativos.append({"pos": pos_global_media, "tamanho_x": 2.2, "tamanho_z": 2.2})
				posicoes_buracos_ativos.append({"pos": pos_global_media + (direcao * (dist_z/4.0)), "tamanho_x": 2.2, "tamanho_z": 2.2})
				posicoes_buracos_ativos.append({"pos": pos_global_media - (direcao * (dist_z/4.0)), "tamanho_x": 2.2, "tamanho_z": 2.2})

func limpar_chunks_antigos() -> void:
	for chunk in container.get_children():
		if chunk.global_position.z < jogador.global_position.z - 30.0:
			chunk.queue_free()
			
	var obs_filtrados: Array[Dictionary] = []
	for data in posicoes_obstaculos_ativos:
		if data["pos"].z >= jogador.global_position.z - 10.0:
			obs_filtrados.append(data)
	posicoes_obstaculos_ativos = obs_filtrados

	var buracos_filtrados: Array[Dictionary] = []
	for data in posicoes_buracos_ativos:
		if data["pos"].z >= jogador.global_position.z - 10.0:
			buracos_filtrados.append(data)
	posicoes_buracos_ativos = buracos_filtrados

func processar_avalanche(delta: float) -> void:
	if cooldown_ataque > 0.0:
		cooldown_ataque -= delta
	
	var distancia = jogador.global_position.z - avalanche_z
	var vel_atual = velocidade_base_avalanche
	
	if distancia > 15.0:
		vel_atual += (distancia * 0.2)
	if cooldown_ataque > 0.0:
		vel_atual *= 0.5

	avalanche_z += vel_atual * delta
	avalanche_mesh.global_position = Vector3(0, 2.5, avalanche_z)

	if distancia <= 1.5 and cooldown_ataque <= 0.0:
		cooldown_ataque = 2.0
		jogador.tomar_dano_e_empurrante(1, 24.0, "avalanche")

func processar_colisao_obstaculos() -> void:
	var pos_player = jogador.global_position
	for i in range(posicoes_obstaculos_ativos.size() - 1, -1, -1):
		var data = posicoes_obstaculos_ativos[i]
		var pos_obs = data["pos"]
		var limite_x = (data["tamanho_x"] / 2.0) + 0.5

		if abs(pos_player.x - pos_obs.x) < limite_x and abs(pos_player.z - pos_obs.z) < 1.4:
			if data["type"] == "low" and jogador.is_jumping:
				continue
				
			posicoes_obstaculos_ativos.remove_at(i)
			# CORREÇÃO: Passa o tipo dinâmico ("high" ou "low") em vez de uma string genérica
			jogador.tomar_dano_e_empurrante(1, -10.0, data["type"])

func processar_queda_buracos() -> void:
	if jogador.is_jumping: return 
	
	var pos_player = jogador.global_position
	for data in posicoes_buracos_ativos:
		var pos_buraco = data["pos"]
		
		var limite_x = (data["tamanho_x"] / 2.0) - 0.2
		var limite_z = (data["tamanho_z"] / 2.0) - 0.2
		
		if abs(pos_player.x - pos_buraco.x) < limite_x and abs(pos_player.z - pos_buraco.z) < limite_z:
			jogador.cair_no_buraco()

func criar_objeto_avalanche() -> void:
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(10, 5, 4)
	avalanche_mesh = MeshInstance3D.new()
	avalanche_mesh.mesh = box_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	avalanche_mesh.material_override = mat
	add_child(avalanche_mesh)

func criar_portal_de_ouro() -> void:
	var portal = MeshInstance3D.new()
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = 2.0
	torus_mesh.outer_radius = 3.0
	portal.mesh = torus_mesh
	
	var mat_ouro = StandardMaterial3D.new()
	mat_ouro.albedo_color = Color(1.0, 0.8, 0.0)
	mat_ouro.emission_enabled = true
	mat_ouro.emission = Color(1.0, 0.8, 0.0)
	portal.material_override = mat_ouro
	
	add_child(portal)
	portal.global_position = Vector3(0, 3.0, distancia_vitoria)

func vitoria() -> void:
	if jogo_finalizado: return
	jogo_finalizado = true
	print("VITÓRIA! PORTAL DE OURO ALCANÇADO!")
	
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()
