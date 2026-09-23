local t = require 'support.assert'
local dat = require 'vpe.dat'
local util = require 'vpe.util'

--- Monta uma area sintetica parecida com um arquivo real.
local function buildSampleArea(areaId)
	areaId = areaId or 15
	local area = dat.newArea(areaId)
	area.vehCount = 3
	area.nodes = {
		{ mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = 2490.5, y = -1680.25, z = 10.5, flags = 0, pathWidth = 0, floodFill = 1,
		  links = {
			  { area = areaId, node = 1, naviID = 0, naviArea = areaId, length = 12 },
			  { area = areaId, node = 2, naviID = 1, naviArea = areaId, length = 30 },
		  } },
		{ mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = 2500.0, y = -1690.0, z = 10.0, flags = 0, pathWidth = 2, floodFill = 1,
		  links = {
			  { area = areaId, node = 0, naviID = 0, naviArea = areaId, length = 12 },
			  { area = areaId, node = 2, naviID = 2, naviArea = areaId, length = 20 },
		  } },
		{ mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = 2510.0, y = -1700.0, z = 9.75, flags = util.setBit(0, 7, true), pathWidth = 0, floodFill = 2,
		  links = {
			  { area = areaId, node = 0, naviID = 1, naviArea = areaId, length = 30 },
			  { area = areaId, node = 1, naviID = 2, naviArea = areaId, length = 20 },
		  } },
		{ mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = 2495.0, y = -1685.0, z = 10.25, flags = 0, pathWidth = 16, floodFill = 5,
		  links = {} },
	}
	area.navis = {
		{ x = 2495.0, y = -1685.0, areaID = areaId, nodeID = 0, dirX = 70, dirY = -70, flags = util.setBits(util.setBits(0, 0, 8, 0), 8, 3, 1) },
		{ x = 2505.0, y = -1695.0, areaID = areaId, nodeID = 1, dirX = -70, dirY = 70, flags = util.setBits(0, 11, 3, 1) },
		{ x = 2515.0, y = -1705.0, areaID = areaId, nodeID = 2, dirX = 0, dirY = 100, flags = 0 },
	}
	return area
end

t.describe('dat - formatos binarios', function()
	t.test('le e escreve inteiros little-endian', function()
		t.eq(dat.readU16(dat.writeU16(0xABCD), 1), 0xABCD)
		t.eq(dat.readI16(dat.writeI16(-1234), 1), -1234)
		t.eq(dat.readU32(dat.writeU32(0xDEADBEEF), 1), 0xDEADBEEF)
		t.eq(dat.readI8(dat.writeI8(-100), 1), -100)
		t.eq(dat.readU16(dat.writeU16(65535), 1), 65535)
	end)

	t.test('converte coordenadas (x8)', function()
		t.eq(dat.coordToInt(10.5), 84)
		t.near(dat.coordFromInt(84), 10.5)
		t.eq(dat.coordToInt(-0.25), -2)
	end)
end)

