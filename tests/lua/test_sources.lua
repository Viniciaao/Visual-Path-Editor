local t = require 'support.assert'
local fs = require 'vpe.fs'
local dat = require 'vpe.dat'
local img = require 'vpe.img'
local sources = require 'vpe.sources'
local i18n = require 'vpe.i18n'

i18n.setLang('pt')

local GAME = (os.getenv('VPE_TEST_GAME_DIR') or 'tests/tmp/game') .. '/sources'
local MODLOADER = GAME .. '/modloader'

local function reset()
	os.execute('rm -rf "' .. GAME .. '"')
	os.execute('mkdir -p "' .. GAME .. '/models"')
end

local function areaBytes(id, x)
	local area = dat.newArea(id or 15)
	area.isNew = false
	area.nodes[1] = {
		mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0,
		x = x or 2495, y = -1684, z = 10,
		heuristic = dat.HEURISTIC_COST, pathWidth = 8, floodFill = 1,
		flags = dat.setNodeFlag(0, 'NOT_HIGHWAY', 1),
		links = {},
	}
	area.vehCount = 1
	return dat.serialize(area)
end

local function writeFile(path, data)
	os.execute('mkdir -p "' .. path:match('^(.*)/[^/]*$') .. '"')
	local f = assert(io.open(path, 'wb'))
	f:write(data)
	f:close()
end

