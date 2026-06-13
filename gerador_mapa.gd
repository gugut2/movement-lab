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

# Grid e Balanço
var colunas_x: Array = [-2.5, 0.0, 2.5]
var posicoes_obstaculos_ativos: Array[Dictionary] = []
var posicoes_buracos_ativos: Array[Dictionary] = [] # Convertido para receber Dicionários

func _ready() -> void:
	for i in range(chunks_visiveis):
		criar_chunk(i == 0)
	criar_objeto_avalanche()
	criar_portal_de_ouro()

func _process(delta: float) -> void:
	if jogo_finalizado: return
	
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

	var mesh_instance = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(8, tamanho_chunk)
	mesh_instance.mesh = plane_mesh
	mesh_instance.position = Vector3(0, 0, tamanho_chunk / 2)
	chunk_node.add_child(mesh_instance)

	if not vazio:
		processar_tokens_e_spawn(chunk_node)

	proxima_posicao_z += tamanho_chunk

func processar_tokens_e_spawn(chunk_node: Node3D) -> void:
	var progresso = clamp(proxima_posicao_z / distancia_vitoria, 0.0, 1.0)
	var tokens_disponiveis = int(lerp(1.0, 4.0, progresso))

	var linhas_z = [5.0, 15.0]
	var buracos_criados_no_chunk = []

	for linha_z in linhas_z:
		if tokens_disponiveis <= 0: break
		
		var max_objetos = min(tokens_disponiveis, 2) # CORRIGIDO PARA min()
		var qtd = randi_range(0, max_objetos)
		if qtd == 0: continue
		
		tokens_disponiveis -= qtd
		
		var colunas = colunas_x.duplicate()
		colunas.shuffle()
		
		var itens_linha = []
		for i in range(qtd):
			var cx = colunas.pop_front()
			var tipo = "hole" if randf() < 0.65 else "cube"
			itens_linha.append({"x": cx, "type": tipo})
			
		# Sistema Unificado de Fusão Horizontal (Linha com 2 perigos idênticos)
		if itens_linha.size() == 2:
			var it1 = itens_linha[0]
			var it2 = itens_linha[1]
			
			if it1["type"] == "cube" and it2["type"] == "cube":
				var mid_x = (it1["x"] + it2["x"]) / 2.0
				criar_cubo_fisico(chunk_node, mid_x, linha_z, 4.3)
			elif it1["type"] == "hole" and it2["type"] == "hole":
				# FUSÃO HORIZONTAL DE BURACO ADJACENTE
				var mid_x = (it1["x"] + it2["x"]) / 2.0
				criar_visual_buraco(chunk_node, mid_x, linha_z, 4.5, 2.2)
				buracos_criados_no_chunk.append(Vector3(mid_x, 0, linha_z))
			else:
				# Tipos mistificados (1 cubo, 1 buraco) -> nacerão separados
				for it in itens_linha:
					if it["type"] == "cube":
						criar_cubo_fisico(chunk_node, it["x"], linha_z, 1.8)
					else:
						criar_visual_buraco(chunk_node, it["x"], linha_z, 2.2, 2.2)
						buracos_criados_no_chunk.append(Vector3(it["x"], 0, linha_z))
		elif itens_linha.size() == 1:
			var it = itens_linha[0]
			if it["type"] == "cube":
				criar_cubo_fisico(chunk_node, it["x"], linha_z, 1.8)
			else:
				criar_visual_buraco(chunk_node, it["x"], linha_z, 2.2, 2.2)
				buracos_criados_no_chunk.append(Vector3(it["x"], 0, linha_z))

	processar_uniao_diagonal_buracos(chunk_node, buracos_criados_no_chunk)

func criar_cubo_fisico(chunk_node: Node3D, x: float, z: float, tam_x: float) -> void:
	var cubo = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(tam_x, 2.0, 1.8)
	cubo.mesh = box_mesh
	
	var mat_verde = StandardMaterial3D.new()
	mat_verde.albedo_color = Color(0.1, 0.8, 0.1)
	cubo.material_override = mat_verde
	
	chunk_node.add_child(cubo)
	cubo.position = Vector3(x, 1.0, z)
	posicoes_obstaculos_ativos.append({"pos": cubo.global_position, "tamanho_x": tam_x})

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
	var b1 = lista_buracos[0]
	var b2 = lista_buracos[1]
	
	if b1.z != b2.z and abs(b1.x - b2.x) >= 1.25:
		var conexao = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(2.2, 0.1, 10.5)
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
		posicoes_buracos_ativos.append({"pos": pos_global_media + (direcao * 3.0), "tamanho_x": 2.2, "tamanho_z": 2.2})
		posicoes_buracos_ativos.append({"pos": pos_global_media - (direcao * 3.0), "tamanho_x": 2.2, "tamanho_z": 2.2})

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
		jogador.tomar_dano_e_empurrante(1, 24.0)

func processar_colisao_obstaculos() -> void:
	var pos_player = jogador.global_position
	for i in range(posicoes_obstaculos_ativos.size() - 1, -1, -1):
		var data = posicoes_obstaculos_ativos[i]
		var pos_obs = data["pos"]
		var limite_x = (data["tamanho_x"] / 2.0) + 0.5

		if abs(pos_player.x - pos_obs.x) < limite_x and abs(pos_player.z - pos_obs.z) < 1.4:
			posicoes_obstaculos_ativos.remove_at(i)
			jogador.tomar_dano_e_empurrante(1, -10.0)

func processar_queda_buracos() -> void:
	# SE O JOGADOR ESTIVER PULANDO, IGNORA A DETECÇÃO DE QUEDA DO BURACO
	if jogador.is_jumping: return 
	
	var pos_player = jogador.global_position
	for data in posicoes_buracos_ativos:
		var pos_buraco = data["pos"]
		var limite_x = (data["tamanho_x"] / 2.0) + 0.4
		var limite_z = (data["tamanho_z"] / 2.0) + 0.4
		
		if abs(pos_player.x - pos_buraco.x) < limite_x and abs(pos_player.z - pos_buraco.z) < limite_z:
			jogador.cair_no_buraco()

func criar_objeto_avalanche() -> void:
	avalanche_mesh = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(10, 5, 4)
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
	jogo_finalizado = true
	print("VITÓRIA COMERCIAL! PORTAL DE OURO ALCANÇADO!")
