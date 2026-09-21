local t = require 'support.assert'
local mock = require 'support.mock_moonloader'
local dat = require 'vpe.dat'
local model = require 'vpe.model'
local render = require 'vpe.render'
local gizmo = require 'vpe.gizmo'
local i18n = require 'vpe.i18n'

i18n.setLang('pt')

local ROAD = dat.setNodeFlag(dat.setNodeFlag(0, 'NOT_HIGHWAY', 1), 'SPAWN_PROBABILITY', 15)

local function makeNode(x, y, z)
	return {
		mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = x, y = y, z = z,
		heuristic = dat.HEURISTIC_COST, pathWidth = 8, floodFill = 1,
		flags = ROAD, links = {},
	}
end

local settings = {
	edicao = { passo_fino = 0.125, passo_normal = 1.0, passo_grosso = 8.0, travar_z = false },
	render = { ativo = true, distancia = 500, altura_nodes = 1.0, tamanho_node = 6.0 },
}

local function fixture(options)
	local p = model.new()
	local area = dat.newArea(15)
	area.isNew = false
	area.nodes[1] = makeNode(2495, -1684, 10)
	area.nodes[2] = makeNode(2500, -1684, 10)
	area.vehCount = 2
	area.nodes[1].links[1] = { area = 15, node = 1, naviArea = 0, naviID = 0, length = 5 }
	area.nodes[2].links[1] = { area = 15, node = 0, naviArea = 0, naviID = 0, length = 5 }
	p:loadArea(15, area)
	p:select(15, 1)
	local r = render.new(p, settings)
	local g = gizmo.new(p, { settings = settings, render = r, snap = options and options.snap })
	return p, g, r
end

--- Converte uma posicao do mundo para a tela usando o mesmo mock do render.
local function toScreen(x, y, z)
	return convert3DCoordsToScreen(x, y, z)
end

