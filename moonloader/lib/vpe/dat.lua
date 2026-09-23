--[[
	Visual Path Editor - vpe.dat
	Leitura e escrita do formato binario nodes*.dat (GTA San Andreas).

	Layout (20 bytes de cabecalho + 7 secoes):

	  [ 20 bytes ] Cabecalho
	      4b - quantidade de nodes (veiculos + pedestres)
	      4b - quantidade de nodes de veiculo
	      4b - quantidade de nodes de pedestre
	      4b - quantidade de navi nodes
	      4b - quantidade de links
	  [ 28 * nodeCount ] Secao 1 - Nodes
	      4b - ponteiro interno (ignorado pelo jogo)
	      4b - sempre zero
	      6b - posicao XYZ (int16, dividir por 8 para obter unidades do mundo)
	      2b - custo heuristico (sempre 0x7FFE)
	      2b - LinkID (indice do primeiro link deste node)
	      2b - AreaID
	      2b - NodeID (indice do node na lista, comeca em 0)
	      1b - Path Width
	      1b - Flood Fill
	      4b - Flags (bits 0-3 = quantidade de links; demais bits = comportamento)
	  [ 14 * naviCount ] Secao 2 - Navi nodes
	      4b - posicao XY (int16)
	      2b - AreaID do node alvo
	      2b - NodeID do node alvo
	      2b - direcao XY (int8, normalizada * 100)
	      4b - Flags (largura, faixas, semaforo, trem)
	  [ 4 * linkCount ] Secao 3 - Links (AreaID, NodeID)
	  [ 768 bytes ] Secao 4 - Preenchimento (192 x FF FF 00 00)
	  [ 2 * linkCount ] Secao 5 - Navi links (10 bits id do navi, 6 bits area)
	  [ 1 * linkCount ] Secao 6 - Comprimento dos links
	  [ 1 * linkCount ] Secao 7 - Flags de interseccao
	  [ 192 bytes ] Cauda (conteudo desconhecido, preservado como esta no arquivo)

	O codificador foi feito para ser "round-trip": ler e gravar sem edicoes
	devolve exatamente os mesmos bytes do arquivo original.
]]

local util = require 'vpe.util'
local bit = util.bit

local M = {}

M.HEADER_SIZE = 20
M.NODE_SIZE = 28
M.NAVI_SIZE = 14
M.LINK_SIZE = 4
M.FILLER_SIZE = 768
M.TAIL_SIZE = 192
M.MAX_LINKS_PER_NODE = 15
M.MAX_NAVI_NODES = 1024
M.MAX_NODES = 65535
M.HEURISTIC_COST = 0x7FFE
M.MEM_ADDRESS_DEFAULT = 0x01A7FF08 -- valor observado nos arquivos originais

M.DEFAULT_FILLER = string.rep(string.char(0xFF, 0xFF, 0x00, 0x00), 192)

--------------------------------------------------------------------------------
-- Leitura/escrita de inteiros little-endian (sem depender de string.pack)
--------------------------------------------------------------------------------

local byte = string.byte

local function readU16(s, i)
	local a, b = byte(s, i, i + 1)
	if not a or not b then return nil end
	return a + b * 256
end

local function readI16(s, i)
	local v = readU16(s, i)
	if not v then return nil end
	if v >= 32768 then v = v - 65536 end
	return v
end

local function readU32(s, i)
	local a, b, c, d = byte(s, i, i + 3)
	if not a or not d then return nil end
	return a + b * 256 + c * 65536 + d * 16777216
end

local function readI8(s, i)
	local v = byte(s, i)
	if not v then return nil end
	if v >= 128 then v = v - 256 end
	return v
end

local function writeU16(v)
	v = math.floor(tonumber(v) or 0) % 65536
	if v < 0 then v = v + 65536 end
	return string.char(v % 256, math.floor(v / 256) % 256)
end

local function writeI16(v)
	return writeU16(util.toUnsigned16(v))
end

