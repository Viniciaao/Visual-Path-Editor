local t = require 'support.assert'
local dat = require 'vpe.dat'
local model = require 'vpe.model'
local validate = require 'vpe.validate'
local i18n = require 'vpe.i18n'

i18n.setLang('pt')

--------------------------------------------------------------------------------

local ROAD = dat.setNodeFlag(dat.setNodeFlag(0, 'NOT_HIGHWAY', 1), 'SPAWN_PROBABILITY', 15)

local function makeNode(x, y, z)
	return {
		mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0,
		x = x, y = y, z = z,
		heuristic = dat.HEURISTIC_COST,
		pathWidth = 8, floodFill = 1,
		flags = ROAD, links = {},
	}
end

--- Area limpa: dois nodes de veiculo ligados um ao outro.
local function cleanArea(id)
	id = id or 15
	local area = dat.newArea(id)
	area.isNew = false
	area.nodes[1] = makeNode(2495, -1684, 10)
	area.nodes[2] = makeNode(2500, -1684, 10)
	area.vehCount = 2
	area.nodes[1].links[1] = { area = id, node = 1, naviArea = 0, naviID = 0, length = 5 }
	area.nodes[2].links[1] = { area = id, node = 0, naviArea = 0, naviID = 0, length = 5 }
	return area
end

local function project(area)
	local p = model.new()
	area = area or cleanArea()
	p:loadArea(area.id, area)
	return p, area
end

local function hasCode(report, code)
	for _, e in ipairs(report.entries) do
		if e.code == code then return e end
	end
	return nil
end

local function countLevel(report, level)
	local n = 0
	for _, e in ipairs(report.entries) do
		if e.level == level then n = n + 1 end
	end
	return n
end

--------------------------------------------------------------------------------

t.describe('validate - area limpa', function()
	t.test('nao acusa nada e libera o salvamento', function()
		local p = project()
		local report = validate.validateArea(p, 15)
		t.eq(report.errors, 0, 'sem erros')
		t.eq(report.warns, 0, 'sem avisos')
		t.eq(countLevel(report, 'info'), 2, 'apenas os dois "beco sem saida"')
		t.ok(report.canSave ~= false)
	end)

	t.test('validateAll marca canSave', function()
		local p = project()
		local report = validate.validateAll(p)
		t.eq(report.canSave, true)
		t.eq(report.errors, 0)
	end)
end)

t.describe('validate - links quebrados', function()
	t.test('link para node que nao existe na mesma area e erro', function()
		local p, area = project()
		area.nodes[1].links[1].node = 9
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'LINK_TARGET_MISSING')
		t.ok(e, 'esperado LINK_TARGET_MISSING')
		t.eq(e.level, 'error')
		t.eq(report.canSave == nil or report.canSave, true, 'validateArea sozinho nao calcula canSave')
		t.ok(validate.validateAll(p).canSave == false, 'erro bloqueia o salvamento')
	end)

	t.test('link para area inexistente e erro', function()
		local p, area = project()
		area.nodes[1].links[1].area = 99
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'LINK_AREA_MISSING')
		t.ok(e)
		t.eq(e.level, 'error')
	end)

	t.test('link para area valida nao carregada e apenas informativo', function()
		local p, area = project()
		area.nodes[1].links[1].area = 63
		local report = validate.validateArea(p, 15)
		t.eq(hasCode(report, 'LINK_AREA_MISSING'), nil)
		local e = hasCode(report, 'LINK_NOT_LOADED')
		t.ok(e)
		t.eq(e.level, 'info')
		t.eq(validate.validateAll(p).canSave, true, 'nao pode bloquear por falta de informacao')
	end)

	t.test('probe permite conferir o cabecalho de uma area nao carregada', function()
		local p, area = project()
		area.nodes[1].links[1].area = 16
		area.nodes[1].links[1].node = 7

		local without = validate.validateArea(p, 15)
		t.eq(hasCode(without, 'LINK_TARGET_MISSING'), nil)

		local probe = function(areaId)
			if areaId == 16 then return { nodeCount = 4, naviCount = 0 } end
			return nil
		end
		local with = validate.validateArea(p, 15, { probe = probe })
		local e = hasCode(with, 'LINK_TARGET_MISSING')
		t.ok(e, 'o probe mostrou que o node 7 nao existe')
		t.eq(e.level, 'error')
	end)

	t.test('link para ele mesmo e erro com correcao', function()
		local p, area = project()
		area.nodes[1].links[2] = { area = 15, node = 0, naviArea = 0, naviID = 0, length = 0 }
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'LINK_SELF')
		t.ok(e)
		t.eq(e.level, 'error')
		local applied, failures = validate.applyAllFixes(p, report)
		t.ok(applied >= 1)
		t.eq(failures, 0)
		t.eq(#p:area(15).nodes[1].links, 1, 'o self link foi removido')
	end)

	t.test('link duplicado e aviso com correcao', function()
		local p, area = project()
		area.nodes[1].links[2] = { area = 15, node = 1, naviArea = 0, naviID = 0, length = 5 }
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'LINK_DUPLICATED')
		t.ok(e)
		t.eq(e.level, 'warn')
		validate.applyAllFixes(p, report)
		t.eq(#p:area(15).nodes[1].links, 1)
	end)

	t.test('link sem o inverso e aviso com correcao', function()
		local p, area = project()
		area.nodes[2].links = {}
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'LINK_NOT_RECIPROCAL')
		t.ok(e)
		t.eq(e.level, 'warn')
		validate.applyAllFixes(p, report)
		t.eq(#p:area(15).nodes[2].links, 1, 'o link inverso foi criado')
	end)

	t.test('comprimento errado e aviso com correcao', function()
		local p, area = project()
		area.nodes[1].links[1].length = 200
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'LINK_LENGTH_WRONG')
		t.ok(e)
		t.eq(e.level, 'warn')
		validate.applyAllFixes(p, report)
		t.eq(p:area(15).nodes[1].links[1].length, 5)
	end)

	t.test('mais de 15 links e erro sem correcao automatica', function()
		local p, area = project()
		for i = 3, 18 do area.nodes[i] = makeNode(2500 + i, -1684, 10) end
		area.vehCount = 18
		local node = area.nodes[1]
		for i = 2, 17 do
			node.links[#node.links + 1] = { area = 15, node = i, naviArea = 0, naviID = 0, length = 5 }
		end
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'TOO_MANY_LINKS')
		t.ok(e)
		t.eq(e.level, 'error')
		t.eq(e.fix, nil)
	end)

	t.test('ped linkado com veiculo e aviso', function()
		local p, area = project()
		area.nodes[3] = makeNode(2505, -1684, 10)
		area.nodes[3].flags = 0
		area.nodes[3].pathWidth = 16
		area.nodes[1].links[2] = { area = 15, node = 2, naviArea = 0, naviID = 0, length = 10 }
		area.nodes[3].links[1] = { area = 15, node = 0, naviArea = 0, naviID = 0, length = 10 }
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'LINK_TYPE_MISMATCH')
		t.ok(e)
		t.eq(e.level, 'warn')
	end)
