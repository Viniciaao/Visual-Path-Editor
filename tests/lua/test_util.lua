local t = require 'support.assert'
local util = require 'vpe.util'

t.describe('util - bits', function()
	t.test('liga, desliga e consulta bits', function()
		local v = 0
		v = util.setBit(v, 7, true)
		t.ok(util.hasBit(v, 7))
		t.eq(v, 128)
		v = util.setBit(v, 7, false)
		t.eq(v, 0)
	end)

	t.test('le e escreve campos de bits', function()
		local v = util.setBits(0, 16, 4, 15)
		t.eq(util.getBits(v, 16, 4), 15)
		t.eq(util.getBits(v, 0, 4), 0)
		v = util.setBits(v, 0, 4, 3)
		t.eq(util.getBits(v, 0, 4), 3)
		t.eq(util.getBits(v, 16, 4), 15)
		-- nao invade os vizinhos
		t.eq(util.getBits(v, 20, 4), 0)
	end)
end)

t.describe('util - numeros', function()
	t.test('clamp e arredondamento (metade afasta do zero)', function()
		t.eq(util.clamp(5, 0, 3), 3)
		t.eq(util.clamp(-1, 0, 3), 0)
		t.eq(util.round(2.5), 3)
		t.eq(util.round(-2.5), -3)
		t.eq(util.round(2.4), 2)
		t.near(util.roundTo(3.14159, 2), 3.14)
	end)

	t.test('conversao int16 com sinal', function()
		t.eq(util.toSigned16(65535), -1)
		t.eq(util.toSigned16(32768), -32768)
		t.eq(util.toUnsigned16(-1), 65535)
	end)
end)

t.describe('util - cores', function()
	t.test('monta ARGB', function()
		t.eq(util.argb(255, 255, 0, 0), 0xFFFF0000)
		t.eq(util.argb(0, 0, 0, 0), 0)
		local r, g, b, a = util.splitArgb(util.argb(128, 10, 20, 30))
		t.eq(r, 10)
		t.eq(g, 20)
		t.eq(b, 30)
		t.eq(a, 128)
	end)

	t.test('aceita texto hexadecimal', function()
		t.eq(util.toArgb('#FF0000'), 0xFFFF0000)
		t.eq(util.toArgb('#80FF0000'), 0x80FF0000)
		t.eq(util.toArgb(0x12345678), 0x12345678)
	end)
end)

t.describe('util - strings', function()
	t.test('trim, split e prefixos', function()
		t.eq(util.trim('  abc  '), 'abc')
		local parts = util.split('a,b,c', ',')
		t.eq(#parts, 3)
		t.eq(parts[2], 'b')
		t.ok(util.startsWith('nodes15.dat', 'nodes'))
		t.ok(util.endsWith('nodes15.dat', '.dat'))
		t.eq(util.padLeft('7', 3, '0'), '007')
	end)

	t.test('remove acentos', function()
		t.eq(util.ascii('Configuração de nós'), 'Configuracao de nos')
		t.eq(util.ascii('ação'), 'acao')
	end)

	t.test('formata tamanho de arquivo', function()
		t.eq(util.formatBytes(512), '512 B')
		t.contains(util.formatBytes(2048), 'KB')
		t.contains(util.formatBytes(5 * 1024 * 1024), 'MB')
	end)
end)

t.describe('util - tabelas', function()
	t.test('deepcopy', function()
		local original = { a = { b = 1 }, c = { 1, 2, 3 } }
		local copy = util.deepcopy(original)
		copy.a.b = 2
		copy.c[1] = 99
		t.eq(original.a.b, 1)
		t.eq(original.c[1], 1)
	end)

	t.test('contagem e chaves ordenadas', function()
		t.eq(util.count({ a = 1, b = 2 }), 2)
		local keys = util.sortedKeys({ [3] = 'c', [1] = 'a', [2] = 'b' }, function(a, b) return a < b end)
		t.eq(keys[1], 1)
		t.eq(keys[3], 3)
	end)

	t.test('remove item por indice', function()
		local list = { 'a', 'b', 'c' }
		util.removeIndex(list, 2)
		t.eq(#list, 2)
		t.eq(list[2], 'c')
	end)
end)

return true