t.describe('gizmo - alvos', function()
	t.test('usa o node selecionado ou a multi selecao', function()
		local p, g = fixture()
		local list, kind = g:targets()
		t.eq(#list, 1)
		t.eq(kind, 'single')
		t.eq(list[1].area, 15)
		t.eq(list[1].index, 1)

		p:toggleMulti(15, 1)
		p:toggleMulti(15, 2)
		local list2, kind2 = g:targets()
		t.eq(#list2, 2)
		t.eq(kind2, 'multi')
	end)

	t.test('sem selecao avisa', function()
		local p, g = fixture()
		p:clearSelection()
		local ok, err = g:moveBy(1, 0, 0)
		t.eq(ok, false)
		t.eq(err, i18n.t('editor.sem_selecao'))
	end)
end)

t.describe('gizmo - arrasto', function()
	t.test('arrastar move o node no plano e gera um unico undo', function()
		local p, g = fixture()
		local node = p:node(15, 1)
		local sx, sy = toScreen(node.x, node.y, node.z)
		t.ok(g:beginDrag(sx, sy))
		t.ok(g:isDragging())
		t.ok(g:updateDrag(sx + 40, sy + 20))
		local area = p:area(15)
		t.near(area.nodes[1].x, 2515, 0.001, 'o mock anda 2 unidades por pixel em x')
		t.near(area.nodes[1].y, -1694, 0.001, 'e -2 em y por pixel')
		t.near(area.nodes[1].z, 10, 0.001, 'z nao muda')
		t.eq(#p.undoStack, 0, 'nada no historico durante o arrasto')

		t.ok(g:finishDrag())
		t.eq(#p.undoStack, 1, 'uma entrada por arrasto')
		p:undo()
		t.near(p:area(15).nodes[1].x, 2495, 0.001)
		t.near(p:area(15).nodes[1].y, -1684, 0.001)
		p:redo()
		t.near(p:area(15).nodes[1].x, 2515, 0.001)
	end)

	t.test('cancelar devolve tudo e nao entra no historico', function()
		local p, g = fixture()
		local sx, sy = toScreen(2495, -1684, 10)
		g:beginDrag(sx, sy)
		g:updateDrag(sx + 100, sy)
		g:cancelDrag()
		t.near(p:area(15).nodes[1].x, 2495, 0.001)
		t.eq(#p.undoStack, 0)
		t.eq(g:isDragging(), false)
	end)

	t.test('arrasto sem mudanca nao cria historico', function()
		local p, g = fixture()
		local sx, sy = toScreen(2495, -1684, 10)
		g:beginDrag(sx, sy)
		g:updateDrag(sx, sy)
		t.eq(g:finishDrag(), false)
		t.eq(#p.undoStack, 0)
	end)

	t.test('arrastar move todos os nodes da multi selecao juntos', function()
		local p, g = fixture()
		p:clearSelection()
		p:toggleMulti(15, 1)
		p:toggleMulti(15, 2)
		local sx, sy = toScreen(2495, -1684, 10)
		g:beginDrag(sx, sy)
		g:updateDrag(sx + 20, sy)
		g:finishDrag()
		t.near(p:area(15).nodes[1].x, 2505, 0.001)
		t.near(p:area(15).nodes[2].x, 2510, 0.001, 'o segundo node anda o mesmo tanto')
		p:undo()
		t.near(p:area(15).nodes[2].x, 2500, 0.001)
	end)

	t.test('snap arredonda o movimento para a grade', function()
		local p, g = fixture({ snap = 10 })
		local sx, sy = toScreen(2495, -1684, 10)
		g:beginDrag(sx, sy)
		g:updateDrag(sx + 4, sy) -- 2 unidades: arredonda para 0
		t.eq(g:finishDrag(), false, 'movimento abaixo de meia grade nao muda nada')
		t.near(p:area(15).nodes[1].x, 2495, 0.001)

		g:beginDrag(sx, sy)
		g:updateDrag(sx + 12, sy) -- 6 unidades: arredonda para 10
		g:finishDrag()
		t.near(p:area(15).nodes[1].x, 2505, 0.001)

		g:beginDrag(sx + 12, sy)
		g:updateDrag(sx + 12 + 40, sy) -- 20 unidades
		g:finishDrag()
		t.near(p:area(15).nodes[1].x, 2525, 0.001)
	end)

	t.test('movimento grande demais e recusado', function()
		local p, g = fixture()
		g.maxStep = 5
		local sx, sy = toScreen(2495, -1684, 10)
		g:beginDrag(sx, sy)
		local ok, err = g:updateDrag(sx + 400, sy)
		t.eq(ok, false)
		t.contains(err, 'grande demais')
		t.near(p:area(15).nodes[1].x, 2495, 0.001, 'o node nao se moveu')
		g:cancelDrag()
	end)
end)

t.describe('gizmo - teclado e posicionamento', function()
	t.test('moveBy empurra o node e registra no historico', function()
		local p, g = fixture()
		t.ok(g:moveBy(1, -2, 0.5))
		t.near(p:area(15).nodes[1].x, 2496, 0.001)
		t.near(p:area(15).nodes[1].y, -1686, 0.001)
		t.near(p:area(15).nodes[1].z, 10.5, 0.001)
		p:undo()
		t.near(p:area(15).nodes[1].x, 2495, 0.001)
	end)

	t.test('moveBy sem movimento nao faz nada', function()
		local p, g = fixture()
		t.eq(g:moveBy(0, 0, 0), false)
		t.eq(#p.undoStack, 0)
	end)

	t.test('moveAxis aceita x, y e z', function()
		local p, g = fixture()
		t.ok(g:moveAxis('x', 2))
		t.ok(g:moveAxis('y', 3))
		t.ok(g:moveAxis('z', 1))
		t.near(p:area(15).nodes[1].x, 2497, 0.001)
		t.near(p:area(15).nodes[1].y, -1681, 0.001)
		t.near(p:area(15).nodes[1].z, 11, 0.001)
		t.eq(g:moveAxis('w', 1), false)
	end)

	t.test('passo depende das teclas de modificacao', function()
		local p, g = fixture()
		t.eq(g:stepFor(false, false), 1.0)
		t.eq(g:stepFor(true, false), 0.125)
		t.eq(g:stepFor(false, true), 8.0)
	end)

	t.test('travar_z impede o movimento vertical', function()
		local p, g = fixture()
		p.settings = p.settings or {}
		g.settings.edicao.travar_z = true
		g:moveBy(0, 0, 5)
		t.near(p:area(15).nodes[1].z, 10, 0.001)
		g.settings.edicao.travar_z = false
	end)

	t.test('colar no chao usa a altura do solo', function()
		local p, g = fixture()
		mock.groundZ = 25.0
		t.ok(g:putOnGround())
		t.near(p:area(15).nodes[1].z, 25.5, 0.001)
		t.eq(p:area(15).nodes[1].x, 2495, 'x e y nao mudam')
		p:undo()
		t.near(p:area(15).nodes[1].z, 10, 0.001)
		mock.groundZ = 10.0
	end)

	t.test('colar no chao avisa quando nada muda', function()
		local p, g = fixture()
		mock.groundZ = 9.5 -- node esta em 10.0 = solo + 0.5
		local ok, err = g:putOnGround()
		t.eq(ok, false)
		t.eq(err, i18n.t('edicao.sem_mudanca'))
		mock.groundZ = 10.0
	end)

	t.test('coloca o node no jogador', function()
		local p, g = fixture()
		mock.playerPos = { x = 2400.0, y = -1700.0, z = 5.0 }
		t.ok(g:putAtPlayer())
		t.near(p:area(15).nodes[1].x, 2400, 0.001)
		t.near(p:area(15).nodes[1].y, -1700, 0.001)
		t.near(p:area(15).nodes[1].z, 5.7, 0.001)
		mock.playerPos = { x = 2495.0, y = -1684.0, z = 10.0 }
	end)

	t.test('coloca o node na mira da camera', function()
		local p, g = fixture()
		mock.groundZ = 30.0
		local sx, sy = toScreen(2495, -1684, 10)
		t.ok(g:putAtCrosshair(10, 0.5))
		local node = p:area(15).nodes[1]
		t.near(node.z, 30.5, 0.001, 'caiu no chao abaixo da mira')
		t.near(node.x, 2495, 0.001, 'a mira esta exatamente em cima do node')
		t.near(node.y, -1684, 0.001)
		mock.groundZ = 10.0
	end)

	t.test('snapToGrid alinha na grade', function()
		local p, g = fixture()
		p:setNodePosition(15, 1, 2496.3, -1683.8, 10)
		t.ok(g:snapToGrid(5))
		t.near(p:area(15).nodes[1].x, 2495, 0.0001)
		t.near(p:area(15).nodes[1].y, -1685, 0.0001)
		p:undo()
		t.near(p:area(15).nodes[1].x, 2496.3, 0.0001)
	end)

	t.test('espelha o node em relacao a um ponto', function()
		local p, g = fixture()
		t.ok(g:mirrorOver(15, 1, 2500, -1684, { ground = false }))
		t.near(p:area(15).nodes[1].x, 2505, 0.001)
		t.near(p:area(15).nodes[1].y, -1684, 0.001)
	end)
end)
