local t = require 'support.assert'
local mock = require 'support.mock_moonloader'
local util = require 'vpe.util'
local fs = require 'vpe.fs'
local dat = require 'vpe.dat'
local geo = require 'vpe.geometry'
local img = require 'vpe.img'
local config = require 'vpe.config'
local i18n = require 'vpe.i18n'
local appModule = require 'vpe.app'
local selftest = require 'vpe.selftest'

i18n.setLang('pt')

local GAME = os.getenv('VPE_TEST_GAME_DIR') or 'tests/tmp/game'
fs._gameDir = GAME

local ROOT = GAME .. '/appsuite'
local ML = ROOT .. '/modloader'
local MOD = ML .. '/VisualPath'
local OVERRIDE = MOD .. '/gta3.img'
local EXPORT = MOD .. '/export'
local BACKUP = MOD .. '/backup'
local VK = {
	F5 = 0x74, F6 = 0x75, F7 = 0x76, F8 = 0x77, F9 = 0x78,
	INSERT = 0x2D, DELETE = 0x2E, TAB = 0x09, RETURN = 0x0D,
	CONTROL = 0x11, L = 0x4C, G = 0x47, P = 0x50, K = 0x4B, Z = 0x5A, Y = 0x59,
}

--------------------------------------------------------------------------------
-- Fixture: um nodes15.dat escrito a mao (bytes crus), com todos os campos
--------------------------------------------------------------------------------

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function i16(v) if v < 0 then v = v + 65536 end return u16(v) end
local function u32(v)
	return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function i16c(coord) return i16(math.floor(coord * 8 + 0.5)) end

local function mkNode(x, y, z, w, flood, flags, links)
	local out = {
		u32(0x01A7FF08), u32(0), i16c(x), i16c(y), i16c(z), u16(0x7FFE),
		u16(0), u16(15), u16(0),
		string.char(w or 8), string.char(flood or 1), u32(flags or 0),
	}
	return table.concat(out), links or {}
end

