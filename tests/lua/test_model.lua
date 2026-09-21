local t = require 'support.assert'
local util = require 'vpe.util'
local dat = require 'vpe.dat'
local model = require 'vpe.model'

--------------------------------------------------------------------------------
-- Ajudantes
--------------------------------------------------------------------------------

local function makeNode(x, y, z, flags)
	return {
		mem1 = dat.MEM_ADDRESS_DEFAULT,
		mem2 = 0,
		x = x, y = y, z = z,
		heuristic = dat.HEURISTIC_COST,
		pathWidth = 8,
		floodFill = 1,
		flags = flags or 0,
		links = {},
	}
end

local function link(area, nodeId, length)
	return { area = area, node = nodeId, naviArea = 0, naviID = 0, length = length or 0 }
end

--- Area 15 com 2 nodes de veiculo + 1 de pedestre, um link entre os veiculos.
local function fixture(id)
	id = id or 15
	local area = dat.newArea(id)
	local road = dat.setNodeFlag(0, 'NOT_HIGHWAY', 1)
	area.nodes[1] = makeNode(2495, -1684, 10, road)
	area.nodes[2] = makeNode(2500, -1684, 10, road)
	area.nodes[3] = makeNode(2505, -1684, 10, 0) -- pedestre
	area.vehCount = 2
	area.nodes[1].links[1] = link(id, 1, 5)
	area.nodes[2].links[1] = link(id, 0, 5)
	area.navis[1] = { x = 2497.5, y = -1684, areaID = id, nodeID = 0, dirX = 0, dirY = 100, flags = 0 }
	-- como se tivesse sido lida de um arquivo existente
	area.isNew = false
	area.source = 'gta3.img'
	return area
end

local function projectWithFixture()
	local p = model.new()
	p:loadArea(15, fixture(15))
	return p
end

--------------------------------------------------------------------------------

