--[[
	Visual Path Editor - vpe.img
	Leitor/escritor do formato IMG VER2 (gta3.img, gta_int.img, ...).

	Estrutura:
	  4 bytes  "VER2"
	  u32      quantidade de entradas
	  n x 32B  entradas: u32 offset (em setores de 2048), u16 streamingSize,
	                     u16 sizeInSectors, char nome[24]
	  ...      dados, alinhados em setores de 2048

	O arquivo NAO e carregado inteiro na memoria (gta3.img passa de 1 GB):
	as leituras usam seek e as escritas acontecem em blocos. Ao trocar um
	arquivo por outro maior, os dados novos vao para o fim do IMG e a entrada
	do diretorio e atualizada - igual fazem as ferramentas de IMG.
]]

local fs = require 'vpe.fs'
local log = require 'vpe.log'

local M = {}

M.MAGIC = 'VER2'
M.SECTOR = 2048
M.ENTRY_SIZE = 32
M.NAME_SIZE = 24
M.HEADER_SIZE = 8
M.CHUNK = 65536

--------------------------------------------------------------------------------
-- Utilitarios binarios
--------------------------------------------------------------------------------

local function readU16At(s, i)
	local a, b = s:byte(i, i + 1)
	if not a or not b then return nil end
	return a + b * 256
end

local function readU32At(s, i)
	local a, b, c, d = s:byte(i, i + 3)
	if not a or not d then return nil end
	return a + b * 256 + c * 65536 + d * 16777216
end

local function writeU16(v)
	v = math.max(0, math.min(65535, math.floor(v + 0.5)))
	return string.char(v % 256, math.floor(v / 256) % 256)
end

local function writeU32(v)
	v = math.max(0, math.floor(v))
	return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

M.readU16At, M.readU32At = readU16At, readU32At
M.writeU16, M.writeU32 = writeU16, writeU32

local function trimName(raw)
	local name = raw:gsub('%z.*$', '')
	return name
end

