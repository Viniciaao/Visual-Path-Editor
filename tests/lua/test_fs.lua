local t = require 'support.assert'
local fs = require 'vpe.fs'

local GAME = os.getenv('VPE_TEST_GAME_DIR') or 'tests/tmp/game'
local DIR = GAME .. '/tests_fs'

local function fresh()
	os.execute('rm -rf "' .. DIR .. '"')
	os.execute('mkdir -p "' .. DIR .. '"')
	return DIR
end

local function ensureGameMarkers()
	-- a pasta de teste precisa parecer um jogo (ter models/gta3.img)
	os.execute('mkdir -p "' .. GAME .. '/models"')
	if not fs.exists(GAME .. '/models/gta3.img') then
		fs.writeAll(GAME .. '/models/gta3.img', 'VER2' .. string.rep('\0', 12))
	end
	fs._gameDir = nil
end

t.describe('fs - caminhos', function()
	t.test('join junta partes e normaliza as barras', function()
		t.eq(fs.join('a', 'b'), 'a/b')
		t.eq(fs.join('a/', '/b'), 'a/b')
		t.eq(fs.join('C:\\Jogo', 'moonloader'), 'C:/Jogo/moonloader')
		t.eq(fs.join('a', 'b', 'c', 'd.txt'), 'a/b/c/d.txt')
	end)

	t.test('basename, dirname e extension', function()
		t.eq(fs.basename('C:/jogo/models/gta3.img'), 'gta3.img')
		t.eq(fs.basename('C:\\jogo\\nodes0.dat'), 'nodes0.dat')
		t.eq(fs.dirname('C:/jogo/models/gta3.img'), 'C:/jogo/models')
		t.eq(fs.dirname('arquivo.dat'), '.')
		t.eq(fs.extension('nodes15.dat'), 'dat')
		t.eq(fs.extension('gta3.img'), 'img')
		t.eq(fs.extension('sem_ponto'), '')
	end)

	t.test('gameDir encontra a pasta do jogo pelo mock', function()
		ensureGameMarkers()
		t.eq(fs.gameDir(), GAME)
	end)

	t.test('gamePath usa a pasta do jogo', function()
		ensureGameMarkers()
		t.eq(fs.gamePath('models', 'gta3.img'), GAME .. '/models/gta3.img')
	end)
end)

t.describe('fs - leitura e escrita', function()
	t.test('writeAll, readAll e readBytes', function()
		fresh()
		local path = DIR .. '/dados.bin'
		t.ok(fs.writeAll(path, 'abcdefghij'))
		t.eq(fs.readAll(path), 'abcdefghij')
		t.eq(fs.readBytes(path, 2, 3), 'cde')
		t.eq(fs.readBytes(path, 8, 10), 'ij')
		t.eq(fs.readBytes(path, 0, 1), 'a')
		t.eq(fs.readAll(DIR .. '/nao_existe.bin'), nil)
	end)

	t.test('readAll devolve erro quando o arquivo nao existe', function()
		local data, err = fs.readAll(DIR .. '/nao_existe.bin')
		t.eq(data, nil)
		t.ok(err ~= nil)
	end)

	t.test('appendLine acrescenta linhas', function()
		fresh()
		local path = DIR .. '/linhas.txt'
		fs.appendLine(path, 'um')
		fs.appendLine(path, 'dois')
		t.eq(fs.readAll(path), 'um\ndois\n')
	end)

	t.test('exists, size e isDir', function()
		fresh()
		local file = DIR .. '/x.dat'
		fs.writeAll(file, '12345')
		t.eq(fs.exists(file), true)
		t.eq(fs.exists(DIR .. '/y.dat'), false)
		t.eq(fs.size(file), 5)
		t.eq(fs.isDir(DIR), true)
		t.eq(fs.isDir(file), false)
		t.eq(fs.isDir(DIR .. '/sub'), false)
		t.ok(fs.mtime(file) ~= nil)
	end)

	t.test('mkdir cria pastas aninhadas', function()
		fresh()
		local deep = DIR .. '/a/b/c'
		t.ok(fs.mkdir(deep))
		t.eq(fs.isDir(deep), true)
		t.ok(fs.mkdir(deep), 'chamar de novo nao da erro')
		t.eq(fs.isDir(DIR .. '/a/b'), true)
	end)

	t.test('remove, copy e rename', function()
		fresh()
		local a = DIR .. '/a.txt'
		local b = DIR .. '/b.txt'
		fs.writeAll(a, 'conteudo')
		t.ok(fs.copy(a, b))
		t.eq(fs.readAll(b), 'conteudo')
		t.ok(fs.rename(b, DIR .. '/c.txt'))
		t.eq(fs.exists(b), false)
		t.eq(fs.readAll(DIR .. '/c.txt'), 'conteudo')
		t.ok(fs.remove(DIR .. '/c.txt'))
		t.eq(fs.exists(DIR .. '/c.txt'), false)
	end)
end)

