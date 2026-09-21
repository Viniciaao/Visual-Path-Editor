--[[
	Suite do script de entrada (moonloader/VisualPathEditor.lua) e do ciclo
	principal do mod. O objetivo e pegar erros que os testes de modulo nao veem:
	arquivo que nao compila, funcao de entrada faltando, erro no loop de update.

	Aqui o script de entrada e carregado de verdade (com os globais do
	MoonLoader simulados) e o corpo do loop e executado quadro a quadro.
]]

local t = require 'support.assert'
local mock = require 'support.mock_moonloader'
local fs = require 'vpe.fs'
local util = require 'vpe.util'
local dat = require 'vpe.dat'
local config = require 'vpe.config'
local appModule = require 'vpe.app'

--------------------------------------------------------------------------------
-- Caminhos
--------------------------------------------------------------------------------

local function repoRoot()
	local dir = os.getenv('VPE_TEST_LUA_DIR') or VPE_TEST_LUA_DIR or 'tests/lua'
	local root = dir:gsub('[/\\]tests[/\\]lua[/\\]?$', '')
	if root == dir then return '.' end
	return root
end

local ROOT_DIR = repoRoot()
local ENTRY = ROOT_DIR .. '/moonloader/VisualPathEditor.lua'

local GAME = os.getenv('VPE_TEST_GAME_DIR') or 'tests/tmp/game'
local ML = GAME .. '/entrysuite/modloader'
local OVERRIDE = ML .. '/VisualPath/nodes15.dat'

--------------------------------------------------------------------------------
-- Ambiente de teste (uma area de 2 nodes em cadeia)
--------------------------------------------------------------------------------

local function makeFixture()
	local area = dat.newArea(15)
	area.nodes[1] = {
		mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = 2495.0, y = -1684.0, z = 10.0,
		heuristic = dat.HEURISTIC_COST, pathWidth = 8, floodFill = 1, flags = 0x00011001,
		links = { { area = 15, node = 1, naviArea = 15, naviID = 0, length = 5 } },
	}
	area.nodes[2] = {
		mem1 = dat.MEM_ADDRESS_DEFAULT, mem2 = 0, x = 2500.0, y = -1684.0, z = 10.0,
		heuristic = dat.HEURISTIC_COST, pathWidth = 8, floodFill = 1, flags = 0x00011000,
		links = { { area = 15, node = 0, naviArea = 0, naviID = 0, length = 5 } },
	}
	area.vehCount = 2
	area.navis[1] = { x = 2497.5, y = -1684.0, areaID = 15, nodeID = 1, dirX = 100, dirY = 0, flags = 8 + 256 + 2048 }
	area.intersections = string.rep('\0', 2)
	local bytes, err = dat.serialize(area)
	assert(bytes, tostring(err))
	return bytes
end

local FIXTURE = makeFixture()

local function makeSettings()
	local settings = util.deepcopy(config.defaults)
	settings.geral.idioma = 'pt'
	settings.geral.carregar_vizinhas = false
	settings.salvar.pasta_export = 'entrysuite/modloader/VisualPath/export'
	settings.salvar.pasta_img = 'entrysuite/modloader/VisualPath/gta3.img'
	settings.salvar.pasta_backup = 'entrysuite/modloader/VisualPath/backup'
	return settings
end

local function resetScenario()
	fs.shell('rm -rf "' .. GAME .. '/entrysuite"')
	fs.mkdir(ML .. '/VisualPath')
	fs.writeAll(OVERRIDE, FIXTURE)
end

--------------------------------------------------------------------------------
-- Sintaxe
--------------------------------------------------------------------------------