local function readFile(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local data = f:read('*a')
	f:close()
	return data
end

local function newSources(extra)
	local opts = {
		gameDir = GAME,
		modloaderDir = MODLOADER,
		ownMod = 'VisualPath',
		imgFiles = { 'models/gta3.img' },
	}
	for k, v in pairs(extra or {}) do opts[k] = v end
	return sources.new(opts)
end

--- Cenario base: nodes0.dat e nodes15.dat dentro do gta3.img do jogo; um mod
--- que substitui apenas o nodes15.dat; nodes20.dat so em data/paths.
local function baseScenario()
	reset()
	local imgPath = GAME .. '/models/gta3.img'
	img.create(imgPath, {
		{ name = 'nodes0.dat', data = areaBytes(0, -2900) },
		{ name = 'nodes15.dat', data = areaBytes(15, 1111) },
		{ name = 'other.dff', data = 'nao mexe' },
	})
	writeFile(GAME .. '/modloader/modA/gta3.img/nodes6.dat', areaBytes(6, 606))
	writeFile(GAME .. '/modloader/modB/gta3.img/nodes15.dat', areaBytes(15, 2222))
	writeFile(MODLOADER .. '/modloader.ini',
		'[Profiles.Default]\nmodA = 80\nmodB = 20\n')
	writeFile(GAME .. '/data/paths/nodes20.dat', areaBytes(20, 2020))
	return imgPath
end

-------------------------------------------------------------------------------

t.describe('sources - descoberta', function()
	t.test('prioriza o override do modloader sobre o gta3.img', function()
		baseScenario()
		local src = newSources()
		src:scan()
		local info = src:info(15)
		t.eq(info.source, 'modloader')
		t.eq(info.mod, 'modB')
		t.contains(info.path, 'modB/gta3.img/nodes15.dat')
		t.eq(info.exists, true)
	end)

	t.test('cai para o gta3.img quando nenhum mod substitui', function()
		baseScenario()
		local src = newSources()
		src:scan()
		local info = src:info(0)
		t.eq(info.source, 'img')
		t.eq(info.imgFile, 'models/gta3.img')
		t.eq(info.exists, true)
	end)

	t.test('areas sem arquivo ficam como "none"', function()
		baseScenario()
		local src = newSources()
		src:scan()
		t.eq(src:info(40).source, 'none')
		t.eq(src:exists(40), false)
	end)

	t.test('detecta conflito entre mods e respeita a prioridade do ini', function()
		baseScenario()
		writeFile(MODLOADER .. '/modC/gta3.img/nodes15.dat', areaBytes(15, 3333))
		writeFile(MODLOADER .. '/modloader.ini', '[Profiles.Default]\nmodA = 80\nmodB = 20\nmodC = 95\n')
		local src = newSources()
		src:scan()
		local info = src:info(15)
		t.eq(info.conflict, true, 'dois mods fornecem o arquivo')
		t.eq(#info.providers, 2)
		t.eq(info.mod, 'modC', 'maior prioridade ganha')
		local found = false
		for _, w in ipairs(src.warnings) do
			if w:find('mods do ModLoader', 1, true) then found = true end
		end
		t.ok(found, 'o conflito vira aviso')
	end)

	t.test('data/paths e carregado mas avisado (o jogo ignora)', function()
		baseScenario()
		local src = newSources()
		src:scan()
		local info = src:info(20)
		t.eq(info.source, 'legacy')
		t.eq(info.exists, true)
		t.ok(info.legacyWarning)
		local warned = false
		for _, w in ipairs(src.warnings) do
			if w:find('data/paths', 1, true) then warned = true end
		end
		t.ok(warned)
	end)

	t.test('summary conta por origem', function()
		baseScenario()
		local src = newSources()
		src:scan()
		local counts = src:summary()
		t.eq(counts.modloader, 2, 'nodes6.dat (mod A) e nodes15.dat (mod B)')
		t.eq(counts.img, 1, 'nodes0.dat no gta3.img')
		t.eq(counts.legacy, 1)
		t.eq(counts.none, 60)
	end)
end)

t.describe('sources - leitura', function()
	t.test('le do IMG e do modloader, com contagens do cabecalho', function()
		baseScenario()
		local src = newSources()
		local data, info = src:read(15)
		t.ok(data, info)
		local area = dat.parse(data, 15)
		t.eq(area.nodes[1].x, 2222, 'veio do mod (modB)')

		local counts = src:readCounts(0)
		t.eq(counts.nodeCount, 1)
		t.eq(counts.vehCount, 1)
		t.eq(counts.naviCount, 0)

		local dataImg, infoImg = src:read(0)
		t.eq(infoImg.source, 'img')
		t.eq(dat.parse(dataImg, 0).nodes[1].x, -2900)
	end)

	t.test('area ausente devolve erro traduzido', function()
		baseScenario()
		local src = newSources()
		local data, err = src:read(63)
		t.eq(data, nil)
		t.contains(err, 'nodes63.dat')
		t.eq(src:readCounts(63), nil)
	end)
end)

t.describe('sources - gravacao', function()
	t.test('grava no override do mod e nao toca no gta3.img', function()
		local imgPath = baseScenario()
		local before = readFile(imgPath)
		local src = newSources()
		local newData = areaBytes(15, 2450)
		local result = src:save(15, newData)

		t.ok(result.ok, table.concat(result.errors, '; '))
		t.eq(result.mainPath, MODLOADER .. '/VisualPath/gta3.img/nodes15.dat')
		t.eq(result.exportPath, MODLOADER .. '/VisualPath/export/nodes15.dat')
		t.eq(readFile(result.mainPath), newData, 'override gravado')
		t.eq(readFile(result.exportPath), newData, 'copia de exportacao')
		t.eq(readFile(imgPath), before, 'o gta3.img do jogo nao foi alterado')
		t.eq(result.img, nil)
	end)

	t.test('cria backup do original antes de gravar', function()
		baseScenario()
		local src = newSources()
		local original = src:read(15)
		src:save(15, areaBytes(15, 2451))
		local backup = readFile(MODLOADER .. '/VisualPath/backup/nodes15.dat')
		t.ok(backup, 'backup criado')
		t.eq(backup, original, 'backup guarda o arquivo original')
		t.eq(dat.parse(backup, 15).nodes[1].x, 2222)
	end)

	t.test('grava area que veio do IMG e ainda assim preserva o original', function()
		local imgPath = baseScenario()
		local before = readFile(imgPath)
		local src = newSources()
		local result = src:save(0, areaBytes(0, -2999))
		t.ok(result.ok)
		t.eq(readFile(imgPath), before, 'IMG intacto')
		t.eq(readFile(MODLOADER .. '/VisualPath/gta3.img/nodes0.dat'), areaBytes(0, -2999))
		local backup = readFile(MODLOADER .. '/VisualPath/backup/nodes0.dat')
		t.ok(backup)
		t.eq(dat.parse(backup, 0).nodes[1].x, -2900, 'backup veio do IMG')
	end)

	t.test('revert apaga o override e o arquivo volta a vir do gta3.img', function()
		baseScenario()
		local src = newSources()
		src:save(15, areaBytes(15, 2452))
		t.eq(src:revert(15), true)
		t.eq(fs.exists(MODLOADER .. '/VisualPath/gta3.img/nodes15.dat'), false)
		local src2 = newSources()
		src2:scan()
		t.eq(src2:info(15).source, 'modloader', 'ainda existe o modB original')
		t.eq(dat.parse(src2:read(15), 15).nodes[1].x, 2222)
	end)

	t.test('restoreBackup devolve o original para o override', function()
		baseScenario()
		local src = newSources()
		src:save(15, areaBytes(15, 2453))
		src:revert(15)
		local ok, err = src:restoreBackup(15)
		t.ok(ok, err)
		local data = readFile(MODLOADER .. '/VisualPath/gta3.img/nodes15.dat')
		t.eq(dat.parse(data, 15).nodes[1].x, 2222)
	end)

	t.test('restoreBackup sem backup avisa', function()
		baseScenario()
		local src = newSources()
		local ok, err = src:restoreBackup(30)
		t.eq(ok, false)
		t.contains(err, 'backup')
	end)

	t.test('marca o aviso de cache do ModLoader', function()
		baseScenario()
		local src = newSources()
		src:save(6, areaBytes(6, 600))
		local marker = src:cacheMarkerPath()
		t.ok(fs.exists(marker), 'marcador criado')
		t.contains(readFile(marker), 'nodes6.dat')
	end)

	t.test('sem backup configurado nao cria a pasta backup', function()
		baseScenario()
		local src = newSources({ backup = false })
		src:save(6, areaBytes(6, 601))
		t.eq(fs.exists(MODLOADER .. '/VisualPath/backup/nodes6.dat'), false)
	end)

	t.test('writeExport desligado grava apenas o override', function()
		baseScenario()
		local src = newSources({ writeExport = false })
		local result = src:save(6, areaBytes(6, 602))
		t.ok(result.ok)
		t.eq(result.exportPath, nil)
		t.eq(fs.exists(MODLOADER .. '/VisualPath/export/nodes6.dat'), false)
		t.eq(fs.exists(result.mainPath), true)
	end)

	t.test('directImg grava no gta3.img somente se pedido', function()
		local imgPath = baseScenario()
		local src = newSources({ directImg = true })
		local result = src:save(0, areaBytes(0, -2777))
		t.ok(result.ok, table.concat(result.errors, '; '))
		t.eq(result.img, true)
		local archive = img.open(imgPath)
		local read = img.read(archive, 'nodes0.dat')
		t.eq(dat.parse(read, 0).nodes[1].x, -2777)
		local other = img.read(img.open(imgPath), 'other.dff')
		t.eq(other:sub(1, 8), 'nao mexe', 'as outras entradas seguem intactas')
	end)

	t.test('targetPath e exportPath seguem a convencao do ModLoader', function()
		baseScenario()
		local src = newSources()
		t.eq(src:targetPath(15), MODLOADER .. '/VisualPath/gta3.img/nodes15.dat')
		t.eq(src:exportPath(15), MODLOADER .. '/VisualPath/export/nodes15.dat')
	end)
end)
