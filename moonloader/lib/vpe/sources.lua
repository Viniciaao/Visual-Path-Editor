--[[
	Visual Path Editor - vpe.sources
	Descobre de onde cada nodesN.dat deve ser LIDO e para onde deve ser GRAVADO.

	Regra do editor (decisao do projeto):
	  * o gta3.img original NUNCA e alterado por padrao;
	  * os arquivos editados vao para a pasta do mod (override do ModLoader):
	        modloader/VisualPath/gta3.img/nodesN.dat
	    porque o ModLoader substitui o conteudo do gta3.img a partir de qualquer
	    subpasta com esse nome. Uma copia extra .dat pode ir para
	        modloader/VisualPath/export/nodesN.dat
	  * se outro mod ja substitui o arquivo, ele e usado como origem (respeitando
	    a prioridade do ModLoader) e o editor avisa que existem dois mods mexendo
	    no mesmo arquivo;
	  * se nenhum mod substitui, a origem e o gta3.img do jogo (models/gta3.img);
	  * opcionalmente (config) da para gravar tambem direto no gta3.img do jogo.

	Nada aqui carrega o IMG inteiro na memoria: apenas o diretorio e os bytes
	necessarios (ver vpe/img).
]]

local fs = require 'vpe.fs'
local img = require 'vpe.img'
local dat = require 'vpe.dat'
local log = require 'vpe.log'
local i18n = require 'vpe.i18n'

local M = {}

local T = i18n.t

M.AREA_COUNT = 64
M.STANDARD_IMGS = { 'models/gta3.img' }

--------------------------------------------------------------------------------
-- Construtor
--------------------------------------------------------------------------------

function M.new(options)
	options = options or {}
	local self = {
		gameDir = options.gameDir or fs.gameDir(),
		modloaderDir = options.modloaderDir,
		ownMod = options.ownMod or 'VisualPath',
		imgFiles = options.imgFiles or M.STANDARD_IMGS,
		exportFolder = options.exportFolder,
		backupFolder = options.backupFolder,
		writeExport = options.writeExport ~= false,
		writeImgFolder = options.writeImgFolder ~= false,
		backup = options.backup ~= false,
		directImg = options.directImg == true,
		areas = {},
		warnings = {},
		mods = {},
		imgs = {},
		backedUp = {},
		scanned = false,
	}
	self.modloaderDir = self.modloaderDir or fs.join(self.gameDir, 'modloader')
	self.exportFolder = self.exportFolder or fs.join(self.modloaderDir, self.ownMod, 'export')
	self.backupFolder = self.backupFolder or fs.join(self.modloaderDir, self.ownMod, 'backup')
	self.ownImgFolder = fs.join(self.modloaderDir, self.ownMod, 'gta3.img')
	setmetatable(self, { __index = M })
	return self
end

--------------------------------------------------------------------------------
-- Descoberta
--------------------------------------------------------------------------------

local function parseInt(text)
	return tonumber((tostring(text):match('%-?%d+') or ''))
end

--- Le as prioridades do modloader.ini (1..100, maior ganha). Melhor esforco.
function M:readPriorities()
	local priorities = {}
	local text = fs.readAll(fs.join(self.modloaderDir, 'modloader.ini'))
	if not text then return priorities end
	local section = ''
	for line in text:gmatch('[^\r\n]+') do
		local trimmed = line:match('^%s*(.-)%s*$')
		local header = trimmed:match('^%[([^%]]+)%]$')
		if header then
			section = header:lower()
		else
			local key, value = trimmed:match('^([^=]+)=(.*)$')
			if key then
				local value2 = parseInt(value)
				if value2 and value2 >= 0 and value2 <= 100 then
					priorities[key:match('^%s*(.-)%s*$'):lower()] = value2
				end
			end
		end
	end
	return priorities
end

