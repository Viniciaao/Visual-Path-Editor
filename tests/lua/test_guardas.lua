--[[
	Guardas contra os erros que derrubam o GTA (violacao de acesso 0xC0000005).

	Nada aqui testa "funcionalidade": sao varreduras no codigo do mod para
	impedir que voltem os padroes que ja causaram crash em jogo:

	1. campo do objeto com o MESMO NOME de um metodo. Em Lua, `self.font = nil`
	   apaga a chave e a leitura cai na metatable, devolvendo a FUNCAO do
	   metodo. Foi assim que uma funcao Lua foi parar em renderFontDrawText
	   (fonte invalida -> leitura em 0x4 -> crash 0xC0000005).
	2. `PLAYER_PED or 0` (e qualquer handle 0/nil) indo para funcao nativa.
	3. API nativa de desenho chamada fora de pcall.
]]

local t = require 'support.assert'
local fs = require 'vpe.fs'

local function repoRoot()
	local dir = os.getenv('VPE_TEST_LUA_DIR') or VPE_TEST_LUA_DIR or 'tests/lua'
	local root = dir:gsub('[/\\]tests[/\\]lua[/\\]?$', '')
	if root == dir then return '.' end
	return root
end

--- Fontes do mod (modulos + script de entrada).
local function sourceFiles()
	local root = repoRoot()
	local out = {}
	local function collect(dir)
		local entries = fs.listDir(dir) or {}
		for i = 1, #entries do
			local entry = entries[i]
			if entry.isDir then
				if entry.name ~= 'lang' then collect(entry.path) end
			elseif entry.name:sub(-4) == '.lua' then
				out[#out + 1] = entry.path
			end
		end
	end
	collect(root .. '/moonloader/lib/vpe')
	out[#out + 1] = root .. '/moonloader/VisualPathEditor.lua'
	return out
end

local function read(path)
	local fh = io.open(path, 'rb')
	if not fh then return nil end
	local data = fh:read('*a')
	fh:close()
	return data
end

local function shortName(path)
	return (path:gsub('.*[/\\]', ''))
end

local function lineOf(src, pos)
	local _, count = src:sub(1, pos):gsub('\n', '\n')
	return count + 1
end

--- Remove comentarios: o proprio codigo documenta os erros que evitamos
--- ("nunca usar PLAYER_PED or 0"), e a varredura nao pode acusar a documentacao.
local function stripComments(src)
	src = src:gsub('%-%-%[%[.-%]%]', '') -- blocos longos
	src = src:gsub('%-%-[^\n]*', '')    -- comentarios de linha
	return src
end

--- Nomes de metodos definidos no modulo (function M.nome / function M:nome).
local function methodNames(src)
	local out = {}
	for name in src:gmatch('function%s+M[%.:]([%a_][%w_]*)%s*%(') do
		out[name] = true
	end
	return out
end

--- Percorre todas as ocorrencias de `self.algumaCoisa` no fonte.
--- Obriga a funcao de callback a devolver true quando for problema.
local function eachSelfField(src, callback, stopAtFirst)
	local problems = {}
	local pos = 1
	while true do
		local s, e = src:find('self%.[%a_][%w_]*', pos)
		if not s then break end
		local name = src:sub(s + 5, e)
		local rest = src:sub(e + 1, e + 4)
		local problem = callback(name, rest, lineOf(src, s))
		if problem then
			problems[#problems + 1] = problem
			if stopAtFirst then break end
		end
		pos = e + 1
	end
	return problems
end

t.describe('guardas - colisao entre campo e metodo', function()
	t.test('nenhum campo do objeto usa o nome de um metodo', function()
		local problems = {}
		for _, path in ipairs(sourceFiles()) do
			local src = read(path)
			if src then src = stripComments(src)
				local methods = methodNames(src)
				local found = eachSelfField(src, function(name, rest, line)
					if not methods[name] then return nil end
					-- chamada de metodo (self.x:y) ou da propria funcao (self.x(...)): ok
					if rest:match('^%s*:') or rest:match('^%s*%(') then return nil end
					-- atribuicao tambem e problema: esconde o metodo do modulo
					if rest:match('^%s*=') and not rest:match('^%s*==') then
						return string.format('%s:%d escreve self.%s (existe metodo com esse nome)',
							shortName(path), line, name)
					end
					return string.format('%s:%d le self.%s como valor (na verdade e o metodo)',
						shortName(path), line, name)
				end)
				for i = 1, #found do problems[#problems + 1] = found[i] end
			end
		end
		t.eq(#problems, 0, table.concat(problems, ' | '))
	end)

	t.test('a varredura acusa de verdade um caso plantado', function()
		local src = 'function M:coisa() end\nfunction M:x()\n\tif self.coisa then return 1 end\nend\n'
		local methods = methodNames(src)
		local found = eachSelfField(src, function(name, rest)
			if methods[name] and not (rest:match('^%s*:') or rest:match('^%s*%(')) then return name end
			return nil
		end)
		t.eq(#found, 1, 'o caso plantado foi encontrado')
	end)
end)

t.describe('guardas - handle do jogador', function()
	t.test('nenhum modulo passa PLAYER_PED or 0 para o jogo', function()
		local problems = {}
		for _, path in ipairs(sourceFiles()) do
			local src = read(path)
			if src then src = stripComments(src)
				local pos = 1
				while true do
					local s = src:find('PLAYER_PED%s*or%s*0', pos)
					if not s then break end
					problems[#problems + 1] = string.format('%s:%d usa "PLAYER_PED or 0" (use util.playerPed())',
						shortName(path), lineOf(src, s))
					pos = s + 1
				end
				pos = 1
				while true do
					local s = src:find('getCharCoordinates%s*%(%s*PLAYER_PED%s*%)', pos)
					if not s then break end
					problems[#problems + 1] = string.format('%s:%d chama getCharCoordinates(PLAYER_PED) sem validar',
						shortName(path), lineOf(src, s))
					pos = s + 1
				end
			end
		end
		t.eq(#problems, 0, table.concat(problems, ' | '))
	end)

	t.test('util.playerPed recusa handles invalidos', function()
		local util = require 'vpe.util'
		local mock = require 'support.mock_moonloader'
		local before = _G.PLAYER_PED

		_G.PLAYER_PED = nil
		t.eq(util.playerPed(), nil, 'sem global')

		_G.PLAYER_PED = 0
		t.eq(util.playerPed(), nil, 'handle 0')

		_G.PLAYER_PED = -5
		t.eq(util.playerPed(), nil, 'handle negativo')

		_G.PLAYER_PED = 2495
		t.eq(util.playerPed(), 2495, 'handle valido')

		mock.pedExists = false
		t.eq(util.playerPed(), nil, 'ped inexistente')
		mock.pedExists = true

		_G.PLAYER_PED = nil
		t.eq(util.playerCoords(), nil, 'sem handle nao chama o jogo')
		_G.PLAYER_PED = 2495
		local x, y = util.playerCoords()
		t.near(x, 2495.0, 0.001)
		t.near(y, -1684.0, 0.001)

		_G.PLAYER_PED = before
		mock.reset()
	end)
end)

t.describe('guardas - chamadas nativas', function()
	t.test('codigo nao chama a api de desenho fora de pcall', function()
		local src = read(repoRoot() .. '/moonloader/lib/vpe/render.lua')
		t.ok(src ~= nil)
		src = stripComments(src)
		local natives = {
			renderDrawLine = true, renderDrawBox = true,
			renderDrawPolygon = true, renderFontDrawText = true,
			renderGetFontDrawTextLength = true,
		}
		local problems = {}
		local pos = 1
		while true do
			local s, e = src:find('([%a_]+)%s*%(', pos)
			if not s then break end
			local name = src:sub(s, e - 1):match('^([%a_]+)%s*$')
			if name and natives[name] then
				local before = src:sub(math.max(1, s - 40), s - 1)
				if not before:find('pcall%s*$') then
					problems[#problems + 1] = string.format('render.lua:%d %s sem pcall', lineOf(src, s), name)
				end
			end
			pos = e
		end
		t.eq(#problems, 0, table.concat(problems, ' | '))
	end)

	t.test('render nao desenha quando o jogo nao esta pronto', function()
		local mock = require 'support.mock_moonloader'
		local render = require 'vpe.render'
		local model = require 'vpe.model'
		mock.reset()
		local r = render.new(model.new(), { render = { ativo = true, distancia = 250 } })
		mock.playerPlaying = false
		t.eq(r:draw(), false)
		t.ok(r.readyReason ~= nil, 'informou o motivo')
		t.eq(#mock.renderCalls, 0)
		mock.reset()
	end)
end)

t.describe('guardas - fonte do HUD', function()
	t.test('font() devolve a fonte e nunca o proprio metodo', function()
		local mock = require 'support.mock_moonloader'
		local render = require 'vpe.render'
		local model = require 'vpe.model'
		mock.reset()
		local r = render.new(model.new(), { render = { distancia = 250 } })
		local f = r:font()
		t.eq(type(f), 'table', 'o mock devolve uma tabela (no jogo, userdata)')
		t.ok(type(f) ~= 'function', 'nunca devolver a funcao do metodo')
		t.eq(r:font(), f, 'criada uma unica vez')
	end)

	t.test('texto nao e desenhado se a fonte for invalida', function()
		local mock = require 'support.mock_moonloader'
		local render = require 'vpe.render'
		local model = require 'vpe.model'
		mock.reset()
		local r = render.new(model.new(), { render = { distancia = 250 } })
		local realFont = r.fontRef
		r.fontRef = nil
		r.fontFailed = true
		t.eq(r:font(), nil)
		local before = #mock.renderCalls
		t.eq(r:text('teste', 10, 10), false, 'sem fonte valida nao chama a api')
		t.eq(#mock.renderCalls, before, 'nada foi desenhado')
		t.eq(r:textWidth('teste'), 30, 'largura estimada, sem chamar a api')
		r.fontRef = realFont
		r.fontFailed = false
	end)
end)
