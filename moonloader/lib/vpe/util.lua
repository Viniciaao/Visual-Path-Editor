--[[
	Visual Path Editor - vpe.util
	Funcoes auxiliares puras (sem dependencia do jogo), para poderem ser testadas fora dele.
]]

local M = {}

--------------------------------------------------------------------------------
-- Compatibilidade de bits (LuaJIT tem a lib 'bit', outros interpretadores nao)
--------------------------------------------------------------------------------

local bitlib = nil
do
	local ok, b = pcall(require, 'bit')
	if ok and type(b) == 'table' and b.band then bitlib = b end
end

if not bitlib then
	-- implementacao pura (32 bits) usada apenas quando 'bit' nao existe (testes)
	local function norm32(n)
		n = tonumber(n) or 0
		n = n % 4294967296
		if n < 0 then n = n + 4294967296 end
		return n
	end
	local function tobits(n)
		local t, v = {}, norm32(n)
		for i = 1, 32 do
			local r = v % 2
			t[i] = r
			v = (v - r) / 2
		end
		return t
	end
	local function frombits(t)
		local n = 0
		for i = 32, 1, -1 do n = n * 2 + t[i] end
		return n
	end
	local function combine(a, b, op)
		local x, y = tobits(a), tobits(b)
		local r = {}
		for i = 1, 32 do r[i] = op(x[i], y[i]) end
		return frombits(r)
	end
	bitlib = {
		band = function(a, b) return combine(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end,
		bor  = function(a, b) return combine(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end,
		bxor = function(a, b) return combine(a, b, function(x, y) return (x ~= y) and 1 or 0 end) end,
		bnot = function(a)
			local x = tobits(a)
			local r = {}
			for i = 1, 32 do r[i] = (x[i] == 1) and 0 or 1 end
			return frombits(r)
		end,
		lshift = function(a, n) local v = norm32(a) * (2 ^ n) return norm32(v) end,
		rshift = function(a, n) return math.floor(norm32(a) / (2 ^ n)) end,
	}
end

M.bit = bitlib
local bit = bitlib

M.band = bit.band
M.bor = bit.bor
M.bxor = bit.bxor
M.lshift = bit.lshift
M.rshift = bit.rshift

--- Verifica se um bit (0-based) esta ligado em um valor inteiro.
function M.hasBit(value, bitIndex)
	return bit.band(value, bit.lshift(1, bitIndex)) ~= 0
end

--- Liga/desliga um bit (0-based) e devolve o novo valor.
function M.setBit(value, bitIndex, state)
	local mask = bit.lshift(1, bitIndex)
	if state then return bit.bor(value, mask) end
	return bit.band(value, bit.bnot(mask))
end

--- Extrai um campo de bits: 'value' bits [first..first+count-1] (0-based), como inteiro.
function M.getBits(value, first, count)
	local mask = bit.band(bit.rshift(0xFFFFFFFF, 32 - count), 0xFFFFFFFF)
	return bit.band(bit.rshift(value, first), mask)
end

--- Escreve um campo de bits.
function M.setBits(value, first, count, newValue)
	local mask = bit.band(bit.rshift(0xFFFFFFFF, 32 - count), 0xFFFFFFFF)
	local cleared = bit.band(value, bit.bnot(bit.lshift(mask, first)))
	return bit.bor(cleared, bit.lshift(bit.band(newValue, mask), first))
end

--------------------------------------------------------------------------------
-- Numeros
--------------------------------------------------------------------------------

function M.clamp(v, min, max)
	if v < min then return min end
	if v > max then return max end
	return v
end

function M.round(v)
	if v >= 0 then return math.floor(v + 0.5) end
	return math.ceil(v - 0.5)
end

--- Arredonda para 'dec' casas (apenas para exibicao).
function M.roundTo(v, dec)
	local mult = 10 ^ (dec or 0)
	return M.round(v * mult) / mult
end

--- Arredonda um valor para o multiplo mais proximo de 'size' (grade do editor).
function M.snapTo(v, size)
	if not size or size <= 0 then return v end
	return M.round(v / size) * size
end

--- Converte int16 sem sinal (0..65535) para sinal (-32768..32767).
function M.toSigned16(v)
	v = v % 65536
	if v >= 32768 then v = v - 65536 end
	return v
end

--- Converte para int16 sem sinal.
function M.toUnsigned16(v)
	v = M.round(v) % 65536
	if v < 0 then v = v + 65536 end
	return v
end

function M.num(v, default)
	local n = tonumber(v)
	if n == nil then return default or 0 end
	return n
end

--------------------------------------------------------------------------------
-- Cores (formato ARGB do MoonLoader / ImGui usa ABGR na U32... aqui so empacotamos)
--------------------------------------------------------------------------------

--- Monta uma cor ARGB (0xAARRGGBB) usada pelas funcoes render* do MoonLoader.
function M.argb(a, r, g, b)
	return (bit.lshift(M.clamp(M.round(a), 0, 255), 24)
		+ bit.lshift(M.clamp(M.round(r), 0, 255), 16)
		+ bit.lshift(M.clamp(M.round(g), 0, 255), 8)
		+ M.clamp(M.round(b), 0, 255)) % 4294967296
end

--- Aceita "#RRGGBB", "#AARRGGBB", numero ou tabela {r,g,b[,a]} e devolve ARGB.
function M.toArgb(color, fallback)
	if type(color) == 'number' then return color end
	if type(color) == 'table' then
		return M.argb(color[4] or 255, color[1] or 255, color[2] or 255, color[3] or 255)
	end
	if type(color) == 'string' then
		local hex = color:gsub('#', '')
		if #hex == 6 then
			return tonumber('0xFF' .. hex) or fallback
		elseif #hex == 8 then
			-- #AARRGGBB
			return tonumber('0x' .. hex) or fallback
		end
	end
	return fallback or 0xFFFFFFFF
end

--- Valida uma cor em texto ("#RRGGBB" ou "#AARRGGBB") e devolve o texto
--- normalizado, ou nil quando nao e uma cor valida.
function M.parseHexColor(text)
	local hex = tostring(text or ''):gsub('^%s*#?', ''):gsub('%s*$', '')
	if #hex ~= 6 and #hex ~= 8 then return nil end
	if not hex:match('^%x+$') then return nil end
	return '#' .. hex:upper()
end

--- Separa ARGB em componentes.
function M.splitArgb(color)
	local a = bit.rshift(bit.band(color, 0xFF000000), 24)
	local r = bit.rshift(bit.band(color, 0x00FF0000), 16)
	local g = bit.rshift(bit.band(color, 0x0000FF00), 8)
	local b = bit.band(color, 0x000000FF)
	return r, g, b, a
end

--- Cor ARGB -> ImVec4 (0..1) para o ImGui.
function M.argbToVec4(color)
	local r, g, b, a = M.splitArgb(color)
	return { r / 255, g / 255, b / 255, a / 255 }
end

--------------------------------------------------------------------------------
-- Strings
--------------------------------------------------------------------------------

function M.trim(s)
	return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

function M.split(s, sep)
	local out = {}
	if sep == nil or sep == '' then
		for i = 1, #s do out[#out + 1] = s:sub(i, i) end
		return out
	end
	local pattern = '([^' .. sep .. ']+)'
	for piece in tostring(s):gmatch(pattern) do out[#out + 1] = piece end
	return out
end

function M.startsWith(s, prefix)
	return s:sub(1, #prefix) == prefix
end

function M.endsWith(s, suffix)
	return suffix == '' or s:sub(-#suffix) == suffix
end

function M.padLeft(s, len, char)
	s = tostring(s)
	char = char or ' '
	while #s < len do s = char .. s end
	return s
end

function M.formatBytes(n)
	if n >= 1024 * 1024 then return string.format('%.2f MB', n / (1024 * 1024)) end
	if n >= 1024 then return string.format('%.1f KB', n / 1024) end
	return tostring(n) .. ' B'
end

--- Remove acentos (o console do MoonLoader e a fonte do jogo nao lidam bem com UTF-8).
local accents = {
	['á'] = 'a', ['à'] = 'a', ['ã'] = 'a', ['â'] = 'a', ['ä'] = 'a',
	['Á'] = 'A', ['À'] = 'A', ['Ã'] = 'A', ['Â'] = 'A', ['Ä'] = 'A',
	['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e',
	['É'] = 'E', ['È'] = 'E', ['Ê'] = 'E', ['Ë'] = 'E',
	['í'] = 'i', ['ì'] = 'i', ['î'] = 'i', ['ï'] = 'i',
	['Í'] = 'I', ['Ì'] = 'I', ['Î'] = 'I', ['Ï'] = 'I',
	['ó'] = 'o', ['ò'] = 'o', ['õ'] = 'o', ['ô'] = 'o', ['ö'] = 'o',
	['Ó'] = 'O', ['Ò'] = 'O', ['Õ'] = 'O', ['Ô'] = 'O', ['Ö'] = 'O',
	['ú'] = 'u', ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u',
	['Ú'] = 'U', ['Ù'] = 'U', ['Û'] = 'U', ['Ü'] = 'U',
	['ç'] = 'c', ['Ç'] = 'C', ['ñ'] = 'n', ['Ñ'] = 'N',
	['ª'] = 'a', ['º'] = 'o',
}

function M.ascii(s)
	s = tostring(s or '')
	for accented, plain in pairs(accents) do
		s = s:gsub(accented, plain)
	end
	-- qualquer outro byte multi-byte UTF-8 vira '?'
	s = s:gsub('[%z\1-\127\194-\244][\128-\191]*', function(c)
		if #c > 1 then return '' end
		return c
	end)
	return s
end

--------------------------------------------------------------------------------
-- Tabelas
--------------------------------------------------------------------------------

function M.count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

function M.sortedKeys(t, comparator)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, comparator or function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

function M.deepcopy(v, seen)
	if type(v) ~= 'table' then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local out = {}
	seen[v] = out
	for k, val in pairs(v) do out[M.deepcopy(k, seen)] = M.deepcopy(val, seen) end
	return out
end

--- Cria um array denso a partir de um mapa {id = valor} ordenado por chave numerica.
function M.toArray(map)
	local keys = {}
	for k in pairs(map) do
		if type(k) == 'number' then keys[#keys + 1] = k end
	end
	table.sort(keys)
	local out = {}
	for i = 1, #keys do out[i] = map[keys[i]] end
	return out
end

function M.indexOf(list, value)
	for i = 1, #list do
		if list[i] == value then return i end
	end
	return nil
end

function M.copyArray(list)
	local out = {}
	for i = 1, #list do out[i] = list[i] end
	return out
end

function M.removeIndex(list, index)
	if index < 1 or index > #list then return false end
	table.remove(list, index)
	return true
end

--------------------------------------------------------------------------------
-- Chamadas seguras (usadas em todo o mod para nunca derrubar o script)
--------------------------------------------------------------------------------

function M.pcall(fn, ...)
	if type(fn) ~= 'function' then return false, 'funcao indisponivel' end
	return pcall(fn, ...)
end

--- Retorna true se a funcao global ou de tabela existir e for chamavel.
function M.hasFunction(tbl, name)
	if name == nil then return type(tbl) == 'function' end
	return type(tbl) == 'table' and type(tbl[name]) == 'function'
end

function M.now()
	return os.date('%Y-%m-%d %H:%M:%S')
end

function M.stamp()
	return os.date('%Y%m%d-%H%M%S')
end

return M