t.describe('fs - listagem', function()
	t.test('listDir lista arquivos e pastas', function()
		fresh()
		fs.writeAll(DIR .. '/um.dat', '1')
		fs.writeAll(DIR .. '/dois.dat', '2')
		fs.mkdir(DIR .. '/subpasta')
		fs.writeAll(DIR .. '/subpasta/tres.dat', '3')

		local entries = fs.listDir(DIR)
		t.ok(entries ~= nil, 'listDir devolveu nil')
		t.eq(#entries, 3)
		local kinds = {}
		for i = 1, #entries do kinds[entries[i].name] = entries[i].isDir end
		t.eq(kinds['um.dat'], false)
		t.eq(kinds['subpasta'], true)
	end)

	t.test('listDir de uma pasta vazia devolve tabela vazia', function()
		fresh()
		fs.mkdir(DIR .. '/vazia')
		local entries = fs.listDir(DIR .. '/vazia')
		t.ok(entries ~= nil)
		t.eq(#entries, 0)
	end)

	t.test('listDir de um caminho inexistente devolve nil', function()
		t.eq(fs.listDir(DIR .. '/nao_existe_mesmo'), nil)
	end)

	t.test('walk entra nas subpastas', function()
		fresh()
		fs.writeAll(DIR .. '/raiz.dat', 'r')
		fs.mkdir(DIR .. '/a/b')
		fs.writeAll(DIR .. '/a/meio.dat', 'm')
		fs.writeAll(DIR .. '/a/b/fundo.dat', 'f')

		local paths = fs.walk(DIR, 3, function(path, name)
			return name:match('%.dat$') ~= nil
		end)
		local found = {}
		for i = 1, #paths do found[#found + 1] = fs.basename(paths[i]) end
		table.sort(found)
		t.eq(#found, 3)
		t.eq(found[1], 'fundo.dat')
		t.eq(found[2], 'meio.dat')
		t.eq(found[3], 'raiz.dat')
	end)
end)

t.describe('fs - shell', function()
	t.test('a plataforma e detectada e o redirecionamento nao cria arquivo "nul"', function()
		t.eq(type(fs.IS_WINDOWS), 'boolean')
		os.remove('nul')
		fs.mkdir(DIR .. '/sem_arquivo_nul')
		fs.listDir(DIR)
		fs.listDir(DIR .. '/nao_existe_mesmo')
		t.eq(fs.exists('nul'), false, 'no POSIX o silencio do shell deve ir para /dev/null')
	end)

	t.test('shellStatus diferencia sucesso, falha e ausencia de shell', function()
		t.eq(fs.shellStatus('true'), true)
		t.eq(fs.shellStatus('false'), false)
		t.eq(fs.shellStatus('test -d "/tmp"'), true)
		t.eq(fs.shellStatus('test -d "/tmp/__nao_existe__"'), false)
	end)

	t.test('shell devolve booleano simples', function()
		t.eq(fs.shell('true'), true)
		t.eq(fs.shell('false'), false)
	end)
end)
