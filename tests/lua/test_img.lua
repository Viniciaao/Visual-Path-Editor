local t = require 'support.assert'
local fs = require 'vpe.fs'
local dat = require 'vpe.dat'
local img = require 'vpe.img'

local GAME = os.getenv('VPE_TEST_GAME_DIR') or 'tests/tmp/game'
local DIR = GAME .. '/tests_img'

local function fresh()
	os.execute('rm -rf "' .. DIR .. '"')
	os.execute('mkdir -p "' .. DIR .. '"')
	return DIR
end

local function sampleAreaData(id)
	local area = dat.newArea(id or 15)
	area.isNew = false
	area.nodes[1] = {
		mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0,
		x = 2495, y = -1684, z = 10,
		heuristic = dat.HEURISTIC_COST, pathWidth = 8, floodFill = 1,
		flags = dat.setNodeFlag(0, 'NOT_HIGHWAY', 1),
		links = {},
	}
	area.vehCount = 1
	local bytes = dat.serialize(area)
	return bytes, area
end

t.describe('img - VER2', function()
	t.test('cria, abre e le entradas', function()
		fresh()
		local path = DIR .. '/test.img'
		local bytes = sampleAreaData(15)
		t.ok(img.create(path, {
			{ name = 'nodes15.dat', data = bytes },
			{ name = 'other.txt', data = 'hello' },
		}))
		local archive, err = img.open(path)
		t.ok(archive, err)
		t.eq(archive.count, 2)
		t.eq(#img.list(archive), 2)
		t.ok(img.find(archive, 'nodes15.dat'), 'acha pelo nome')
		t.ok(img.find(archive, 'NODES15.DAT'), 'acha ignorando maiusculas')
		t.eq(img.find(archive, 'nao_existe.dat'), nil)

		local read = img.read(archive, 'nodes15.dat')
		t.ok(read)
		t.eq(#read, math.ceil(#bytes / 2048) * 2048, 'dados alinhados no setor')
		t.eq(read:sub(1, #bytes), bytes, 'o comeco e igual ao arquivo original')

		local other = img.read(archive, 'other.txt')
		t.eq(other:sub(1, 5), 'hello')
	end)

	t.test('readHead le so o comeco da entrada', function()
		fresh()
		local path = DIR .. '/head.img'
		local bytes = sampleAreaData(15)
		img.create(path, { { name = 'nodes15.dat', data = bytes } })
		local archive = img.open(path)
		local head = img.readHead(archive, 'nodes15.dat', 20)
		t.eq(#head, 20)
		local area = dat.parse(bytes, 15)
		t.eq(img.readU32At(head, 1), #area.nodes, 'cabecalho: nodeCount')
	end)

	t.test('assinatura e diretorio invalidos dao erro claro', function()
		fresh()
		local bad = DIR .. '/bad.img'
		fs.writeAll(bad, 'XXXX' .. string.rep('\0', 40))
		local archive, err = img.open(bad)
		t.eq(archive, nil)
		t.contains(err, 'VER2')

		local tiny = DIR .. '/tiny.img'
		fs.writeAll(tiny, 'VER2')
		local archive2, err2 = img.open(tiny)
		t.eq(archive2, nil)
		t.contains(err2, 'pequeno')

		local missing, err3 = img.open(DIR .. '/nao_existe.img')
		t.eq(missing, nil)
		t.contains(err3, 'abrir')
	end)
end)

t.describe('img - substituicao', function()
	t.test('troca que cabe no espaco atual nao move os dados', function()
		fresh()
		local path = DIR .. '/replace.img'
		local big = string.rep('A', 4096)
		img.create(path, { { name = 'nodes15.dat', data = big } })
		local archive = img.open(path)
		local entry = img.find(archive, 'nodes15.dat')
		t.eq(entry.sectors, 2)
		local offsetBefore = entry.offset

		local small = string.rep('B', 100)
		local ok, err, mode = img.replace(archive, 'nodes15.dat', small)
		t.ok(ok)
		t.eq(mode, 'inplace')
		t.eq(entry.offset, offsetBefore, 'nao mudou de lugar')
		t.eq(entry.sectors, 1)

		local reopened = img.open(path)
		local data = img.read(reopened, 'nodes15.dat')
		t.eq(data:sub(1, 100), small)
		t.eq(data:sub(101, 110), string.rep('\0', 10), 'o resto do setor foi zerado')
	end)

	t.test('dados maiores vao para o fim do arquivo', function()
		fresh()
		local path = DIR .. '/grow.img'
		img.create(path, {
			{ name = 'a.txt', data = 'a' },
			{ name = 'nodes16.dat', data = 'curto' },
		})
		local archive = img.open(path)
		local entry = img.find(archive, 'nodes16.dat')
		local before = entry.offset

		local grown = string.rep('X', 5000)
		local ok, err, mode = img.replace(archive, 'nodes16.dat', grown)
		t.ok(ok, err)
		t.eq(mode, 'appended')
		t.ok(entry.offset > before, 'mudou para o fim')
		t.eq(entry.sectors, 3)

		local reopened = img.open(path)
		local data = img.read(reopened, 'nodes16.dat')
		t.eq(data:sub(1, 5000), grown)
		local a = img.read(reopened, 'a.txt')
		t.eq(a:sub(1, 1), 'a', 'as outras entradas continuam legiveis')
	end)

	t.test('entrada inexistente da erro', function()
		fresh()
		local path = DIR .. '/missing.img'
		img.create(path, { { name = 'a.txt', data = 'a' } })
		local archive = img.open(path)
		local ok, err = img.replace(archive, 'nodes15.dat', 'x')
		t.eq(ok, nil)
		t.contains(err, 'nao encontrada')
	end)

	t.test('extrai uma entrada para um arquivo comum', function()
		fresh()
		local path = DIR .. '/extract.img'
		local bytes = sampleAreaData(15)
		img.create(path, { { name = 'nodes15.dat', data = bytes } })
		local archive = img.open(path)
		local dest = DIR .. '/nodes15.dat'
		t.ok(img.extractTo(archive, 'nodes15.dat', dest))
		local data = fs.readAll(dest)
		t.ok(data)
		t.eq(#data, math.ceil(#bytes / 2048) * 2048)
		local area, err = dat.parse(data, 15)
		t.ok(area, err)
		t.eq(#area.nodes, 1)
	end)

	t.test('o nome da entrada segue o padrao nodesN.dat', function()
		t.eq(img.nodeEntryName(0), 'nodes0.dat')
		t.eq(img.nodeEntryName(63), 'nodes63.dat')
	end)
end)

t.describe('img - ida e volta com o codec', function()
	t.test('grava e relê uma area completa pelo IMG', function()
		fresh()
		local path = DIR .. '/roundtrip.img'
		local bytes = sampleAreaData(15)
		img.create(path, { { name = 'nodes15.dat', data = bytes } })
		local archive = img.open(path)

		local area = dat.parse(bytes, 15)
		area.nodes[1].x = 2500
		local edited = dat.serialize(area)
		t.ok(img.replace(archive, 'nodes15.dat', edited))

		local reopened = img.open(path)
		local read = img.read(reopened, 'nodes15.dat')
		local reparsed, err = dat.parse(read, 15)
		t.ok(reparsed, err)
		t.eq(reparsed.nodes[1].x, 2500)
	end)
end)