end)

t.describe('validate - nodes', function()
	t.test('coordenada fora do int16 e erro', function()
		local p, area = project()
		area.nodes[1].x = 9000
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'POS_OUT_OF_RANGE')
		t.ok(e)
		t.eq(e.level, 'error')
	end)

	t.test('node fora dos limites da area e aviso', function()
		local p, area = project()
		area.nodes[1].x = 1200 -- longe da area 15
		area.nodes[1].links[1].length = 200
		area.nodes[2].links[1].length = 200
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'POS_OUTSIDE_AREA')
		t.ok(e)
		t.eq(e.level, 'warn')
	end)

	t.test('node isolado e aviso; area vazia nao quebra', function()
		local p, area = project()
		area.nodes[3] = makeNode(2900, -1684, 10)
		p:rebuildIndex(15)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NODE_ISOLATED')
		t.ok(e)
		t.eq(e.level, 'warn')
	end)

	t.test('nodes sobrepostos e aviso', function()
		local p, area = project()
		area.nodes[2].x = area.nodes[1].x
		area.nodes[2].y = area.nodes[1].y
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NODE_OVERLAP')
		t.ok(e)
		t.eq(e.level, 'warn')
	end)

	t.test('area nao carregada e apenas informativo', function()
		local p = model.new()
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'AREA_NOT_LOADED')
		t.ok(e)
		t.eq(report.errors, 0)
	end)
end)