--- Pastas de mods dentro de modloader/ (nome -> prioridade).
function M:scanMods()
	local mods = {}
	local entries = fs.listDir(self.modloaderDir)
	if not entries then
		return mods, false
	end
	local priorities = self:readPriorities()
	for i = 1, #entries do
		local entry = entries[i]
		if entry.isDir then
			local key = entry.name:lower()
			local priority = priorities[key]
			if not priority then
				priority = priorities[entry.name] or 50
			end
			mods[#mods + 1] = { name = entry.name, path = entry.path, priority = priority }
		end
	end
	table.sort(mods, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.name:lower() < b.name:lower()
	end)
	return mods, true
end

--- Caminhos possiveis de um override "solto" dentro de uma pasta de mod.
local function looseVariants(modPath, entryName)
	return {
		fs.join(modPath, 'gta3.img', entryName),
		fs.join(modPath, 'models', 'gta3.img', entryName),
		fs.join(modPath, entryName),
	}
end

--- Procura o arquivo em todos os mods. Devolve lista de provedores (ordenada).
function M:findOverrides(areaId)
	local entryName = img.nodeEntryName(areaId)
	local found = {}
	for i = 1, #self.mods do
		local mod = self.mods[i]
		local variants = looseVariants(mod.path, entryName)
		for v = 1, #variants do
			local path = variants[v]
			if fs.exists(path) then
				found[#found + 1] = {
					mod = mod.name,
					path = path,
					priority = mod.priority,
					readonly = mod.name == self.ownMod,
				}
				break
			end
		end
	end
	return found
end

function M:openImg(relative)
	local path = fs.join(self.gameDir, relative)
	if self.imgs[path] == nil then
		if fs.exists(path) then
			local archive, err = img.open(path)
			self.imgs[path] = archive or false
			if err then
				self.warnings[#self.warnings + 1] = string.format('IMG %s: %s', relative, tostring(err))
			end
		else
			self.imgs[path] = false
		end
	end
	return self.imgs[path] or nil
end

--- Monta a tabela de origens das 64 areas.
function M:scan()
	self.mods, self.modsListed = self:scanMods()
	self.areas = {}
	self.warnings = {}
	for id = 0, M.AREA_COUNT - 1 do
		local info = { id = id, entryName = img.nodeEntryName(id), providers = {}, source = 'none' }
		local overrides = self:findOverrides(id)
		info.providers = overrides
		info.conflict = #overrides > 1

		local best
		for i = 1, #overrides do
			local provider = overrides[i]
			if not best or provider.priority > best.priority then best = provider end
		end

		if best then
			info.source = 'modloader'
			info.path = best.path
			info.mod = best.mod
			info.priority = best.priority
			info.exists = true
			info.size = fs.size(best.path)
		else
			for i = 1, #self.imgFiles do
				local relative = self.imgFiles[i]
				local archive = self:openImg(relative)
				if archive then
					local entry = img.find(archive, info.entryName)
					if entry then
						info.source = 'img'
						info.imgFile = relative
						info.imgPath = archive.path
						info.size = entry.byteSize
						info.exists = true
						break
					end
				end
			end
		end

		if not info.exists then
			local legacy = fs.join(self.gameDir, 'data', 'paths', info.entryName)
			if fs.exists(legacy) then
				info.source = 'legacy'
				info.path = legacy
				info.exists = true
				info.size = fs.size(legacy)
				info.legacyWarning = true
			end
		end

		if info.legacyWarning then
			self.warnings[#self.warnings + 1] = T('src.legacy_warning', id)
		end
		if info.conflict then
			self.warnings[#self.warnings + 1] = T('src.conflict', id, #info.providers)
		end
		self.areas[id] = info
	end
	if not self.modsListed then
		self.warnings[#self.warnings + 1] = T('src.no_modloader')
	end
	self.scanned = true
	return self.areas
end

function M:info(areaId)
	if not self.scanned then self:scan() end
	return self.areas[tonumber(areaId) or 0]
end

function M:exists(areaId)
	local info = self:info(areaId)
	return info and info.exists == true
end

function M:list() 
	local out = {}
	for id = 0, M.AREA_COUNT - 1 do
		if self.areas[id] and self.areas[id].exists then out[#out + 1] = id end
	end
	return out
end

function M:summary()
	local counts = { modloader = 0, img = 0, legacy = 0, none = 0 }
	for id = 0, M.AREA_COUNT - 1 do
		local info = self.areas[id]
		if info then
			counts[info.source] = (counts[info.source] or 0) + 1
		end
	end
	return counts
end

--------------------------------------------------------------------------------
-- Leitura
--------------------------------------------------------------------------------

--- Le os bytes de uma area. Devolve (data, info) ou (nil, erro, info).
function M:read(areaId)
	local info = self:info(areaId)
	if not info then return nil, 'area invalida' end
	if not info.exists then return nil, T('src.not_found', info.id), info end

	if info.source == 'img' then
		local archive = self:openImg(info.imgFile)
		if not archive then return nil, T('src.img_unavailable', tostring(info.imgFile)), info end
		local data, err = img.read(archive, info.entryName)
		if not data then return nil, err, info end
		return data, info
	end

	local data, err = fs.readAll(info.path)
	if not data then return nil, err, info end
	return data, info
end

--- Le apenas o cabecalho (20 bytes) e devolve as contagens.
function M:readCounts(areaId)
	local info = self:info(areaId)
	if not info or not info.exists then return nil end
	local head
	if info.source == 'img' then
		local archive = self:openImg(info.imgFile)
		if not archive then return nil end
		head = img.readHead(archive, info.entryName, dat.HEADER_SIZE)
	else
		head = fs.readBytes(info.path, 0, dat.HEADER_SIZE)
	end
	if not head or #head < dat.HEADER_SIZE then return nil end
	return {
		nodeCount = img.readU32At(head, 1),
		vehCount = img.readU32At(head, 5),
		pedCount = img.readU32At(head, 9),
		naviCount = img.readU32At(head, 13),
		linkCount = img.readU32At(head, 17),
	}
end

--------------------------------------------------------------------------------
-- Gravacao
--------------------------------------------------------------------------------

function M:targetPath(areaId)
	return fs.join(self.ownImgFolder, img.nodeEntryName(areaId))
end

function M:exportPath(areaId)
	return fs.join(self.exportFolder, img.nodeEntryName(areaId))
end

function M:backupPath(areaId)
	return fs.join(self.backupFolder, img.nodeEntryName(areaId))
end

function M:cacheMarkerPath()
	return fs.join(self.modloaderDir, '.vpe_cache_warning')
end

--- Avisa (uma vez por salvamento) que o cache do ModLoader precisa ser limpo.
function M:noteCache(areaId)
	local path = self:cacheMarkerPath()
	local text = os.date('%Y-%m-%d %H:%M:%S') .. ' nodes' .. tostring(areaId) .. '.dat\n'
	fs.appendLine(path, text)
end

--- Guarda uma copia do arquivo original (so uma vez por sessao/area).
function M:makeBackup(areaId)
	if not self.backup then return true, 'desativado' end
	local info = self:info(areaId)
	if not info or not info.exists then return true, 'nada para copiar' end
	local dest = self:backupPath(areaId)
	if self.backedUp[areaId] then return true, 'ja feito' end
	if fs.exists(dest) then
		self.backedUp[areaId] = true
		return true, 'backup anterior mantido'
	end
	local data, err = self:read(areaId)
	if not data then return false, err end
	fs.mkdir(self.backupFolder)
	local ok, werr = fs.writeAll(dest, data)
	if not ok then return false, werr end
	self.backedUp[areaId] = true
	return true, dest
end

--- Grava os bytes de uma area.
--- Devolve resultado = { written = {caminhos}, img = bool, errors = {}, exportPath =, mainPath = }
function M:save(areaId, data, options)
	options = options or {}
	local result = { written = {}, errors = {}, areaId = areaId, size = #data }
	local info = self:info(areaId)

	if options.backup ~= false then
		local ok, where = self:makeBackup(areaId)
		if not ok then
			result.errors[#result.errors + 1] = T('save.backup_falha', tostring(where))
		elseif where and where ~= 'desativado' and where ~= 'nada para copiar' and where ~= 'ja feito' then
			result.backupPath = where
		end
	end

	local wrote = false
	if self.writeImgFolder then
		fs.mkdir(self.ownImgFolder)
		local target = self:targetPath(areaId)
		local ok, err = fs.writeAll(target, data)
		if ok then
			result.mainPath = target
			result.written[#result.written + 1] = target
			wrote = true
		else
			result.errors[#result.errors + 1] = T('save.falha_escrita', tostring(err))
		end
	elseif self.writeExport then
		fs.mkdir(self.exportFolder)
		local target = self:exportPath(areaId)
		local ok, err = fs.writeAll(target, data)
		if ok then
			result.mainPath = target
			result.written[#result.written + 1] = target
			wrote = true
		else
			result.errors[#result.errors + 1] = T('save.falha_escrita', tostring(err))
		end
	end

	if self.writeExport and self.writeImgFolder then
		fs.mkdir(self.exportFolder)
		local target = self:exportPath(areaId)
		local ok, err = fs.writeAll(target, data)
		if ok then
			result.exportPath = target
			result.written[#result.written + 1] = target
		else
			result.errors[#result.errors + 1] = T('save.falha_escrita', tostring(err))
		end
	end

	if self.directImg and info and info.source == 'img' then
		local archive = self:openImg(info.imgFile)
		if archive then
			local ok, err = img.replace(archive, info.entryName, data)
			if ok then
				result.img = true
				result.written[#result.written + 1] = archive.path
			else
				result.errors[#result.errors + 1] = T('save.img_falha', tostring(err))
			end
		end
	end

	if wrote then self:noteCache(areaId) end
	result.ok = wrote and #result.errors == 0
	return result
end

--- Apaga o override do editor (o jogo volta a usar o arquivo original).
function M:revert(areaId)
	local target = self:targetPath(areaId)
	local removed = false
	if fs.exists(target) then
		removed = fs.remove(target)
	end
	local exportPath = self:exportPath(areaId)
	if fs.exists(exportPath) then
		fs.remove(exportPath)
	end
	return removed
end

--- Copia o backup de volta para o override.
function M:restoreBackup(areaId)
	local backup = self:backupPath(areaId)
	if not fs.exists(backup) then return false, T('src.no_backup', areaId) end
	local data = fs.readAll(backup)
	if not data then return false, 'falha ao ler o backup' end
	fs.mkdir(self.ownImgFolder)
	return fs.writeAll(self:targetPath(areaId), data)
end

M.looseVariants = looseVariants

return M