local function writeU32(v)
	v = tonumber(v) or 0
	v = v % 4294967296
	if v < 0 then v = v + 4294967296 end
	local b1 = v % 256
	local b2 = math.floor(v / 256) % 256
	local b3 = math.floor(v / 65536) % 256
	local b4 = math.floor(v / 16777216) % 256
	return string.char(b1, b2, b3, b4)
end

local function writeI8(v)
	v = util.round(tonumber(v) or 0)
	if v < -128 then v = -128 elseif v > 127 then v = 127 end
	if v < 0 then v = v + 256 end
	return string.char(v)
end

M.readU16, M.readI16, M.readU32, M.readI8 = readU16, readI16, readU32, readI8
M.writeU16, M.writeI16, M.writeU32, M.writeI8 = writeU16, writeI16, writeU32, writeI8

--------------------------------------------------------------------------------
-- Conversao de posicao
--------------------------------------------------------------------------------

function M.coordToInt(value)
	return util.round((tonumber(value) or 0) * 8)
end

function M.coordFromInt(value)
	return (tonumber(value) or 0) / 8
end

--- Cabecalho calculado a partir das tabelas (usado ao gravar).
function M.counts(area)
	local nodes = area.nodes or {}
	local navis = area.navis or {}
	local linkCount = 0
	for i = 1, #nodes do
		linkCount = linkCount + #(nodes[i].links or {})
	end
	local nodeCount = #nodes
	local vehCount = util.clamp(util.num(area.vehCount, nodeCount), 0, nodeCount)
	return {
		nodeCount = nodeCount,
		vehCount = vehCount,
		pedCount = nodeCount - vehCount,
		naviCount = #navis,
		linkCount = linkCount,
	}
end

--- Tamanho esperado do arquivo para o cabecalho informado.
function M.expectedSize(counts)
	return M.HEADER_SIZE
		+ M.NODE_SIZE * (counts.nodeCount or 0)
		+ M.NAVI_SIZE * (counts.naviCount or 0)
		+ M.LINK_SIZE * (counts.linkCount or 0)
		+ M.FILLER_SIZE
		+ 2 * (counts.linkCount or 0)
		+ (counts.linkCount or 0)
		+ (counts.linkCount or 0)
		+ M.TAIL_SIZE
end

--------------------------------------------------------------------------------
-- Tipos de node
--------------------------------------------------------------------------------

--- 'veh' | 'boat' | 'ped' para o indice (1-based) do node.
function M.nodeType(area, index)
	local vehCount = util.num(area.vehCount, 0)
	if index > vehCount then return 'ped' end
	local node = area.nodes[index]
	if node and util.hasBit(node.flags or 0, 7) then return 'boat' end
	return 'veh'
end

function M.isVehicleIndex(area, index)
	return index <= util.num(area.vehCount, 0)
end

function M.nodeTypeLabel(area, index)
	local t = M.nodeType(area, index)
	if t == 'ped' then return 'Ped' end
	if t == 'boat' then return 'Barco' end
	return 'Veiculo'
end

--------------------------------------------------------------------------------
-- Flags de node
--------------------------------------------------------------------------------

M.NODE_FLAG = {
	LINK_COUNT = { first = 0, count = 4 },
	TRAFFIC_LEVEL = { first = 4, count = 2 },
	ROAD_BLOCK = { first = 6, count = 1 },
	BOAT = { first = 7, count = 1 },
	EMERGENCY = { first = 8, count = 1 },
	NOT_HIGHWAY = { first = 12, count = 1 },
	HIGHWAY = { first = 13, count = 1 },
	SPAWN_PROBABILITY = { first = 16, count = 4 },
	ROAD_BLOCK_2 = { first = 20, count = 1 },
	PARKING = { first = 21, count = 1 },
	ROAD_BLOCK_3 = { first = 23, count = 1 },
}

--- Le um campo das flags de node pelo nome da tabela NODE_FLAG.
function M.getNodeFlag(flags, name)
	local f = M.NODE_FLAG[name]
	if not f then return 0 end
	return util.getBits(flags, f.first, f.count)
