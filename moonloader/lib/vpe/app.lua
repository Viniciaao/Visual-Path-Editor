--[[
	Visual Path Editor - vpe.app
	Cola entre os modulos: configuracoes, fontes de arquivo, modelo, validacao,
	render, gizmo e interface.

	Todas as chamadas de jogo passam por checagens de tipo/pcall: o modulo roda
	(fora do jogo) nos testes, sem MoonLoader.

	Fluxo principal:
		app.new{...} -> app:init() -> (loop) app:update(); app:drawWorld()
		               e, no callback do ImGui, app:frame()
]]

local util = require 'vpe.util'
local fs = require 'vpe.fs'
local log = require 'vpe.log'
local dat = require 'vpe.dat'
local geo = require 'vpe.geometry'
local model = require 'vpe.model'
local validate = require 'vpe.validate'
local sources = require 'vpe.sources'
local config = require 'vpe.config'
local i18n = require 'vpe.i18n'
local gizmoMod = require 'vpe.gizmo'
local renderMod = require 'vpe.render'

local M = {}

local T = i18n.t

M.VERSION = '1.0.5'
M.AREA_COUNT = 64

M.VK_CONTROL = 0x11
M.VK_SHIFT = 0x10
M.VK_MENU = 0x12

-- Teclas do numpad usadas para empurrar o node selecionado.
M.NUDGE_KEYS = {
	{ key = 100, axis = 'x', dir = -1 }, -- numpad 4
	{ key = 102, axis = 'x', dir = 1 },  -- numpad 6
	{ key = 104, axis = 'y', dir = 1 },  -- numpad 8
	{ key = 98, axis = 'y', dir = -1 },  -- numpad 2
	{ key = 105, axis = 'z', dir = 1 },  -- numpad 9
	{ key = 99, axis = 'z', dir = -1 },  -- numpad 3
	{ key = 33, axis = 'z', dir = 1 },   -- page up
	{ key = 34, axis = 'z', dir = -1 },  -- page down
}

--------------------------------------------------------------------------------
-- Helpers de jogo (sempre guardados)
--------------------------------------------------------------------------------

local function call(name, ...)
	local fn = _G[name]
	if type(fn) ~= 'function' then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

--- Posicao do jogador (nil quando o jogo nao esta pronto).
local function playerPosition()
	-- util.playerCoords nunca passa handle invalido (nem 0) para o jogo
	local x, y, z = util.playerCoords()
	if not x then return nil end
	return x, y, z
end

--------------------------------------------------------------------------------
-- Construtor
--------------------------------------------------------------------------------

function M.new(options)
	options = options or {}
	local self = {
		version = M.VERSION,
		gameDir = options.gameDir or fs.gameDir(),
		modloaderDir = options.modloaderDir,
		settings = options.settings,
		autoload = options.autoload ~= false,
		withUi = options.withUi ~= false,
		project = nil,
		sources = nil,
		render = nil,
		gizmo = nil,
		ui = nil,
		keys = {},
		vkeys = options.vkeys,
		log = nil,
		status = nil,
		statusLevel = 'info',
		statusTime = 0,
		report = nil,
		lastSave = nil,
		showMenu = false,
		selectionKind = nil,
		newNodeKind = 'veh',
		linkMode = 'auto',
		linkSource = nil,
		map = { ativo = false, raio = 200.0, tamanho = 320, modo = 'standard' },
		mouse = { hover = nil, dragging = false, enabled = true },
		repeatTimer = 0,
		autoValidateTimer = 0,
		autoValidateDirty = false,
		pendingConfirm = nil,
		originals = {},
		locked = {},
		toasts = {},
	}
	setmetatable(self, { __index = M })
	return self
end

--- Completa as configuracoes com os valores padrao (o INI pode estar velho).
local function ensureDefaults(settings)
	settings = settings or {}
	for section, values in pairs(config.defaults) do
		settings[section] = settings[section] or {}
		for key, value in pairs(values) do
			if settings[section][key] == nil then settings[section][key] = value end
		end
	end
	return settings
end

M.ensureDefaults = ensureDefaults

function M:init()
	self.settings = ensureDefaults(self.settings or config.load())

	if self.withUi and not self.ui then
		local ok, uimod = pcall(require, 'vpe.ui')
		if ok and type(uimod) == 'table' then self.ui = uimod.new(self) end
	end

	i18n.setLang(self.settings.geral.idioma or 'pt')

	log.init(fs.gamePath('moonloader', 'VisualPathEditor.log'), M.VERSION)
	self.log = log
	log.info('==== Visual Path Editor %s ====', M.VERSION)
	log.info('pasta do jogo: %s', tostring(self.gameDir))

	-- teclas
	for name, value in pairs(self.settings.teclas or {}) do
		local code, mods = config.keyCode(value, self.vkeys or _G.vkeys)
		self.keys[name] = { code = code, mods = mods or {}, raw = value }
	end

	-- fontes de arquivo
	local salvar = self.settings.salvar or {}
	self.sources = sources.new({
		gameDir = self.gameDir,
		modloaderDir = self.modloaderDir,
		exportFolder = self:resolveFolder(salvar.pasta_export, 'modloader/VisualPath/export'),
		backupFolder = self:resolveFolder(salvar.pasta_backup, 'modloader/VisualPath/backup'),
		writeExport = salvar.escrever_export ~= false,
		writeImgFolder = salvar.escrever_img ~= false,
		backup = salvar.backup ~= false,
		directImg = salvar.tambem_gta3img_direto == true,
	})
	self.sources.scanned = false

	self.project = model.new(self.settings)
	self.render = renderMod.new(self.project, self.settings, {})
	self.gizmo = gizmoMod.new(self.project, {
		settings = self.settings,
		render = self.render,
		snap = 0,
	})

	if self.ui then self.ui:init() end

	if self.autoload then
		local ok, err = pcall(function() return self:loadAroundPlayer() end)
		if not ok then log.error('falha ao carregar areas: %s', tostring(err)) end
	end
	return self
end

--- Pasta configurada no INI, relativa a pasta do jogo.
function M:resolveFolder(value, fallback)
	local text = util.trim(value or '')
	if text == '' then text = fallback end
	if text:match('^%a:') or text:match('^[/\\]') then return fs.join(text) end
	return fs.gamePath(text)
end

--------------------------------------------------------------------------------
-- Log / mensagens
--------------------------------------------------------------------------------

function M:setStatus(fmt, level, ...)
	local text = select('#', ...) > 0 and string.format(fmt, ...) or tostring(fmt)
	self.status = text
	self.statusLevel = level or 'info'
	self.statusTime = self:now()
	if self.log then
		if level == 'error' then log.error('%s', text)
		elseif level == 'warn' then log.warn('%s', text)
		else log.info('%s', text) end
	end
	return text
end

function M:now()
	local clock = type(os.clock) == 'function' and os.clock() or 0
	return clock
end

function M:statusAlive(seconds)
	if not self.status then return false end
	return (self:now() - (self.statusTime or 0)) < (seconds or 6)
end

function M:warnPlayer(fmt, ...)
	local text = select('#', ...) > 0 and string.format(fmt, ...) or tostring(fmt)
	self:setStatus(text, 'warn')
	call('printStringNow', '~y~VPE: ~w~' .. tostring(text), 4000)
	return text
end

--------------------------------------------------------------------------------
-- Areas
--------------------------------------------------------------------------------

