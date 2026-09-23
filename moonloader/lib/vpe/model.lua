--[[
	Visual Path Editor - vpe.model
	Modelo de dados do editor: conjunto de areas carregadas, selecao, indice
	espacial, operacoes de edicao (com undo/redo) e utilidades de consulta.

	Regras importantes do formato que o modelo respeita:
	  * NodeID e o indice do node na lista (nodes de veiculo primeiro, depois pedestres).
	  * Todo link e uma referencia (AreaID, NodeID) e o jogo espera que ela exista.
	  * Navi link = 10 bits do id do navi + 6 bits da area.
]]

local util = require 'vpe.util'
local dat = require 'vpe.dat'
local geo = require 'vpe.geometry'

local M = {}

M.MAX_UNDO = 60
M.CELL_SIZE = 50
M.NEIGHBOR_SEARCH_LIMIT = 4096

--------------------------------------------------------------------------------
-- Construtor
--------------------------------------------------------------------------------

function M.new(settings)
	local p = {
		settings = settings or {},
		areas = {},          -- id -> area (carregada)
		meta = {},           -- id -> metadados (existe, origem, contagens...)
		index = {},          -- id -> indice espacial
		undoStack = {},
		redoStack = {},
		selection = { area = nil, node = nil, navi = nil },
		hovered = { area = nil, node = nil, navi = nil },
		multi = {},          -- chaves "area:node" selecionadas
		linkSource = nil,    -- { area = , node = } para criar links
		lastModified = {},   -- id -> true quando a area foi editada
	}
	setmetatable(p, { __index = M })
	return p
end

--------------------------------------------------------------------------------
-- Acesso basico
--------------------------------------------------------------------------------

--- Area carregada ou nil.
function M:area(id)
	return self.areas[id]
end

--- Metadados (contagens do cabecalho) de qualquer area, mesmo nao carregada.
function M:metaOf(id)
	return self.meta[id]
end

--- Node pelo indice (1-based) da area carregada.
function M:node(areaId, index)
	local area = self.areas[areaId]
	if not area then return nil end
	return area.nodes[index]
end

--- Node pelo NodeID do arquivo (0-based).
function M:nodeById(areaId, nodeId)
	return self:node(areaId, nodeId + 1)
end

--- Resolve um link: devolve node, area, index ou nil + motivo.
function M:resolveLink(link)
	if not link then return nil, nil, nil, 'link vazio' end
	local area = self.areas[link.area]
	if not area then return nil, nil, nil, 'area nao carregada' end
	local node = area.nodes[link.node + 1]
	if not node then return nil, nil, nil, 'node inexistente' end
	return node, area, link.node + 1
end

--- Indice de um link (por destino) dentro do node.
function M:findLink(node, areaId, nodeId)
	if not node or not node.links then return nil end
	for i = 1, #node.links do
		local l = node.links[i]
		if l.area == areaId and l.node == nodeId then return i end
	end
	return nil
end

function M:countNodes(areaId)
	local area = self.areas[areaId]
	if not area then return 0 end
	return #area.nodes
end

function M:countNavis(areaId)
	local area = self.areas[areaId]
	if not area then return 0 end
	return #area.navis
end

function M:isDirty(areaId)
	return self.lastModified[areaId] == true
end

