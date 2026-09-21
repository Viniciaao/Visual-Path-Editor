--[[
	Visual Path Editor - vpe.gizmo
	Manipulacao dos nodes no mundo (arrastar com o mouse, empurrar com as
	teclas, colar no chao, colocar no jogador / na mira).

	Cada arrasto gera UMA entrada no historico (nao uma por quadro): as
	posicoes sao aplicadas "cruas" durante o movimento e o undo e registrado
	no fim, comparando com as posicoes originais.
]]

local util = require 'vpe.util'
local dat = require 'vpe.dat'
local geo = require 'vpe.geometry'
local i18n = require 'vpe.i18n'

local M = {}

local T = i18n.t

M.MAX_STEP = 250.0 -- maior salto aceito em um unico passo (evita acidentes)

function M.new(project, options)
	options = options or {}
	local self = {
		project = project,
		settings = options.settings or {},
		render = options.render,
		steps = {
			fine = (options.settings and options.settings.edicao and options.settings.edicao.passo_fino) or 0.125,
			normal = (options.settings and options.settings.edicao and options.settings.edicao.passo_normal) or 1.0,
			coarse = (options.settings and options.settings.edicao and options.settings.edicao.passo_grosso) or 8.0,
		},
		snap = options.snap or 0,
		dragging = false,
		before = nil,
		anchor = nil,
		planeZ = 0,
		lastError = nil,
		maxStep = options.maxStep or M.MAX_STEP,
	}
	setmetatable(self, { __index = M })
	return self
end

--------------------------------------------------------------------------------
-- Alvos
--------------------------------------------------------------------------------

--- Lista de nodes que o gizmo manipula: a multi selecao ou o node selecionado.
function M:targets()
	local project = self.project
	local list = {}
	local multi = project:multiList()
	if #multi > 0 then
		for i = 1, #multi do list[#list + 1] = { area = multi[i].area, index = multi[i].index } end
		return list, 'multi'
	end
	local sel = project.selection
	if sel.area and sel.node then
		list[1] = { area = sel.area, index = sel.node }
		return list, 'single'
	end
	return list, nil
end

function M:selectedNode()
	local sel = self.project.selection
	if not sel.area or not sel.node then return nil end
	return self.project:node(sel.area, sel.node), sel.area, sel.node
end

--------------------------------------------------------------------------------
-- Arrasto com o mouse
--------------------------------------------------------------------------------

local function worldOnPlane(screenX, screenY, planeZ)
	local ax, ay, az, bx, by, bz = geo.screenRay(screenX, screenY)
	if not ax then return nil end
	return geo.rayPlaneZ(ax, ay, az, bx, by, bz, planeZ)
end

M.worldOnPlane = worldOnPlane

function M:beginDrag(screenX, screenY, options)
	options = options or {}
	local list, kind = self:targets()
	if #list == 0 then
		self.lastError = T('editor.sem_selecao')
		return false, self.lastError
	end
	local first = self.project:node(list[1].area, list[1].index)
	if not first then
		self.lastError = 'node inexistente'
		return false, self.lastError
	end

	self.planeZ = options.planeZ or first.z or 0
	local wx, wy = worldOnPlane(screenX, screenY, self.planeZ)
	if not wx then
		self.lastError = 'nao foi possivel converter a posicao do mouse para o mundo'
		return false, self.lastError
	end

	self.before = self.project:capturePositions(list)
	self.anchor = { wx = wx, wy = wy }
	self.dragging = true
	self.lastError = nil
	return true
end

function M:updateDrag(screenX, screenY)
	if not self.dragging then return false, 'sem arrasto em andamento' end
	local wx, wy = worldOnPlane(screenX, screenY, self.planeZ)
	if not wx then return false, 'fora do mundo' end

	local dx = wx - self.anchor.wx
	local dy = wy - self.anchor.wy
	if self.snap and self.snap > 0 then
		dx = util.snapTo(dx, self.snap)
		dy = util.snapTo(dy, self.snap)
	end

	local limit = self.maxStep
	if math.abs(dx) > limit or math.abs(dy) > limit then
		self.lastError = 'movimento grande demais (talvez a camera tenha mudado)'
		return false, self.lastError
	end

	local positions = {}
	for i = 1, #self.before do
		local b = self.before[i]
		positions[i] = { area = b.area, index = b.index, x = b.x + dx, y = b.y + dy, z = b.z }
	end
	self.project:setPositionsRaw(positions)
	self.lastOffset = { x = dx, y = dy, z = 0 }
	return true