--- Layout: 4 nodes de veiculo em cadeia (A<->B<->C<->D), 6 links, 1 navi node.
local function rawArea()
	local area = dat.newArea(15)
	local function addNode(x, y, z, flags, w, flood)
		area.nodes[#area.nodes + 1] = {
			mem1 = 0x01A7FF08, mem2 = 0,
			x = x, y = y, z = z,
			heuristic = 0x7FFE,
			pathWidth = w or 8, floodFill = flood or 1,
			flags = flags, links = {},
		}
		return #area.nodes
	end
	-- flags: bits 0-3 = numero de links (reescrito no serialize), bit 12 = "nao e rodovia",
	-- bits 16-19 = probabilidade de spawn
	local a = addNode(2495.0, -1684.0, 10.0, 0x00011001)
	local b = addNode(2500.0, -1684.0, 10.0, 0x00021001)
	local c = addNode(2505.0, -1684.0, 10.0, 0x00021001)
	local d = addNode(2510.0, -1684.0, 10.0, 0x00011001)
	area.vehCount = 4

	-- navi node entre A e B, apontando para B
	area.navis[1] = {
		x = 2497.5, y = -1684.0, areaID = 15, nodeID = b - 1,
		dirX = 100, dirY = 0, flags = 8 + 1 * 256 + 1 * 2048,
	}

	-- pares reciprocos: A<->B (navi 0 no sentido A->B), B<->C, C<->D
	local function linkPair(from, to, withNavi)
		local n1, n2 = area.nodes[from], area.nodes[to]
		n1.links[#n1.links + 1] = { area = 15, node = to - 1, naviArea = withNavi and 15 or 0, naviID = 0, length = 5 }
		n2.links[#n2.links + 1] = { area = 15, node = from - 1, naviArea = 0, naviID = 0, length = 5 }
	end
	linkPair(a, b, true)
	linkPair(b, c, false)
	linkPair(c, d, false)

	-- cauda marcada para conferir que o editor preserva os bytes desconhecidos
	area.tail = 'VPE!' .. string.rep('\0', 188)
	area.intersections = string.rep('\0', 6)

	local bytes, err = dat.serialize(area)
	assert(bytes, tostring(err))
	assert(#bytes == dat.expectedSize(dat.counts(area)), 'tamanho do fixture incorreto: ' .. #bytes)
	return bytes
end

local FIXTURE = rawArea()

local function resetScenario()
	for _, dir in ipairs { ROOT, ML, MOD, OVERRIDE, EXPORT, BACKUP, ROOT .. '/models' } do
		fs.shell('rm -rf "' .. dir .. '"')
	end
	fs.mkdir(OVERRIDE)
	fs.writeAll(OVERRIDE .. '/nodes15.dat', FIXTURE)
	return FIXTURE
end

local function makeSettings()
	local settings = util.deepcopy(config.defaults)
	settings.geral.idioma = 'pt'
	settings.geral.carregar_vizinhas = false
	settings.salvar.pasta_export = 'appsuite/modloader/VisualPath/export'
	settings.salvar.pasta_img = 'appsuite/modloader/VisualPath/gta3.img'
	settings.salvar.pasta_backup = 'appsuite/modloader/VisualPath/backup'
	return settings
end

local function newApp(options)
	options = options or {}
	local A = appModule.new({
		gameDir = GAME,
		modloaderDir = ML,
		settings = options.settings or makeSettings(),
		withUi = options.withUi ~= false,
		autoload = false,
		vkeys = nil,
	})
	A:init()
	A.originals = {}
	return A
end

--- App ja com a area 15 carregada (e sem UI).
local function liveApp(options)
	resetScenario()
	local A = newApp(options)
	local ok, err = A:loadArea(15)
	assert(ok, 'nao carregou a area 15: ' .. tostring(err))
	return A
end

--------------------------------------------------------------------------------
-- Ambiente / fontes
--------------------------------------------------------------------------------

t.describe('app - ambiente e fontes', function()
	t.test('carrega a area 15 do override do ModLoader', function()
		local A = liveApp()
		t.eq(#A.project:loadedAreas(), 1)
		t.eq(A.project:loadedAreas()[1], 15)
		local area = A.project:area(15)
		t.eq(#area.nodes, 4)
		t.eq(area.vehCount, 4)
		t.eq(#area.navis, 1)
		t.eq(dat.counts(area).linkCount, 6)
		local info = A.sources:info(15)
		t.eq(info.source, 'modloader')
		t.eq(info.path, OVERRIDE .. '/nodes15.dat')
	end)

	t.test('sem override, le do gta3.img', function()
		resetScenario()
		fs.remove(OVERRIDE .. '/nodes15.dat')
		fs.mkdir(ROOT .. '/models')
		local ok = img.create(ROOT .. '/models/gta3.img', { { name = 'nodes15.dat', data = FIXTURE } })
		t.ok(ok, 'criou o gta3.img')

		local A = newApp()
		A.sources.imgFiles = { 'appsuite/models/gta3.img' }
		A.sources.scanned = false
		local loaded, err = A:loadArea(15)
		t.ok(loaded, tostring(err))
		t.eq(A.sources:info(15).source, 'img')
		t.eq(#A.project:area(15).nodes, 4)

		-- dentro do gta3.img o arquivo ocupa setores de 2048 bytes: o mod guarda
		-- so a parte que pertence ao formato, senao o round-trip acusaria diferenca
		local area = A.project:area(15)
		t.eq(#A.originals[15], dat.expectedSize(dat.counts(area)), 'bytes do IMG cortados no tamanho do formato')
		local report = selftest.roundTrip(A, { 15 })
		t.eq(report.failed, 0, report.tests[1] and report.tests[1].text or '')
	end)

	t.test('area sem arquivo nenhum da erro explicado', function()
		resetScenario()
		local A = newApp()
		local ok, err = A:loadArea(20)
		t.eq(ok, false)
		t.contains(err, 'nodes20.dat')
	end)

	t.test('area sem arquivo nenhum vira uma area nova ao criar node', function()
		resetScenario()
		local A = newApp()
		local ok, err = A:loadArea(20)
		t.eq(ok, false, 'nao existe nodes20.dat')

		-- criar um node numa area sem arquivo comeca a area do zero
		-- (300, -1000) esta na area 20: coluna 4, linha 2 da grade de 750
		t.eq(geo.areaFromCoords(300.0, -1000.0), 20)
		local created, index = A:createNode('veh', 300.0, -1000.0, 12.0)
		t.ok(created, 'criou o node: ' .. tostring(index))
		t.eq(index, 1, 'primeiro node da area nova')
		t.eq(#A.project:loadedAreas(), 1)
		local area = A.project:area(20)
		t.eq(#area.nodes, 1)
		t.eq(area.isNew, true)
		t.ok(A.project:isDirty(20), 'area marcada como alterada')

		-- e o arquivo so nasce quando salvar
		t.eq(fs.exists(ML .. '/VisualPath/gta3.img/nodes20.dat'), false, 'nada gravado ainda')
		local report = A:validate({ inGame = false, silent = true })
		t.eq(report.errors, 0)
		local result = A:save({ confirmed = true })
		t.eq(result.ok, true, tostring(result.reason))
		local written = ML .. '/VisualPath/gta3.img/nodes20.dat'
		t.eq(fs.exists(written), true, 'arquivo criado')
		local back = dat.parse(fs.readAll(written), 20)
		t.ok(back, 'o arquivo gravado e legivel')
		t.eq(#back.nodes, 1)
		t.eq(back.vehCount, 1)
	end)

	t.test('criar area vazia nao sobrescreve arquivo existente', function()
		local A = liveApp()
		local ok, err = A:newArea(15)
		t.eq(ok, false, 'area 15 tem arquivo')
		t.contains(tostring(err), '15')
		t.eq(#A.project:area(15).nodes, 4, 'nada mudou')
	end)

	t.test('followPlayerTick carrega a area do jogador', function()
		resetScenario()
		local A = newApp()
		t.eq(#A.project:loadedAreas(), 0)
		t.ok(A:followPlayerTick(true), 'carregou')
		t.eq(A.project:loadedAreas()[1], 15)
		t.eq(A:followPlayerTick(true), false, 'nao recarrega a mesma area')
	end)
end)

--------------------------------------------------------------------------------
-- Edicao
--------------------------------------------------------------------------------

t.describe('app - edicao', function()
	t.test('mover, desfazer e refazer', function()
		local A = liveApp()
		A:selectNode(15, 1)
		t.ok(A:nudge(2, -3, 0.5))
		local node = A.project:node(15, 1)
		t.near(node.x, 2497, 0.001)
		t.near(node.y, -1687, 0.001)
		t.near(node.z, 10.5, 0.001)
		t.ok(A.project:isDirty(15))
		t.ok(A:undo())
		t.near(A.project:node(15, 1).x, 2495, 0.001)
		t.ok(A:redo())
		t.near(A.project:node(15, 1).x, 2497, 0.001)
	end)

	t.test('criar node na mira e selecionar', function()
		local A = liveApp()
		local ok, index = A:createNode('veh')
		t.ok(ok, 'criou')
		t.eq(index, 5, 'novo node entra logo depois dos veiculos')
		t.eq(A.project.selection.node, 5)
		t.eq(#A.project:area(15).nodes, 5)
		t.eq(A.project:area(15).vehCount, 5)
		t.ok(A.project:area(15).nodes[5].x > 0)
	end)

	t.test('criar node no modo automatico ja liga no node mais proximo', function()
		local A = liveApp()
		A.linkMode = 'auto'
		local ok, index = A:createNode('veh')
		t.ok(ok)
		local node = A.project:node(15, index)
		t.ok(#node.links >= 1, 'o node novo ganhou link')
		local target = A.project:node(15, node.links[1].node + 1)
		t.ok(target ~= nil, 'o link aponta para um node que existe')
		t.ok(index ~= node.links[1].node + 1, 'nao linka nele mesmo')
		local back = false
		for i = 1, #target.links do
			if target.links[i].area == 15 and target.links[i].node == index - 1 then back = true end
		end
		t.ok(back, 'o link de volta tambem foi criado')
	end)

	t.test('criar um navi node associa ao node de veiculo mais proximo', function()
		local A = liveApp()
		local ok, naviIndex = A:createNode('navi', 2496.0, -1684.0, 10.0)
		t.ok(ok, 'criou o navi')
		local area = A.project:area(15)
		t.eq(#area.navis, 2)
		local navi = area.navis[naviIndex]
		t.eq(navi.areaID, 15, 'aponta para a area certa')
		t.ok(navi.nodeID < #area.nodes, 'aponta para um node que existe: ' .. tostring(navi.nodeID))
		t.eq(A.project.selection.navi, naviIndex, 'o navi novo ficou selecionado')
	end)

	t.test('sem nenhum node de veiculo por perto, o navi nao e criado', function()
		local A = liveApp()
		local ok, err = A:createNode('navi', 2000.0, -1684.0, 10.0)
		t.eq(ok, false)
		t.ok(tostring(err):len() > 0, 'explicou o motivo')
		t.eq(#A.project:area(15).navis, 1, 'nada foi criado')
	end)

	t.test('criar link pela origem marcada', function()
		local A = liveApp()
		A:selectNode(15, 1)
		t.ok(A:markLinkSource())
		A:selectNode(15, 3)
		t.ok(A:createLink())
		local n1 = A.project:node(15, 1)
		t.eq(#n1.links, 2, 'origem ganhou o link')
		t.eq(n1.links[2].node, 2, 'NodeID 0-based do node 3')
		local n3 = A.project:node(15, 3)
		t.eq(#n3.links, 3, 'destino ganhou o inverso')
		local back = false
		for i = 1, #n3.links do
			if n3.links[i].area == 15 and n3.links[i].node == 0 then back = true end
		end
		t.ok(back, 'link de volta')
		t.eq(A.linkSource, nil, 'origem limpa depois de criar')
	end)

	t.test('link de sentido unico avisa a validacao', function()
		local A = liveApp()
		A.linkMode = 'unico'
		A:selectNode(15, 1)
		A:markLinkSource()
		A:selectNode(15, 3)
		A:createLink()
		t.eq(#A.project:node(15, 1).links, 2, 'a origem ganhou o link')
		local target = A.project:node(15, 3)
		for i = 1, #target.links do
			t.ok(target.links[i].node ~= 0 or target.links[i].area ~= 15, 'sem o inverso')
		end
		local report = A:validate({ inGame = false, silent = true })
		local found = false
		for _, entry in ipairs(report.entries) do
			if entry.code == 'LINK_NOT_RECIPROCAL' then found = true end
		end
		t.ok(found, 'validacao apontou o link sem inverso')
	end)

	t.test('apagar node pede confirmacao quando ele tem links', function()
		local A = liveApp()
		A:selectNode(15, 1)
		local ok, err = A:deleteSelected(false)
		t.eq(ok, false)
		t.eq(err, 'confirmar')
		t.ok(A.pendingConfirm)
		t.eq(#A.project:area(15).nodes, 4, 'nada foi apagado ainda')
		t.ok(A:confirmPending())
		t.eq(#A.project:area(15).nodes, 3)
		t.eq(A.pendingConfirm, nil)
	end)

	t.test('apagar node sem links apaga direto', function()
		local A = liveApp()
		A.linkMode = 'manual' -- sem link automatico: o node novo nasce solto
		local _, index = A:createNode('veh')
		A:selectNode(15, index)
		t.eq(#A.project:node(15, index).links, 0)
		t.ok(A:deleteSelected(false))
		t.eq(#A.project:area(15).nodes, 4)
		t.ok(A:undo())
		t.eq(#A.project:area(15).nodes, 5)
	end)

	t.test('gerar navi nodes que faltam e remover os inuteis', function()
		local A = liveApp()
		-- o fixture tem 1 navi referenced pelo link 1: nada de inutil
		t.eq(A:removeOrphanNavis(15), 0)
		t.eq(#A.project:area(15).navis, 1)

		-- os pares B<->C e C<->D nao tem navi: o gerador cria um para cada
		local created = A:generateMissingNavis(15)
		t.eq(created, 2, 'criou um navi para cada par que faltava')
		t.eq(#A.project:area(15).navis, 3)
		t.eq(A:removeOrphanNavis(15), 0, 'nenhum navi ficou sobrando')

		-- um navi solto e removido
		A.project:addNavi(15, 2503, -1684, 15, 2)
		t.eq(A:removeOrphanNavis(15), 1)
	end)

	t.test('bloqueio impede mover e apagar', function()
		local A = liveApp()
		A:selectNode(15, 2)
		A:setLocked(15, 2, true)
		local ok, err = A:nudge(5, 0, 0)
		t.eq(ok, false)
		t.contains(err, 'loqueando')
		t.near(A.project:node(15, 2).x, 2500, 0.001)
		A:setLocked(15, 2, false)
		t.ok(A:nudge(5, 0, 0))
		t.near(A.project:node(15, 2).x, 2505, 0.001)
	end)

	t.test('teclas de atalho: F7 abre o menu e F5 salva', function()
		local A = liveApp()
		t.eq(A.showMenu, false)
		mock.pressKey(VK.F7)
		A:update(0.016)
		mock.releaseKeys()
		t.eq(A.showMenu, true)
		t.eq(A.ui.visible, true)

		A:selectNode(15, 1)
		A:nudge(1, 0, 0)
		mock.pressKey(VK.F5)
		A:update(0.016)
		mock.releaseKeys()
		t.ok(A.lastSave, 'salvou pelo atalho')
		t.ok(A.lastSave.ok, 'sem erros')
	end)

	t.test('TAB anda pelos nodes proximos', function()
		local A = liveApp()
		t.ok(A:cycleNode(1))
		local first = A.project.selection.node
		t.ok(first ~= nil)
		t.ok(A:cycleNode(1))
		t.ok(A.project.selection.node ~= first)
	end)

	t.test('colar no chao usa a altura do solo', function()
		local A = liveApp()
		A:selectNode(15, 1)
		mock.groundZ = 30.0
		t.ok(A:snapGround())
		t.near(A.project:node(15, 1).z, 30.5, 0.001)
		mock.groundZ = 10.0
	end)
end)

--------------------------------------------------------------------------------
-- Validacao e salvamento
--------------------------------------------------------------------------------

t.describe('app - validacao e salvamento', function()
	t.test('validar uma area limpa nao acusa erro', function()
		local A = liveApp()
		local report = A:validate({ inGame = false, silent = true })
		t.eq(report.errors, 0)
		t.eq(report.warns, 0)
		t.eq(report.canSave, true)
	end)

	t.test('link apontando para node inexistente bloqueia o salvamento', function()
		local A = liveApp()
		A:selectNode(15, 1)
		A.project:addLink(15, 1, 15, 2)
		A.project:node(15, 1).links[#A.project:node(15, 1).links + 1] = { area = 15, node = 9999, length = 5 }
		A:changed(15)

		local result = A:save({})
		t.eq(result.ok, false)
		t.eq(result.reason, 'validation')
		t.ok(A.report.errors > 0)
		t.eq(fs.exists(OVERRIDE .. '/nodes15.dat') and fs.readAll(OVERRIDE .. '/nodes15.dat') == FIXTURE, true,
			'arquivo original intacto')
	end)

	t.test('o filtro de erros e corrigivel: applyFixes libera o salvamento', function()
		local A = liveApp()
		A.project:node(15, 1).links[#A.project:node(15, 1).links + 1] = { area = 15, node = 9999, length = 5 }
		A:changed(15)
		local report = A:validate({ inGame = false, silent = true })
		t.ok(report.errors > 0)
		local applied = A:applyFixes('1')
		t.ok(applied >= 1, 'aplicou alguma correcao')
		t.eq(A.report.errors, 0, 'sem erros depois de corrigir')
		local result = A:save({})
		t.eq(result.ok, true, 'salvou depois de corrigir')
	end)

	t.test('avisos pedem confirmacao antes de salvar', function()
		local A = liveApp()
		A.linkMode = 'unico'
		A:selectNode(15, 1)
		A:markLinkSource()
		A:selectNode(15, 3)
		A:createLink()
		local result = A:save({})
		t.eq(result.ok, false)
		t.eq(result.reason, 'warnings')
		t.ok(A.pendingConfirm and A.pendingConfirm.kind == 'save')
		t.eq(fs.readAll(OVERRIDE .. '/nodes15.dat'), FIXTURE, 'nada foi gravado')
		A:cancelPending()
		A.pendingConfirm = { kind = 'save', report = result.report }
		t.ok(A:confirmPending(), 'confirmou o salvamento')
		t.eq(fs.exists(EXPORT .. '/nodes15.dat'), true)
	end)

	t.test('salvar grava no modloader, no export e faz backup do original', function()
		local A = liveApp()
		A:selectNode(15, 1)
		A:nudge(10, 0, 0)
		local result = A:save({ force = true })
		t.eq(result.ok, true)
		t.eq(#result.errors, 0)
		t.ok(fs.exists(OVERRIDE .. '/nodes15.dat'))
		t.ok(fs.exists(EXPORT .. '/nodes15.dat'))
		t.eq(fs.readAll(BACKUP .. '/nodes15.dat'), FIXTURE, 'backup guardou o original byte a byte')
		t.eq(fs.readAll(EXPORT .. '/nodes15.dat'), fs.readAll(OVERRIDE .. '/nodes15.dat'), 'copia igual')

		local area = dat.parse(fs.readAll(OVERRIDE .. '/nodes15.dat'), 15)
		t.near(area.nodes[1].x, 2505, 0.001, 'a alteracao foi para o arquivo')
		t.eq(A.project:isDirty(15), false, 'area marcada como limpa')
		t.eq(#A.project:dirtyAreas(), 0)
	end)

	t.test('reverter e restaurar backup', function()
		local A = liveApp()
		A:selectNode(15, 1)
		A:nudge(10, 0, 0)
		A:save({ force = true })
		t.ok(A.sources:revert(15))
		t.eq(fs.exists(OVERRIDE .. '/nodes15.dat'), false)
		t.ok(A:restoreBackup(15))
		t.eq(fs.readAll(OVERRIDE .. '/nodes15.dat'), FIXTURE, 'voltou ao original')
	end)

	t.test('a pasta do mod tem prioridade e o gta3.img do jogo nao e tocado', function()
		local A = liveApp()
		local gameImg = ROOT .. '/models/gta3.img'
		fs.mkdir(ROOT .. '/models')
		img.create(gameImg, { { name = 'nodes15.dat', data = FIXTURE } })
		local before = fs.readAll(gameImg)

		A:selectNode(15, 1)
		A:nudge(10, 0, 0)
		A:save({ force = true })
		t.eq(fs.readAll(gameImg), before, 'gta3.img intacto')
		t.eq(A.sources.directImg, false)
	end)
end)

--------------------------------------------------------------------------------
-- Autoteste (round-trip byte a byte)
--------------------------------------------------------------------------------

t.describe('app - autoteste', function()
	t.test('round-trip: parse + serialize devolve os bytes originais', function()
		local A = liveApp()
		local report = selftest.roundTrip(A, { 15 })
		t.eq(report.checked, 1)
		t.eq(report.failed, 0, report.tests[1] and report.tests[1].text or '')
	end)

	t.test('round-trip continua valido depois de editar', function()
		local A = liveApp()
		A:selectNode(15, 1)
		A:nudge(1, 2, 3)
		A:createNode('veh')
		A:selectNode(15, 3)
		A:markLinkSource()
		A:selectNode(15, 5)
		A:createLink()
		A:save({ force = true })
		-- recarrega do disco e confere de novo
		A.originals[15] = nil
		local ok = A:loadArea(15, { force = true })
		t.ok(ok)
		local report = selftest.roundTrip(A, { 15 })
		t.eq(report.failed, 0, report.tests[1] and report.tests[1].text or '')
	end)

	t.test('selftest.run resume tudo', function()
		local A = liveApp()
		local result = selftest.run(A, {})
		t.ok(result.total > 0)
		t.ok(result.ok, selftest.summaryText(result))
	end)
end)

--------------------------------------------------------------------------------
-- Interface
--------------------------------------------------------------------------------

t.describe('app - interface', function()
	t.test('registra o hook do ImGui e desenha o painel', function()
		local A = liveApp({ withUi = true })
		t.ok(A.ui and A.ui.binding, 'binding carregado')
		t.eq(A.ui.hook, 'OnDrawFrame=fn')
		A:toggleMenu()
		mock.clearUiLog()
		t.ok(mock.runUiFrame(), 'desenhou')
		t.ok(mock.countCalls('Begin') == 1)
		t.ok(#mock.texts() > 3, 'escreveu informacao na tela')
	end)

	t.test('todas as abas desenham sem erro', function()
		local A = liveApp({ withUi = true })
		A:selectNode(15, 1)
		t.ok(A:markLinkSource())
		A:toggleMenu()
		A.linkMode = 'unico'
		A.newNodeKind = 'navi'
		A:validate({ inGame = false, silent = true })
		local tabs = {}
		for i = 1, #require('vpe.ui').TABS do tabs[i] = require('vpe.ui').TABS[i].id end
		for i = 1, #tabs do
			A.ui.tab = tabs[i]
			mock.clearUiLog()
			t.ok(mock.runUiFrame(), 'desenhou a aba ' .. tabs[i])
			t.ok(#mock.texts() > 0, 'a aba ' .. tabs[i] .. ' escreveu algo')
			t.eq(#mock.unbalanced(), 0, 'aba ' .. tabs[i] .. ': ImGui desbalanceado (' ..
				table.concat(mock.unbalanced(), ', ') .. ')')
		end
	end)

	t.test('clicar em "Salvar alteracoes" salva', function()
		local A = liveApp({ withUi = true })
		A:selectNode(15, 1)
		A:nudge(3, 0, 0)
		A.ui.tab = 'salvar'
		A:toggleMenu()
		mock.click(i18n.t('ui.salvar_alteracoes'))
		mock.runUiFrame()
		t.ok(A.lastSave, 'salvou pelo botao')
		t.eq(A.lastSave.ok, true)
	end)

	t.test('a confirmacao de exclusao funciona pelo modal', function()
		local A = liveApp({ withUi = true })
		A:selectNode(15, 1)
		local ok, err = A:deleteSelected(false)
		t.eq(ok, false)
		t.eq(err, 'confirmar')
		t.ok(A.pendingConfirm, 'modal pedido')
		A:toggleMenu()
		mock.clearUiLog()
		t.ok(mock.runUiFrame(), 'desenhou com o modal aberto')
		t.ok(mock.countCalls('BeginPopupModal') == 1, 'o modal apareceu')
		t.eq(#mock.unbalanced(), 0, 'modal balanceado (' .. table.concat(mock.unbalanced(), ', ') .. ')')
		mock.click(i18n.t('misc.sim'))
		mock.runUiFrame()
		t.eq(A.pendingConfirm, nil, 'confirmacao resolvida')
		t.eq(#A.project:area(15).nodes, 3, 'o node foi apagado')
		t.ok(A:undo(), 'o apagamento entrou no historico')
		t.eq(#A.project:area(15).nodes, 4)
	end)

	t.test('cancelar no modal nao apaga nada', function()
		local A = liveApp({ withUi = true })
		A:selectNode(15, 1)
		A:deleteSelected(false)
		A:toggleMenu()
		mock.clearUiLog()
		mock.runUiFrame()
		mock.click(i18n.t('misc.nao'))
		mock.runUiFrame()
		t.eq(A.pendingConfirm, nil)
		t.eq(#A.project:area(15).nodes, 4, 'nada foi apagado')
	end)

	t.test('selecionar navi e desenhar a aba com ele selecionado', function()
		local A = liveApp({ withUi = true })
		local area = A.project:area(15)
		A.project:select(15, nil, 1)
		A.ui.tab = 'navis'
		A:toggleMenu()
		mock.clearUiLog()
		t.ok(mock.runUiFrame(), 'desenhou a aba navis com um navi selecionado')
		t.ok(#mock.texts() > 0)
		t.eq(A.project.selection.navi, 1)
		t.ok(area.navis[1] ~= nil)
	end)

	t.test('clicar em "Ir" teleporta o jogador', function()
		local A = liveApp({ withUi = true })
		A:selectNode(15, 1)
		A.ui.tab = 'editor'
		A:toggleMenu()
		mock.click(i18n.t('act.ir'))
		mock.runUiFrame()
		t.near(mock.playerPos.x, 2495, 0.001)
		t.near(mock.playerPos.y, -1684, 0.001)
	end)

	t.test('menu fechado nao desenha e nao captura o mouse', function()
		local A = liveApp({ withUi = true })
		A.ui:setVisible(false)
		mock.resetImgui()
		t.eq(mock.runUiFrame(), false)
		t.eq(mock.countCalls('Begin'), 0)
		t.eq(A.ui:worldMouseEnabled(), false)
	end)
end)