t.describe('model - carga de areas', function()
	t.test('carrega, lista e totaliza nodes', function()
		local p = projectWithFixture()
		t.eq(p:totalNodes(), 3)
		local list = p:loadedAreas()
		t.eq(#list, 1)
		t.eq(list[1], 15)
		t.ok(p:area(15) ~= nil)
		t.eq(p:area(99), nil)
		t.eq(p:area(15).loaded, true)
	end)

	t.test('meta e criada a partir das contagens quando nao informada', function()
		local p = projectWithFixture()
		local meta = p:metaOf(15)
		t.ok(meta ~= nil)
		t.eq(meta.counts.nodeCount, 3)
		t.eq(meta.counts.vehCount, 2)
		t.eq(meta.counts.naviCount, 1)
		t.eq(meta.counts.linkCount, 2)
		t.eq(meta.exists, true)
	end)

	t.test('unloadArea remove a area e o indice', function()
		local p = projectWithFixture()
		p:unloadArea(15)
		t.eq(p:totalNodes(), 0)
		t.eq(p:area(15), nil)
		t.eq(p.index[15], nil)
	end)

	t.test('nodeById converte o NodeID 0-based do arquivo', function()
		local p = projectWithFixture()
		t.eq(p:nodeById(15, 0).x, 2495)
		t.eq(p:nodeById(15, 2).x, 2505)
		t.eq(p:nodeById(15, 3), nil)
	end)
end)

t.describe('model - indice espacial', function()
	t.test('nearby respeita raio e filtro', function()
		local p = projectWithFixture()
		t.eq(#p:nearby(15, 2495, -1684, 3), 1)
		t.eq(#p:nearby(15, 2495, -1684, 10), 3)          -- 0, 5 e 10 unidades
		t.eq(#p:nearby(15, 2495, -1684, 10, 'ped'), 1)
		t.eq(#p:nearby(15, 2495, -1684, 3, 'ped'), 0)
		t.eq(#p:nearby(15, 2495, -1684, 10, 'vehicle'), 2) -- veh + boat
		t.eq(#p:nearby(99, 2495, -1684, 10), 0)          -- area inexistente
	end)

	t.test('nearby ordena por distancia e respeita o limite', function()
		local p = projectWithFixture()
		local list = p:nearby(15, 2495, -1684, 20)
		t.eq(list[1].index, 1)
		t.eq(list[1].distance, 0)
		t.eq(list[2].index, 2)
		local only = p:nearby(15, 2495, -1684, 20, nil, 1)
		t.eq(#only, 1)
		t.eq(only[1].index, 1)
	end)

	t.test('nearestNode e nearestNavi', function()
		local p = projectWithFixture()
		t.eq(p:nearestNode(15, 2501, -1684, 5).index, 2)
		t.eq(p:nearestNode(15, 2501, -1684, 5, 'vehicle').index, 2)
		t.eq(p:nearestNode(15, 2501, -1684, 0.5), nil)
		t.eq(p:nearestNavi(15, 2497.6, -1684, 1).index, 1)
		t.eq(p:nearestNavi(15, 2600, -1684, 1), nil)
	end)

	t.test('o indice acompanha nodes movidos', function()
		local p = projectWithFixture()
		t.ok(p:setNodePosition(15, 3, 2800, -1684, 10))
		t.eq(#p:nearby(15, 2505, -1684, 1), 0)
		local found = p:nearby(15, 2800, -1684, 1)
		t.eq(#found, 1)
		t.eq(found[1].index, 3)
	end)
end)

t.describe('model - criar e apagar nodes', function()
	t.test('addNode de veiculo entra antes dos pedestres e reindexa o resto', function()
		local p = model.new()
		local area = fixture(15)
		area.nodes[1].links[2] = link(15, 2, 5) -- link para o pedestre (NodeID 2)
		p:loadArea(15, area)

		local index, nodeId = p:addNode(15, 'veh', 2497, -1680, 11)
		t.eq(index, 3, 'indice do novo node')
		t.eq(nodeId, 2, 'NodeID do novo node')
		t.eq(#p:area(15).nodes, 4)
		t.eq(p:area(15).vehCount, 3)
		t.eq(dat.nodeType(p:area(15), 3), 'veh')
		t.eq(dat.nodeType(p:area(15), 4), 'ped')
		-- o link que apontava para o pedestre (antigo NodeID 2) foi ajustado
		t.eq(p:area(15).nodes[1].links[2].node, 3)
	end)

	t.test('addNode de pedestre vai para o fim da lista', function()
		local p = projectWithFixture()
		local index = p:addNode(15, 'ped', 2510, -1684, 10)
		t.eq(index, 4)
		t.eq(p:area(15).vehCount, 2)
		t.eq(dat.nodeType(p:area(15), 4), 'ped')
		t.eq(p:area(15).nodes[4].pathWidth, 16)
	end)

	t.test('addNode de barco define as flags de barco', function()
		local p = projectWithFixture()
		local index = p:addNode(15, 'boat', 2600, -1700, 0)
		local node = p:area(15).nodes[index]
		t.eq(dat.nodeType(p:area(15), index), 'boat')
		t.eq(util.hasBit(node.flags, 7), true)
		t.eq(p:area(15).vehCount, 3)
	end)

	t.test('removeNode de veiculo desconta vehCount e limpa links que apontavam para ele', function()
		local p = model.new()
		local area = fixture(15)
		area.nodes[1].links[2] = link(15, 2, 5) -- link extra para o pedestre (NodeID 2)
		local other = dat.newArea(16)
		other.nodes[1] = makeNode(2500, -1600, 10, 0)
		other.vehCount = 1
		other.nodes[1].links[1] = link(15, 1, 5) -- aponta para o node 2 da area 15
		p:loadArea(15, area)
		p:loadArea(16, other)
		p:setNaviField(15, 1, 'nodeID', 1) -- navi apontando para o node que sera removido

		t.ok(p:removeNode(15, 2))
		t.eq(#p:area(15).nodes, 2)
		t.eq(p:area(15).vehCount, 1)
		t.eq(#p:area(15).nodes[1].links, 1, 'o link para o node removido saiu')
		t.eq(p:area(15).nodes[1].links[1].node, 1, 'sobrou o link para o pedestre, reindexado')
		t.eq(#p:area(16).nodes[1].links, 0, 'link de outra area tambem foi limpo')
		t.eq(p:area(15).navis[1].nodeID, 0xFFFF, 'navi orfao')
	end)

	t.test('removeNode de pedestre nao altera vehCount', function()
		local p = projectWithFixture()
		t.ok(p:removeNode(15, 3))
		t.eq(p:area(15).vehCount, 2)
		t.eq(#p:area(15).nodes, 2)
	end)

	t.test('removeNode em indice invalido falha', function()
		local p = projectWithFixture()
		local ok, err = p:removeNode(15, 99)
		t.eq(ok, false)
		t.contains(err, 'inexistente')
	end)

	t.test('addNode respeita o limite de nodes', function()
		local p = model.new()
		local area = dat.newArea(20)
		local road = dat.setNodeFlag(0, 'NOT_HIGHWAY', 1)
		for i = 1, 4 do area.nodes[i] = makeNode(2400 + i, -1600, 10, road) end
		area.vehCount = 4
		p:loadArea(20, area)
		local saved = dat.MAX_NODES
		dat.MAX_NODES = 4
		local index, _, err = p:addNode(20, 'veh', 2400, -1600, 10)
		dat.MAX_NODES = saved
		t.eq(index, nil)
		t.contains(err, 'limite')
	end)
end)

t.describe('model - links', function()
	local function twoNodes()
		local p = model.new()
		local area = dat.newArea(22)
		local road = dat.setNodeFlag(0, 'NOT_HIGHWAY', 1)
		area.nodes[1] = makeNode(0, 0, 10, road)
		area.nodes[2] = makeNode(3, 4, 10, road)
		area.vehCount = 2
		p:loadArea(22, area)
		return p
	end

	t.test('addLink cria os dois sentidos com o comprimento calculado', function()
		local p = twoNodes()
		t.ok(p:addLink(22, 1, 22, 2))
		local n1, n2 = p:area(22).nodes[1], p:area(22).nodes[2]
		t.eq(#n1.links, 1)
		t.eq(#n2.links, 1)
		t.eq(n1.links[1].area, 22)
		t.eq(n1.links[1].node, 1)
		t.eq(n2.links[1].node, 0)
		t.eq(n1.links[1].length, 5) -- 3-4-5
		t.eq(n2.links[1].length, 5)
		t.isDirty = p:isDirty(22)
		t.ok(t.isDirty)
	end)

	t.test('addLink recusa duplicado, self e excesso', function()
		local p = twoNodes()
		t.ok(p:addLink(22, 1, 22, 2))
		local ok, err = p:addLink(22, 1, 22, 2)
		t.eq(ok, false)
		t.contains(err, 'ja existe')
		local ok2, err2 = p:addLink(22, 1, 22, 1)
		t.eq(ok2, false)
		t.contains(err2, 'ele mesmo')
	end)

	t.test('addLink respeita o maximo de 15 links por node', function()
		local p = model.new()
		local area = dat.newArea(23)
		local road = dat.setNodeFlag(0, 'NOT_HIGHWAY', 1)
		for i = 1, 18 do area.nodes[i] = makeNode(i * 10, 0, 10, road) end
		area.vehCount = 18
		p:loadArea(23, area)
		for i = 2, 16 do
			t.ok(p:addLink(23, 1, 23, i), 'link ' .. i)
		end
		t.eq(#p:area(23).nodes[1].links, 15)
		local ok, err = p:addLink(23, 1, 23, 17)
		t.eq(ok, false)
		t.contains(err, 'maximo')
	end)

	t.test('removeLink apaga tambem o sentido inverso', function()
		local p = twoNodes()
		p:addLink(22, 1, 22, 2)
		t.ok(p:removeLink(22, 1, 1))
		t.eq(#p:area(22).nodes[1].links, 0)
		t.eq(#p:area(22).nodes[2].links, 0)
		t.eq(p:removeLink(22, 1, 1), false)
	end)

	t.test('removeLink entre areas diferentes limpa o inverso', function()
		local p = model.new()
		local a22 = dat.newArea(22)
		local a23 = dat.newArea(23)
		local road = dat.setNodeFlag(0, 'NOT_HIGHWAY', 1)
		a22.nodes[1] = makeNode(0, 0, 10, road)
		a22.vehCount = 1
		a23.nodes[1] = makeNode(10, 0, 10, road)
		a23.vehCount = 1
		p:loadArea(22, a22)
		p:loadArea(23, a23)
		t.ok(p:addLink(22, 1, 23, 1))
		t.eq(p:area(23).nodes[1].links[1].area, 22)
		t.ok(p:removeLink(23, 1, 1))
		t.eq(#p:area(22).nodes[1].links, 0)
		t.eq(#p:area(23).nodes[1].links, 0)
	end)

	t.test('clearNodeLinks apaga todos os links do node e os inversos', function()
		local p = twoNodes()
		p:addNode(22, 'veh', 100, 0, 10)
		p:addLink(22, 1, 22, 2)
		p:addLink(22, 1, 22, 3)
		t.eq(#p:area(22).nodes[1].links, 2)
		t.ok(p:clearNodeLinks(22, 1))
		t.eq(#p:area(22).nodes[1].links, 0)
		t.eq(#p:area(22).nodes[2].links, 0)
		t.eq(#p:area(22).nodes[3].links, 0)
	end)

	t.test('recomputeLengths corrige apenas os comprimentos errados', function()
		local p = twoNodes()
		p:addLink(22, 1, 22, 2)
		p:area(22).nodes[1].links[1].length = 200
		t.eq(p:recomputeLengths(22), 1)
		t.eq(p:area(22).nodes[1].links[1].length, 5)
		t.eq(p:recomputeLengths(22), 0)
	end)
end)

t.describe('model - navi nodes', function()
	t.test('addNavi calcula a direcao para o node alvo', function()
		local p = projectWithFixture()
		local index = p:addNavi(15, 2490, -1684, 15, 1)
		t.eq(index, 2)
		local navi = p:area(15).navis[2]
		t.eq(navi.areaID, 15)
		t.eq(navi.nodeID, 0)
		t.eq(navi.dirX, 100)
		t.eq(navi.dirY, 0)
		t.eq(dat.getNaviFlag(navi.flags, 'LEFT_LANES'), 1)
	end)

	t.test('addNavi sem alvo cria um navi desconectado (0xFFFF)', function()
		local p = projectWithFixture()
		local index = p:addNavi(15, 2490, -1684)
		t.eq(p:area(15).navis[index].nodeID, 0xFFFF)
	end)

	t.test('removeNavi limpa as referencias dos links', function()
		local p = projectWithFixture()
		local naviIndex = p:addNavi(15, 2497, -1684, 15, 1)
		p:setLinkNavi(15, 1, 1, 15, naviIndex - 1)
		t.eq(p:area(15).nodes[1].links[1].naviID, naviIndex - 1)
		t.ok(p:removeNavi(15, naviIndex))
		local l = p:area(15).nodes[1].links[1]
		t.eq(l.naviID, 0)
		t.eq(l.naviArea, 0)
	end)

	t.test('removeNavi reindexa os ids dos navi nodes seguintes', function()
		local p = projectWithFixture()
		local n2 = p:addNavi(15, 2498, -1684, 15, 1)
		local n3 = p:addNavi(15, 2499, -1684, 15, 1)
		t.eq(n2, 2)
		t.eq(n3, 3)
		p:setLinkNavi(15, 1, 1, 15, n3 - 1) -- link usa o navi de id 2
		t.ok(p:removeNavi(15, n2))          -- remove o navi de id 1
		t.eq(#p:area(15).navis, 2)
		t.eq(p:area(15).nodes[1].links[1].naviID, 1, 'o id 2 virou 1')
	end)

	t.test('addNaviOnSegment coloca o navi no meio e liga os dois sentidos', function()
		local p = model.new()
		local area = fixture(15)
		area.navis = {}
		p:loadArea(15, area)
		local index = p:addNaviOnSegment(15, 2, 1) -- link do node 2 para o node 1
		t.eq(index, 1)
		local navi = p:area(15).navis[1]
		t.near(navi.x, 2497.5, 0.001)
		t.near(navi.y, -1684, 0.001)
		t.eq(navi.areaID, 15)
		t.eq(navi.nodeID, 0, 'o alvo e o node de id menor')
		t.eq(dat.getNaviFlag(navi.flags, 'WIDTH'), 8, 'herda a largura do node')
		t.eq(p:area(15).nodes[2].links[1].naviID, 0)
		t.eq(p:area(15).nodes[1].links[1].naviID, 0, 'link inverso tambem recebe o navi')
	end)

	t.test('addNaviOnSegment falha em link inexistente', function()
		local p = projectWithFixture()
		local index, err = p:addNaviOnSegment(15, 1, 9)
		t.eq(index, nil)
		t.contains(err, 'inexistente')
	end)
end)

t.describe('model - undo/redo', function()
	t.test('delta: mover node', function()
		local p = projectWithFixture()
		p:setNodePosition(15, 1, 2400, -1700, 12)
		t.eq(p:area(15).nodes[1].x, 2400)
		t.ok(p:canUndo())
		t.ok(not p:canRedo())
		local ok, label = p:undo()
		t.ok(ok)
		t.contains(label, 'mover')
		t.eq(p:area(15).nodes[1].x, 2495)
		t.eq(p:area(15).nodes[1].y, -1684)
		t.ok(p:canRedo())
		p:redo()
		t.eq(p:area(15).nodes[1].x, 2400)
	end)

	t.test('delta: alterar campo e flag', function()
		local p = projectWithFixture()
		p:setNodeField(15, 1, 'pathWidth', 20)
		p:setNodeFlag(15, 1, 'HIGHWAY', 1)
		t.eq(p:area(15).nodes[1].pathWidth, 20)
		t.eq(dat.getNodeFlag(p:area(15).nodes[1].flags, 'HIGHWAY'), 1)
		p:undo()
		t.eq(dat.getNodeFlag(p:area(15).nodes[1].flags, 'HIGHWAY'), 0)
		p:undo()
		t.eq(p:area(15).nodes[1].pathWidth, 8)
	end)

	t.test('snapshot: criar node e desfazer', function()
		local p = projectWithFixture()
		p:addNode(15, 'veh', 2400, -1700, 10)
		t.eq(#p:area(15).nodes, 4)
		local ok, label = p:undo()
		t.ok(ok)
		t.contains(label, 'criar node')
		t.eq(#p:area(15).nodes, 3, 'o snapshot restaurou a contagem')
		t.eq(p:area(15).vehCount, 2)
		t.ok(p:canRedo())
		p:redo()
		t.eq(#p:area(15).nodes, 4, 'o redo reaplica o estado depois')
		t.eq(p:area(15).vehCount, 3)
	end)

	t.test('snapshot: apagar node e desfazer', function()
		local p = projectWithFixture()
		p:removeNode(15, 2)
		t.eq(#p:area(15).nodes, 2)
		t.ok(p:undo())
		t.eq(#p:area(15).nodes, 3)
		t.eq(p:area(15).vehCount, 2)
		t.eq(p:area(15).nodes[1].links[1].node, 1, 'o link restaurado aponta de novo para o node 2')
	end)

	t.test('snapshot: criar link e desfazer', function()
		local p = projectWithFixture()
		p:addNode(15, 'veh', 2400, -1700, 10)
		local index = p:area(15).vehCount
		p:addLink(15, 1, 15, index)
		t.eq(#p:area(15).nodes[1].links, 2)
		p:undo()
		t.eq(#p:area(15).nodes[1].links, 1)
		p:redo()
		t.eq(#p:area(15).nodes[1].links, 2)
	end)

	t.test('undo/redo de snapshot avisa quando nao ha nada', function()
		local p = model.new()
		local ok, err = p:undo()
		t.eq(ok, false)
		t.contains(err, 'desfazer')
		local ok2, err2 = p:redo()
		t.eq(ok2, false)
		t.contains(err2, 'refazer')
	end)

	t.test('pushDelta limpa a pilha de redo', function()
		local p = projectWithFixture()
		p:setNodePosition(15, 1, 2400, -1700, 10)
		p:undo()
		t.ok(p:canRedo())
		p:setNodeField(15, 1, 'pathWidth', 3)
		t.ok(not p:canRedo(), 'uma edicao nova invalida o redo')
	end)

	t.test('a pilha de undo respeita MAX_UNDO', function()
		local p = projectWithFixture()
		for i = 1, model.MAX_UNDO + 5 do
			p:pushDelta('dummy ' .. i, function() end, function() end)
		end
		t.eq(#p.undoStack, model.MAX_UNDO)
		t.contains(p:undoLabel(), 'dummy 65')
	end)

	t.test('undoLabel mostra a ultima operacao', function()
		local p = projectWithFixture()
		p:setNodePosition(15, 1, 1, 1, 1)
		t.contains(p:undoLabel(), 'mover node')
	end)
end)

t.describe('model - sujeira, selecao e estatisticas', function()
	t.test('markDirty / dirtyAreas / markClean', function()
		local p = projectWithFixture()
		t.eq(p:isDirty(15), false)
		p:setNodePosition(15, 1, 2400, -1700, 10)
		t.eq(p:isDirty(15), true)
		t.eq(p:area(15).dirty, true)
		local list = p:dirtyAreas()
		t.eq(#list, 1)
		t.eq(list[1], 15)
		p:markClean(15)
		t.eq(p:isDirty(15), false)
		t.eq(#p:dirtyAreas(), 0)
	end)

	t.test('selecao de node e navi', function()
		local p = projectWithFixture()
		p:select(15, 2, 1)
		t.eq(p:selectedNode().x, 2500)
		t.eq(p:selectedNavi().x, 2497.5)
		p:clearSelection()
		t.eq(p:selectedNode(), nil)
		t.eq(p:selectedNavi(), nil)
	end)

	t.test('multi selecao', function()
		local p = projectWithFixture()
		t.eq(#p:multiList(), 0)
		t.eq(p:toggleMulti(15, 1), true)
		t.eq(p:toggleMulti(15, 3), true)
		p:setNodePosition(15, 1, 1, 1, 1)
		t.eq(#p:multiList(), 2)
		t.eq(p:toggleMulti(15, 1), false)
		t.eq(#p:multiList(), 1)
		p:clearMulti()
		t.eq(#p:multiList(), 0)
	end)

	t.test('translateNodes move todos e desfaz de uma vez', function()
		local p = projectWithFixture()
		local list = { { area = 15, index = 1 }, { area = 15, index = 2 } }
		t.ok(p:translateNodes(list, 10, 5, 0))
		t.eq(p:area(15).nodes[1].x, 2505)
		t.eq(p:area(15).nodes[2].y, -1679)
		p:undo()
		t.eq(p:area(15).nodes[1].x, 2495)
		t.eq(p:area(15).nodes[2].y, -1684)
		t.eq(p:translateNodes({}, 1, 1, 1), false)
	end)

	t.test('stats resume a area', function()
		local p = projectWithFixture()
		local s = p:stats(15)
		t.eq(s.nodeCount, 3)
		t.eq(s.vehCount, 2)
		t.eq(s.pedCount, 1)
		t.eq(s.naviCount, 1)
		t.eq(s.linkCount, 2)
		t.eq(s.boatCount, 0)
		t.eq(s.isolated, 1)
		t.eq(s.oneLink, 2)
		t.eq(s.maxLinks, 1)
		t.eq(p:stats(99), nil)
	end)

	t.test('resolveLink explica o motivo da falha', function()
		local p = projectWithFixture()
		local node, area, index = p:resolveLink({ area = 15, node = 1 })
		t.eq(node.x, 2500)
		t.eq(area.id, 15)
		t.eq(index, 2)
		local n2, _, _, why = p:resolveLink({ area = 15, node = 77 })
		t.eq(n2, nil)
		t.contains(why, 'inexistente')
		local n3, _, _, why3 = p:resolveLink({ area = 44, node = 0 })
		t.eq(n3, nil)
		t.contains(why3, 'nao carregada')
	end)
end)