end

--- Fecha o arrasto registrando UMA entrada de historico.
function M:finishDrag()
	if not self.dragging then return false end
	self.dragging = false
	local changed = false
	if self.before and self.lastOffset and (self.lastOffset.x ~= 0 or self.lastOffset.y ~= 0) then
		self.project:pushMoveHistory(self.before, T('log.node_movido'))
		changed = true
	end
	self.before = nil
	self.lastOffset = nil
	return changed
end

--- Cancela o arrasto devolvendo os nodes para o lugar.
function M:cancelDrag()
	if not self.dragging then return false end
	self.dragging = false
	if self.before then
		self.project:setPositionsRaw(self.before)
	end
	self.before = nil
	self.lastOffset = nil
	return true
end

function M:isDragging()
	return self.dragging == true
end

function M:isDraggingZ()
	return self.draggingZ == true
end

--------------------------------------------------------------------------------
-- Movimento por teclado
--------------------------------------------------------------------------------

--- Empurra os nodes selecionados. Devolve true quando algo mudou.
function M:moveBy(dx, dy, dz)
	local list = self:targets()
	if #list == 0 then return false, T('editor.sem_selecao') end
	if dx == 0 and dy == 0 and dz == 0 then return false end
	if (self.settings.edicao or {}).travar_z == true and dz ~= 0 then dz = 0 end
	local ok = self.project:translateNodes(list, dx, dy, dz)
	if ok then
		self.lastOffset = { x = dx, y = dy, z = dz }
		self.lastError = nil
	end
	return ok
end

--- Passo conforme as teclas de modificacao (ctrl = fino, shift = grosso).
function M:stepFor(ctrl, shift)
	if ctrl then return self.steps.fine end
	if shift then return self.steps.coarse end
	return self.steps.normal
end

--- Empurra o node no eixo informado ('x', 'y', 'z').
function M:moveAxis(axis, amount)
	if axis == 'x' then return self:moveBy(amount, 0, 0) end
	if axis == 'y' then return self:moveBy(0, amount, 0) end
	if axis == 'z' then return self:moveBy(0, 0, amount) end
	return false, 'eixo invalido'
end

--------------------------------------------------------------------------------
-- Posicionamento
--------------------------------------------------------------------------------

--- Leva o node (ou todos os selecionados) para uma posicao absoluta.
function M:setToPoint(x, y, z, options)
	options = options or {}
	local list = self:targets()
	if #list == 0 then return false, T('editor.sem_selecao') end
	local before = self.project:capturePositions(list)
	local positions = {}
	for i = 1, #before do
		local b = before[i]
		if options.keepZ then
			positions[i] = { area = b.area, index = b.index, x = x, y = y, z = b.z }
		else
			positions[i] = { area = b.area, index = b.index, x = x, y = y, z = z or b.z }
		end
	end
	if options.offset then
		for i = 1, #positions do
			positions[i].x = positions[i].x + (options.offset.x or 0)
			positions[i].y = positions[i].y + (options.offset.y or 0)
		end
	end
	self.project:setPositionsRaw(positions)
	self.project:pushMoveHistory(before, options.label or T('log.node_movido'))
	return true
end