function M:dirtyAreas()
	local list = {}
	for id in pairs(self.lastModified) do list[#list + 1] = id end
	table.sort(list)
	return list
end

--------------------------------------------------------------------------------
-- Carregar / descarregar
--------------------------------------------------------------------------------

function M:loadArea(id, area, meta)
	self.areas[id] = area
	area.id = id
	area.loaded = true
	if meta then
		self.meta[id] = meta
		self.meta[id].area = id
	end
	if not self.meta[id] then
		self.meta[id] = { area = id, exists = not area.isNew, source = area.source or 'memoria', size = 0 }
	end
	self:rebuildIndex(id)
	return area
end

--- Atualiza as contagens do cabecalho guardadas nos metadados.
--- (a validacao usa essas contagens para conferir links de areas nao carregadas)
function M:refreshMeta(id)
	local area = self.areas[id]
	if not area then return end
	local meta = self.meta[id]
	if not meta then
		meta = { area = id, exists = not area.isNew, source = area.source or 'memoria', size = 0 }
		self.meta[id] = meta
	end
	meta.area = id
	meta.counts = dat.counts(area)
	return meta
end

function M:unloadArea(id)
	self.areas[id] = nil
	self.index[id] = nil
end

function M:loadedAreas()
	local list = {}
	for id in pairs(self.areas) do list[#list + 1] = id end
	table.sort(list)
	return list
end

function M:totalNodes()
	local total = 0
	for _, area in pairs(self.areas) do total = total + #area.nodes end
	return total
end

--------------------------------------------------------------------------------
-- Indice espacial (grade de M.CELL_SIZE unidades)
--------------------------------------------------------------------------------

local function cellKey(x, y)
	return math.floor(x / M.CELL_SIZE) .. ':' .. math.floor(y / M.CELL_SIZE)
end

function M:rebuildIndex(id)
	local area = self.areas[id]
	if not area then
		self.index[id] = nil
		return
	end
	self:refreshMeta(id)
	local idx = { cells = {} }
	for i = 1, #area.nodes do
		local node = area.nodes[i]
		local key = cellKey(node.x, node.y)
		local cell = idx.cells[key]
		if not cell then
			cell = {}
			idx.cells[key] = cell
		end
		cell[#cell + 1] = i
	end
	self.index[id] = idx
end

local function indexUpdate(project, id, nodeIndex, oldX, oldY, newX, newY)
	local idx = project.index[id]
	if not idx then return end
	local oldKey = cellKey(oldX, oldY)
	local newKey = cellKey(newX, newY)
	if oldKey == newKey then return end
	local oldCell = idx.cells[oldKey]
	if oldCell then
		for i = 1, #oldCell do
			if oldCell[i] == nodeIndex then
				table.remove(oldCell, i)
				break
			end
		end
	end
	local newCell = idx.cells[newKey]
	if not newCell then
		newCell = {}
		idx.cells[newKey] = newCell
	end
	newCell[#newCell + 1] = nodeIndex
end

--- Encontra nodes perto de (x, y) dentro do raio. Retorna lista de {index, node, distance}.
--- filter pode ser 'veh', 'boat', 'ped', 'vehicle' (veh+boat), 'navi'(nao aplicavel) ou nil.
function M:nearby(areaId, x, y, radius, filter, limit)
	local area = self.areas[areaId]
	if not area then return {} end
	local out = {}
	limit = limit or M.NEIGHBOR_SEARCH_LIMIT

	local function consider(i)
		if #out >= limit then return end
		local node = area.nodes[i]
		if not node then return end
		local t = dat.nodeType(area, i)
		local okType
		if filter == nil or filter == 'all' then
			okType = true
		elseif filter == 'vehicle' then
			okType = (t == 'veh' or t == 'boat')
		else
			okType = (t == filter)
		end
		if not okType then return end
		local dist = geo.distance2d(x, y, node.x, node.y)
		if dist <= radius then
			out[#out + 1] = { index = i, node = node, distance = dist, nodeId = i - 1 }
		end
	end

	local idx = self.index[areaId]
	if idx then
		local minCx = math.floor((x - radius) / M.CELL_SIZE)
		local maxCx = math.floor((x + radius) / M.CELL_SIZE)
		local minCy = math.floor((y - radius) / M.CELL_SIZE)
		local maxCy = math.floor((y + radius) / M.CELL_SIZE)
		for cx = minCx, maxCx do
			for cy = minCy, maxCy do
				local cell = idx.cells[cx .. ':' .. cy]
				if cell then
					for k = 1, #cell do consider(cell[k]) end
				end
			end
		end
	else
		for i = 1, #area.nodes do consider(i) end
	end

	table.sort(out, function(a, b) return a.distance < b.distance end)
	return out
end

--- Node mais proximo de (x, y). filter opcional.
function M:nearestNode(areaId, x, y, maxRadius, filter)
	local list = self:nearby(areaId, x, y, maxRadius or 10.0, filter, 1)
	return list[1]
end

--- Proximo navi node de (x, y).
function M:nearestNavi(areaId, x, y, maxRadius)
	local area = self.areas[areaId]
	if not area then return nil end
	local best, bestDist
	for i = 1, #area.navis do
		local navi = area.navis[i]
		local d = geo.distance2d(x, y, navi.x, navi.y)
		if d <= (maxRadius or 10.0) and (not bestDist or d < bestDist) then
			best, bestDist = i, d
		end
	end
	if best then return { index = best, navi = area.navis[best], distance = bestDist } end
	return nil
end

--------------------------------------------------------------------------------
-- Undo / Redo
--------------------------------------------------------------------------------

function M:pushUndo(entry)
	self.undoStack[#self.undoStack + 1] = entry
	if #self.undoStack > M.MAX_UNDO then table.remove(self.undoStack, 1) end
	self.redoStack = {}
end

--- Delta simples: guarda funcoes de desfazer/refazer.
function M:pushDelta(label, undoFn, redoFn)
	self:pushUndo({ label = label, undo = undoFn, redo = redoFn })
end

--- Snapshot completo: guarda os bytes das areas antes da alteracao.
--- Usado em operacoes estruturais (criar/apagar nodes, navis, links).
function M:pushSnapshot(areaIds, label)
	local snapshot = {}
	for i = 1, #areaIds do
		local id = areaIds[i]
		local area = self.areas[id]
		if area then
			local bytes = dat.serialize(area)
			if bytes then snapshot[id] = bytes end
		end
	end
	self:pushUndo({
		label = label,
		areaIds = areaIds,
		snapshot = snapshot,
		kind = 'snapshot',
	})
end

function M:undo()
	local entry = table.remove(self.undoStack)
	if not entry then return false, 'nada para desfazer' end
	if entry.undo then
		entry.undo()
	elseif entry.kind == 'snapshot' then
		for id, bytes in pairs(entry.snapshot) do
			self:restoreSnapshot(id, bytes)
		end
	end
	self.redoStack[#self.redoStack + 1] = entry
	return true, entry.label
end

function M:redo()
	local entry = table.remove(self.redoStack)
	if not entry then return false, 'nada para refazer' end
	if entry.redo then
		entry.redo()
	elseif entry.kind == 'snapshot' then
		-- refazer um snapshot significa aplicar o "depois", guardado em entry.after
		if entry.after then
			for id, bytes in pairs(entry.after) do
				self:restoreSnapshot(id, bytes)
			end
		end
	end
	self.undoStack[#self.undoStack + 1] = entry
	if #self.undoStack > M.MAX_UNDO then table.remove(self.undoStack, 1) end
	return true, entry.label
end

--- Troca a area carregada pelos bytes guardados em um snapshot.
function M:restoreSnapshot(id, bytes)
	local area = dat.parse(bytes, id)
	if not area then return false end
	if not self.meta[id] then
		self.meta[id] = { area = id, exists = true, source = 'snapshot', size = #bytes }
	end
	self.areas[id] = area
	self:markDirty(id)
	self:rebuildIndex(id)
	return true
end

--- Guarda os bytes "depois" de um snapshot (chamar apos a operacao estrutural).
function M:closeSnapshot(label)
	local entry = self.undoStack[#self.undoStack]
	if not entry or entry.kind ~= 'snapshot' or entry.label ~= label then return end
	local after = {}
	for i = 1, #entry.areaIds do
		local id = entry.areaIds[i]
		local area = self.areas[id]
		if area then
			local bytes = dat.serialize(area)
			if bytes then after[id] = bytes end
		end
	end
	entry.after = after
end

function M:canUndo() return #self.undoStack > 0 end
function M:canRedo() return #self.redoStack > 0 end

function M:undoLabel()
	local entry = self.undoStack[#self.undoStack]
	return entry and entry.label
end

--------------------------------------------------------------------------------
-- Marcar como editada
--------------------------------------------------------------------------------

function M:markDirty(id)
	self.lastModified[id] = true
	local area = self.areas[id]
	if area then area.dirty = true end
end

function M:markClean(id)
	self.lastModified[id] = nil
	local area = self.areas[id]
	if area then area.dirty = false end
end

--------------------------------------------------------------------------------
-- Edicao: posicao e campos do node
--------------------------------------------------------------------------------

--- Move um node (com undo em delta).
function M:setNodePosition(areaId, index, x, y, z)
	local node = self:node(areaId, index)
	if not node then return false, 'node inexistente' end
	local ox, oy, oz = node.x, node.y, node.z
	if ox == x and oy == y and oz == z then return true end
	self:pushDelta(string.format('mover node a%d n%d', areaId, index - 1), function()
		node.x, node.y, node.z = ox, oy, oz
		indexUpdate(self, areaId, index, x, y, ox, oy)
	end, function()
		node.x, node.y, node.z = x, y, z
		indexUpdate(self, areaId, index, ox, oy, x, y)
	end)
	node.x, node.y, node.z = x, y, z
	indexUpdate(self, areaId, index, ox, oy, x, y)
	self:markDirty(areaId)
	return true
end

--- Move varios nodes de uma vez (usado ao arrastar uma selecao).
function M:translateNodes(list, dx, dy, dz)
	local origins = {}
	for i = 1, #list do
		local ref = list[i]
		local node = self:node(ref.area, ref.index)
		if node then
			origins[#origins + 1] = { area = ref.area, index = ref.index, x = node.x, y = node.y, z = node.z, node = node }
		end
	end
	if #origins == 0 then return false end

	local function applyOffsets(dx2, dy2, dz2)
		for i = 1, #origins do
			local o = origins[i]
			o.node.x, o.node.y, o.node.z = o.x + dx2, o.y + dy2, o.z + dz2
			indexUpdate(self, o.area, o.index, o.x, o.y, o.node.x, o.node.y)
			self:markDirty(o.area)
		end
	end

	-- applyOffsets usa deslocamentos relativos a origem: desfazer = offset zero.
	self:pushDelta(string.format('mover %d nodes', #origins),
		function() applyOffsets(0, 0, 0) end,
		function() applyOffsets(dx, dy, dz) end)
	applyOffsets(dx, dy, dz)
	return true
end

--- Posicoes atuais dos nodes de uma lista {{area=, index=}, ...}.
function M:capturePositions(list)
	local out = {}
	for i = 1, #list do
		local node = self:node(list[i].area, list[i].index)
		if node then
			out[i] = { area = list[i].area, index = list[i].index, x = node.x, y = node.y, z = node.z }
		end
	end
	return out
end

--- Aplica posicoes sem entrar no historico (usado durante um arrasto).
function M:setPositionsRaw(positions)
	for i = 1, #positions do
		local p = positions[i]
		local node = self:node(p.area, p.index)
		if node then
			indexUpdate(self, p.area, p.index, node.x, node.y, p.x, p.y)
			node.x, node.y, node.z = p.x, p.y, p.z
			self:markDirty(p.area)
		end
	end
	return true
end

--- Registra no historico um movimento ja aplicado. 'before' = posicoes antigas.
function M:pushMoveHistory(before, label)
	if not before or #before == 0 then return false end
	local after = self:capturePositions(before)
	local function applyFrom(list)
		self:setPositionsRaw(list)
	end
	self:pushDelta(label or string.format('mover %d nodes', #before),
		function() applyFrom(before) end,
		function() applyFrom(after) end)
	return true
end

--- Coloca um node no chao/agua (se as funcoes do jogo existirem).
function M:snapToGround(areaId, index, offset)
	local node = self:node(areaId, index)
	if not node then return false, 'node inexistente' end
	local z = geo.surfaceZ(node.x, node.y, node.z + 5.0)
	if not z then return false, 'nao foi possivel obter a altura do solo' end
	return self:setNodePosition(areaId, index, node.x, node.y, z + (offset or 0.5))
end

--- Altera um campo simples do node (pathWidth, floodFill, flags, heuristic...).
function M:setNodeField(areaId, index, field, value)
	local node = self:node(areaId, index)
	if not node then return false, 'node inexistente' end
	local old = node[field]
	if old == value then return true end
	self:pushDelta(string.format('alterar %s do node a%d n%d', tostring(field), areaId, index - 1), function()
		node[field] = old
	end, function()
		node[field] = value
	end)
	node[field] = value
	self:markDirty(areaId)
	return true
end

--- Altera um bit/campo das flags do node (usa dat.NODE_FLAG).
function M:setNodeFlag(areaId, index, flagName, value)
	local node = self:node(areaId, index)
	if not node then return false, 'node inexistente' end
	if type(value) == 'boolean' then value = value and 1 or 0 end
	local newFlags = dat.setNodeFlag(node.flags or 0, flagName, value)
	return self:setNodeField(areaId, index, 'flags', newFlags)
end

--- Campos do navi que na verdade sao BITS da palavra de flags (o arquivo so
--- guarda x, y, areaID, nodeID, dirX, dirY e flags).
local NAVI_FLAG_FIELDS = {
	width = 'WIDTH',              -- 0..255
	leftLanes = 'LEFT_LANES',     -- 0..7
	rightLanes = 'RIGHT_LANES',   -- 0..7
	lightDirection = 'LIGHT_DIRECTION', -- 0/1
	trafficLight = 'TRAFFIC_LIGHT',     -- 0..2
	trainCrossing = 'TRAIN_CROSSING',   -- 0/1
}

--- Grava um campo do navi. Campos de flags vao para a palavra de flags (antes
--- eram gravados como campos soltos, que o serializador simplesmente ignorava).
function M:setNaviField(areaId, naviIndex, field, value)
	local area = self.areas[areaId]
	if not area or not area.navis[naviIndex] then return false, 'navi inexistente' end
	local navi = area.navis[naviIndex]

	-- aceita true/false tambem (o painel manda 1/0, mas scripts e testes podem
	-- mandar booleano)
	if type(value) == 'boolean' then value = value and 1 or 0 end

	local flagName = NAVI_FLAG_FIELDS[field]
	local before, after
	if flagName then
		before = navi.flags or 0
		after = dat.setNaviFlag(before, flagName, value)
	else
		before = navi[field]
		after = value
	end
	if before == after then return true end

	self:pushDelta(string.format('alterar %s do navi a%d #%d', tostring(field), areaId, naviIndex - 1), function()
		if flagName then navi.flags = before else navi[field] = before end
	end, function()
		if flagName then navi.flags = after else navi[field] = after end
	end)
	if flagName then
		navi.flags = after
	else
		navi[field] = after
	end
	self:markDirty(areaId)
	return true
end

--------------------------------------------------------------------------------
-- Reindexacao (quando um node e inserido ou removido)
--------------------------------------------------------------------------------

--- Corrige todas as referencias de node apos inserir/remover um node em 'areaId'.
--- 'fromId' = NodeID a partir do qual os ids mudam; 'delta' = +1 (insercao) ou -1 (remocao).
--- 'skipArea' + 'skipIndex' permitem ignorar um node especifico (o que esta sendo removido).
function M:reindexNodeReferences(areaId, fromId, delta, skipArea, skipIndex)
	local project = self

	local function fixLinks(area, node)
		local links = node.links
		if not links then return end
		local i = 1
		while i <= #links do
			local link = links[i]
			if link.area == areaId then
				if delta < 0 and link.node == fromId then
					-- link apontava para o node removido: sai da lista
					table.remove(links, i)
				elseif link.node >= fromId then
					link.node = link.node + delta
					i = i + 1
				else
					i = i + 1
				end
			else
				i = i + 1
			end
		end
	end

	for _, area in pairs(project.areas) do
		for index = 1, #area.nodes do
			if not (skipArea and area.id == skipArea and index == skipIndex) then
				fixLinks(area, area.nodes[index])
			end
		end
	end
end

--- Corrige as referencias de navi nodes (target area/node e ids na secao 5).
--- deltaNode: ajuste no NodeID alvo; deltaNavi: ajuste nos ids de navi nodes.
function M:reindexNaviReferences(areaId, fromNodeId, nodeDelta, fromNaviId, naviDelta)
	for _, area in pairs(self.areas) do
		-- nodes alvo dos navi nodes desta area
		if area.id == areaId then
			for i = 1, #area.navis do
				local navi = area.navis[i]
				if navi.areaID == areaId and navi.nodeID >= fromNodeId and navi.nodeID < 0xFFFF then
					navi.nodeID = navi.nodeID + nodeDelta
				end
			end
		end
		-- ids de navi nodes referenciados nos links (secao 5)
		if area.id == areaId and naviDelta and naviDelta ~= 0 then
			for i = 1, #area.nodes do
				local links = area.nodes[i].links
				if links then
					for j = 1, #links do
						local link = links[j]
						if link.naviArea == areaId and link.naviID >= fromNaviId then
							link.naviID = link.naviID + naviDelta
						end
					end
				end
			end
		end
	end
end

--- Remove as referencias a um navi node que deixou de existir.
function M:clearNaviReferences(areaId, naviId)
	for _, area in pairs(self.areas) do
		if area.id == areaId then
			for i = 1, #area.nodes do
				local links = area.nodes[i].links
				if links then
					for j = 1, #links do
						local link = links[j]
						if link.naviArea == areaId and link.naviID == naviId then
							link.naviID = 0
							link.naviArea = 0
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Edicao: criar e apagar nodes
--------------------------------------------------------------------------------

local function defaultFlagsForNode(kind)
	local flags = 0
	if kind == 'boat' then
		flags = dat.setNodeFlag(flags, 'BOAT', 1)
		flags = dat.setNodeFlag(flags, 'NOT_HIGHWAY', 1)
	elseif kind == 'veh' then
		flags = dat.setNodeFlag(flags, 'NOT_HIGHWAY', 1)
	elseif kind == 'ped' then
		flags = 0
	end
	flags = dat.setNodeFlag(flags, 'SPAWN_PROBABILITY', 15)
	return flags
end

--- Cria um node. kind = 'veh' | 'boat' | 'ped'. Devolve index, nodeId.
function M:addNode(areaId, kind, x, y, z)
	local area = self.areas[areaId]
	if not area then return nil, nil, 'area nao carregada' end
	if #area.nodes >= dat.MAX_NODES then return nil, nil, 'limite de nodes atingido' end

	self:pushSnapshot({ areaId }, 'criar node')
	local node = {
		mem1 = dat.MEM_ADDRESS_DEFAULT,
		mem2 = 0,
		x = x, y = y, z = z,
		heuristic = dat.HEURISTIC_COST,
		pathWidth = (kind == 'ped') and 16 or 0,
		floodFill = (kind == 'ped') and 5 or (kind == 'boat' and 2 or 1),
		flags = defaultFlagsForNode(kind),
		links = {},
	}

	local index
	if kind == 'ped' then
		index = #area.nodes + 1
		area.nodes[index] = node
	else
		-- nodes de veiculo ficam antes dos de pedestre
		index = area.vehCount + 1
		table.insert(area.nodes, index, node)
		area.vehCount = area.vehCount + 1
		self:reindexNodeReferences(areaId, index - 1, 1)
		self:reindexNaviReferences(areaId, index - 1, 1)
	end

	self:rebuildIndex(areaId)
	self:markDirty(areaId)
	self:closeSnapshot('criar node')
	return index, index - 1
end

--- Apaga um node e tudo que aponta para ele (links e navi nodes).
function M:removeNode(areaId, index)
	local area = self.areas[areaId]
	if not area then return false, 'area nao carregada' end
	local node = area.nodes[index]
	if not node then return false, 'node inexistente' end

	self:pushSnapshot({ areaId }, 'apagar node')

	local nodeId = index - 1
	local isVehicle = index <= area.vehCount
	table.remove(area.nodes, index)
	if isVehicle then area.vehCount = area.vehCount - 1 end

	-- ajusta referencias (links e navi nodes)
	self:reindexNodeReferences(areaId, nodeId, -1)

	-- navi nodes que apontavam para este node ficam marcados como invalidos (NodeID = 0xFFFF)
	local area2 = self.areas[areaId]
	if area2 then
		for i = 1, #area2.navis do
			local navi = area2.navis[i]
			if navi.areaID == areaId then
				if navi.nodeID == nodeId then
					navi.nodeID = 0xFFFF
				elseif navi.nodeID > nodeId and navi.nodeID < 0xFFFF then
					navi.nodeID = navi.nodeID - 1
				end
			end
		end
	end

	self:rebuildIndex(areaId)
	self:markDirty(areaId)
	self:closeSnapshot('apagar node')
	return true
end

--------------------------------------------------------------------------------
-- Edicao: links
--------------------------------------------------------------------------------

local function linkLength(from, to)
	return util.clamp(util.round(geo.distance2d(from.x, from.y, to.x, to.y)), 0, 255)
end

--- Cria um link entre dois nodes (nos dois sentidos, como o jogo espera).
function M:addLink(fromArea, fromIndex, toArea, toIndex, options)
	options = options or {}
	local a1 = self.areas[fromArea]
	local a2 = self.areas[toArea]
	if not a1 or not a2 then return false, 'area nao carregada' end
	local n1 = a1.nodes[fromIndex]
	local n2 = a2.nodes[toIndex]
	if not n1 or not n2 then return false, 'node inexistente' end
	if fromArea == toArea and fromIndex == toIndex then return false, 'nao pode ligar um node a ele mesmo' end

	-- Se um dos sentidos ja existe, cria apenas o que falta (usado para
	-- consertar links sem o inverso).
	local hasForward = self:findLink(n1, toArea, toIndex - 1) ~= nil
	local hasBackward = self:findLink(n2, fromArea, fromIndex - 1) ~= nil
	if hasForward and hasBackward then return false, 'link ja existe' end
	if not hasForward and #n1.links >= dat.MAX_LINKS_PER_NODE then
		return false, string.format('node %d ja tem %d links (maximo)', fromIndex - 1, #n1.links)
	end
	local oneWay = options.oneWay == true
	if not oneWay and not hasBackward and #n2.links >= dat.MAX_LINKS_PER_NODE then
		return false, string.format('node %d ja tem %d links (maximo)', toIndex - 1, #n2.links)
	end

	self:pushSnapshot({ fromArea, toArea }, 'criar link')

	local length = linkLength(n1, n2)
	if not hasForward then
		n1.links[#n1.links + 1] = { area = toArea, node = toIndex - 1, naviArea = 0, naviID = 0, length = length }
	end
	if not oneWay and not hasBackward then
		n2.links[#n2.links + 1] = { area = fromArea, node = fromIndex - 1, naviArea = 0, naviID = 0, length = length }
	end

	self:markDirty(fromArea)
	if toArea ~= fromArea then self:markDirty(toArea) end
	self:closeSnapshot('criar link')
	return true
end

--- Remove um link (e o sentido inverso).
function M:removeLink(areaId, index, linkIndex)
	local area = self.areas[areaId]
	if not area then return false, 'area nao carregada' end
	local node = area.nodes[index]
	if not node or not node.links[linkIndex] then return false, 'link inexistente' end

	local link = node.links[linkIndex]
	local targetArea = self.areas[link.area]
	local targetNode = targetArea and targetArea.nodes[link.node + 1]

	self:pushSnapshot({ areaId, link.area }, 'apagar link')
	table.remove(node.links, linkIndex)
	if targetNode then
		local inverse = self:findLink(targetNode, areaId, index - 1)
		if inverse then table.remove(targetNode.links, inverse) end
	end
	self:markDirty(areaId)
	if link.area ~= areaId then self:markDirty(link.area) end
	self:closeSnapshot('apagar link')
	return true
end

--- Apaga todos os links de um node (nos dois sentidos).
function M:clearNodeLinks(areaId, index)
	local node = self:node(areaId, index)
	if not node then return false end
	local toRemove = {}
	for i = 1, #node.links do toRemove[i] = node.links[i] end
	local affected = { areaId }
	for i = 1, #toRemove do affected[#affected + 1] = toRemove[i].area end
	self:pushSnapshot(affected, 'limpar links do node')
	for _, link in ipairs(toRemove) do
		local targetArea = self.areas[link.area]
		local targetNode = targetArea and targetArea.nodes[link.node + 1]
		if targetNode then
			local inverse = self:findLink(targetNode, areaId, index - 1)
			if inverse then table.remove(targetNode.links, inverse) end
		end
	end
	node.links = {}
	self:markDirty(areaId)
	self:closeSnapshot('limpar links do node')
	return true
end

--- Recalcula os comprimentos de todos os links de uma area (o jogo usa isso para roteamento).
function M:recomputeLengths(areaId, onlyLinksWithTarget)
	local area = self.areas[areaId]
	if not area then return 0 end
	local changed = 0
	for i = 1, #area.nodes do
		local node = area.nodes[i]
		for j = 1, #node.links do
			local link = node.links[j]
			local targetArea = self.areas[link.area]
			local target = targetArea and targetArea.nodes[link.node + 1]
			if target then
				local newLength = linkLength(node, target)
				if link.length ~= newLength then
					link.length = newLength
					changed = changed + 1
				end
			end
		end
	end
	if changed > 0 then self:markDirty(areaId) end
	return changed
end

--------------------------------------------------------------------------------
-- Edicao: navi nodes
--------------------------------------------------------------------------------

--- Cria um navi node. Se targetNodeIndex for informado, a direcao e calculada.
function M:addNavi(areaId, x, y, targetAreaId, targetNodeIndex, options)
	options = options or {}
	local area = self.areas[areaId]
	if not area then return nil, 'area nao carregada' end
	if #area.navis >= dat.MAX_NAVI_NODES then return nil, 'limite de navi nodes atingido' end

	self:pushSnapshot({ areaId }, 'criar navi node')

	local flags = 0
	flags = dat.setNaviFlag(flags, 'WIDTH', options.width or 0)
	flags = dat.setNaviFlag(flags, 'LEFT_LANES', options.leftLanes or 1)
	flags = dat.setNaviFlag(flags, 'RIGHT_LANES', options.rightLanes or 1)
	flags = dat.setNaviFlag(flags, 'TRAFFIC_LIGHT', options.trafficLight or 0)
	flags = dat.setNaviFlag(flags, 'TRAIN_CROSSING', options.trainCrossing or 0)
	flags = dat.setNaviFlag(flags, 'LIGHT_DIRECTION', options.lightDirection or 0)

	local dirX, dirY = 0, 100
	if targetAreaId and targetNodeIndex then
		local targetArea = self.areas[targetAreaId]
		local target = targetArea and targetArea.nodes[targetNodeIndex]
		if target then
			dirX, dirY = geo.vectorToNaviBytes(target.x - x, target.y - y)
		end
	end

	local navi = {
		x = x, y = y,
		areaID = targetAreaId or areaId,
		nodeID = targetNodeIndex and (targetNodeIndex - 1) or 0xFFFF,
		dirX = dirX, dirY = dirY,
		flags = flags,
	}
	area.navis[#area.navis + 1] = navi
	self:markDirty(areaId)
	self:refreshMeta(areaId)
	self:closeSnapshot('criar navi node')
	return #area.navis
end

--- Apaga um navi node e limpa as referencias (secao 5 e reindexacao dos ids).
function M:removeNavi(areaId, naviIndex)
	local area = self.areas[areaId]
	if not area or not area.navis[naviIndex] then return false, 'navi inexistente' end

	self:pushSnapshot({ areaId }, 'apagar navi node')
	table.remove(area.navis, naviIndex)
	self:clearNaviReferences(areaId, naviIndex - 1)
	self:reindexNaviReferences(areaId, 0xFFFFF, 0, naviIndex, -1)

	self:markDirty(areaId)
	self:refreshMeta(areaId)
	self:closeSnapshot('apagar navi node')
	return true
end

--- Cria um navi node no meio de um link (como o mod CLEO fazia com P / update).
function M:addNaviOnSegment(areaId, nodeIndex, linkIndex)
	local area = self.areas[areaId]
	if not area then return nil, 'area nao carregada' end
	local node = area.nodes[nodeIndex]
	if not node or not node.links[linkIndex] then return nil, 'link inexistente' end
	local link = node.links[linkIndex]
	local targetArea = self.areas[link.area]
	local target = targetArea and targetArea.nodes[link.node + 1]
	if not target then return nil, 'link para area nao carregada' end

	-- o alvo do navi e sempre o node de id menor (regra observada nos arquivos)
	local targetAreaId, targetNodeId
	if link.area < areaId or (link.area == areaId and link.node < (nodeIndex - 1)) then
		targetAreaId, targetNodeId = link.area, link.node
	else
		targetAreaId, targetNodeId = areaId, nodeIndex - 1
	end

	local mx = (node.x + target.x) / 2
	local my = (node.y + target.y) / 2
	local mz = (node.z + target.z) / 2
	local naviIndex, err = self:addNavi(areaId, mx, my, targetAreaId, targetNodeId + 1, {
		width = node.pathWidth or 0,
		leftLanes = 1,
		rightLanes = 1,
	})
	if not naviIndex then return nil, err end

	-- liga o navi ao link (nos dois sentidos)
	self:setLinkNavi(areaId, nodeIndex, linkIndex, areaId, naviIndex - 1)
	local inverseIndex = self:findLink(target, areaId, nodeIndex - 1)
	if inverseIndex then
		self:setLinkNavi(link.area, link.node + 1, inverseIndex, areaId, naviIndex - 1)
	end
	return naviIndex
end

--- Define o navi node de um link.
function M:setLinkNavi(areaId, index, linkIndex, naviArea, naviId)
	local node = self:node(areaId, index)
	if not node or not node.links[linkIndex] then return false, 'link inexistente' end
	local link = node.links[linkIndex]
	local oldArea, oldId = link.naviArea, link.naviID
	self:pushDelta('alterar navi do link', function()
		link.naviArea, link.naviID = oldArea, oldId
	end, function()
		link.naviArea, link.naviID = naviArea, naviId
	end)
	link.naviArea, link.naviID = naviArea, naviId
	self:markDirty(areaId)
	return true
end

--------------------------------------------------------------------------------
-- Selecao
--------------------------------------------------------------------------------

function M:select(areaId, nodeIndex, naviIndex)
	self.selection.area = areaId
	self.selection.node = nodeIndex
	self.selection.navi = naviIndex
end

function M:clearSelection()
	self.selection = { area = nil, node = nil, navi = nil }
	self.multi = {}
end

function M:selectedNode()
	if self.selection.area and self.selection.node then
		return self.areas[self.selection.area] and self.areas[self.selection.area].nodes[self.selection.node]
	end
	return nil
end

function M:selectedNavi()
	if self.selection.area and self.selection.navi then
		return self.areas[self.selection.area] and self.areas[self.selection.area].navis[self.selection.navi]
	end
	return nil
end

function M:multiKey(areaId, index)
	return tostring(areaId) .. ':' .. tostring(index)
end

function M:toggleMulti(areaId, index)
	local key = self:multiKey(areaId, index)
	if self.multi[key] then
		self.multi[key] = nil
		return false
	end
	self.multi[key] = { area = areaId, index = index }
	return true
end

function M:multiList()
	local list = {}
	for _, ref in pairs(self.multi) do list[#list + 1] = ref end
	return list
end

function M:clearMulti()
	self.multi = {}
end

--------------------------------------------------------------------------------
-- Estatisticas
--------------------------------------------------------------------------------

function M:stats(areaId)
	local area = self.areas[areaId]
	if not area then return nil end
	local stats = {
		area = areaId,
		nodeCount = #area.nodes,
		vehCount = area.vehCount,
		pedCount = #area.nodes - area.vehCount,
		naviCount = #area.navis,
		linkCount = 0,
		boatCount = 0,
		isolated = 0,
		oneLink = 0,
		maxLinks = 0,
	}
	for i = 1, #area.nodes do
		local node = area.nodes[i]
		local count = #(node.links or {})
		stats.linkCount = stats.linkCount + count
		if count == 0 then stats.isolated = stats.isolated + 1 end
		if count == 1 then stats.oneLink = stats.oneLink + 1 end
		if count > stats.maxLinks then stats.maxLinks = count end
		if i <= area.vehCount and util.hasBit(node.flags or 0, 7) then stats.boatCount = stats.boatCount + 1 end
	end
	return stats
end

return M