t.describe('dat - round trip', function()
	t.test('serialize e parse preservam todos os campos', function()
		local area = buildSampleArea()
		local bytes, err = dat.serialize(area)
		t.ok(bytes, 'serialize falhou: ' .. tostring(err))

		local parsed = dat.parse(bytes, area.id)
		t.ok(parsed, 'parse falhou')
		t.eq(#parsed.nodes, 4)
		t.eq(#parsed.navis, 3)
		t.eq(parsed.vehCount, 3)
		t.eq(#parsed.nodes[1].links, 2)
		t.near(parsed.nodes[1].x, 2490.5)
		t.near(parsed.nodes[1].y, -1680.25)
		t.near(parsed.nodes[1].z, 10.5)
		t.eq(parsed.nodes[1].mem1, dat.MEM_ADDRESS_DEFAULT)
		t.eq(parsed.nodes[1].links[1].node, 1)
		t.eq(parsed.nodes[1].links[2].length, 30)
		t.eq(parsed.nodes[1].links[2].naviID, 1)
		t.eq(parsed.nodes[1].links[2].naviArea, area.id)
		t.eq(parsed.nodes[2].pathWidth, 2)
		t.eq(parsed.nodes[3].floodFill, 2)
		t.ok(util.hasBit(parsed.nodes[3].flags, 7), 'flag de barco')
		t.eq(parsed.nodes[4].pathWidth, 16)
		t.eq(parsed.navis[1].dirX, 70)
		t.eq(parsed.navis[1].dirY, -70)
		t.eq(dat.getNaviFlag(parsed.navis[1].flags, 'LEFT_LANES'), 1)
		t.eq(dat.getNaviFlag(parsed.navis[2].flags, 'RIGHT_LANES'), 1)
		t.eq(parsed.nodes[2].nodeID, 1)
		t.eq(parsed.nodes[2].areaID, area.id)
	end)

	t.test('bytes de ida e volta sao identicos', function()
		local area = buildSampleArea()
		local bytes = dat.serialize(area)
		local parsed = dat.parse(bytes, area.id)
		local bytes2 = dat.serialize(parsed)
		t.eq(bytes2, bytes, 'round trip naive')
		local parsed2 = dat.parse(bytes2, area.id)
		t.eq(dat.serialize(parsed2), bytes, 'round trip duplo')
	end)

	t.test('tamanho do arquivo segue a formula do formato', function()
		local area = buildSampleArea()
		local bytes = dat.serialize(area)
		local counts = dat.counts(area)
		t.eq(counts.nodeCount, 4)
		t.eq(counts.vehCount, 3)
		t.eq(counts.pedCount, 1)
		t.eq(counts.naviCount, 3)
		t.eq(counts.linkCount, 6)
		t.eq(#bytes, dat.expectedSize(counts))
		t.eq(#bytes, 20 + 28 * 4 + 14 * 3 + 4 * 6 + 768 + 2 * 6 + 6 + 6 + 192)
	end)

	t.test('cabecalho e secoes ficam nas posicoes corretas', function()
		local area = buildSampleArea()
		local bytes = dat.serialize(area)
		t.eq(dat.readU32(bytes, 1), 4)
		t.eq(dat.readU32(bytes, 5), 3)
		t.eq(dat.readU32(bytes, 9), 1)
		t.eq(dat.readU32(bytes, 13), 3)
		t.eq(dat.readU32(bytes, 17), 6)

		-- primeiro node
		t.eq(dat.readU32(bytes, 21), dat.MEM_ADDRESS_DEFAULT)
		t.eq(dat.readI16(bytes, 29), dat.coordToInt(2490.5))
		t.eq(dat.readU16(bytes, 37), 0)      -- linkID do primeiro node
		t.eq(dat.readU16(bytes, 39), area.id) -- areaID
		t.eq(dat.readU16(bytes, 41), 0)      -- nodeID
		t.eq(bytes:byte(43), 0)              -- path width
		t.eq(bytes:byte(44), 1)              -- flood fill
		t.eq(util.getBits(dat.readU32(bytes, 45), 0, 4), 2) -- contagem de links

		-- preenchimento comeca depois dos links
		local fillerStart = 20 + 28 * 4 + 14 * 3 + 4 * 6 + 1
		t.eq(bytes:sub(fillerStart, fillerStart + 3), string.char(0xFF, 0xFF, 0x00, 0x00))
	end)

	t.test('heuristica e reescrita das flags de contagem de links', function()
		local area = buildSampleArea()
		-- estraga de proposito: flags dizem 5 links, mas existem 2
		area.nodes[1].flags = util.setBits(area.nodes[1].flags, 0, 4, 5)
		local bytes = dat.serialize(area)
		local parsed = dat.parse(bytes, area.id)
		t.eq(util.getBits(parsed.nodes[1].flags, 0, 4), 2, 'contagem corrigida')
		t.eq(parsed.nodes[1].heuristic, dat.HEURISTIC_COST)
	end)

	t.test('rejeita coordenadas fora do intervalo int16', function()
		local area = dat.newArea(0)
		area.nodes = { { x = 100000, y = 0, z = 0, flags = 0, links = {} } }
		local bytes, err = dat.serialize(area)
		t.eq(bytes, nil)
		t.contains(err, 'coordenada')
	end)

	t.test('rejeita mais de 15 links por node', function()
		local area = dat.newArea(0)
		local links = {}
		for i = 1, 16 do links[i] = { area = 0, node = 0, length = 1 } end
		area.nodes = { { x = 0, y = 0, z = 0, links = links, flags = 0 } }
		local bytes, err = dat.serialize(area)
		t.eq(bytes, nil)
		t.contains(err, 'links')
	end)

	t.test('detecta e completa arquivo truncado (bug do mod CLEO)', function()
		local area = buildSampleArea()
		local bytes = dat.serialize(area)
		-- remove a secao de interseccoes e a cauda (como o mod CLEO fazia)
		local truncated = bytes:sub(1, #bytes - 192 - 6)
		local parsed, err = dat.parse(truncated, area.id)
		t.ok(parsed, 'deveria conseguir ler mesmo truncado: ' .. tostring(err))
		t.eq(#parsed.intersections, 0)
		local fixed = dat.serialize(parsed)
		t.eq(#fixed, #bytes, 'arquivo corrigido volta ao tamanho certo')
		t.eq(#parsed.notes > 0, true, 'registra observacoes sobre o arquivo')
	end)

	t.test('nao aceita lixo no lugar de um cabecalho', function()
		local parsed, err = dat.parse('abc', 0)
		t.eq(parsed, nil)
		t.contains(err, 'pequeno')
		local parsed2, err2 = dat.parse(string.rep('\255', 32), 0)
		t.eq(parsed2, nil)
	end)
end)

t.describe('dat - flags', function()
	t.test('le e escreve flags de node', function()
		local flags = 0
		flags = dat.setNodeFlag(flags, 'HIGHWAY', 1)
		flags = dat.setNodeFlag(flags, 'SPAWN_PROBABILITY', 15)
		flags = dat.setNodeFlag(flags, 'TRAFFIC_LEVEL', 3)
		t.eq(dat.getNodeFlag(flags, 'HIGHWAY'), 1)
		t.eq(dat.getNodeFlag(flags, 'SPAWN_PROBABILITY'), 15)
		t.eq(dat.getNodeFlag(flags, 'TRAFFIC_LEVEL'), 3)
		t.eq(dat.getNodeFlag(flags, 'BOAT'), 0)
		flags = dat.setNodeFlag(flags, 'SPAWN_PROBABILITY', 99) -- deve saturar em 15
		t.eq(dat.getNodeFlag(flags, 'SPAWN_PROBABILITY'), 15)
	end)

	t.test('le e escreve flags de navi', function()
		local flags = 0
		flags = dat.setNaviFlag(flags, 'WIDTH', 200)
		flags = dat.setNaviFlag(flags, 'LEFT_LANES', 2)
		flags = dat.setNaviFlag(flags, 'RIGHT_LANES', 3)
		flags = dat.setNaviFlag(flags, 'TRAFFIC_LIGHT', 2)
		flags = dat.setNaviFlag(flags, 'TRAIN_CROSSING', 1)
		t.eq(dat.getNaviFlag(flags, 'WIDTH'), 200)
		t.eq(dat.getNaviFlag(flags, 'LEFT_LANES'), 2)
		t.eq(dat.getNaviFlag(flags, 'RIGHT_LANES'), 3)
		t.eq(dat.getNaviFlag(flags, 'TRAFFIC_LIGHT'), 2)
		t.eq(dat.getNaviFlag(flags, 'TRAIN_CROSSING'), 1)
		t.eq(dat.getNaviFlag(flags, 'LIGHT_DIRECTION'), 0)
	end)

	t.test('empacota navi link (area + id)', function()
		local raw = dat.packNaviLink(15, 300)
		local id, areaId = dat.unpackNaviLink(raw)
		t.eq(id, 300)
		t.eq(areaId, 15)
		local raw2 = dat.packNaviLink(63, 1023)
		local id2, area2 = dat.unpackNaviLink(raw2)
		t.eq(id2, 1023)
		t.eq(area2, 63)
	end)

	t.test('classifica tipo do node', function()
		local area = buildSampleArea()
		t.eq(dat.nodeType(area, 1), 'veh')
		t.eq(dat.nodeType(area, 3), 'boat')
		t.eq(dat.nodeType(area, 4), 'ped')
	end)
end)

return true
