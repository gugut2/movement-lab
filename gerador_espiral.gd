extends Node3D

@onready var jogador = $Player

var tamanho_bloco: float = 8.0
var blocos_container: Node3D # CORRIGIDO

var mapa_grid: Dictionary = {}

var mat_gelo: StandardMaterial3D
var mat_safe: StandardMaterial3D

func _ready() -> void:
	blocos_container = Node3D.new()
	blocos_container.name = "PistaEspiral"
	add_child(blocos_container)
	
	configurar_materiais()
	gerar_espiral_procedural()

func configurar_materiais() -> void:
	mat_gelo = StandardMaterial3D.new()
	mat_gelo.albedo_color = Color(0.12, 0.56, 1.0)
	mat_gelo.roughness = 0.02
	
	mat_safe = StandardMaterial3D.new()
	mat_safe.albedo_color = Color(1.0, 0.6, 0.0)

func gerar_espiral_procedural() -> void:
	var passos = [
		{"dir": Vector2i(1, 0), "qtd": 6},  
		{"dir": Vector2i(0, 1), "qtd": 6},  
		{"dir": Vector2i(-1, 0), "qtd": 6}, 
		{"dir": Vector2i(0, -1), "qtd": 4}, 
		{"dir": Vector2i(1, 0), "qtd": 4},  
		{"dir": Vector2i(0, 1), "qtd": 2},  
		{"dir": Vector2i(-1, 0), "qtd": 2}, 
		{"dir": Vector2i(0, -1), "qtd": 1}  
	]
	
	var coord_atual = Vector2i(0, 0)
	mapa_grid[coord_atual] = true # Registra o bloco de spawn inicial
	criar_bloco_infraestrutura(coord_atual, true, Vector3(1, 0, 0)) 
	jogador.global_position = Vector3(0, 1.0, 0)
	
	for passo in passos:
		var dir = passo["dir"]
		var qtd = passo["qtd"]
		
		for i in range(qtd):
			coord_atual += dir
			mapa_grid[coord_atual] = true # Registra cada novo bloco gerado
			var eh_quina = (i == qtd - 1)
			var dir_3d = Vector3(dir.x, 0, dir.y)
			criar_bloco_infraestrutura(coord_atual, eh_quina, dir_3d)
			
	gerar_paredes_invisiveis() # Ergue a geometria de contenção nas bordas baleadas

func criar_bloco_infraestrutura(coord: Vector2i, laranja_safe: bool, dir_pista: Vector3) -> void:
	var pos_mundo = Vector3(coord.x * tamanho_bloco, 0, coord.y * tamanho_bloco)
	
	var chao_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(tamanho_bloco, tamanho_bloco)
	chao_mesh.mesh = plane
	chao_mesh.material_override = mat_safe if laranja_safe else mat_gelo
	chao_mesh.position = pos_mundo
	blocos_container.add_child(chao_mesh)
	
	var corpo_chao = StaticBody3D.new()
	var colisor = CollisionShape3D.new()
	var caixa = BoxShape3D.new()
	caixa.size = Vector3(tamanho_bloco, 0.2, tamanho_bloco)
	colisor.shape = caixa
	corpo_chao.add_child(colisor)
	corpo_chao.position = pos_mundo + Vector3(0, -0.1, 0)
	blocos_container.add_child(corpo_chao)

	var area_trigger = Area3D.new()
	var colisor_trigger = CollisionShape3D.new()
	var caixa_trigger = BoxShape3D.new()
	caixa_trigger.size = Vector3(tamanho_bloco - 0.2, 1.5, tamanho_bloco - 0.2)
	colisor_trigger.shape = caixa_trigger
	area_trigger.add_child(colisor_trigger)
	area_trigger.position = pos_mundo + Vector3(0, 0.75, 0)
	blocos_container.add_child(area_trigger)
	
	if laranja_safe:
		area_trigger.area_entered.connect(func(area):
			if area.has_method("desativar_mecanica_gelo"):
				area.desativar_mecanica_gelo(pos_mundo)
		)
	else:
		area_trigger.area_entered.connect(func(area):
			if area.has_method("aplicar_mecanica_gelo"):
				area.aplicar_mecanica_gelo(dir_pista, pos_mundo)
		)

func gerar_paredes_invisiveis() -> void:
	var direcoes_vizinhos = [
		{"vec": Vector2i(1, 0), "eixo": "X", "sinal": 1.0, "rot": 90},   # Direita
		{"vec": Vector2i(-1, 0), "eixo": "X", "sinal": -1.0, "rot": 90}, # Esquerda
		{"vec": Vector2i(0, 1), "eixo": "Z", "sinal": 1.0, "rot": 0},    # Baixo
		{"vec": Vector2i(0, -1), "eixo": "Z", "sinal": -1.0, "rot": 0}   # Cima
	]
	
	for coord in mapa_grid.keys():
		var pos_bloco = Vector3(coord.x * tamanho_bloco, 0, coord.y * tamanho_bloco)
		
		for vizinho in direcoes_vizinhos:
			var coord_vizinho = coord + vizinho["vec"]
			
			# Geometria pura: se o vizinho não existe na pista, cria uma barreira física
			if not mapa_grid.has(coord_vizinho):
				var parede = Area3D.new()
				parede.add_to_group("paredes_invisiveis")
				parede.set_meta("eixo", vizinho["eixo"])
				parede.set_meta("sinal", vizinho["sinal"])
				
				var colisor = CollisionShape3D.new()
				var caixa = BoxShape3D.new()
				caixa.size = Vector3(tamanho_bloco, 4.0, 4.0) # Espessura fina de contenção
				colisor.shape = caixa
				parede.add_child(colisor)
				
				# assim a borda interna continua alinhada perfeitamente com o gelo.
				var margem_externa = (tamanho_bloco / 2.0) + 2.0
				var deslocamento = Vector3(vizinho["vec"].x, 0, vizinho["vec"].y) * margem_externa
				
				parede.position = pos_bloco + deslocamento + Vector3(0, 2.0, 0)
				parede.rotation_degrees.y = vizinho["rot"]
				
				blocos_container.add_child(parede)
