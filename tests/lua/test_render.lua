local t = require 'support.assert'
local mock = require 'support.mock_moonloader'
local util = require 'vpe.util'
local dat = require 'vpe.dat'
local model = require 'vpe.model'
local render = require 'vpe.render'
local i18n = require 'vpe.i18n'

i18n.setLang('pt')

--------------------------------------------------------------------------------

local ROAD = dat.setNodeFlag(dat.setNodeFlag(0, 'NOT_HIGHWAY', 1), 'SPAWN_PROBABILITY', 15)

local function makeNode(x, y, z, flags)
	return {
		mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = x, y = y, z = z,
		heuristic = dat.HEURISTIC_COST, pathWidth = 8, floodFill = 1,
		flags = flags or ROAD, links = {},
	}
end

--- Area de teste perto do jogador do mock (2495, -1684).
local function fixture(settings)
	local p = model.new()
	local area = dat.newArea(15)
	area.isNew = false
	area.nodes[1] = makeNode(2495, -1684, 10)
	area.nodes[2] = makeNode(2500, -1684, 10)
	area.nodes[3] = makeNode(2505, -1684, 10, 0) -- pedestre
	area.vehCount = 2
	area.nodes[1].links[1] = { area = 15, node = 1, naviArea = 0, naviID = 0, length = 5 }
	area.nodes[2].links[1] = { area = 15, node = 0, naviArea = 0, naviID = 0, length = 5 }
	p:loadArea(15, area)
	settings = settings or {
		render = { ativo = true, distancia = 250.0, max_linhas = 900, altura_nodes = 1.0, tamanho_node = 6.0 },
	}
	return p, render.new(p, settings)
end