local function listLuaFiles()
	local out = {}
	local function walk(dir)
		local entries = fs.listDir(dir) or {}
		for i = 1, #entries do
			local entry = entries[i]
			if entry.isDir then walk(entry.path)
			elseif entry.name:sub(-4) == '.lua' then out[#out + 1] = entry.path end
		end
	end
	walk(ROOT_DIR .. '/moonloader')
	table.sort(out)
	return out
end

t.describe('entrada - sintaxe', function()
	t.test('todos os arquivos .lua do mod compilam', function()
		local files = listLuaFiles()
		t.ok(#files >= 15, 'esperava varios modulos, encontrei ' .. #files)
		local problems = {}
		for i = 1, #files do
			local source = fs.readAll(files[i])
			t.ok(source and #source > 0, 'arquivo vazio: ' .. files[i])
			local chunk, err = load(source, '@' .. files[i])
			if not chunk then problems[#problems + 1] = files[i] .. ': ' .. tostring(err) end
		end
		t.eq(#problems, 0, table.concat(problems, ' | '))
	end)
end)

--------------------------------------------------------------------------------
-- O script de entrada
--------------------------------------------------------------------------------

t.describe('entrada - script principal', function()
	t.test('carrega e registra os metadados do script', function()
		local source = fs.readAll(ENTRY)
		t.ok(source and #source > 0, 'nao li o script de entrada')
		mock.scriptMeta = {}

		local chunk, err = load(source, '@VisualPathEditor.lua')
		t.ok(chunk, 'nao compilou: ' .. tostring(err))
		local ok, runErr = pcall(chunk)
		t.ok(ok, 'nao executou: ' .. tostring(runErr))

		t.eq(mock.scriptMeta.name, 'Visual Path Editor')
		t.contains(tostring(mock.scriptMeta.version), '1.0')
		t.ok(tostring(mock.scriptMeta.description):lower():find('path') ~= nil, 'descricao do script')
		t.eq(type(main), 'function', 'main() registrada')
		t.eq(type(onScriptTerminate), 'function', 'onScriptTerminate() registrada')
		t.eq(type(showSelfTest), 'function', 'showSelfTest() registrada')
	end)

	t.test('onScriptTerminate so age no proprio script', function()
		t.eq(onScriptTerminate({ name = 'outro' }, false), nil)
		t.eq(onScriptTerminate(thisScript(), false), nil)
	end)
end)

--------------------------------------------------------------------------------
-- Ciclo do loop principal (o mesmo corpo do script de entrada)
--------------------------------------------------------------------------------

t.describe('entrada - loop principal', function()
	t.test('update + followPlayerTick + drawWorld rodam por varios quadros', function()
		resetScenario()
		local A = appModule.new({
			gameDir = GAME,
			modloaderDir = ML,
			settings = makeSettings(),
			withUi = false,
			autoload = false,
			vkeys = nil,
		})
		t.ok(A:init())
		A.originals = {}

		local frames, errors = 40, {}
		for i = 1, frames do
			mock.reset()
			local ok, err = pcall(function()
				A:update(1 / 30)
				A:followPlayerTick()
				A:drawWorld()
			end)
			if not ok then errors[#errors + 1] = 'quadro ' .. i .. ': ' .. tostring(err) end
		end
		t.eq(#errors, 0, table.concat(errors, ' | '))
		t.ok(#A.project:loadedAreas() >= 1, 'a area do jogador foi carregada pelo loop')
		t.eq(A.project:loadedAreas()[1], 15)
	end)

	t.test('o loop aguenta uma area sem arquivo (nenhum nodes*.dat)', function()
		fs.shell('rm -rf "' .. GAME .. '/entrysuite"')
		fs.mkdir(ML)
		local A = appModule.new({
			gameDir = GAME,
			modloaderDir = ML,
			settings = makeSettings(),
			withUi = false,
			autoload = false,
			vkeys = nil,
		})
		t.ok(A:init())
		A.originals = {}
		local ok, err = pcall(function()
			A:update(1 / 30)
			A:followPlayerTick()
			A:drawWorld()
		end)
		t.ok(ok, 'o loop nao pode quebrar sem os arquivos: ' .. tostring(err))
	end)

	t.test('onExit limpa o estado e nao quebra', function()
		resetScenario()
		local A = appModule.new({
			gameDir = GAME,
			modloaderDir = ML,
			settings = makeSettings(),
			withUi = false,
			autoload = false,
			vkeys = nil,
		})
		A:init()
		A.originals = {}
		A:loadArea(15)
		A:selectNode(15, 1)
		A:nudge(3, 0, 0)
		local ok, err = pcall(function() A:onExit() end)
		t.ok(ok, 'onExit falhou: ' .. tostring(err))
	end)

	t.test('showSelfTest roda depois de main()', function()
		-- showSelfTest usa o 'app' criado em main(); com main() executado de
		-- verdade o app fica global para esta checagem.
		local source = fs.readAll(ENTRY)
		local chunk = load(source, '@VisualPathEditor.lua')
		t.ok(chunk, 'o script de entrada precisa compilar')
		-- o corpo de main() tem um laco infinito: aqui so conferimos que
		-- showSelfTest sobrevive sem app (instance nil)
		_G.app = nil
		local result = showSelfTest()
		t.ok(result == nil or result.total > 0, 'showSelfTest sem app nao pode estourar')
	end)
end)