end

function M.setNodeFlag(flags, name, value)
	local f = M.NODE_FLAG[name]
	if not f then return flags end
	local max = 2 ^ f.count - 1
	return util.setBits(flags, f.first, f.count, util.clamp(util.round(value), 0, max))
end

M.TRAFFIC_LEVEL_NAMES = { [0] = 'FULL', [1] = 'HIGH', [2] = 'MEDIUM', [3] = 'LOW' }

--------------------------------------------------------------------------------
-- Flags de navi node
--------------------------------------------------------------------------------

M.NAVI_FLAG = {
	WIDTH = { first = 0, count = 8 },
	LEFT_LANES = { first = 8, count = 3 },
	RIGHT_LANES = { first = 11, count = 3 },
	LIGHT_DIRECTION = { first = 14, count = 1 },
	TRAFFIC_LIGHT = { first = 16, count = 2 },
	TRAIN_CROSSING = { first = 18, count = 1 },
}

function M.getNaviFlag(flags, name)
	local f = M.NAVI_FLAG[name]
	if not f then return 0 end
	return util.getBits(flags, f.first, f.count)
end

function M.setNaviFlag(flags, name, value)
	local f = M.NAVI_FLAG[name]
	if not f then return flags end
	local max = 2 ^ f.count - 1
	return util.setBits(flags, f.first, f.count, util.clamp(util.round(value), 0, max))
end

M.TRAFFIC_LIGHT_NAMES = { [0] = 'DESLIGADO', [1] = 'NORTE-SUL', [2] = 'LESTE-OESTE' }

--------------------------------------------------------------------------------
-- Navi link (16 bits: 10 bits id + 6 bits area)
--------------------------------------------------------------------------------

--- Um link tem navi node associado? (o valor cru 0 significa "nenhum")
function M.naviLinkIsSet(link)
	if not link then return false end
	return ((link.naviID or 0) ~= 0) or ((link.naviArea or 0) ~= 0)
end

function M.packNaviLink(areaId, naviId)
	areaId = util.clamp(util.num(areaId, 0), 0, 63)
	naviId = util.clamp(util.num(naviId, 0), 0, 1023)
	return bit.bor(bit.lshift(areaId, 10), naviId)
end

function M.unpackNaviLink(raw)
	raw = util.num(raw, 0)
	return bit.band(raw, 0x3FF), bit.rshift(bit.band(raw, 0xFFFF), 10) -- naviId, areaId
end

--------------------------------------------------------------------------------
-- Area vazia (para arquivos que nao existem)
--------------------------------------------------------------------------------

function M.newArea(areaId)
	return {
		id = areaId,
		nodes = {},
		navis = {},
		vehCount = 0,
		filler = M.DEFAULT_FILLER,
		intersections = '',
		tail = string.rep('\0', M.TAIL_SIZE),
		loaded = true,
		dirty = false,
		source = 'new',
		isNew = true,
		notes = {},
	}
end

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------

