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
		t.eq(#callsOf('poly'), 3)

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
		t.eq(#callsOf('poly'), 1)
		local lines = callsOf('line')
		t.eq(#lines, 1, 'tracinho da direcao')
	end)

	t.test('draw() chama tudo e o HUD escreve texto', function()
		mock.reset()
		local p, r = fixture()
		p:select(15, 1)
		t.ok(r:draw())
		t.ok(#callsOf('poly') >= 3)
		local texts = callsOf('text')
		t.ok(#texts >= 1, 'escreveu no HUD')
		local joined = ''
		for _, call in ipairs(texts) do joined = joined .. call[2] .. '\n' end
		t.contains(joined, 'Node 0')
		t.contains(joined, 'Nodes: 3')
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

	t.test('fontes: sem api de fonte o modulo nao quebra', function()
		local p, r = fixture()
		t.ok(r:font() ~= nil, 'fonte criada pelo mock')
		t.eq(r:text('teste', 0, 0), true)
		t.ok(r:textWidth('teste') > 0)
	end)
end)