t.describe('validate - navi nodes', function()
	t.test('navi desconectado (0xFFFF) e erro com correcao', function()
		local p, area = project()
		local index = p:addNavi(15, 2497, -1684)
		t.eq(p:area(15).navis[index].nodeID, 0xFFFF)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_NOT_CONNECTED')
		t.ok(e)
		t.eq(e.level, 'error')
		t.ok(e.fix, 'tem correcao automatica')

		local applied = validate.applyAllFixes(p, report)
		t.ok(applied >= 1)
		t.eq(p:area(15).navis[index].nodeID, 0, 'conectado ao node mais proximo')
		local again = validate.validateArea(p, 15)
		t.eq(hasCode(again, 'NAVI_NOT_CONNECTED'), nil)
	end)

	t.test('a correcao falha quando nao ha node de veiculo perto', function()
		local p = project()
		local index = p:addNavi(15, 2600, -1600)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_NOT_CONNECTED')
		t.ok(e)
		local ok, err = e.fix()
		t.eq(ok, false)
		t.ok(err ~= nil)
		local applied, failures = validate.applyAllFixes(p, report)
		t.eq(applied, 0)
		t.ok(failures >= 1, 'conta a falha da correcao')
	end)

	t.test('a correcao alternativa (fix2) remove o navi node', function()
		local p = project()
		local index = p:addNavi(15, 2600, -1600)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_NOT_CONNECTED')
		local applied = validate.applyAllFixes(p, report, '2')
		t.eq(applied, 1)
		t.eq(#p:area(15).navis, 0)
	end)

	t.test('navi apontando para node inexistente e erro', function()
		local p, area = project()
		local index = p:addNavi(15, 2497, -1684, 15, 1)
		p:setNaviField(15, index, 'nodeID', 40)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_TARGET_MISSING')
		t.ok(e)
		t.eq(e.level, 'error')
	end)

	t.test('navi apontando para node de pedestre e aviso', function()
		local p, area = project()
		area.nodes[3] = makeNode(2505, -1684, 10)
		area.nodes[3].flags = 0
		p:rebuildIndex(15)
		local index = p:addNavi(15, 2505, -1684, 15, 3)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_TARGET_IS_PED')
		t.ok(e)
		t.eq(e.level, 'warn')
	end)

	t.test('navi sem faixas e sem link e avisado', function()
		local p = project()
		local index = p:addNavi(15, 2497, -1684, 15, 1)
		p:setNaviField(15, index, 'flags', 0)
		local report = validate.validateArea(p, 15)
		t.ok(hasCode(report, 'NAVI_NO_LANES'))
		t.ok(hasCode(report, 'NAVI_NOT_LINKED'))
		t.eq(report.errors, 0)
	end)

	t.test('direcao zerada e aviso com correcao', function()
		local p = project()
		local index = p:addNavi(15, 2497, -1684, 15, 1)
		p:setNaviField(15, index, 'dirX', 0)
		p:setNaviField(15, index, 'dirY', 0)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_DIRECTION_ZERO')
		t.ok(e)
		t.eq(e.level, 'warn')
		validate.applyAllFixes(p, report)
		t.ok(p:area(15).navis[index].dirX ~= 0 or p:area(15).navis[index].dirY ~= 0)
	end)

	t.test('navi link apontando para id inexistente e erro', function()
		local p, area = project()
		area.nodes[1].links[1].naviArea = 15
		area.nodes[1].links[1].naviID = 5
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_LINK_OUT_OF_RANGE')
		t.ok(e)
		t.eq(e.level, 'error')
		validate.applyAllFixes(p, report)
		t.eq(p:area(15).nodes[1].links[1].naviID, 0)
	end)

	t.test('navi link em node de pedestre e aviso', function()
		local p, area = project()
		area.nodes[3] = makeNode(2505, -1684, 10)
		area.nodes[3].flags = 0
		area.nodes[3].links[1] = { area = 15, node = 1, naviArea = 15, naviID = 0, length = 5 }
		area.nodes[2].links[2] = { area = 15, node = 2, naviArea = 0, naviID = 0, length = 5 }
		p:rebuildIndex(15)
		local report = validate.validateArea(p, 15)
		local e = hasCode(report, 'NAVI_LINK_ON_PED')
		t.ok(e)
		t.eq(e.level, 'warn')
	end)
end)

t.describe('validate - aplicar correcoes', function()
	t.test('applyAllFixes resolve os problemas corrigiveis', function()
		local p, area = project()
		area.nodes[2].links = {}                                   -- sem inverso
		area.nodes[1].links[1].length = 200                        -- comprimento errado
		area.nodes[1].links[2] = { area = 15, node = 1, naviArea = 0, naviID = 0, length = 0 } -- duplicado
		area.nodes[1].links[3] = { area = 15, node = 0, naviArea = 0, naviID = 0, length = 0 } -- self
		local report = validate.validateArea(p, 15)
		t.ok(report.errors >= 1)
		local applied, failures = validate.applyAllFixes(p, report)
		t.ok(applied >= 3, 'aplicadas: ' .. tostring(applied))
		t.eq(failures, 0)
		local again = validate.validateArea(p, 15)
		t.eq(again.errors, 0, 'sem erros depois das correcoes')
		t.ok(hasCode(again, 'LINK_DUPLICATED') == nil)
		t.eq(p:area(15).nodes[1].links[1].length, 5)
	end)

	t.test('validateAll ordena erros antes de avisos e infos', function()
		local p, area = project()
		area.nodes[1].x = 9000                    -- erro
		area.nodes[2].links = {}                  -- aviso (sem inverso)
		area.nodes[1].links[1].area = 63          -- info (area nao carregada)
		local report = validate.validateAll(p)
		t.eq(report.entries[1].level, 'error')
		local last = report.entries[#report.entries]
		t.eq(last.level, 'info')
		t.eq(report.canSave, false)
	end)
end)