local function noteFor(area, text, level)
	area.notes = area.notes or {}
	area.notes[#area.notes + 1] = { level = level or 'info', text = text }
end

--- Le um arquivo nodes*.dat. Devolve (area, nil) ou (nil, erro).
--- areaId informa a qual area o arquivo pertence (normalmente o numero do arquivo).
function M.parse(data, areaId)
	if type(data) ~= 'string' then return nil, 'dados invalidos' end
	if #data < M.HEADER_SIZE then
		return nil, string.format('arquivo muito pequeno (%d bytes)', #data)
	end

	local nodeCount = readU32(data, 1)
	local vehCount = readU32(data, 5)
	local pedCount = readU32(data, 9)
	local naviCount = readU32(data, 13)
	local linkCount = readU32(data, 17)

	if nodeCount > M.MAX_NODES or naviCount > 200000 or linkCount > 3000000 then
		return nil, string.format('cabecalho suspeito (nodes=%s navis=%s links=%s)', tostring(nodeCount), tostring(naviCount), tostring(linkCount))
	end

	local area = {
		id = areaId,
		nodes = {},
		navis = {},
		vehCount = vehCount,
		loaded = true,
		dirty = false,
		header = {
			nodeCount = nodeCount,
			vehCount = vehCount,
			pedCount = pedCount,
			naviCount = naviCount,
			linkCount = linkCount,
		},
		notes = {},
	}

	local expected = M.expectedSize(area.header)
	if #data ~= expected then
		noteFor(area, string.format('tamanho do arquivo difere do esperado (%d bytes, esperado %d)', #data, expected), 'warn')
	end
	if pedCount ~= (nodeCount - vehCount) then
		noteFor(area, string.format('cabecalho inconsistente: pedCount=%d mas nodeCount-vehCount=%d', pedCount, nodeCount - vehCount), 'warn')
	end

	-- Secao 1: nodes
	local base = M.HEADER_SIZE + 1 -- primeira posicao (1-based) depois do cabecalho
	for i = 1, nodeCount do
		local p = base + (i - 1) * M.NODE_SIZE
		local node = {
			mem1 = readU32(data, p) or 0,
			mem2 = readU32(data, p + 4) or 0,
			x = M.coordFromInt(readI16(data, p + 8) or 0),
			y = M.coordFromInt(readI16(data, p + 10) or 0),
			z = M.coordFromInt(readI16(data, p + 12) or 0),
			heuristic = readU16(data, p + 14) or M.HEURISTIC_COST,
			linkID = readU16(data, p + 16) or 0,
			areaID = readU16(data, p + 18) or areaId,
			nodeID = readU16(data, p + 20) or (i - 1),
			pathWidth = byte(data, p + 22) or 0,
			floodFill = byte(data, p + 23) or 0,
			flags = readU32(data, p + 24) or 0,
			links = {},
		}
		area.nodes[i] = node
	end

	-- Secao 2: navi nodes
	local naviBase = base + M.NODE_SIZE * nodeCount
	for i = 1, naviCount do
		local p = naviBase + (i - 1) * M.NAVI_SIZE
		area.navis[i] = {
			x = M.coordFromInt(readI16(data, p) or 0),
			y = M.coordFromInt(readI16(data, p + 2) or 0),
			areaID = readU16(data, p + 4) or 0,
			nodeID = readU16(data, p + 6) or 0,
			dirX = readI8(data, p + 8) or 0,
			dirY = readI8(data, p + 9) or 0,
			flags = readU32(data, p + 10) or 0,
		}
	end

	-- Secao 3: links (AreaID, NodeID) - indices globais
	local linksBase = naviBase + M.NAVI_SIZE * naviCount
	local links = {}
	for i = 1, linkCount do
		local p = linksBase + (i - 1) * M.LINK_SIZE
		links[i] = {
			area = readU16(data, p) or 0,
			node = readU16(data, p + 2) or 0,
		}
	end

	-- Secao 5: navi links
	local naviLinksBase = linksBase + M.LINK_SIZE * linkCount + M.FILLER_SIZE
	for i = 1, linkCount do
		local raw = readU16(data, naviLinksBase + (i - 1) * 2) or 0
		local naviId, naviArea = M.unpackNaviLink(raw)
		links[i].naviID = naviId
		links[i].naviArea = naviArea
		links[i].naviRaw = raw
	end

	-- Secao 6: comprimento dos links
	local lengthsBase = naviLinksBase + 2 * linkCount
	for i = 1, linkCount do
		links[i].length = byte(data, lengthsBase + (i - 1)) or 0
	end

	-- Secao 7: flags de interseccao (1 byte por link)
	local interBase = lengthsBase + linkCount
	local interLen = math.min(linkCount, math.max(0, #data - interBase + 1))
	area.intersections = data:sub(interBase, interBase + interLen - 1)
	if interLen < linkCount then
		noteFor(area, string.format('secao de interseccoes ausente/incompleta (%d de %d bytes) - sera completada com zeros ao salvar', interLen, linkCount), 'warn')
	end

	-- Cauda (bytes apos a secao 7, preservados exatamente como no arquivo)
	local tailOffset = interBase + interLen
	area.tail = data:sub(tailOffset)
	if #area.tail < M.TAIL_SIZE then
		noteFor(area, string.format('cauda do arquivo com %d bytes (esperado %d) - sera completada ao salvar', #area.tail, M.TAIL_SIZE), 'warn')
	elseif #area.tail > M.TAIL_SIZE then
		noteFor(area, string.format('cauda do arquivo maior que o esperado (%d bytes)', #area.tail), 'info')
	end

	-- Preenchimento (secao 4) - guardado para round-trip
	local fillerStart = linksBase + M.LINK_SIZE * linkCount
	area.filler = data:sub(fillerStart, fillerStart + M.FILLER_SIZE - 1)
	if #area.filler < M.FILLER_SIZE then
		area.filler = area.filler .. M.DEFAULT_FILLER:sub(1, M.FILLER_SIZE - #area.filler)
		noteFor(area, 'secao de preenchimento ausente - sera recriada ao salvar', 'warn')
	end

	-- Liga os links aos nodes usando o LinkID + contagem (bits 0-3 das flags)
	local maxLink = math.min(linkCount, #links)
	for i = 1, nodeCount do
		local node = area.nodes[i]
		local count = util.getBits(node.flags or 0, 0, 4)
		local start = node.linkID + 1
		for j = 0, count - 1 do
			local idx = start + j
			if idx >= 1 and idx <= maxLink then
				local src = links[idx]
				node.links[#node.links + 1] = {
					area = src.area,
					node = src.node,
					naviID = src.naviID,
					naviArea = src.naviArea,
					length = src.length,
				}
			else
				noteFor(area, string.format('node %d aponta para link inexistente (linkID=%d + %d)', i - 1, node.linkID, j), 'warn')
			end
		end
		if #node.links ~= count then
			-- corrige a contagem declarada nas flags
			node.flags = util.setBits(node.flags or 0, 0, 4, #node.links)
			noteFor(area, string.format('node %d: contagem de links nas flags (%d) diferente do encontrado (%d) - corrigido em memoria', i - 1, count, #node.links), 'warn')
		end
	end

	return area
end

--------------------------------------------------------------------------------
-- Serializer
--------------------------------------------------------------------------------

--- Gera os bytes do arquivo. Devolve (string, nil) ou (nil, erro).
function M.serialize(area)
	local nodes = area.nodes or {}
	local navis = area.navis or {}

	local counts = M.counts(area)
	if counts.nodeCount > M.MAX_NODES then
		return nil, string.format('nodes demais: %d (maximo %d)', counts.nodeCount, M.MAX_NODES)
	end
	if counts.naviCount > M.MAX_NAVI_NODES then
		return nil, string.format('navi nodes demais: %d (maximo %d)', counts.naviCount, M.MAX_NAVI_NODES)
	end
	if counts.linkCount > 0xFFFF then
		return nil, string.format('links demais: %d (maximo 65535)', counts.linkCount)
	end

	-- valida limites de cada node antes de escrever
	for i = 1, counts.nodeCount do
		local node = nodes[i]
		local linkCount = #(node.links or {})
		if linkCount > M.MAX_LINKS_PER_NODE then
			return nil, string.format('node %d tem %d links (maximo %d por node)', i - 1, linkCount, M.MAX_LINKS_PER_NODE)
		end
		local x, y, z = M.coordToInt(node.x), M.coordToInt(node.y), M.coordToInt(node.z)
		if x < -32768 or x > 32767 or y < -32768 or y > 32767 or z < -32768 or z > 32767 then
			return nil, string.format('node %d tem coordenada fora do intervalo do formato (%.2f, %.2f, %.2f)', i - 1, node.x or 0, node.y or 0, node.z or 0)
		end
	end

	local out = {}
	local push = function(s) out[#out + 1] = s end

	-- Cabecalho
	push(writeU32(counts.nodeCount))
	push(writeU32(counts.vehCount))
	push(writeU32(counts.pedCount))
	push(writeU32(counts.naviCount))
	push(writeU32(counts.linkCount))

	-- Secao 1
	local linkId = 0
	for i = 1, counts.nodeCount do
		local node = nodes[i]
		local nodeFlags = util.setBits(node.flags or 0, 0, 4, #(node.links or {}))
		push(writeU32(node.mem1 or M.MEM_ADDRESS_DEFAULT))
		push(writeU32(node.mem2 or 0))
		push(writeI16(M.coordToInt(node.x)))
		push(writeI16(M.coordToInt(node.y)))
		push(writeI16(M.coordToInt(node.z)))
		push(writeU16(M.HEURISTIC_COST))
		push(writeU16(linkId))
		push(writeU16(area.id))
		push(writeU16(i - 1))
		push(string.char(util.clamp(util.round(node.pathWidth or 0), 0, 255)))
		push(string.char(util.clamp(util.round(node.floodFill or 0), 0, 255)))
		push(writeU32(nodeFlags))
		linkId = linkId + #(node.links or {})
	end

	-- Secao 2
	for i = 1, counts.naviCount do
		local navi = navis[i]
		push(writeI16(M.coordToInt(navi.x)))
		push(writeI16(M.coordToInt(navi.y)))
		push(writeU16(util.clamp(util.round(navi.areaID or 0), 0, 65535)))
		push(writeU16(util.clamp(util.round(navi.nodeID or 0), 0, 65535)))
		push(writeI8(navi.dirX or 0))
		push(writeI8(navi.dirY or 0))
		push(writeU32(navi.flags or 0))
	end

	-- Secao 3
	for i = 1, counts.nodeCount do
		local links = nodes[i].links or {}
		for j = 1, #links do
			push(writeU16(util.clamp(util.round(links[j].area or 0), 0, 65535)))
			push(writeU16(util.clamp(util.round(links[j].node or 0), 0, 65535)))
		end
	end

	-- Secao 4: preenchimento
	local filler = area.filler
	if type(filler) ~= 'string' or #filler ~= M.FILLER_SIZE then
		filler = M.DEFAULT_FILLER
	end
	push(filler)

	-- Secao 5: navi links
	for i = 1, counts.nodeCount do
		local links = nodes[i].links or {}
		for j = 1, #links do
			local link = links[j]
			push(writeU16(M.packNaviLink(link.naviArea or 0, link.naviID or 0)))
		end
	end

	-- Secao 6: comprimentos
	for i = 1, counts.nodeCount do
		local links = nodes[i].links or {}
		for j = 1, #links do
			push(string.char(util.clamp(util.round(links[j].length or 0), 0, 255)))
		end
	end

	-- Secao 7: flags de interseccao
	local inter = area.intersections
	if type(inter) ~= 'string' then inter = '' end
	if #inter < counts.linkCount then
		inter = inter .. string.rep('\0', counts.linkCount - #inter)
	end
	push(inter:sub(1, counts.linkCount))

	-- Cauda
	local tail = area.tail
	if type(tail) ~= 'string' then tail = '' end
	if #tail < M.TAIL_SIZE then
		tail = tail .. string.rep('\0', M.TAIL_SIZE - #tail)
	end
	push(tail:sub(1, M.TAIL_SIZE))

	return table.concat(out)
end

--- Compara os bytes serializados com o arquivo original (para saber o que mudou).
function M.diffSummary(area, originalData)
	if not originalData then return nil end
	local newData = M.serialize(area)
	if not newData then return nil end
	if newData == originalData then return { identical = true, oldSize = #originalData, newSize = #newData } end
	return {
		identical = false,
		oldSize = #originalData,
		newSize = #newData,
		delta = #newData - #originalData,
	}
end

return M