--- As entradas do gta3.img sao gravadas em blocos de 2048 bytes, entao um
--- nodes*.dat lido de la vem com zeros sobrando no fim. Corta o excesso para o
--- arquivo em memoria ser exatamente o mesmo que o editor grava (senao o
--- "round-trip" e o diff acusariam diferenca que nao existe).
local function trimToFormat(data, area)
	local expected = dat.expectedSize(dat.counts(area))
	if type(data) == 'string' and #data > expected then
		return data:sub(1, expected), #data - expected
	end
	return data, 0
end

local function readArea(project, source, areaId)
	local data, err, info = source:read(areaId)
	if not data then return nil, err, info end
	local area, perr = dat.parse(data, areaId)
	if not area then return nil, perr, info end
	local trimmed, dropped = trimToFormat(data, area)
	area.source = info and info.source or 'desconhecido'
	area.path = info and info.path
	area.isNew = false
	if dropped > 0 then
		log.info('area %d: %d byte(s) de preenchimento do gta3.img descartados', areaId, dropped)
	end
	return area, nil, info, trimmed
end

--- Carrega uma area (bytes do modloader, do gta3.img ou um arquivo novo).
function M:loadArea(areaId, options)
	options = options or {}
	areaId = tonumber(areaId)
	if not areaId or areaId < 0 or areaId > M.AREA_COUNT - 1 then
		return false, 'area invalida'
	end
	if self.project:area(areaId) and not options.force then return true, 'ja carregada' end

	local info = self.sources:info(areaId)
	if not info or not info.exists then
		return false, T('src.not_found', areaId)
	end
	local area, err, _info, raw = readArea(self.project, self.sources, areaId)
	if not area then return false, err end

	self.project:loadArea(areaId, area, { exists = true, source = area.source, path = area.path })
	self:scanTargetMeta(areaId, area)
	if raw and (not self.originals[areaId] or options.resetOriginal) then
		self.originals[areaId] = raw
	end
	if self.log then log.info(T('log.area_carregada', areaId, #area.nodes)) end
	return true
end

--- Cria uma area vazia na memoria (para areas que ainda nao tem arquivo).
--- Nao sobrescreve nada: se ja existe arquivo em algum lugar, recusa.
function M:newArea(areaId, options)
	options = options or {}
	areaId = tonumber(areaId)
	if not areaId or areaId < 0 or areaId > M.AREA_COUNT - 1 then
		return false, T('area.invalida')
	end
	if self.project:area(areaId) and not options.force then
		return false, T('area.ja_carregada', areaId)
	end
	local info = self.sources:info(areaId)
	if info and info.exists and not options.force then
		return false, T('area.ja_existe', areaId, tostring(info.source))
	end

	local area = dat.newArea(areaId)
	area.isNew = true
	area.source = 'memoria'
	area.path = nil
	self.project:loadArea(areaId, area, { exists = false, source = 'memoria', path = nil })
	self.project.meta[areaId] = { area = areaId, exists = true, counts = dat.counts(area), source = 'memoria' }
	self:markEdited(areaId)
	self:clearSelection()
	self:setStatus(T('area.criada', areaId, areaId), 'info')
	if self.log then log.info('area %d criada na memoria (salvar gera o arquivo)', areaId) end
	return true
end

--- Guarda as contagens do cabecalho (a validacao usa para areas nao carregadas).
function M:scanTargetMeta(areaId, area)
	local counts = area and dat.counts(area) or nil
	local meta = self.project.meta[areaId]
	if not meta then
		meta = { area = areaId, exists = true }
		self.project.meta[areaId] = meta
	end
	meta.exists = true
	meta.counts = counts
	meta.source = (area and area.source) or (self.sources:info(areaId) or {}).source
	return meta
end

--- Le o cabecalho das 64 areas (barato) para a validacao poder conferir
--- links que apontam para areas que nao estao carregadas.
function M:scanAllMeta()
	local read = 0
	for id = 0, M.AREA_COUNT - 1 do
		if not self.project:area(id) then
			local counts = self.sources:readCounts(id)
			local info = self.sources:info(id)
			self.project.meta[id] = {
				area = id,
				exists = info and info.exists == true and counts ~= nil,
				counts = counts,
				source = info and info.source or 'none',
			}
			if counts then read = read + 1 end
		end
	end
	return read
end

function M:probeCounts(areaId)
	return self.sources:readCounts(areaId)
end

function M:unloadArea(areaId, force)
	if self.project:isDirty(areaId) and not force then
		return false, T('sel.descartar') .. ': nodes' .. tostring(areaId) .. '.dat'
	end
	if not self.project:area(areaId) then return false, 'nao carregada' end
	self.project:unloadArea(areaId)
	if self.log then log.info(T('log.area_descarregada', areaId)) end
	return true
end

function M:unloadAll(force)
	local list = self.project:loadedAreas()
	for i = 1, #list do
		local id = list[i]
		if self.project:isDirty(id) and not force then
			return false, T('sel.descartar') .. ' (area ' .. tostring(id) .. ')'
		end
	end
	for i = 1, #list do self.project:unloadArea(list[i]) end
	self.originals = {}
	self.project:clearSelection()
	return true
end

--- Area correspondente a um ponto do mundo.
function M:areaOf(x, y)
	return geo.areaFromCoords(x, y)
end

function M:playerArea()
	local x, y = playerPosition()
	if not x then return nil end
	return geo.areaFromCoords(x, y), x, y
end

--- Carrega a area do jogador (+ vizinhas, conforme a configuracao).
function M:loadAroundPlayer()
	local areaId, x, y = self:playerArea()
	local loaded = {}
	if not areaId then
		-- sem jogo: cai na primeira area configurada ou na 0
		areaId = tonumber(util.trim(self.settings.geral.areas_extras or ''):match('^(%d+)')) or 0
		self:loadArea(areaId)
		loaded[#loaded + 1] = areaId
		return loaded
	end

	local ok, err = self:loadArea(areaId)
	if ok then loaded[#loaded + 1] = areaId else self:setStatus(err, 'warn') end

	if self.settings.geral.carregar_vizinhas ~= false then
		local neighbors = geo.areaNeighborhood(areaId)
		for i = 1, #neighbors do
			local id = neighbors[i]
			if id ~= areaId and not self.project:area(id) and self.sources:exists(id) then
				if self:loadArea(id) then loaded[#loaded + 1] = id end
			end
		end
	end

	for text in tostring(self.settings.geral.areas_extras or ''):gmatch('%d+') do
		local extraId = tonumber(text)
		if extraId and extraId >= 0 and extraId < M.AREA_COUNT
			and not self.project:area(extraId) and self.sources:exists(extraId) then
			if self:loadArea(extraId) then loaded[#loaded + 1] = extraId end
		end
	end

	if self.log then log.info('areas carregadas: %s', table.concat(loaded, ', ')) end
	return loaded
end

function M:reload()
	local hadSelection = self:hasSelection()
	local dirty = self.project:dirtyAreas()
	if #dirty > 0 then
		return false, T('sel.perg_desfazer')
	end
	self:unloadAll(true)
	self.render:update()
	self:loadAroundPlayer()
	if hadSelection then self.project:clearSelection() end
	self:setStatus(T('log.restaurado'), 'info')
	return true
end

--------------------------------------------------------------------------------
-- Selecao
--------------------------------------------------------------------------------

function M:hasSelection()
	local sel = self.project.selection
	return (sel.area and (sel.node or sel.navi)) and true or false
end

function M:selectionKind()
	local sel = self.project.selection
	if sel.navi then return 'navi' end
	if sel.node then return 'node' end
	return nil
end

function M:selectNode(areaId, index)
	if not self.project:area(areaId) or not self.project:node(areaId, index) then return false end
	self.project:select(areaId, index, nil)
	return true
end

function M:selectNavi(areaId, index)
	local area = self.project:area(areaId)
	if not area or not area.navis[index] then return false end
	self.project.navisHighlight = index
	self.project:select(areaId, nil, index)
	return true
end

--- Posicao do jogador (nil/erro quando o jogo nao esta pronto).
function M:playerPosition()
	local x, y, z = playerPosition()
	if not x then return nil end
	return x, y, z
end

function M:clearSelection()
	self.project:clearSelection()
	self.linkSource = nil
end

function M:selectedRef()
	local sel = self.project.selection
	if not sel.area then return nil end
	local kind = self:selectionKind()
	if kind == 'node' then
		return { kind = 'node', area = sel.area, index = sel.node, node = self.project:node(sel.area, sel.node) }
	elseif kind == 'navi' then
		local area = self.project:area(sel.area)
		return { kind = 'navi', area = sel.area, index = sel.navi, navi = area and area.navis[sel.navi] }
	end
	return nil
end

function M:selectFromPick(pick)
	if not pick then return false end
	if pick.navi then return self:selectNavi(pick.area, pick.navi) end
	return self:selectNode(pick.area, pick.index)
end

--- Seleciona o node mais proximo do centro da tela (mira).
function M:selectNearestToCrosshair(radius)
	local w, h = 1920, 1080
	local sw, sh = call('getScreenResolution')
	if type(sw) == 'number' then w, h = sw, sh end
	local pick = self.render:pick(w / 2, h / 2, radius or 90)
	if not pick then return false, T('misc.nenhum_resultado') end
	self:selectFromPick(pick)
	return true
end

--- Anda pela lista de nodes proximos (TAB).
function M:cycleNode(step)
	local list = self:nearbyList()
	if #list == 0 then return false, T('misc.nenhum_resultado') end
	local sel = self.project.selection
	local current = -1
	for i = 1, #list do
		if list[i].area == sel.area and list[i].index == sel.node then current = i break end
	end
	local next_ = current + (step or 1)
	if next_ < 1 then next_ = #list end
	if next_ > #list then next_ = 1 end
	self:selectNode(list[next_].area, list[next_].index)
	return true, list[next_]
end

--- Nodes das areas carregadas ordenados pela distancia do jogador.
function M:nearbyList(limit)
	local px, py = playerPosition()
	if not px then px, py = 0, 0 end
	local radius = (self.settings.render or {}).distancia or 250.0
	local out = {}
	for _, areaId in ipairs(self.project:loadedAreas()) do
		local area = self.project:area(areaId)
		if area then
			for i = 1, #area.nodes do
				local node = area.nodes[i]
				local d = geo.distance2d(px, py, node.x, node.y)
				if d <= radius then
					out[#out + 1] = { area = areaId, index = i, distance = d, node = node }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.distance < b.distance end)
	if limit and #out > limit then
		local trimmed = {}
		for i = 1, limit do trimmed[i] = out[i] end
		return trimmed
	end
	return out
end

--------------------------------------------------------------------------------
-- Edicao: posicao
--------------------------------------------------------------------------------

function M:nudge(dx, dy, dz)
	if not self:hasSelection() then return false, T('editor.sem_selecao') end
	local allowed, err = self:editableTargets()
	if not allowed or #allowed == 0 then return false, err or T('editor.sem_selecao') end
	if dx == 0 and dy == 0 and dz == 0 then return false end
	if (self.settings.edicao or {}).travar_z == true and dz ~= 0 then dz = 0 end

	local before = self.project:capturePositions(allowed)
	local positions = {}
	for i = 1, #before do
		positions[i] = {
			area = before[i].area, index = before[i].index,
			x = before[i].x + dx, y = before[i].y + dy, z = before[i].z + dz,
		}
	end
	self.project:setPositionsRaw(positions)
	self.project:pushMoveHistory(before, T('log.node_movido'))
	return true
end

function M:nudgeAxis(axis, amount)
	local dx, dy, dz = 0, 0, 0
	if axis == 'x' then dx = amount elseif axis == 'y' then dy = amount else dz = amount end
	return self:nudge(dx, dy, dz)
end

function M:snapGround()
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' then return false, T('editor.sem_selecao') end
	return self.gizmo:putOnGround()
end

function M:atPlayer()
	local ok, err = self.gizmo:putAtPlayer()
	if not ok then self:setStatus(err, 'warn') end
	return ok, err
end

function M:atCrosshair()
	local ok, err = self.gizmo:putAtCrosshair()
	if not ok then self:setStatus(err, 'warn') end
	return ok, err
end

function M:snapGrid(size)
	return self.gizmo:snapToGrid(size or self.settings.edicao.grade or 5.0)
end

function M:setPosition(x, y, z)
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' then return false, T('editor.sem_selecao') end
	local ok, err = self.project:setNodePosition(ref.area, ref.index, x, y, z)
	if ok then self:markEdited(ref.area) end
	return ok, err
end

--------------------------------------------------------------------------------
-- Edicao: criar / apagar
--------------------------------------------------------------------------------

--- Ponto do mundo onde um node novo deve nascer.
function M:createPoint()
	-- 1) mira da camera (se estiver olhando o chao)
	local x, y, z = self.gizmo:crosshairPoint(12.0)
	if x then return x, y, z, 'mira' end
	-- 2) na frente do jogador
	local px, py, pz = playerPosition()
	if not px then return nil end
	return px, py, (pz or 0), 'jogador'
end

function M:createNode(kind, x, y, z)
	kind = kind or self.newNodeKind or 'veh'
	if not x then
		x, y, z = self:createPoint()
		if not x then return false, T('misc.sem_area') end
	end

	-- limites do mundo: nenhum arquivo consegue guardar isso
	if math.abs(x) > 4000 or math.abs(y) > 4000 then
		return false, T('val.pos_out_of_range')
	end

	local areaId = geo.areaFromCoords(x, y)
	if not self.project:area(areaId) then
		local ok, err = self:loadArea(areaId)
		if not ok then
			-- nao existe arquivo para essa area: comeca uma area vazia
			local created, cerr = self:newArea(areaId)
			if not created then return false, cerr or err end
		else
			self:setStatus(T('log.area_carregada', areaId, self.project:countNodes(areaId)), 'info')
		end
	end

	if kind == 'navi' then
		local targetIndex, targetArea = nil, nil
		local nearest = self.project:nearestNode(areaId, x, y, 60.0, 'vehicle')
		if nearest then targetArea, targetIndex = areaId, nearest.index end
		if not targetIndex then
			for _, otherId in ipairs(self.project:loadedAreas()) do
				if otherId ~= areaId then
					local other = self.project:nearestNode(otherId, x, y, 60.0, 'vehicle')
					if other then targetArea, targetIndex = otherId, other.index break end
				end
			end
		end
		if not targetIndex then return false, T('navi.nao_associado') end
		local naviIndex, err = self.project:addNavi(areaId, x, y, targetArea, targetIndex)
		if not naviIndex then return false, err end
		self:markEdited(areaId)
		self:selectNavi(areaId, naviIndex)
		return true, naviIndex
	end

	local index, err = self.project:addNode(areaId, kind == 'boat' and 'boat' or kind, x, y, z)
	if not index then return false, err end
	self:markEdited(areaId)
	if self.settings.edicao.snap_solo then
		self.project:snapToGround(areaId, index)
	end
	self:selectNode(areaId, index)

	if self.linkMode == 'auto' then
		local nearest = self.project:nearestNode(areaId, x, y, 40.0, kind == 'ped' and 'ped' or 'vehicle')
		-- nearestNode devolve { index, node, distance }: o link precisa do indice
		if nearest and nearest.index ~= index then
			self.project:addLink(areaId, index, areaId, nearest.index, { oneWay = self:linkIsOneWay() })
			if self.settings.edicao.criar_navi_automatico then
				local linkIndex = self.project:findLink(self.project:node(areaId, index), areaId, nearest.index - 1)
				if linkIndex then self.project:addNaviOnSegment(areaId, index, linkIndex) end
			end
		end
	end
	self:setStatus(T('log.node_criado', index - 1), 'info')
	return true, index
end

function M:deleteSelected(force)
	local ref = self:selectedRef()
	if not ref then return false, T('editor.sem_selecao') end
	if ref.kind == 'navi' then
		local ok, err = self.project:removeNavi(ref.area, ref.index)
		if ok then
			self:markEdited(ref.area)
			self:clearSelection()
			self:setStatus(T('log.navi_removido', ref.index - 1), 'info')
		end
		return ok, err
	end

	local node = ref.node
	local count = #(node and node.links or {})
	if count > 0 and not force and not self.pendingConfirm then
		self.pendingConfirm = { kind = 'delete', area = ref.area, index = ref.index, links = count }
		return false, 'confirmar'
	end
	local ok, err = self.project:removeNode(ref.area, ref.index)
	if ok then
		self:markEdited(ref.area)
		self:clearSelection()
		self:setStatus(T('log.node_removido', ref.index - 1), 'info')
	end
	return ok, err
end

--- Pede confirmacao antes de mexer nos arquivos do ModLoader.
function M:askRevert(areaId)
	self.pendingConfirm = { kind = 'revert', area = areaId }
	return false, 'confirmar'
end

function M:askRestoreBackup(areaId)
	self.pendingConfirm = { kind = 'restore', area = areaId }
	return false, 'confirmar'
end

function M:confirmPending()
	local pending = self.pendingConfirm
	self.pendingConfirm = nil
	if not pending then return false end
	if pending.kind == 'delete' then
		return self:deleteSelected(true)
	elseif pending.kind == 'save' then
		return self:save({ force = true })
	elseif pending.kind == 'revert' then
		self.project:unloadArea(pending.area, false)
		return self:revertArea(pending.area)
	elseif pending.kind == 'restore' then
		return self:restoreBackup(pending.area)
	end
	return false
end

function M:cancelPending()
	self.pendingConfirm = nil
end

--------------------------------------------------------------------------------
-- Edicao: links
--------------------------------------------------------------------------------

function M:markLinkSource()
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' then return false, T('editor.sem_selecao') end
	self.linkSource = { area = ref.area, index = ref.index }
	self:setStatus(T('cr.link_origem') .. ': ' .. T('nav.node_number', ref.index - 1), 'info')
	return true
end

--- O proximo link sai de mao unica? (modo "sentido unico" ou espelhamento desligado)
function M:linkIsOneWay()
	if self.linkMode == 'unico' then return true end
	return self.settings.edicao.espelhar_links == false
end

function M:createLink(targetArea, targetIndex)
	local source = self.linkSource
	if not source then return false, T('cr.link_origem') end
	local ref = self:selectedRef()
	local dstArea, dstIndex
	if targetArea then
		dstArea, dstIndex = targetArea, targetIndex
	elseif ref and ref.kind == 'node' then
		dstArea, dstIndex = ref.area, ref.index
	else
		return false, T('cr.link_destino')
	end

	local ok, err = self.project:addLink(source.area, source.index, dstArea, dstIndex, { oneWay = self:linkIsOneWay() })
	if not ok then
		self:setStatus(err, 'warn')
		return false, err
	end
	self:markEdited(source.area)
	if dstArea ~= source.area then self:markEdited(dstArea) end
	self:setStatus(T('log.link_criado'), 'info')
	self.linkSource = nil
	return true
end

function M:removeLink(linkIndex)
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' or not ref.node then return false, T('editor.sem_selecao') end
	local ok, err = self.project:removeLink(ref.area, ref.index, linkIndex)
	if ok then
		self:markEdited(ref.area)
		self:setStatus(T('log.link_removido'), 'info')
	end
	return ok, err
end

function M:clearLinks()
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' then return false end
	local ok, err = self.project:clearNodeLinks(ref.area, ref.index)
	if ok then
		self:markEdited(ref.area)
		self:setStatus(T('log.limpar_links'), 'info')
	end
	return ok, err
end

function M:goToLinkTarget(linkIndex)
	local ref = self:selectedRef()
	if not ref or not ref.node or not ref.node.links[linkIndex] then return false end
	local link = ref.node.links[linkIndex]
	if self.project:area(link.area) then
		return self:selectNode(link.area, link.node + 1)
	end
	return false, T('val.area_not_loaded', link.area)
end

--------------------------------------------------------------------------------
-- Edicao: navi
--------------------------------------------------------------------------------

function M:addNaviOnLink(linkIndex)
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' then return false, T('editor.sem_selecao') end
	local naviIndex, err = self.project:addNaviOnSegment(ref.area, ref.index, linkIndex)
	if naviIndex then
		self:markEdited(ref.area)
		self:setStatus(T('log.navi_criado'), 'info')
		self:selectNavi(ref.area, naviIndex)
	end
	return naviIndex, err
end

--- Cria os navi nodes que faltam nos links de veiculo das areas carregadas.
function M:generateMissingNavis(areaId)
	local areas = areaId and { areaId } or self.project:loadedAreas()
	local created, skipped = 0, 0
	for a = 1, #areas do
		local area = self.project:area(areas[a])
		if area then
			local nodeCount = #area.nodes
			for i = 1, nodeCount do
				local node = area.nodes[i]
				if i <= area.vehCount and not util.hasBit(node.flags or 0, 7) then
					for l = 1, #node.links do
						local link = node.links[l]
						if not dat.naviLinkIsSet(link) then
							if i < link.node + 1 then -- so uma vez por par
								local ok = self.project:addNaviOnSegment(areas[a], i, l)
								if ok then created = created + 1 else skipped = skipped + 1 end
							end
						end
					end
				end
			end
			if created > 0 then self:markEdited(areas[a]) end
		end
	end
	if created then self:setStatus(T('navi.gerar') .. ': ' .. created, 'info') end
	return created, skipped
end

--- Remove navi nodes que nao estao ligados a nenhum link.
function M:removeOrphanNavis(areaId)
	local areas = areaId and { areaId } or self.project:loadedAreas()
	local removed = 0
	for a = 1, #areas do
		local id = areas[a]
		local area = self.project:area(id)
		if area then
			local referenced = {}
			for i = 1, #area.nodes do
				local node = area.nodes[i]
				for l = 1, #node.links do
					local link = node.links[l]
					if dat.naviLinkIsSet(link) and (link.naviArea == 0 or link.naviArea == id) then
						referenced[link.naviID] = true
					end
				end
			end
			local index = #area.navis
			while index >= 1 do
				if not referenced[index - 1] then
					if self.project:removeNavi(id, index) then removed = removed + 1 end
				end
				index = index - 1
			end
			if removed > 0 then self:markEdited(id) end
		end
	end
	self:setStatus(T('navi.remover_inuteis') .. ': ' .. removed, 'info')
	return removed
end

--------------------------------------------------------------------------------
-- Edicao: campos
--------------------------------------------------------------------------------

function M:setNodeField(field, value)
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' then return false, T('editor.sem_selecao') end
	local ok, err = self.project:setNodeField(ref.area, ref.index, field, value)
	if ok then
		self:markEdited(ref.area)
		if self.log then log.info(T('log.node_flag') .. ' %s = %s', tostring(field), tostring(value)) end
	end
	return ok, err
end

function M:setNodeFlag(name, value)
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'node' then return false, T('editor.sem_selecao') end
	local ok, err = self.project:setNodeFlag(ref.area, ref.index, name, value)
	if ok then
		self:markEdited(ref.area)
		if self.log then log.info('%s %s = %s', T('log.node_flag'), tostring(name), tostring(value)) end
	end
	return ok, err
end

function M:setNaviField(field, value)
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'navi' then return false, T('editor.sem_selecao') end
	local ok, err = self.project:setNaviField(ref.area, ref.index, field, value)
	if ok then
		self:markEdited(ref.area)
		if self.log then log.info('%s %s = %s', T('log.navi_flag'), tostring(field), tostring(value)) end
	end
	return ok, err
end

--- Direcao do navi (graus) -> bytes do arquivo.
function M:setNaviHeading(degrees)
	local ref = self:selectedRef()
	if not ref or ref.kind ~= 'navi' or not ref.navi then return false, T('editor.sem_selecao') end
	local rad = math.rad(degrees or 0)
	local dx, dy = geo.vectorToNaviBytes(math.sin(rad) * 100, math.cos(rad) * 100)
	local ok1 = self.project:setNaviField(ref.area, ref.index, 'dirX', dx)
	local ok2 = self.project:setNaviField(ref.area, ref.index, 'dirY', dy)
	if ok1 and ok2 then self:markEdited(ref.area) end
	return ok1 and ok2
end

function M:changed(areaId)
	self:markEdited(areaId)
end

function M:markEdited(areaId)
	self.project:markDirty(areaId)
	self.autoValidateDirty = true
	self:scanTargetMeta(areaId, self.project:area(areaId))
end

function M:undo()
	local ok, label = self.project:undo()
	if ok then
		self.autoValidateDirty = true
		self.project:rebuildIndex(self.project.selection.area or -1)
		self:setStatus(T('log.desfeito') .. ' (' .. tostring(label or '') .. ')', 'info')
	else
		self:setStatus(T('log.nada_desfazer'), 'warn')
	end
	return ok
end

function M:redo()
	local ok, label = self.project:redo()
	if ok then
		self.autoValidateDirty = true
		self:setStatus(T('log.refeito') .. ' (' .. tostring(label or '') .. ')', 'info')
	else
		self:setStatus(T('log.nada_refazer'), 'warn')
	end
	return ok
end

--------------------------------------------------------------------------------
-- Validacao
--------------------------------------------------------------------------------

function M:changes()
	return self.project:dirtyAreas()
end

function M:hasChanges()
	return #self.project:dirtyAreas() > 0
end

--- Roda a validacao das areas carregadas. options: {inGame = bool, silent = bool}
function M:validate(options)
	options = options or {}
	if self.log then log.info(T('val.titulo') .. '...') end
	self:scanAllMeta()
	local layers = { project = self.project, probe = function(id) return self:probeCounts(id) end }
	local report = validate.validateAll(self.project, layers)
	if options.inGame ~= false then
		for _, areaId in ipairs(self.project:loadedAreas()) do
			report = validate.checkInGame(self.project, areaId, { report = report })
		end
		report.canSave = report.errors == 0
	end
	self.report = report
	self.autoValidateDirty = false
	if self.log then
		log.info(T('val.resumo', report.errors, report.warns, report.infos, report.fixable or 0))
		for _, entry in ipairs(report.entries) do
			if entry.level == 'error' then log.error('[%s] area %d: %s', tostring(entry.code), entry.area or -1, tostring(entry.text)) end
		end
	end
	if not options.silent then
		if report.errors > 0 then
			self:warnPlayer(T('save.falha_validacao', report.errors, report.warns))
		elseif report.warns > 0 then
			self:setStatus(T('val.resumo', report.errors, report.warns, report.infos, report.fixable or 0), 'warn')
		else
			self:setStatus(T('val.resumo', 0, 0, report.infos, 0), 'info')
		end
	end
	return report
end

--- Revalida sozinho depois de uma edicao (no maximo a cada 1,5s).
function M:autoValidateTick()
	if not self.autoValidateDirty then return end
	local t = self:now()
	if t - (self.autoValidateTimer or 0) < 1.5 then return end
	self.autoValidateTimer = t
	self:validate({ inGame = false, silent = true })
	if self.report and self.report.errors > 0 then
		self:warnPlayer(T('val.erros_impedem', self.report.errors))
	end
end

function M:applyFixes(which)
	local report = self.report or self:validate({ inGame = false, silent = true })
	local applied, failures, fresh = validate.applyAllFixes(self.project, report, which or '1', 6)
	self.report = fresh
	self.autoValidateDirty = false
	self:setStatus(T('val.corrigido', applied, failures), applied > 0 and 'info' or 'warn')
	return applied, failures, fresh
end

function M:applySingleFix(entry)
	if not entry or not entry.fix then return false end
	local ok = entry.fix()
	if ok then
		self.autoValidateDirty = true
		self.report = nil
		self:setStatus(T('val.corrigido', 1, 0), 'info')
	end
	return ok
end

--------------------------------------------------------------------------------
-- Alteracoes (diff para a janela de salvar)
--------------------------------------------------------------------------------

function M:diffArea(areaId)
	local area = self.project:area(areaId)
	if not area then return nil end
	local original = self.originals and self.originals[areaId]
	if not original then return { identical = not self.project:isDirty(areaId) } end
	local before = dat.parse(original, areaId)
	if not before then return { identical = false } end

	local diff = {
		identical = true,
		nodesBefore = #before.nodes, nodesAfter = #area.nodes,
		navisBefore = #before.navis, navisAfter = #area.navis,
		linksBefore = dat.counts(before).linkCount, linksAfter = dat.counts(area).linkCount,
		moved = 0, flagsChanged = 0, added = 0, removed = 0,
	}
	local minNodes = math.min(#before.nodes, #area.nodes)
	for i = 1, minNodes do
		local a, b = before.nodes[i], area.nodes[i]
		if a and b then
			if a.x ~= b.x or a.y ~= b.y or a.z ~= b.z then diff.moved = diff.moved + 1 end
			if a.flags ~= b.flags or (a.pathWidth or 0) ~= (b.pathWidth or 0) then diff.flagsChanged = diff.flagsChanged + 1 end
		end
	end
	if diff.nodesAfter > diff.nodesBefore then diff.added = diff.nodesAfter - diff.nodesBefore
	elseif diff.nodesAfter < diff.nodesBefore then diff.removed = diff.nodesBefore - diff.nodesAfter end

	diff.identical = (diff.moved == 0 and diff.flagsChanged == 0 and diff.added == 0 and diff.removed == 0
		and diff.navisBefore == diff.navisAfter and diff.linksBefore == diff.linksAfter)
	return diff
end

function M:diffAll()
	local out = {}
	for _, id in ipairs(self.project:loadedAreas()) do
		out[id] = self:diffArea(id)
	end
	return out
end

--------------------------------------------------------------------------------
-- Salvar
--------------------------------------------------------------------------------

function M:canSave()
	if not self:hasChanges() then return false, T('save.aviso_so_alteracoes') end
	return true
end

--- Salva as areas alteradas. options: {force = bool, areas = {ids}, skipValidation = bool}
function M:save(options)
	options = options or {}
	local areas = options.areas or self.project:dirtyAreas()
	if #areas == 0 then
		self:setStatus(T('save.aviso_so_alteracoes'), 'warn')
		self.lastSave = { ok = false, reason = 'nothing', errors = {} }
		return self.lastSave
	end

	-- mover um node muda o comprimento dos links: recalcula antes de validar
	-- para nao acusar "comprimento errado" em algo que o salvamento ja corrige.
	if not options.skipValidation and self.settings.edicao.recalcular_comprimentos ~= false then
		for i = 1, #areas do
			self.project:recomputeLengths(areas[i])
		end
	end

	if not options.skipValidation then
		local report = self:validate({ inGame = true, silent = true })
		if report.errors > 0 and not options.force then
			self:warnPlayer(T('save.falha_validacao', report.errors, report.warns))
			self.lastSave = { ok = false, reason = 'validation', report = report, errors = {} }
			return self.lastSave
		end
		if report.warns > 0 and not options.force and not options.confirmed then
			self.pendingConfirm = { kind = 'save', report = report }
			self:setStatus(T('val.avisos_continuar'), 'warn')
			self.lastSave = { ok = false, reason = 'warnings', report = report, errors = {} }
			return self.lastSave
		end
	end

	local result = { ok = true, reason = 'saved', areas = {}, errors = {}, written = {}, size = 0 }
	for i = 1, #areas do
		local id = areas[i]
		local area = self.project:area(id)
		if area then
			if self.settings.edicao.recalcular_comprimentos ~= false then
				self.project:recomputeLengths(id)
			end
			self.project:refreshMeta(id)
			local bytes, err = dat.serialize(area)
			if not bytes then
				result.ok = false
				result.errors[#result.errors + 1] = T('save.falha_escrita', tostring(err))
				if self.log then log.error('area %d: %s', id, tostring(err)) end
			else
				self:setStatus(T('src.saving_n', id, #bytes), 'info')
				local one = self.sources:save(id, bytes, { backup = options.backup ~= false })
				result.areas[id] = one
				result.size = result.size + #bytes
				for w = 1, #one.written do result.written[#result.written + 1] = one.written[w] end
				for e = 1, #one.errors do result.errors[#result.errors + 1] = one.errors[e] end
				if not one.ok then result.ok = false end
				if one.ok then
					self.project:markClean(id)
					self.originals[id] = bytes
				end
			end
		end
	end

	self.lastSave = result
	if result.ok and #result.errors == 0 then
		self:setStatus(T('save.salvo', tostring(result.written[1] or ''), #result.written), 'info')
		if self.settings.salvar.limpar_cache_modloader ~= false then self:clearModloaderCache() end
		call('printStringNow', '~g~VPE: ' .. T('save.salvo', '', #result.written), 4000)
	else
		self:setStatus(result.errors[1] or T('save.aviso_nada'), 'error')
		call('printStringNow', '~r~VPE: ' .. (result.errors[1] or 'erro ao salvar'), 4000)
	end
	self.autoValidateDirty = false
	return result
end

function M:saveArea(areaId, options)
	return self:save({ areas = { areaId }, force = options and options.force, skipValidation = options and options.skipValidation })
end

--- Apaga os arquivos de cache do ModLoader (senao ele continua usando os antigos).
function M:clearModloaderCache()
	local cache = fs.join(self.sources.modloaderDir, '.data', 'cache')
	if not fs.exists(cache) then return false, 'sem cache' end
	local removed = 0
	local entries = fs.listDir(cache)
	for i = 1, #entries do
		local entry = entries[i]
		if entry.isDir then
			fs.shell('rmdir /s /q "' .. fs.join(entry.path) .. '"')
		else
			if fs.remove(entry.path) then removed = removed + 1 end
		end
	end
	if self.log then log.info('cache do ModLoader limpo (%d arquivo(s))', removed) end
	return true, removed
end

function M:revertArea(areaId)
	local ok = self.sources:revert(areaId)
	if self.log then log.info('override removido da area %d: %s', areaId, tostring(ok)) end
	self:setStatus(ok and T('sel.descartar') or T('save.sub_nada_alterado'), ok and 'info' or 'warn')
	return ok
end

function M:restoreBackup(areaId)
	local ok, err = self.sources:restoreBackup(areaId)
	if ok then
		self.project:unloadArea(areaId)
		local loaded = self:loadArea(areaId, { force = true })
		self:setStatus(T('log.restaurado'), 'info')
		return loaded
	end
	self:setStatus(tostring(err), 'warn')
	return false
end

--------------------------------------------------------------------------------
-- Teleporte / camera
--------------------------------------------------------------------------------

function M:teleportTo(x, y, z)
	if type(setCharCoordinates) ~= 'function' then return false, 'sem jogo' end
	local ped = util.playerPed(false)
	if not ped then return false end
	local ok = pcall(setCharCoordinates, ped, x, y, z or 10.0)
	if ok then
		call('loadScene', x, y)
		self.render:update()
	end
	return ok
end

function M:teleportToSelected()
	local ref = self:selectedRef()
	if not ref then return false, T('editor.sem_selecao') end
	local x, y, z
	if ref.kind == 'node' then
		x, y, z = ref.node.x, ref.node.y, ref.node.z + 1.0
	else
		x, y, z = ref.navi.x, ref.navi.y, 10.0
	end
	if geo.areaFromCoords(x, y) ~= ref.area then
		return false, T('val.pos_outside_area', ref.area)
	end
	local ok = self:teleportTo(x, y, z)
	if ok then self:setStatus(T('sel.ir') .. ' ' .. T('nav.node_number', ref.index - 1), 'info') end
	return ok
end

--------------------------------------------------------------------------------
-- Render / interface
--------------------------------------------------------------------------------

function M:toggleMenu()
	self.showMenu = not self.showMenu
	if self.ui then self.ui:setVisible(self.showMenu) end
end

function M:toggleRender()
	local conf = self.settings.render
	conf.ativo = not conf.ativo
	if conf.ativo and self.render then
		-- ligar o visual de novo: zera o "modo leve" e avisa se o jogo nao
		-- esta em condicoes de desenhar (pausa/carregando)
		self.render.lightFactor = 1.0
		self.render.slowFrames = 0
		self.render.readyReason = nil
		self.render.phase = 'ligado'
	end
	self:setStatus((conf.ativo and T('ui.enabled') or T('ui.disabled')) .. ': ' .. T('ui.visualizar'), 'info')
	self:warnRenderState()
	return conf.ativo
end

--- Presets de desenho: 'limpo' (padrao, para editar) e 'completo' (para ver a
--- rede toda). O primeiro deixa a tela legivel, o segundo mostra tudo.
M.RENDER_PRESETS = {
	limpo = {
		distancia = 120.0, distancia_navis = 60.0, distancia_links = 120.0,
		max_nodes = 250, max_navis = 80, max_linhas = 400,
		links_modo = 'selecionado', escala_por_distancia = true,
		tamanho_mundo = 1.2, tamanho_minimo = 1.5, tamanho_maximo = 6.0,
		fade_distancia = true, oclusao = true, mostrar_hud = true,
	},
	completo = {
		distancia = 400.0, distancia_navis = 200.0, distancia_links = 400.0,
		max_nodes = 1500, max_navis = 500, max_linhas = 3000,
		links_modo = 'todos', escala_por_distancia = false,
		tamanho_node = 4.0, fade_distancia = false, oclusao = false,
		mostrar_hud = true,
	},
}

--- Aplica um preset de desenho e salva a configuracao.
function M:applyRenderPreset(name)
	local preset = M.RENDER_PRESETS[name]
	if not preset then return false end
	for key, value in pairs(preset) do
		self.settings.render[key] = value
	end
	self:applySettings()
	if self.log then log.info('preset de desenho aplicado: %s', tostring(name)) end
	self:setStatus(T(name == 'completo' and 'cfg.preset_completo_ok' or 'cfg.preset_limpo_ok'), 'info')
	if config and config.save then config.save(self.settings) end
	return true
end

--- Liga/desliga as marcas de diagnostico do desenho (F10) e grava os numeros
--- crus da projecao no log: e assim que se descobre problema de coordenadas.
function M:toggleDiagnostic()
	if not self.render then return false end
	self.render.diagnostic = not self.render.diagnostic
	local on = self.render.diagnostic
	if self.log then
		if on then
			log.info('diagnostico do desenho LIGADO: %s', self.render:diagnosticLine())
			log.info('  esperado: quadrado VERMELHO no canto superior esquerdo, cruz VERDE no centro, quadrado AZUL no canto inferior direito')
			log.info('  no mundo: AMARELO no jogador, MAGENTA 20 m ao norte (Y+), CIANO 20 m a leste (X+)')
		else
			log.info('diagnostico do desenho desligado')
		end
	end
	self:setStatus(T(on and 'ui.diag_ligado' or 'ui.diag_desligado'), 'info')
	return on
end

--- Registra o diagnostico no log (chamado a cada segundo enquanto ligado).
function M:diagnosticTick()
	if not self.render or not self.render.diagnostic then return false end
	local t = self:now()
	if t - (self.diagTimer or 0) < 1.0 then return false end
	self.diagTimer = t
	if self.log then log.info('diag: %s', self.render:diagnosticLine()) end
	return true
end

--- Aviso curto quando o desenho esta ligado mas o jogo nao deixa desenhar.
function M:warnRenderState()
	local render = self.render
	if not render or not self.settings.render.ativo then return nil end
	local reason = render.readyReason
	if not reason then return nil end
	local text = T('ui.render_aguardando', tostring(reason))
	self:setStatus(text, 'warn')
	return text
end

function M:frame()
	if self.ui then return self.ui:frame() end
	return false
end

--------------------------------------------------------------------------------
-- Mouse no mundo
--------------------------------------------------------------------------------

local function cursorToGameScreen()
	local mx, my = call('getCursorPos')
	if type(mx) ~= 'number' then return nil end
	local gx, gy = call('convertWindowScreenCoordsToGameScreenCoords', mx, my)
	if type(gx) == 'number' then return gx, gy end
	return mx, my
end

function M:worldMouseEnabled()
	if not self.mouse.enabled then return false end
	if not self.ui then return false end
	return self.ui:worldMouseEnabled()
end

function M:updateMouse()
	self.mouse.hover = nil
	if not self:worldMouseEnabled() then
		if self.mouse.dragging then
			self.gizmo:cancelDrag()
			self.mouse.dragging = false
		end
		return
	end

	local gx, gy = cursorToGameScreen()
	if not gx then return end
	local pick = self.render:pick(gx, gy, 14)
	if not pick then pick = self.render:pickNavi(gx, gy, 12) end
	self.mouse.hover = pick

	if type(wasKeyPressed) == 'function' then
		local ok, right = pcall(wasKeyPressed, 2)
		if ok and right and pick then self:selectFromPick(pick) end
	end

	local left = false
	if type(isKeyDown) == 'function' then
		local ok, down = pcall(isKeyDown, 1)
		left = ok and down == true
	end

	if left then
		if not self.mouse.dragging then
			local ref = self:selectedRef()
			local onSelected = pick and ref and ref.kind == 'node' and pick.area == ref.area and pick.index == ref.index
			if onSelected then
				if self.gizmo:beginDrag(gx, gy) then self.mouse.dragging = true end
			end
		else
			local ok, err = self.gizmo:updateDrag(gx, gy)
			if not ok and err then self:setStatus(err, 'warn') end
		end
	elseif self.mouse.dragging then
		self.mouse.dragging = false
		if self.gizmo:finishDrag() then
			local ref = self:selectedRef()
			if ref and ref.kind == 'node' then
				self:setStatus(T('log.node_movido', ref.index - 1), 'info')
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Teclado
--------------------------------------------------------------------------------

function M:keyDown(vk)
	if not vk or type(isKeyDown) ~= 'function' then return false end
	local ok, down = pcall(isKeyDown, vk)
	return ok and down == true
end

function M:pressed(name)
	local entry = self.keys[name]
	if not entry or not entry.code then return false end
	local mods = entry.mods or {}
	local ctrl = self:keyDown(M.VK_CONTROL)
	local shift = self:keyDown(M.VK_SHIFT)
	local alt = self:keyDown(M.VK_MENU)
	if mods.ctrl and not ctrl then return false end
	if mods.shift and not shift then return false end
	if mods.alt and not alt then return false end
	if not (mods.ctrl or mods.shift or mods.alt) then
		if ctrl or alt then return false end -- CTRL_Z nao pode disparar a acao da tecla Z
	end
	if type(wasKeyPressed) ~= 'function' then return false end
	local ok, res = pcall(wasKeyPressed, entry.code)
	return ok and res == true
end

function M:updateKeys()
	if self:pressed('abrir_menu') then self:toggleMenu() end
	if self:pressed('ligar_render') then self:toggleRender() end
	if self:pressed('validar') then self:validate({}) end
	if self:pressed('salvar') then self:save({}) end
	if self:pressed('recarregar') then
		local ok, err = self:reload()
		if not ok then self:warnPlayer(err) end
	end
	if self:pressed('desfazer') then self:undo() end
	if self:pressed('refazer') then self:redo() end
	if self:pressed('criar_link') then self:createLink() end
	if self:pressed('marcar_origem') then self:markLinkSource() end
	if self:pressed('ir_para_node') then self:teleportToSelected() end
	if self:pressed('node_no_jogador') then self:atPlayer() end
	if self:pressed('node_na_mira') then self:atCrosshair() end
	if self:pressed('snap_solo') then self:snapGround() end
	if self:pressed('diagnostico') then self:toggleDiagnostic() end
	if self:pressed('proximo_node') then
		local ok, entry = self:cycleNode(1)
		if ok and entry then
			self:setStatus(T('nav.node_number', entry.index - 1) .. ' (' .. string.format('%.1f m', entry.distance) .. ')', 'info')
		end
	end
	if self:pressed('criar_node') then
		local ok, err = self:createNode(self.newNodeKind)
		if not ok then self:warnPlayer(err) end
	end
	if self:pressed('apagar_node') then
		local ok, err = self:deleteSelected(false)
		if not ok and err and err ~= 'confirmar' then self:warnPlayer(err) end
	end
end

--- Empurra o node com o numpad enquanto o painel esta aberto.
function M:updateNudge(dt)
	if not self.showMenu or not self:hasSelection() then return false end
	local step = self.gizmo:stepFor(self:keyDown(M.VK_CONTROL), self:keyDown(M.VK_SHIFT))
	local held = false
	for i = 1, #M.NUDGE_KEYS do
		local entry = M.NUDGE_KEYS[i]
		if entry.key == 101 and self:keyDown(101) then -- numpad 5 = colar no chao
			held = true
			if self.repeatTimer <= 0 then
				self:snapGround()
				self.repeatTimer = 0.25
			end
		elseif self:keyDown(entry.key) then
			held = true
			if self.repeatTimer <= 0 then
				self:nudgeAxis(entry.axis, entry.dir * step)
				self.repeatTimer = 0.06
			end
		end
	end
	if not held then
		self.repeatTimer = 0
	else
		self.repeatTimer = self.repeatTimer - (dt or 0.016)
	end
	return held
end

--------------------------------------------------------------------------------
-- Loop
--------------------------------------------------------------------------------

function M:update(dt)
	dt = dt or 0.016
	self:updateKeys()
	self:updateMouse()
	self:updateNudge(dt)
	self:autoValidateTick()
	self:diagnosticTick()
end

function M:drawWorld()
	if not self.settings.render.ativo then return false end
	local result = self.render:draw()
	if (self.settings.geral or {}).log_api and self.log then
		-- log de diagnostico: a ultima linha antes de um travamento diz em que
		-- fase do desenho ele aconteceu
		local now = self:now()
		if self.logPhase ~= self.render.phase or (now - (self.logPhaseTime or -999)) >= 2.0 then
			self.logPhase = self.render.phase
			self.logPhaseTime = now
			self.log.info('desenho: fase=%s %s', tostring(self.render.phase), self.render:statsLine())
		end
	end
	return result
end

function M:runtimeInfo()
	local info = {
		version = M.VERSION,
		gameDir = self.gameDir,
		luaVersion = _VERSION,
		moonloader = call('getMoonloaderVersion'),
		game = call('getGameVersion'),
		modloader = fs.exists(fs.join(self.gameDir, 'modloader')),
		gta3img = fs.exists(fs.join(self.gameDir, 'models', 'gta3.img')),
		exportFolder = self.sources.exportFolder,
		imgFolder = self.sources.ownImgFolder,
		backupFolder = self.sources.backupFolder,
		logPath = self.log and log.path,
		lang = i18n.getLang(),
		sources = self.sources:summary(),
		areas = #self.project:loadedAreas(),
	}
	return info
end

function M:onExit()
	if self.project and self:hasChanges() then
		local dirty = self.project:dirtyAreas()
		if self.log then
			log.warn('saindo com %d area(s) alterada(s) e nao salva(s): %s', #dirty, table.concat(dirty, ', '))
		end
	end
	if self.settings and self.settings.geral and self.log then
		config.save(self.settings)
	end
	if self.log then log.info('Visual Path Editor finalizado') end
end

--------------------------------------------------------------------------------
-- Bloqueio de nodes/links (trava para nao editar sem querer)
--------------------------------------------------------------------------------

local function lockKey(areaId, index)
	return tostring(areaId) .. ':' .. tostring(index)
end

function M:isLocked(areaId, index)
	if not areaId or not index then return false end
	return self.locked[lockKey(areaId, index)] == true
end

function M:setLocked(areaId, index, value)
	if not areaId or not index then return false end
	local key = lockKey(areaId, index)
	if value then
		self.locked[key] = true
		self:setStatus(T('cr.bloqueio') .. ': ' .. T('nav.node_number', index - 1), 'info')
	else
		self.locked[key] = nil
		self:setStatus(T('cr.remover_bloqueio') .. ': ' .. T('nav.node_number', index - 1), 'info')
	end
	return true
end

--- Nodes da selecao que podem ser editados (nenhum bloqueado).
function M:editableTargets()
	local list, kind = self.gizmo:targets()
	local blocked = 0
	local allowed = {}
	for i = 1, #list do
		if self:isLocked(list[i].area, list[i].index) then
			blocked = blocked + 1
		else
			allowed[#allowed + 1] = list[i]
		end
	end
	if blocked > 0 and #allowed == 0 then
		return nil, T('cr.bloqueando_node')
	end
	if blocked > 0 then
		self:setStatus(T('cr.bloqueando_node') .. ' (' .. blocked .. ')', 'warn')
	end
	return allowed, kind
end

--------------------------------------------------------------------------------
-- Aplicar configuracoes carregadas (usado quando o usuario restaura o padrao)
--------------------------------------------------------------------------------

function M:applySettings()
	self.settings = ensureDefaults(self.settings or {})
	i18n.setLang(self.settings.geral.idioma or 'pt')
	log.debugEnabled = self.settings.geral.debug == true
	local salvar = self.settings.salvar or {}
	if self.sources then
		self.sources.writeImgFolder = salvar.escrever_img ~= false
		self.sources.writeExport = salvar.escrever_export ~= false
		self.sources.backup = salvar.backup ~= false
		self.sources.directImg = salvar.tambem_gta3img_direto == true
	end
	if self.render then self.render:refreshColors() end
	for name, value in pairs(self.settings.teclas or {}) do
		local code, mods = config.keyCode(value, self.vkeys or _G.vkeys)
		self.keys[name] = { code = code, mods = mods or {}, raw = value }
	end
	return self.settings
end


--------------------------------------------------------------------------------
-- Acompanhar o jogador (carregar a area em que ele entrou)
--------------------------------------------------------------------------------

--- Chamado no loop: carrega a area do jogador quando ele muda de area.
function M:followPlayerTick(force)
	-- OBS: "carregar_vizinhas" controla apenas as areas AO REDOR; a area onde o
	-- jogador esta sempre e carregada (senao o editor nao acompanha o jogo).
	local t = self:now()
	-- na primeira chamada (followTimer ainda nil) carrega na hora
	if not force and self.followTimer and (t - self.followTimer) < 3.0 then return false end
	self.followTimer = t

	local areaId = self:playerArea()
	if not areaId then return false end
	if self.project:area(areaId) then return false end

	local ok, err = self:loadArea(areaId)
	if not ok then
		if self.log then log.warn('nao foi possivel carregar a area %d: %s', areaId, tostring(err)) end
		return false
	end
	if self.settings.geral.carregar_vizinhas ~= false then
		local neighbors = geo.areaNeighborhood(areaId)
		for i = 1, #neighbors do
			local id = neighbors[i]
			if id ~= areaId and not self.project:area(id) and self.sources:exists(id) then
				self:loadArea(id)
			end
		end
	end
	self:setStatus(T('log.area_carregada', areaId, self.project:countNodes(areaId)), 'info')
	return true
end


return M