--- Coloca o node no chao (ou na agua, se for mais alto).
function M:putOnGround(offset)
	local list = self:targets()
	if #list == 0 then return false, T('editor.sem_selecao') end
	local offsetZ = offset or 0.5
	if self.snap and self.snap > 0 then offsetZ = 0 end
	local before = self.project:capturePositions(list)
	local positions = {}
	local moved = false
	for i = 1, #before do
		local b = before[i]
		local z = geo.surfaceZ(b.x, b.y, b.z + 5.0)
		if z then
			positions[i] = { area = b.area, index = b.index, x = b.x, y = b.y, z = z + offsetZ }
			if math.abs((z + offsetZ) - b.z) > 0.001 then moved = true end
		else
			positions[i] = { area = b.area, index = b.index, x = b.x, y = b.y, z = b.z }
		end
	end
	if not moved then return false, T('edicao.sem_mudanca') end
	self.project:setPositionsRaw(positions)
	self.project:pushMoveHistory(before, T('log.node_solo'))
	return true
end

--- Coloca o node no jogador (ou no veiculo, se estiver dirigindo).
function M:putAtPlayer(offset)
	local x, y, z = util.playerCoords()
	if not x then return false, T('ui.sem_jogador') end
	return self:setToPoint(x, y, z + (offset or 0.7), { keepZ = false, label = T('log.node_jogador') })
end

--- Ponto do mundo na mira da camera (usado para criar nodes novos).
--- Devolve x, y, z ou nil, motivo.
function M:crosshairPoint(distance)
	local w, h = 1920, 1080
	if type(getScreenResolution) == 'function' then
		local ok, sw, sh = pcall(getScreenResolution)
		if ok and type(sw) == 'number' and sw > 0 then w, h = sw, sh end
	end
	local ax, ay, az, bx, by, bz = geo.screenRay(w / 2, h / 2)
	if not ax then return nil, 'nao foi possivel ler a camera' end
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 0.0001 then return nil, 'direcao invalida' end
	distance = distance or 12.0
	local x = ax + dx / len * distance
	local y = ay + dy / len * distance
	local z = az + dz / len * distance
	local ground = geo.surfaceZ(x, y, z + 5.0)
	if ground then z = ground + 0.5 end
	return x, y, z
end

--- Coloca o node no ponto que a camera esta mirando (centro da tela).
function M:putAtCrosshair(distance, offset)
	local w, h = 1920, 1080
	if type(getScreenResolution) == 'function' then
		local ok, sw, sh = pcall(getScreenResolution)
		if ok and type(sw) == 'number' and sw > 0 then w, h = sw, sh end
	end
	local ax, ay, az, bx, by, bz = geo.screenRay(w / 2, h / 2)
	if not ax then return false, 'nao foi possivel ler a camera' end
	distance = distance or 12.0
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 0.0001 then return false, 'direcao invalida' end
	local x = ax + dx / len * distance
	local y = ay + dy / len * distance
	local z = az + dz / len * distance
	local ground = geo.surfaceZ(x, y, z + 5.0)
	if ground then z = ground + (offset or 0.5) end
	return self:setToPoint(x, y, z, { keepZ = false, label = T('log.node_mira') })
end

--- Arredonda as posicoes para uma grade (ex.: 5 unidades).
function M:snapToGrid(size)
	size = size or self.snap
	if not size or size <= 0 then return false, 'grade invalida' end
	local list = self:targets()
	if #list == 0 then return false, T('editor.sem_selecao') end
	local before = self.project:capturePositions(list)
	local positions = {}
	for i = 1, #before do
		local b = before[i]
		positions[i] = {
			area = b.area, index = b.index,
			x = util.snapTo(b.x, size), y = util.snapTo(b.y, size), z = b.z,
		}
	end
	self.project:setPositionsRaw(positions)
	self.project:pushMoveHistory(before, T('log.node_grade'))
	return true
end

--- Espelha o node em relacao a um ponto (usado para duplicar uma via).
function M:mirrorOver(areaId, index, px, py, options)
	options = options or {}
	local node = self.project:node(areaId, index)
	if not node then return false, 'node inexistente' end
	local x = 2 * px - node.x
	local y = 2 * py - node.y
	local ok, err = self.project:setNodePosition(areaId, index, x, y, node.z)
	if ok and options.ground ~= false then
		self.project:snapToGround(areaId, index)
	end
	return ok, err
end

return M