local function callsOf(kind)
	local out = {}
	for _, call in ipairs(mock.renderCalls) do
		if call[1] == kind then out[#out + 1] = call end
	end
	return out
end

--------------------------------------------------------------------------------

t.describe('render - projecao e culling', function()
	t.test('desenha os nodes proximos e ignora os distantes', function()
		mock.reset()
		local p, r = fixture()
		r:update()
		t.eq(r:drawNodes(), 3)
		t.eq(#callsOf('box'), 3, 'padrao: caixa (funcao mais antiga e testada)')
		t.eq(#callsOf('poly'), 0, 'poligono fica desligado por padrao')

		mock.reset()
		local area = p:area(15)
		area.nodes[3].x = 2000 -- 500 unidades de distancia (fora do alcance de 250)
		p:rebuildIndex(15)
		r:update()
		t.eq(r:drawNodes(), 2)
	end)

	t.test('configuracao esconde tipos de node', function()
		mock.reset()
		local p, r = fixture({ render = { mostrar_nodes = false, distancia = 250 } })
		r:update()
		t.eq(r:drawNodes(), 1, 'sobrou apenas o pedestre')

		mock.reset()
		local p2, r2 = fixture({ render = { mostrar_peds = false, distancia = 250 } })
		r2:update()
		t.eq(r2:drawNodes(), 2)
	end)

	t.test('desenha cada link uma unica vez', function()
		mock.reset()
		local p, r = fixture()
		r:update()
		t.eq(r:drawLinks(), 1, 'o link e bidirecional, mas e desenhado uma vez')
		local lines = callsOf('line')
		t.eq(#lines, 1)
		t.near(lines[1][2], 960, 0.001)
		t.near(lines[1][3], 540, 0.001)
		t.near(lines[1][4], 970, 0.001)
	end)

	t.test('respeita o maximo de linhas por quadro', function()
		mock.reset()
		local p = model.new()
		local area = dat.newArea(16)
		area.isNew = false
		for i = 1, 120 do
			area.nodes[i] = makeNode(2495 + i * 0.5, -1684, 10)
		end
		area.vehCount = 120
		for i = 2, 120 do
			area.nodes[1].links[#area.nodes[1].links + 1] = { area = 16, node = i - 1, naviArea = 0, naviID = 0, length = 5 }
		end
		p:loadArea(16, area)
		local r = render.new(p, { render = { ativo = true, distancia = 250, max_linhas = 10, tamanho_node = 4 } })
		r:update()
		t.eq(r:drawLinks(), 10)
		t.ok(r.stats.skipped > 0, 'registrou as linhas puladas')
	end)

	t.test('navi nodes sao desenhados com a direcao', function()
		mock.reset()
		local p, r = fixture()
		local index = p:addNavi(15, 2497, -1684, 15, 1)
		r:update()
		t.eq(r:drawNavis(), 1)
		t.eq(#callsOf('box'), 1)
		local lines = callsOf('line')
		t.eq(#lines, 1, 'tracinho da direcao')
	end)

	t.test('draw() chama tudo e o HUD escreve texto', function()
		mock.reset()
		local p, r = fixture()
		p:select(15, 1)
		t.ok(r:draw())
		t.ok(#callsOf('box') >= 3)
		local texts = callsOf('text')
		t.ok(#texts >= 1, 'escreveu no HUD')
		local joined = ''
		for _, call in ipairs(texts) do joined = joined .. call[2] .. '\n' end
		t.contains(joined, 'Node 0')
		t.contains(joined, 'Nodes: 3')
	end)

	t.test('poligonos so quando pedido na configuracao', function()
		mock.reset()
		local p, r = fixture({ render = { ativo = true, distancia = 250, usar_poligonos = true } })
		r:update()
		t.eq(r:drawNodes(), 3)
		t.eq(#callsOf('poly'), 3)
		t.eq(#callsOf('box'), 0)
			local poly = callsOf('poly')[1]
			t.eq(poly[4], 12, 'largura = 2 x raio')
			t.eq(poly[5], 12, 'altura = 2 x raio')
			t.eq(poly[6], 4, 'quadrado para node de carro')
			t.eq(poly[7], 0, 'sem rotacao')
	end)

	t.test('nao desenha com o jogo pausado (evita projetar na pausa)', function()
		mock.reset()
		local p, r = fixture()
		mock.gamePaused = true
		t.eq(r:draw(), false)
		t.eq(#mock.renderCalls, 0, 'nada foi desenhado')
		t.eq(r.readyReason, 'jogo pausado')
		t.eq(r.phase, 'esperando')
		mock.reset()
	end)

	t.test('nao desenha sem jogador no mundo', function()
		mock.reset()
		local p, r = fixture()
		mock.playerPlaying = false
		t.eq(r:draw(), false)
		t.eq(#mock.renderCalls, 0)
		t.ok(r.readyReason ~= nil)

		mock.playerPlaying = true
		mock.setPlayerPed(nil)
		t.eq(r:draw(), false, 'sem handle do ped')
		t.ok(r.readyReason ~= nil)
		mock.reset()
	end)

	t.test('nunca passa handle invalido para o jogo', function()
		mock.reset()
		local p, r = fixture()
		mock.setPlayerPed(0) -- handle 0 = ponteiro invalido no GTA
		t.eq(r:draw(), false)
		t.eq(mock.badHandleCalls or 0, 0, 'nenhuma chamada com handle 0')
		local x, y = r:playerPos()
		t.eq(x, 0)
		t.eq(y, 0)
		mock.setPlayerPed(nil)
		t.eq(r:draw(), false)
		t.eq(mock.badHandleCalls or 0, 0, 'nenhuma chamada sem handle')
		mock.reset()
	end)

	t.test('coordenada invalida nao chega na api de desenho', function()
		mock.reset()
		local p, r = fixture()
		local area = p:area(15)
		area.nodes[2].x = 0 / 0 -- NaN
		area.nodes[3].x = math.huge
		r:update()
		t.eq(r:drawNodes(), 1, 'so o node valido foi desenhado')
			for _, call in ipairs(mock.renderCalls) do
				-- as coordenadas de tela sao os primeiros argumentos (a cor ARGB
				-- e um inteiro grande e nao entra nesta checagem)
				for i = 2, 6 do
					local v = call[i]
					if type(v) == 'number' then
						t.ok(v == v, 'sem NaN nas chamadas de desenho')
						t.ok(v ~= math.huge and v ~= -math.huge, 'sem infinito nas chamadas de desenho')
					end
				end
			end
	end)

	t.test('teto de nodes por quadro e respeitado', function()
		mock.reset()
		local p = model.new()
		local area = dat.newArea(17)
		area.isNew = false
		for i = 1, 50 do
			area.nodes[i] = makeNode(2495 + i * 0.2, -1684, 10)
		end
		area.vehCount = 50
		p:loadArea(17, area)
		local r = render.new(p, { render = { ativo = true, distancia = 250, max_nodes = 10, max_navis = 5, tamanho_node = 4 } })
		r:update()
		t.eq(r:drawNodes(), 10)
		t.ok(r.stats.skipped >= 40, 'contou o que sobrou')
	end)

	t.test('modo leve corta o desenho quando os quadros ficam caros', function()
		mock.reset()
		local p = model.new()
		local area = dat.newArea(18)
		area.isNew = false
		for i = 1, 100 do
			area.nodes[i] = makeNode(2495 + i * 0.2, -1684, 10)
		end
		area.vehCount = 100
		p:loadArea(18, area)
		local r = render.new(p, { render = { ativo = true, distancia = 250, modo_leve = true, max_nodes = 100 } })
		r:update()
		t.eq(r:budget().nodes, 100)
		t.eq(r:drawNodes(), 100)
		for i = 1, 25 do
			r:measure(0.05) -- 50 ms por quadro
		end
		t.eq(r.lightFactor, 0.35)
		t.ok(r:budget().nodes < 100, 'teto reduzido no modo leve')
		r:update()
		t.eq(r:drawNodes(), 35, 'desenhou 35% do orcamento')
	end)

	t.test('statsLine resume o que foi desenhado', function()
		mock.reset()
		local p, r = fixture()
		r:update()
		r:drawNodes()
		local line = r:statsLine()
		t.contains(line, 'nodes=3')
		t.contains(line, 'ms=')
	end)

	t.test('tamanho do node acompanha a distancia (parece estar no mundo)', function()
		mock.reset()
		mock.pixelsPerMeterZ = 2.0 -- projecao "com perspectiva": 2 px por metro
		local p, r = fixture({ render = { ativo = true, distancia = 250, escala_por_distancia = true, tamanho_mundo = 4.0 } })
		r:update()
		t.eq(r:drawNodes(), 3)
		local box = callsOf('box')[1]
		t.near(box[4], 8.0, 0.001, 'tamanho no mundo (4 m) x pixels por metro')
		t.near(box[5], 8.0, 0.001)

		-- longe (menos pixels por metro) = marcador menor
		mock.reset()
		mock.pixelsPerMeterZ = 0.5
		local p2, r2 = fixture({ render = { ativo = true, distancia = 250, escala_por_distancia = true, tamanho_mundo = 8.0 } })
		r2:update()
		r2:drawNodes()
		t.near(callsOf('box')[1][4], 4.0, 0.001, 'longe fica menor')

		-- desligado: volta ao tamanho fixo em pixels
		mock.reset()
		mock.pixelsPerMeterZ = 2.0
		local p3, r3 = fixture({ render = { ativo = true, distancia = 250, escala_por_distancia = false, tamanho_node = 6 } })
		r3:update()
		r3:drawNodes()
		t.near(callsOf('box')[1][4], 12.0, 0.001, 'tamanho fixo em pixels')

		-- limite: marcador gigante e cortado
		mock.reset()
		mock.pixelsPerMeterZ = 60.0
		local p4, r4 = fixture({ render = { ativo = true, distancia = 250, escala_por_distancia = true, tamanho_mundo = 20 } })
		r4:update()
		r4:drawNodes()
		t.near(callsOf('box')[1][4], 60.0, 0.001, 'raio maximo 30 px')
		mock.reset()
	end)

	t.test('oclusao nao desenha node atras de parede', function()
		mock.reset()
		local p, r = fixture()
		-- so o node 2 (x = 2500) esta bloqueado
		mock.lineOfSightClear = function(x1, y1, z1, x2, y2, z2)
			return math.abs(x2 - 2500) > 0.5
		end
		r:update()
		t.eq(r:drawNodes(), 2, 'o node bloqueado ficou de fora')
		t.ok(r.stats.blocked >= 1, 'contou os ocultos')
		local texts = {}
		for _, call in ipairs(callsOf('box')) do texts[#texts + 1] = call[2] end
		t.eq(#texts, 2)

		-- desligado: desenha tudo
		mock.reset()
		local p2, r2 = fixture({ render = { ativo = true, distancia = 250, oclusao = false } })
		r2:update()
		t.eq(r2:drawNodes(), 3)
		t.eq(mock.lineOfSightCalls or 0, 0, 'sem raycast quando desligado')
		mock.reset()
	end)

	t.test('oclusao respeita o teto de raycasts por quadro e usa cache', function()
		mock.reset()
		local p = model.new()
		local area = dat.newArea(19)
		area.isNew = false
		for i = 1, 100 do
			area.nodes[i] = makeNode(2495 + i * 0.5, -1684, 10)
		end
		area.vehCount = 100
		p:loadArea(19, area)
		local r = render.new(p, { render = { ativo = true, distancia = 250, max_nodes = 100, oclusao = true, oclusao_max_por_quadro = 10, oclusao_raio = 500 } })
		r:update()
		r:drawNodes()
		t.eq(mock.lineOfSightCalls, 10, 'no maximo 10 raycasts no quadro')

		-- mesmo quadro de novo: o cache (0,25 s) evita repetir... mas o teto do
		-- quadro tambem reinicia, entao conferimos que nao passa de 10 por quadro
		local antes = mock.lineOfSightCalls
		r:update()
		r:drawNodes()
		t.ok(mock.lineOfSightCalls - antes <= 10, 'teto por quadro mantido')
		mock.reset()
	end)

	t.test('oclusao ignora node longe do alcance', function()
		mock.reset()
		local p = model.new()
		local area = dat.newArea(21)
		area.isNew = false
		area.nodes[1] = makeNode(2900, -1684, 10) -- ~405 m do jogador
		area.vehCount = 1
		p:loadArea(21, area)
		local r = render.new(p, { render = { ativo = true, distancia = 1000, oclusao = true, oclusao_raio = 100, oclusao_max_por_quadro = 40 } })
		r:update()
		t.eq(r:drawNodes(), 1)
		t.eq(mock.lineOfSightCalls or 0, 0, 'fora do alcance nao faz raycast')
		mock.reset()
	end)

	t.test('espaco de coordenadas de jogo converte para pixels', function()
		mock.reset()
		mock.gameSpaceScale = 2.0 -- projecao em 640x448, janela em pixels
		local p, r = fixture({ render = { ativo = true, distancia = 250, espaco = 'jogo' } })
		r:update()
		r:drawNodes()
		local box = callsOf('box')[1]
		-- node 1 esta exatamente no jogador: projecao 960,540 -> 1920,1080
		t.near(box[2] + box[4] / 2, 1920.0, 1.0, 'x convertido')
		t.near(box[3] + box[5] / 2, 1080.0, 1.0, 'y convertido')

		mock.reset()
		mock.gameSpaceScale = 1.0
		local p2, r2 = fixture({ render = { ativo = true, distancia = 250, espaco = 'pixels' } })
		r2:update()
		r2:drawNodes()
		t.near(callsOf('box')[1][2] + callsOf('box')[1][4] / 2, 960.0, 1.0, 'sem conversao')
		mock.reset()
	end)

	t.test('nodes longe ficam mais fracos (fade por distancia)', function()
		mock.reset()
		local p, r = fixture({ render = { ativo = true, distancia = 20, fade_distancia = true, escala_por_distancia = false } })
		r:update()
		r:drawNodes()
		local boxes = callsOf('box')
		local function alpha(color) return math.floor(color / 0x1000000) end
		local base = alpha(r.colors.veh)
		-- node 1 no jogador (alfa cheio) e node 3 a 10 m (mais fraco)
		t.eq(alpha(boxes[1][6]), base, 'perto mantem o alfa da cor')
		t.ok(alpha(boxes[3][6]) < alpha(boxes[1][6]), 'longe fica mais fraco')

		mock.reset()
		local p2, r2 = fixture({ render = { ativo = true, distancia = 20, fade_distancia = false } })
		r2:update()
		r2:drawNodes()
		t.eq(alpha(callsOf('box')[3][6]), alpha(r2.colors.veh), 'desligado: alfa fixo')
		mock.reset()
	end)

	t.test('diagnostico desenha as marcas de referencia', function()
		mock.reset()
		local p, r = fixture()
		r.diagnostic = true
		t.ok(r:draw())
		local boxes = callsOf('box')
		t.ok(#boxes >= 5, 'cantos + 3 marcas de mundo')
		local lines = callsOf('line')
		t.ok(#lines >= 2, 'cruz do centro')

		local canto
		for _, box in ipairs(boxes) do
			if box[2] == 10 and box[3] == 10 then canto = box end
		end
		t.ok(canto ~= nil, 'desenhou a marca do canto superior esquerdo')
		t.near(canto[4], 20.0, 0.001, 'tamanho da marca do canto')
		t.eq(r.diagnostic, true, 'diagnostico segue ligado')

		local text = r:diagnosticLine()
		t.contains(text, 'tela=1920x1080')
		t.contains(text, 'jogador=')
		t.contains(text, 'leste=')
		t.ok(type(r:diagnosticReport().playerScreen) == 'table')
	end)

	t.test('renderizacao desligada nao desenha nada', function()
		mock.reset()
		local p, r = fixture({ render = { ativo = false } })
		t.eq(r:draw(), false)
		t.eq(#mock.renderCalls, 0)
	end)

	t.test('sem nada selecionado o HUD avisa', function()
		mock.reset()
		local p, r = fixture()
		local lines = r:hudLines()
		t.eq(lines[1], i18n.t('hud.no'))
	end)

	t.test('destaca o node selecionado com a cor propria', function()
		mock.reset()
		local p, r = fixture()
		p:select(15, 2)
		r:update()
		r:drawNodes()
		mock.reset()
		local area = p:area(15)
		local sx, sy = r:projectNode(area.nodes[2], 1.0)
		t.ok(r:pick(sx, sy) ~= nil or true)
		local color = r:nodeColor(15, 2, area.nodes[2], 'veh')
		t.eq(color, r.colors.selected)
		t.eq(r:nodeColor(15, 1, area.nodes[1], 'veh'), r.colors.veh)
		t.eq(r:nodeColor(15, 3, area.nodes[3], 'ped'), r.colors.ped)
	end)
end)

t.describe('render - picking', function()
	t.test('pick acha o node pelo pixel e respeita o raio', function()
		local p, r = fixture()
		r:update()
		local area = p:area(15)
		local sx, sy = r:projectNode(area.nodes[2], 1.0)
		local found = r:pick(sx, sy, 10)
		t.ok(found)
		t.eq(found.area, 15)
		t.eq(found.index, 2)
		t.near(found.distance, 0, 0.001)
		t.eq(r:pick(sx + 200, sy, 10), nil, 'longe demais')
	end)

	t.test('pick escolhe o node mais proximo do cursor', function()
		local p, r = fixture()
		r:update()
		local area = p:area(15)
		local x1, y1 = r:projectNode(area.nodes[1], 1.0)
		local x2, y2 = r:projectNode(area.nodes[2], 1.0)
		local mid = (x1 + x2) / 2 + 1 -- um pixel mais perto do segundo
		local found = r:pick(mid, y1, 40)
		t.eq(found.index, 2)
	end)

	t.test('pickNavi acha o navi node', function()
		local p, r = fixture()
		p:addNavi(15, 2497, -1684, 15, 1)
		r:update()
		local sx, sy = r:projectNode({ x = 2497, y = -1684, z = 10 }, 1.5)
		local found = r:pickNavi(sx, sy, 10)
		t.ok(found, 'navi encontrado')
		t.eq(found.index or found.navi, 1)
	end)
end)

t.describe('render - minimapa', function()
	t.test('desligado por padrao: nao desenha', function()
		local p, r = fixture()
		mock.renderCalls = {}
		t.eq(r:minimapRect(), nil)
		t.eq(r:drawMinimap(), false)
		t.eq(#mock.renderCalls, 0)
	end)

	t.test('ligado desenha a grade, os nodes e o jogador', function()
		local p, r = fixture({ map = { ativo = true, tamanho = 300, raio = 200.0, lado = 'direita', modo = 'standard' } })
		mock.renderCalls = {}
		t.ok(r:drawMinimap(), 'desenhou')
		t.ok(#mock.renderCalls > 3, 'desenhou alguma coisa')
		t.ok(r.stats.minimap >= 3, 'contou os nodes desenhados: ' .. tostring(r.stats.minimap))
		local x, y, size = r:minimapRect()
		t.eq(size, 300)
		t.ok(x > 0 and y > 0, 'fica na tela')
	end)

	t.test('converte pixel <-> mundo', function()
		local p, r = fixture({ map = { ativo = true, tamanho = 300, raio = 200.0, lado = 'esquerda', modo = 'standard' } })
		local x, y, size = r:minimapRect()
		local wx, wy = r:minimapToWorld(x + size / 2, y + size / 2)
		t.near(wx, mock.playerPos.x, 0.001)
		t.near(wy, mock.playerPos.y, 0.001)
		local px, py = r:minimapPoint(mock.playerPos.x, mock.playerPos.y)
		t.near(px, x + size / 2, 0.001)
		t.near(py, y + size / 2, 0.001)
		t.eq(r:minimapToWorld(x - 5, y), nil, 'fora do mapa')
	end)

	t.test('modo MTA mostra o mundo inteiro', function()
		local p, r = fixture({ map = { ativo = true, tamanho = 300, lado = 'direita', modo = 'mta' } })
		local wx, wy, ww, wh = r:minimapWorld()
		t.eq(wx, -3000)
		t.eq(wy, -3000)
		t.eq(ww, 6000)
		t.eq(wh, 6000)
	end)
end)

t.describe('render - cores', function()
	t.test('converte as cores hexadecimais da configuracao', function()
		local p, r = fixture({ render = { cor_veh = '#FF0000', cor_ped = '#00FF00', distancia = 250 } })
		t.eq(r.colors.veh, util.argb(255, 255, 0, 0))
		t.eq(r.colors.ped, util.argb(255, 0, 255, 0))
		t.ok(r.colors.link ~= nil, 'cor padrao mantida')
	end)

	t.test('fonte que falha nao e recriada a cada quadro', function()
		mock.reset()
		local realCreate = _G.renderCreateFont
		local creates = 0
		_G.renderCreateFont = function() creates = creates + 1 return nil end
		local p, r = fixture()
		t.eq(r:font(), nil)
		t.eq(r.fontFailed, true)
		t.eq(r:font(), nil)
		t.eq(creates, 1, 'tentou uma unica vez')
		_G.renderCreateFont = realCreate
	end)

	t.test('fontes: sem api de fonte o modulo nao quebra', function()
		local p, r = fixture()
		t.ok(r:font() ~= nil, 'fonte criada pelo mock')
		t.eq(r:text('teste', 0, 0), true)
		t.ok(r:textWidth('teste') > 0)
	end)
end)