local function padName(name)
	name = tostring(name or '')
	if #name > M.NAME_SIZE - 1 then name = name:sub(1, M.NAME_SIZE - 1) end
	return name .. string.rep('\0', M.NAME_SIZE - #name)
end

local function sectorsFor(bytes)
	local sectors = math.ceil(bytes / M.SECTOR)
	if sectors < 1 then sectors = 1 end
	return sectors
end

local function padToSector(data)
	local rest = #data % M.SECTOR
	if rest == 0 then return data end
	return data .. string.rep('\0', M.SECTOR - rest)
end

--------------------------------------------------------------------------------
-- Leitura
--------------------------------------------------------------------------------

--- Abre o IMG e le apenas o diretorio. Devolve (archive, nil) ou (nil, erro).
function M.open(path)
	local f, err = io.open(path, 'rb')
	if not f then return nil, string.format('nao foi possivel abrir %s (%s)', tostring(path), tostring(err)) end
	local header = f:read(M.HEADER_SIZE)
	if not header or #header < M.HEADER_SIZE then
		f:close()
		return nil, 'arquivo pequeno demais para ser um IMG'
	end
	local magic = header:sub(1, 4)
	if magic ~= M.MAGIC then
		f:close()
		return nil, string.format('assinatura inesperada "%s" (esperado VER2)', magic)
	end
	local count = readU32At(header, 5) or 0
	if count == 0 or count > 500000 then
		f:close()
		return nil, string.format('quantidade de entradas invalida: %d', count)
	end
	local dir = f:read(count * M.ENTRY_SIZE)
	f:close()
	if not dir or #dir < count * M.ENTRY_SIZE then
		return nil, 'diretorio do IMG truncado'
	end

	local archive = { path = path, count = count, entries = {}, order = {}, byName = {} }
	for i = 1, count do
		local p = (i - 1) * M.ENTRY_SIZE + 1
		local entry = {
			index = i - 1,
			offset = readU32At(dir, p),
			streaming = readU16At(dir, p + 4),
			sizeSectors = readU16At(dir, p + 6),
			name = trimName(dir:sub(p + 8, p + 8 + M.NAME_SIZE - 1)),
		}
		entry.sectors = (entry.sizeSectors > 0) and entry.sizeSectors or entry.streaming
		entry.compressed = entry.sizeSectors == 0
		entry.byteOffset = entry.offset * M.SECTOR
		entry.byteSize = entry.sectors * M.SECTOR
		archive.entries[i] = entry
		archive.order[#archive.order + 1] = entry
		if entry.name ~= '' then
			local key = entry.name:lower()
			local list = archive.byName[key]
			if not list then
				list = {}
				archive.byName[key] = list
			end
			list[#list + 1] = entry
		end
	end
	return archive
end

function M.find(archive, name)
	if not archive or not name then return nil end
	local list = archive.byName[(tostring(name)):lower()]
	if not list then return nil end
	return list[1]
end

function M.list(archive)
	local names = {}
	for i = 1, #(archive.order or {}) do names[#names + 1] = archive.order[i].name end
	return names
end

--- Le os bytes de uma entrada. Devolve (data, nil) ou (nil, erro).
function M.read(archive, name)
	local entry = type(name) == 'table' and name or M.find(archive, name)
	if not entry then return nil, 'entrada nao encontrada' end
	local f, err = io.open(archive.path, 'rb')
	if not f then return nil, tostring(err) end
	if not f:seek('set', entry.byteOffset) then
		f:close()
		return nil, 'nao foi possivel posicionar no arquivo'
	end
	local data = f:read(entry.byteSize)
	f:close()
	if not data then return nil, 'leitura falhou' end
	return data
end

--- Le apenas os primeiros 'count' bytes de uma entrada (para o cabecalho de nodes*.dat).
function M.readHead(archive, name, count)
	local entry = type(name) == 'table' and name or M.find(archive, name)
	if not entry then return nil, 'entrada nao encontrada' end
	local f, err = io.open(archive.path, 'rb')
	if not f then return nil, tostring(err) end
	f:seek('set', entry.byteOffset)
	local data = f:read(count)
	f:close()
	return data
end

--- Extrai uma entrada para um arquivo comum.
function M.extractTo(archive, name, destPath)
	local data, err = M.read(archive, name)
	if not data then return nil, err end
	return fs.writeAll(destPath, data)
end

--------------------------------------------------------------------------------
-- Escrita
--------------------------------------------------------------------------------

local function writeDirectoryEntry(f, entry, offsetSectors, sectors)
	local fh, err = f:seek('set', M.HEADER_SIZE + entry.index * M.ENTRY_SIZE)
	if not fh then return nil, err end
	local ok, werr = f:write(writeU32(offsetSectors) .. writeU16(sectors) .. writeU16(sectors) .. padName(entry.name))
	if not ok then return nil, tostring(werr) end
	return true
end

--- Substitui o conteudo de uma entrada.
--- Se couber no espaco atual, grava no lugar; se nao, grava no fim do arquivo.
--- Devolve (true, nil, 'inplace'|'appended') ou (nil, erro).
function M.replace(archive, name, data)
	local entry = type(name) == 'table' and name or M.find(archive, name)
	if not entry then return nil, 'entrada nao encontrada' end
	if entry.compressed then
		return nil, 'entrada comprimida: o editor nao sabe gravar dados comprimidos'
	end

	local sectors = sectorsFor(#data)
	local padded = padToSector(data)
	local f, err = io.open(archive.path, 'r+b')
	if not f then return nil, tostring(err) end

	local mode = 'inplace'
	local offsetSectors = entry.offset
	if sectors > entry.sectors then
		-- nao cabe: vai para o fim do arquivo
		local endPos = f:seek('end')
		local aligned = math.ceil(endPos / M.SECTOR) * M.SECTOR
		offsetSectors = math.floor(aligned / M.SECTOR)
		mode = 'appended'
		if not f:seek('set', aligned) then
			f:close()
			return nil, 'nao foi possivel posicionar no fim do arquivo'
		end
	elseif not f:seek('set', entry.byteOffset) then
		f:close()
		return nil, 'nao foi possivel posicionar no arquivo'
	end

	local ok, werr = f:write(padded)
	if not ok then
		f:close()
		return nil, tostring(werr)
	end
	-- zera o resto do espaco antigo (evita lixo depois dos dados novos)
	local slack = entry.sectors * M.SECTOR - #padded
	if mode == 'inplace' and slack > 0 then
		local zeros = string.rep('\0', math.min(slack, M.CHUNK))
		local left = slack
		while left > 0 do
			local n = math.min(left, #zeros)
			f:write(zeros:sub(1, n))
			left = left - n
		end
	end

	local okDir, dirErr = writeDirectoryEntry(f, entry, offsetSectors, sectors)
	f:close()
	if not okDir then return nil, dirErr end

	entry.offset = offsetSectors
	entry.sectors = sectors
	entry.streaming = sectors
	entry.sizeSectors = sectors
	entry.compressed = false
	entry.byteOffset = offsetSectors * M.SECTOR
	entry.byteSize = sectors * M.SECTOR
	return true, nil, mode
end

--- Cria um IMG novo com as entradas informadas: { {name=, data=}, ... }.
function M.create(path, entries)
	local dir = {}
	local payload = {}
	local offset = 1 -- setor 0 e o cabecalho + diretorio
	local headerSectors = math.ceil((M.HEADER_SIZE + #entries * M.ENTRY_SIZE) / M.SECTOR)
	if headerSectors < 1 then headerSectors = 1 end
	offset = headerSectors

	local out = {}
	for i = 1, #entries do
		local e = entries[i]
		local sectors = sectorsFor(#e.data)
		dir[#dir + 1] = writeU32(offset) .. writeU16(sectors) .. writeU16(sectors) .. padName(e.name)
		local padded = padToSector(e.data)
		out[#out + 1] = padded
		offset = offset + sectors
	end

	local f, err = io.open(path, 'wb')
	if not f then return nil, tostring(err) end
	f:write(M.MAGIC .. writeU32(#entries))
	f:write(table.concat(dir))
	-- completa o setor do cabecalho
	local used = M.HEADER_SIZE + #dir * M.ENTRY_SIZE
	local pad = headerSectors * M.SECTOR - used
	if pad > 0 then f:write(string.rep('\0', pad)) end
	f:write(table.concat(out))
	f:close()
	return true
end

--- Nome canonico dentro do IMG (os arquivos de path sao gravados em minusculas).
function M.nodeEntryName(areaId)
	return string.format('nodes%d.dat', areaId)
end

return M
