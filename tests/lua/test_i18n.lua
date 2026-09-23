local t = require 'support.assert'
local fs = require 'vpe.fs'
local i18n = require 'vpe.i18n'

--- Raiz do repositorio (o runner define VPE_TEST_LUA_DIR).
local function repoRoot()
	local dir = os.getenv('VPE_TEST_LUA_DIR') or VPE_TEST_LUA_DIR or 'tests/lua'
	local root = dir:gsub('[/\\]tests[/\\]lua[/\\]?$', '')
	if root == dir then return '.' end
	return root
end

--- Arquivos do mod que usam T('chave').
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

t.describe('i18n - dicionarios', function()
	t.test('pt e en tem exatamente as mesmas chaves', function()
		local missing = i18n.missingKeys()
		t.eq(#missing, 0, 'chaves ausentes: ' .. table.concat(missing, ', '))
	end)

	t.test('ha dois idiomas e o padrao e portugues', function()
		i18n.setLang('pt')
		t.eq(#i18n.languages, 2)
		t.eq(i18n.languages[1].code, 'pt')
		t.eq(i18n.languages[2].code, 'en')
		t.eq(i18n.getLang(), 'pt')
	end)

	t.test('o dicionario cobre a interface toda', function()
		t.ok(#i18n.keys() > 400, 'esperado um dicionario grande')
	end)

	t.test('toda chave usada no codigo existe nos dois idiomas', function()
		local keys = {}
		for _, key in ipairs(i18n.keys()) do keys[key] = true end

		local missing, scanned = {}, 0
		local files = sourceFiles()
		t.ok(#files > 10, 'nao encontrei os fontes do mod (' .. #files .. ' arquivos)')
		for i = 1, #files do
			local path = files[i]
			local text = fs.readAll(path)
			if text then
				scanned = scanned + 1
				local name = path:match('[^/\\]+$') or path
				for key in text:gmatch("T%(%-?%s*'([^']+)'") do
					if not keys[key] then missing[#missing + 1] = name .. ': ' .. key end
				end
				for key in text:gmatch('T%(%-?%s*"([^"]+)"') do
					if not keys[key] then missing[#missing + 1] = name .. ': ' .. key end
				end
			end
		end
		t.ok(scanned >= #files, 'li todos os arquivos')
		table.sort(missing)
		t.eq(#missing, 0, 'chaves sem traducao: ' .. table.concat(missing, ', '))
	end)
end)

t.describe('i18n - traducao', function()
	t.test('troca de idioma muda o texto', function()
		i18n.setLang('pt')
		local pt = i18n.t('val.too_many_links', 3, 20, 15)
		i18n.setLang('en')
		local en = i18n.t('val.too_many_links', 3, 20, 15)
		t.eq(i18n.getLang(), 'en')
		t.contains(pt, 'links')
		t.contains(en, 'links')
		t.ok(pt ~= en, 'os dois idiomas devem diferir')
		t.contains(en, 'Node #3')
		t.contains(en, '15')
		i18n.setLang('pt')
	end)

	t.test('idioma desconhecido nao muda nada', function()
		i18n.setLang('pt')
		t.eq(i18n.setLang('de'), false)
		t.eq(i18n.getLang(), 'pt')
	end)

	t.test('chave desconhecida vira [chave]', function()
		t.eq(i18n.t('nao.existe'), '[nao.existe]')
	end)

	t.test('numero errado de argumentos nao quebra', function()
		local text = i18n.t('val.too_many_links', 1)
		t.contains(text, '%d')
	end)
end)
