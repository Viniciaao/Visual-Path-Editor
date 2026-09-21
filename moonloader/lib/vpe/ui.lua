--[[
	Visual Path Editor - vpe.ui
	Interface em Moon ImGui (a Moon ImGui 1.1.5 usa o ImGui 1.52).

	Nada aqui depende de uma versao exata do binding: cada chamada passa por
	M:call(), que checa a existencia da funcao e captura erros (o menu continua
	funcionando mesmo que um widget nao exista naquela build).

	A interface nao guarda estado de edicao: tudo fica no vpe.app.
]]

local util = require 'vpe.util'
local fs = require 'vpe.fs'
local log = require 'vpe.log'
local dat = require 'vpe.dat'
local geo = require 'vpe.geometry'
local i18n = require 'vpe.i18n'
local config = require 'vpe.config'
local validate = require 'vpe.validate'

local M = {}

local T = i18n.t

M.TABS = {
	{ id = 'editor', label = 'ui.aba_editor' },
	{ id = 'navis', label = 'ui.aba_navis' },
	{ id = 'criar', label = 'ui.aba_edicao' },
	{ id = 'area', label = 'ui.aba_area' },
	{ id = 'salvar', label = 'ui.aba_salvar' },
	{ id = 'camera', label = 'ui.aba_camera' },
	{ id = 'config', label = 'ui.aba_config' },
	{ id = 'log', label = 'ui.aba_log' },
	{ id = 'ajuda', label = 'ui.aba_ajuda' },
}

M.AREA_COUNT = 64

M.CORES = {
	error = { 1.00, 0.35, 0.35, 1.0 },
	warn = { 1.00, 0.80, 0.30, 1.0 },
	info = { 0.70, 0.85, 1.00, 1.0 },
	dim = { 0.65, 0.65, 0.65, 1.0 },
	good = { 0.45, 0.95, 0.45, 1.0 },
}

local TRAFFIC_LEVELS = { 'flag.traffic_full', 'flag.traffic_high', 'flag.traffic_medium', 'flag.traffic_low' }
local TRAFFIC_LIGHTS = { 'navi.no_semaforo', 'navi.ns', 'navi.we' }

--------------------------------------------------------------------------------
-- Construtor
--------------------------------------------------------------------------------

function M.new(app)
	local self = {
		app = app,
		visible = false,
		binding = nil,
		bindingName = nil,
		hook = nil,
		refs = {},
		pages = {},
		failures = {},
		warned = {},
		tab = 'editor',
		openRef = nil,
		tabRef = nil,
		posSync = nil,
		posRefs = nil,
		filterRef = nil,
		filter = '',
		linkTarget = nil,
		showConfirm = false,
	}
	setmetatable(self, { __index = M })
	return self
end

--- Carrega o binding do ImGui. Devolve true quando o menu esta disponivel.
function M:init()
	local binding, name = M.loadBinding()
	self.binding = binding
	self.bindingName = name
	if not binding then
		log.warn('Moon ImGui nao encontrado: o mod roda sem o menu (instale o ImGui 1.1.5 na pasta do jogo).')
		return false
	end
	self:installHook()
	log.info('interface: %s (%s)', tostring(name), tostring(self.hook or 'sem hook'))
	return true
end

function M.loadBinding()
	local ok, mod = pcall(require, 'imgui')
	if ok and type(mod) == 'table' and type(mod.Begin) == 'function' then return mod, 'imgui' end
	local ok2, mod2 = pcall(require, 'mimgui')
	if ok2 and type(mod2) == 'table' and type(mod2.Begin) == 'function' then return mod2, 'mimgui' end
	return nil, nil
end

function M:installHook()
	local binding = self.binding
	if not binding then return false end
	local draw = function() return self:frame() end

	if type(binding.OnFrame) == 'function' then
		local ok = pcall(binding.OnFrame, function() return self.visible end, draw)
		if ok then self.hook = 'OnFrame' return true end
	end
	if type(binding.OnDrawFrame) == 'function' then
		local ok = pcall(binding.OnDrawFrame, draw)
		if ok then self.hook = 'OnDrawFrame(fn)' return true end
	end
	binding.OnDrawFrame = draw
	self.hook = 'OnDrawFrame=fn'
	return true
end

function M:setVisible(value)
	self.visible = value and true or false
	if self.binding then
		pcall(function() self.binding.Process = self.visible end)
		if self.binding.LockPlayer ~= nil then
			pcall(function() self.binding.LockPlayer = self.visible end)
		end
		if self.binding.ShowCursor ~= nil then
			pcall(function() self.binding.ShowCursor = self.visible end)
		end
	end
	return self.visible
end

function M:toggle()
	return self:setVisible(not self.visible)
end

function M:available()
	return self.binding ~= nil
end

--- O mouse esta livre para interagir com o mundo (fora das janelas)?
function M:worldMouseEnabled()
	if not self.visible or not self.binding then return false end
	local io = self:getIO()
	if io and io.WantCaptureMouse ~= nil then
		local ok, value = pcall(function() return io.WantCaptureMouse end)
		if ok and type(value) == 'boolean' then return not value end
	end
	return true
end

--------------------------------------------------------------------------------
-- Adaptador de widgets
--------------------------------------------------------------------------------

function M:call(name, ...)
	local binding = self.binding
	if not binding then return nil end
	local fn = binding[name]
	if type(fn) ~= 'function' then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		self.failures[name] = tostring(a)
		if not self.warned[name] then
			self.warned[name] = true
			log.warn('imgui.%s falhou: %s', tostring(name), tostring(a))
		end
		return nil
	end
	return a, b, c
end

function M:has(name)
	return type(self.binding and self.binding[name]) == 'function'
end

--- Cria um "ref" (ImBool/ImInt/ImFloat/ImBuffer ou os cdata do mimgui) com
--- acesso uniforme por :get()/:set().
function M:makeRef(kind, value)
	local binding = self.binding
	local native, isCdata = nil, false
	if kind == 'bool' then
		if type(binding.ImBool) == 'function' then native = binding.ImBool(value and true or false)
		elseif binding.new and binding.new.bool then native = binding.new.bool(value and true or false) isCdata = true end
	elseif kind == 'int' then
		if type(binding.ImInt) == 'function' then native = binding.ImInt(util.round(value or 0))
		elseif binding.new and binding.new.int then native = binding.new.int(util.round(value or 0)) isCdata = true end
	elseif kind == 'float' then
		if type(binding.ImFloat) == 'function' then native = binding.ImFloat(value or 0)
		elseif binding.new and binding.new.float then native = binding.new.float(value or 0) isCdata = true end
	elseif kind == 'buffer' then
		if type(binding.ImBuffer) == 'function' then
			local ok, buf = pcall(binding.ImBuffer, value or 256)
			if ok then native = buf end
		elseif binding.new and binding.new.char then
			local ok, buf = pcall(function() return binding.new.char[value or 256]() end)
			if ok then native = buf isCdata = true end
		end
	end
	local ref = { kind = kind, native = native, isCdata = isCdata, value = value, size = value }
	if not native then return nil end
	function ref:get()
		if self.isCdata then
			if self.kind == 'buffer' then return tostring(self.value or '') end
			return self.native[0]
		end
		if self.kind == 'buffer' then return self.native.v end
		return self.native.v
	end
	function ref:set(v)
		self.value = v
		if not self.native then return end
		if self.isCdata then
			if self.kind == 'buffer' then return end
			self.native[0] = v
			return
		end
		if self.kind == 'buffer' then
			local ok = pcall(function() self.native.v = v end)
			return ok
		end
		self.native.v = v
	end
	ref:set(value)
	return ref
end

function M:ref(kind, key, value)
	local existing = self.refs[key]
	if existing then return existing end
	local created = self:makeRef(kind, value)
	if created then created.key = key self.refs[key] = created end
	return created
end

--- Sincroniza um ref com um valor novo (sem perder o objeto nativo).
function M:syncRef(kind, key, value)
	local r = self.refs[key]
	if not r then return self:ref(kind, key, value) end
	if r:get() ~= value then r:set(value) end
	return r
end

function M:vec2(x, y)
	local binding = self.binding
	if type(binding.ImVec2) == 'function' then
		local ok, v = pcall(binding.ImVec2, x, y)
		if ok then return v end
	end
	if binding.new and binding.new.ImVec2 then
		local ok, v = pcall(function() return binding.new.ImVec2(x, y) end)
		if ok then return v end
	end
	return nil
end

function M:vec4(r, g, b, a)
	local binding = self.binding
	if type(binding.ImVec4) == 'function' then
		local ok, v = pcall(binding.ImVec4, r, g, b, a)
		if ok then return v end
	end
	if binding.new and binding.new.ImVec4 then
		local ok, v = pcall(function() return binding.new.ImVec4(r, g, b, a) end)
		if ok then return v end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Atalhos de widget
--------------------------------------------------------------------------------

function M:text(fmt, ...)
	local text = (select('#', ...) > 0) and string.format(fmt, ...) or tostring(fmt)
	self:call('Text', '%s', text)
end

function M:textWrapped(fmt, ...)
	local text = (select('#', ...) > 0) and string.format(fmt, ...) or tostring(fmt)
	if not self:has('TextWrapped') or not self:call('TextWrapped', '%s', text) then
		self:call('Text', '%s', text)
	end
end

function M:textColored(color, text)
	local v = self:vec4(color[1], color[2], color[3], color[4] or 1.0)
	if v and self:has('TextColored') and self:call('TextColored', v, '%s', text) then return end
	self:call('Text', '%s', text)
end

function M:textDim(text)
	self:textColored(M.CORES.dim, text)
end

function M:separator() self:call('Separator') end
function M:sameLine() self:call('SameLine') end
function M:spacing() self:call('Spacing') end
function M:dummy(w, h) self:call('Dummy', self:vec2(w, h)) end
function M:bullet(text) self:call('BulletText', '%s', text) end
function M:treePop() self:call('TreePop') end
function M:endChild() self:call('EndChild') end

function M:button(label, w, h)
	local size = (w and self:vec2(w, h or 0)) or nil
	if size then return self:call('Button', label, size) == true end
	return self:call('Button', label) == true
end

function M:smallButton(label)
	return self:call('SmallButton', label) == true
end

function M:checkbox(label, ref)
	if not ref then return false end
	return self:call('Checkbox', label, ref.native) == true
end

function M:inputInt(label, ref, step, fast)
	if not ref then return false end
	return self:call('InputInt', label, ref.native, step or 1, fast or 10) == true
end

function M:inputFloat(label, ref, step)
	if not ref then return false end
	return self:call('InputFloat', label, ref.native, step or 0.5, 2) == true
end

function M:sliderInt(label, ref, min, max)
	if not ref then return false end
	return self:call('SliderInt', label, ref.native, min, max) == true
end

function M:sliderFloat(label, ref, min, max)
	if not ref then return false end
	return self:call('SliderFloat', label, ref.native, min, max) == true
end

function M:combo(label, ref, items)
	if not ref or not items or #items == 0 then return false end
	local index = util.round(ref:get()) + 1
	if index < 1 then index = 1 end
	if index > #items then index = #items end
	local changed = self:call('Combo', label, ref.native, items)
	if changed == true then
		local newIndex = util.round(ref:get()) + 1
		return newIndex ~= index, newIndex
	end
	return false, index
end

function M:selectable(label, selected)
	if self:has('Selectable') then
		return self:call('Selectable', label, selected == true) == true
	end
	return self:button((selected and '[x] ' or '[  ] ') .. label)
end

function M:treeNode(label)
	if self:has('TreeNode') then return self:call('TreeNode', '%s', label) == true end
	return false
end

function M:collapsingHeader(label, ref)
	if self:has('CollapsingHeader') then
		if ref then return self:call('CollapsingHeader', label, ref.native) == true end
		return self:call('CollapsingHeader', label) == true
	end
	return false
end

function M:beginChild(id, w, h)
	local size = self:vec2(w or 0, h or 0)
	if size then return self:call('BeginChild', id, size, false) == true end
	return self:call('BeginChild', id) == true
end

function M:beginWindow(title, ref)
	if ref then return self:call('Begin', title, ref.native) == true end
	return self:call('Begin', title) == true
end

function M:endWindow() self:call('End') end

function M:setNextWindowSize(w, h, cond)
	local size = self:vec2(w, h)
	if not size then return end
	local flag = nil
	if cond and self.binding then flag = self.binding.Cond and self.binding.Cond.FirstUseEver end
	if flag then self:call('SetNextWindowSize', size, flag) else self:call('SetNextWindowSize', size) end
end

function M:pushItemWidth(w) self:call('PushItemWidth', w) end
function M:popItemWidth() self:call('PopItemWidth') end

function M:openPopup(name) self:call('OpenPopup', name) end
function M:beginPopupModal(name)
	return self:call('BeginPopupModal', name, nil) == true
end
function M:endPopup() self:call('EndPopup') end
function M:closeCurrentPopup() self:call('CloseCurrentPopup') end

function M:getIO()
	if not self.binding then return nil end
	if not self.ioRef then
		local ok, io = pcall(function() return self.binding.GetIO and self.binding.GetIO() end)
		if ok then self.ioRef = io end
	end
	return self.ioRef
end

function M:tooltip(text)
	if self:has('SetTooltip') then self:call('SetTooltip', '%s', text) return end
	if self:has('BeginTooltip') and self:call('BeginTooltip') then
		self:call('Text', '%s', text)
		self:call('EndTooltip')
	end
end

function M:progressBar(frac, w, h)
	if not self:has('ProgressBar') then return end
	local size = (w and self:vec2(w, h or 0)) or nil
	if size then self:call('ProgressBar', frac, size) else self:call('ProgressBar', frac) end
end

--------------------------------------------------------------------------------
-- Utilidades de layout
--------------------------------------------------------------------------------

function M:labelValue(label, text)
	self:text('%s: %s', label, text)
end

function M:labeledSlider(label, kind, key, value, min, max, step)
	local ref = self:syncRef(kind, key, value)
	if not ref then self:labelValue(label, string.format('%.3f', value or 0)) return false end
	local changed
	if kind == 'int' then changed = self:sliderInt(label, ref, min, max)
	else changed = self:sliderFloat(label, ref, min, max) end
	if changed then return true, ref:get() end
	return false, value
end

function M:checkboxBinding(label, kind, key, value, onChange)
	local ref = self:syncRef(kind or 'bool', key, value)
	if not ref then return false end
	local changed = self:checkbox(label, ref)
	if changed and onChange then onChange(ref:get()) end
	return changed, ref:get()
end

--- Paginacao simples (usada nas listas de nodes/navis).
function M:paginate(key, total, perPage)
	local state = self.pages[key]
	if not state then
		state = { page = 1, perPage = perPage or 60 }
		self.pages[key] = state
	end
	local pages = math.max(1, math.ceil(total / state.perPage))
	if state.page > pages then state.page = pages end
	self:text('%d %s %d  (%s %d)', state.page, T('nav.de'), pages, T('ui.prox'), state.perPage)
	self:sameLine()
	if self:smallButton('<') then state.page = state.page - 1 end
	self:sameLine()
	if self:smallButton('>') then state.page = state.page + 1 end
	if state.page < 1 then state.page = 1 end
	if state.page > pages then state.page = pages end
	local first = (state.page - 1) * state.perPage + 1
	local last = math.min(total, first + state.perPage - 1)
	return first, last, state
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

function M:frame()
	if not self.binding then return false end
	pcall(function()
		if self.binding.Process ~= nil then self.binding.Process = self.visible end
	end)
	if not self.visible then return false end
	local app = self.app
	self:drawWindow()
	self:drawConfirm()
	return true
end

function M:drawWindow()
	local app = self.app
	local areaId = app.project.selection.area
	local title
	if areaId then
		title = T('ui.painel_lateral', app.version, areaId)
	else
		title = T('ui.painel_lateral_sem_area', app.version)
	end

	self.openRef = self.openRef or self:makeRef('bool', true)
	if not self:beginWindow(title, self.openRef) then
		self:endWindow()
		return false
	end
	local open = self.openRef:get()
	if open == false then
		self.visible = false
		self:endWindow()
		return false
	end

	-- barra com o seletor de abas
	self:drawTabs()
	self:separator()

	local panel = self['draw_' .. tostring(self.tab) .. '_tab']
	if panel then
		panel(self)
	else
		self:text(T('ui.aba_editor'))
	end

	self:drawStatusBar()
	self:endWindow()
	return true
end

function M:drawTabs()
	local app = self.app
	local labels = {}
	for i = 1, #M.TABS do labels[i] = T(M.TABS[i].label) end
	self.tabRef = self:syncRef('int', 'tab', self:tabIndex() - 1)
	local changed, index = self:combo(T('ui.painel'), self.tabRef, labels)
	if changed and index then
		self.tab = M.TABS[index] and M.TABS[index].id or self.tab
	end
	self:sameLine()
	if self:button(T('ui.fechar')) then self:setVisible(false) end
end

function M:tabIndex()
	for i = 1, #M.TABS do
		if M.TABS[i].id == self.tab then return i end
	end
	return 1
end

function M:drawStatusBar()
	local app = self.app
	self:separator()
	if app.status and app:statusAlive(10) then
		local color = (app.statusLevel == 'error' and M.CORES.error)
			or (app.statusLevel == 'warn' and M.CORES.warn) or M.CORES.info
		self:textColored(color, app.status)
	else
		local dirty = app:changes()
		if #dirty > 0 then
			self:textColored(M.CORES.warn, T('hud.modificado') .. ': ' .. table.concat(dirty, ', '))
		else
			self:textDim(T('log.sem_alteracoes'))
		end
	end
	self:sameLine()
	self:textDim(string.format('| %s | %s', T('hud.sel'), app:hasSelection() and T('misc.sim') or T('misc.nao')))
end

function M:drawConfirm()
	local app = self.app
	local pending = app.pendingConfirm
	if not pending then return end
	local name = T('misc.confirmar') or 'confirmar'
	self:openPopup(name)
	if not self:beginPopupModal(name) then return end

	if pending.kind == 'save' then
		self:text(T('val.avisos_continuar'))
		self:text(T('val.resumo', pending.report.errors or 0, pending.report.warns or 0, pending.report.infos or 0, pending.report.fixable or 0))
	else
		self:text(T('sel.perg_excluir'))
		self:text(string.format('%s: %d', T('cr.links'), pending.links or 0))
	end
	self:separator()
	if self:button(T('misc.sim')) then
		app:confirmPending()
		self:closeCurrentPopup()
	end
	self:sameLine()
	if self:button(T('misc.nao')) or self:button(T('act.cancelar')) then
		app:cancelPending()
		self:closeCurrentPopup()
	end
	self:endPopup()
end

--------------------------------------------------------------------------------
-- Aba: editor
--------------------------------------------------------------------------------

local function nodeKindLabel(area, index)
	local kind = dat.nodeType(area, index)
	if kind == 'ped' then return T('editor.type_ped') end
	if kind == 'boat' then return T('editor.type_boat') end
	return T('editor.type_veh')
end

function M:draw_editor_tab()
	local app = self.app
	local ref = app:selectedRef()
	local area = app.project:area(app.project.selection.area)

	if not area then
		self:textDim(T('save.sem_area'))
		if self:button(T('nav.carregar')) then app:loadAroundPlayer() end
		return
	end

	local stats = app.project:stats(area.id) or {}
	self:text(T('ui.painel_lateral', app.version, area.id))
	self:text(T('nav.counts', stats.nodeCount or 0, stats.vehCount or 0, stats.pedCount or 0,
		stats.naviCount or 0, stats.linkCount or 0))
	if app.project:isDirty(area.id) then self:sameLine() self:textColored(M.CORES.warn, '(' .. T('hud.modificado') .. ')') end

	if self:collapsingHeader(T('ui.visualizar')) then
		self:checkboxBinding(T('cfg.ativo'), 'bool', 'cfg_ativo', app.settings.render.ativo, function(v) app.settings.render.ativo = v end)
		local changed, value = self:labeledSlider(T('cfg.distancia'), 'float', 'cfg_distancia', app.settings.render.distancia, 25, 1500, 1)
		if changed then app.settings.render.distancia = value end
		self:checkboxBinding(T('cfg.mostrar_nodes'), 'bool', 'cfg_mn', app.settings.render.mostrar_nodes ~= false, function(v) app.settings.render.mostrar_nodes = v end)
		self:checkboxBinding(T('cfg.mostrar_links'), 'bool', 'cfg_ml', app.settings.render.mostrar_links ~= false, function(v) app.settings.render.mostrar_links = v end)
		self:checkboxBinding(T('cfg.mostrar_navis'), 'bool', 'cfg_mn2', app.settings.render.mostrar_navis ~= false, function(v) app.settings.render.mostrar_navis = v end)
		self:checkboxBinding(T('cfg.mostrar_hud'), 'bool', 'cfg_mh', app.settings.render.mostrar_hud ~= false, function(v) app.settings.render.mostrar_hud = v end)
	end

	self:separator()
	if not ref then
		self:textColored(M.CORES.warn, T('sel.nenhum'))
		self:textDim(T('sel.tipo_no_editor'))
		self:drawWorldButtons()
		return
	end

	-- cabecalho da selecao
	local pos = ref.node or ref.navi
	local index = ref.index
	if ref.kind == 'navi' then
		self:text('%s  %s', T('navi.titulo'), T('navi.nome_gerado', index - 1))
	else
		self:text('%s  %s  (%s)', T('sel.node_sel'), T('nav.node_number', index - 1), nodeKindLabel(area, index))
	end
	if app:isLocked(ref.area, index) then
		self:sameLine()
		self:textColored(M.CORES.info, '[' .. T('cr.bloqueio') .. ']')
	end

	local dist = 0
	local px, py = app.render:playerPos()
	dist = geo.distance2d(px, py, pos.x, pos.y)
	self:textDim(string.format('%s: %.2f  |  %.1f, %.1f, %.1f', T('act.dist'), dist, pos.x, pos.y, pos.z or 0))

	-- posicao
	if self:collapsingHeader(T('editor.position'), self:ref('bool', 'chk_pos', true)) then
		self.posRefs = self.posRefs or {
			x = self:makeRef('float', pos.x), y = self:makeRef('float', pos.y), z = self:makeRef('float', pos.z or 0),
		}
		if not self.posSync or self.posSync.area ~= ref.area or self.posSync.index ~= index or self.posSync.kind ~= ref.kind then
			self.posSync = { area = ref.area, index = index, kind = ref.kind }
			self.posRefs.x:set(pos.x)
			self.posRefs.y:set(pos.y)
			self.posRefs.z:set(pos.z or 0)
		end
		self:pushItemWidth(120)
		local changed = false
		changed = self:inputFloat(T('editor.x'), self.posRefs.x, 0.25) or changed
		changed = self:inputFloat(T('editor.y'), self.posRefs.y, 0.25) or changed
		changed = self:inputFloat(T('editor.z'), self.posRefs.z, 0.25) or changed
		self:popItemWidth()
		if changed then
			app:setPosition(self.posRefs.x:get(), self.posRefs.y:get(), self.posRefs.z:get())
		end

		if self:button(T('act.nova_pos')) then app:setPosition(self.posRefs.x:get(), self.posRefs.y:get(), self.posRefs.z:get()) end
		self:sameLine()
		if self:button(T('act.no_jogador')) then app:atPlayer() end
		self:sameLine()
		if self:button(T('act.na_mira')) then app:atCrosshair() end

		-- deslocamento fino
		self:text(T('act.desloc'))
		local step = app.gizmo:stepFor(false, false)
		self:sameLine()
		if self:smallButton('-X') then app:nudgeAxis('x', -step) end
		self:sameLine()
		if self:smallButton('+X') then app:nudgeAxis('x', step) end
		self:sameLine()
		if self:smallButton('-Y') then app:nudgeAxis('y', -step) end
		self:sameLine()
		if self:smallButton('+Y') then app:nudgeAxis('y', step) end
		self:sameLine()
		if self:smallButton('-Z') then app:nudgeAxis('z', -step) end
		self:sameLine()
		if self:smallButton('+Z') then app:nudgeAxis('z', step) end
		self:sameLine()
		if self:smallButton(T('key.snap_solo')) then app:snapGround() end

		if self:button(T('sel.copiar_coord')) then
			local text = string.format('%.3f, %.3f, %.3f', pos.x, pos.y, pos.z or 0)
			if type(setClipboardText) == 'function' then pcall(setClipboardText, text) end
			app:setStatus(T('sel.coord_copiada', text), 'info')
		end
		self:sameLine()
		if self:button(T('sel.colar')) then
			local text
			if type(getClipboardText) == 'function' then
				local ok, value = pcall(getClipboardText)
				if ok then text = value end
			end
			local cx, cy, cz = tostring(text or ''):match('(-?%d+%.?%d*),%s*(-?%d+%.?%d*),%s*(-?%d+%.?%d*)')
			if cx then app:setPosition(tonumber(cx), tonumber(cy), tonumber(cz)) else app:setStatus(T('act.nada'), 'warn') end
		end
	end

	-- campos do node
	if ref.kind == 'node' and ref.node then
		if self:collapsingHeader(T('editor.flags'), self:ref('bool', 'chk_flags', true)) then
			self:drawNodeFlags(ref, area)
		end
		if self:collapsingHeader(T('cr.links'), self:ref('bool', 'chk_links', true)) then
			self:drawLinks(ref, area)
		end
	elseif ref.kind == 'navi' and ref.navi then
		if self:collapsingHeader(T('editor.navi_flags'), self:ref('bool', 'chk_naviflags', true)) then
			self:drawNaviFlags(ref)
		end
	end

	self:separator()
	self:drawWorldButtons()
end

function M:drawNodeFlags(ref, area)
	local app = self.app
	local node = ref.node
	local flags = node.flags or 0
	local linkCount = dat.getNodeFlag(flags, 'LINK_COUNT')
	self:text(T('editor.bits') .. ': 0x%08X   %s: %d', flags, T('cr.links'), linkCount)

	-- estrada
	self:textDim(T('flag.group_road'))
	local highway = dat.getNodeFlag(flags, 'HIGHWAY') == 1
	local normal = dat.getNodeFlag(flags, 'NOT_HIGHWAY') == 1
	if self:checkbox(T('flag.highway'), self:syncRef('bool', 'flag_highway', highway)) then
		app:setNodeFlag('HIGHWAY', not highway and 1 or 0)
		if not highway then app:setNodeFlag('NOT_HIGHWAY', 0) end
		return
	end
	if self:checkbox(T('flag.normal_road'), self:syncRef('bool', 'flag_normal', normal)) then
		app:setNodeFlag('NOT_HIGHWAY', not normal and 1 or 0)
		if not normal then app:setNodeFlag('HIGHWAY', 0) end
		return
	end
	self:checkboxBinding(T('flag.boat'), 'bool', 'flag_boat', dat.getNodeFlag(flags, 'BOAT') == 1, function(v) app:setNodeFlag('BOAT', v and 1 or 0) end)
	self:checkboxBinding(T('flag.emergency'), 'bool', 'flag_emergency', dat.getNodeFlag(flags, 'EMERGENCY') == 1, function(v) app:setNodeFlag('EMERGENCY', v and 1 or 0) end)
	self:checkboxBinding(T('flag.parking'), 'bool', 'flag_parking', dat.getNodeFlag(flags, 'PARKING') == 1, function(v) app:setNodeFlag('PARKING', v and 1 or 0) end)

	-- trafego
	self:textDim(T('flag.group_traffic'))
	local level = dat.getNodeFlag(flags, 'TRAFFIC_LEVEL')
	local labels = {}
	for i = 1, #TRAFFIC_LEVELS do labels[i] = T(TRAFFIC_LEVELS[i]) end
	local changed, indexT = self:combo(T('flag.traffic_level'), self:syncRef('int', 'flag_level', level), labels)
	if changed then app:setNodeFlag('TRAFFIC_LEVEL', (indexT or 1) - 1) return end

	-- spawn
	self:textDim(T('flag.group_spawn'))
	local spawn = dat.getNodeFlag(flags, 'SPAWN_PROBABILITY')
	local spawnChanged, spawnValue = self:labeledSlider(T('flag.spawn_prob'), 'int', 'flag_spawn', spawn, 0, 15, 1)
	if spawnChanged then app:setNodeFlag('SPAWN_PROBABILITY', spawnValue) return end
	if spawn == 0 then self:textColored(M.CORES.warn, T('flag.spawn_prob_never')) end

	-- largura e flood
	self:textDim(T('flag.group_width'))
	local widthChanged, widthValue = self:labeledSlider(T('editor.path_width'), 'int', 'flag_width', node.pathWidth or 0, 0, 255, 1)
	if widthChanged then app:setNodeField('pathWidth', widthValue) return end
	local floodChanged, floodValue = self:labeledSlider(T('flag.flood'), 'int', 'flag_flood', node.floodFill or 0, 0, 255, 1)
	if floodChanged then app:setNodeField('floodFill', floodValue) return end

	-- bloqueios e bits altos
	self:textDim(T('flag.group_misc'))
	self:checkboxBinding(T('flag.ped_crossing'), 'bool', 'flag_roadblock', dat.getNodeFlag(flags, 'ROAD_BLOCK') == 1, function(v) app:setNodeFlag('ROAD_BLOCK', v and 1 or 0) end)
	if math.floor(flags / 0x1000000) > 0 then
		self:textColored(M.CORES.warn, T('val.flags_high_bits'))
		if self:smallButton(T('val.fix_clear_high_bits')) then
			app.project:setNodeField(ref.area, ref.index, 'flags', flags % 0x1000000)
			app:changed(ref.area)
		end
	end
end

function M:drawNaviFlags(ref)
	local app = self.app
	local navi = ref.navi
	local flags = navi.flags or 0
	self:text(T('editor.bits') .. ': 0x%08X', flags)

	local widthChanged, widthValue = self:labeledSlider(T('navi.largura'), 'int', 'nv_width', dat.getNaviFlag(flags, 'WIDTH'), 0, 255, 1)
	if widthChanged then app:setNaviField('width', widthValue) return end
	local leftChanged, leftValue = self:labeledSlider(T('navi.faixas_esq'), 'int', 'nv_left', dat.getNaviFlag(flags, 'LEFT_LANES'), 0, 7, 1)
	if leftChanged then app:setNaviField('leftLanes', leftValue) return end
	local rightChanged, rightValue = self:labeledSlider(T('navi.faixas_dir'), 'int', 'nv_right', dat.getNaviFlag(flags, 'RIGHT_LANES'), 0, 7, 1)
	if rightChanged then app:setNaviField('rightLanes', rightValue) return end

	local labels = {}
	for i = 1, #TRAFFIC_LIGHTS do labels[i] = T(TRAFFIC_LIGHTS[i]) end
	local changed, index = self:combo(T('navi.semaforo'), self:syncRef('int', 'nv_light', dat.getNaviFlag(flags, 'TRAFFIC_LIGHT')), labels)
	if changed then app:setNaviField('trafficLight', (index or 1) - 1) return end

	self:checkboxBinding(T('navi.luz_direcao'), 'bool', 'nv_lightdir', dat.getNaviFlag(flags, 'LIGHT_DIRECTION') == 1,
		function(v) app:setNaviField('lightDirection', v and 1 or 0) end)
	self:checkboxBinding(T('navi.trem'), 'bool', 'nv_train', dat.getNaviFlag(flags, 'TRAIN_CROSSING') == 1,
		function(v) app:setNaviField('trainCrossing', v and 1 or 0) end)

	-- direcao
	local dirX, dirY = navi.dirX or 0, navi.dirY or 0
	local len = math.sqrt(dirX * dirX + dirY * dirY)
	local heading = math.deg(math.atan2(dirX, dirY))
	self:text('%s: %.1f deg  (%.0f, %.0f, |v| = %.0f)', T('navi.direcao'), heading, dirX, dirY, len)
	local angleStep = app.settings.edicao.angulo_navi_passo or 15
	if self:smallButton('- ' .. angleStep) then app:setNaviHeading(heading - angleStep) end
	self:sameLine()
	if self:smallButton('+ ' .. angleStep) then app:setNaviHeading(heading + angleStep) end
	self:sameLine()
	if self:smallButton(T('navi.angular')) then
		-- aponta para o node alvo (se houver)
		local targetArea = app.project:area(navi.areaID or ref.area)
		local target = targetArea and targetArea.nodes[(navi.nodeID or 0) + 1]
		if target then app:setNaviHeading(math.deg(math.atan2(target.x - navi.x, target.y - navi.y))) end
	end

	if navi.nodeID == 0xFFFF or navi.nodeID == nil then
		self:textColored(M.CORES.warn, T('navi.nao_associado'))
	else
		self:text(T('navi.associado', navi.nodeID))
	end
	self:checkboxBinding(T('cr.bloqueio'), 'bool', 'navi_lock', app:isLocked(ref.area, ref.index),
		function(v) app:setLocked(ref.area, ref.index, v) end)
end

function M:drawLinks(ref, area)
	local app = self.app
	local node = ref.node
	if not node.links or #node.links == 0 then
		self:textDim(T('editor.sem_links'))
	else
		for i = 1, #node.links do
			local link = node.links[i]
			local label = string.format('%s %d: %s %d -> %d  (%s %d, %s %.1f)',
				T('nav.link'), i, T('sel.area'), ref.area, link.node, T('sel.area'), link.area, T('act.dist'), link.length or 0)
			self:text(label)
			self:sameLine()
			if self:smallButton(T('act.ir') .. '##' .. i) then app:goToLinkTarget(i) end
			self:sameLine()
			if self:smallButton(T('cr.remover_link') .. '##' .. i) then app:removeLink(i) return end
			if dat.naviLinkIsSet(link) then
				self:textDim(string.format('    %s %d / %s %d', T('nav.navi'), link.naviID, T('sel.area'), link.naviArea or 0))
			elseif node and dat.nodeType(area, ref.index) ~= 'ped' then
				self:sameLine()
				if self:smallButton(T('navi.criar') .. '##' .. i) then app:addNaviOnLink(i) return end
			end
		end
	end

	self:separator()
	-- origem/destino
	if app.linkSource then
		self:text(string.format('%s: %s %d / %s %d', T('cr.link_origem'), T('sel.area'),
			app.linkSource.area, T('nav.node'), app.linkSource.index - 1))
	else
		self:textDim(T('cr.nenhum_link_sel'))
	end
	if self:button(T('cr.marcar_origem')) then app:markLinkSource() end
	self:sameLine()
	if self:button(T('cr.criar')) then app:createLink() end
	self:sameLine()
	if self:button(T('cr.remover_link')) then app:clearLinks() end
	local modeRef = self:syncRef('int', 'link_mode', app.linkMode == 'unico' and 1 or 0)
	local changed, index = self:combo(T('cr.link'), modeRef, { T('cr.link_bidirecional'), T('cr.link_sentido_unico') })
	if changed then app.linkMode = (index == 2) and 'unico' or 'auto' end
end

function M:drawWorldButtons()
	local app = self.app
	self:separator()
	if self:button(T('act.ir')) then app:teleportToSelected() end
	self:sameLine()
	if self:button(T('sel.desfazer')) then app:undo() end
	self:sameLine()
	if self:button(T('sel.refazer')) then app:redo() end
	self:sameLine()
	if self:button(T('cr.bloqueio')) then
		local ref = app:selectedRef()
		if ref then app:setLocked(ref.area, ref.index, not app:isLocked(ref.area, ref.index)) end
	end
	self:sameLine()
	if self:button(T('act.apagar')) then app:deleteSelected(false) end
end

--------------------------------------------------------------------------------
-- Aba: navi nodes
--------------------------------------------------------------------------------

function M:draw_navis_tab()
	local app = self.app
	local area = app.project:area(app.project.selection.area)
	if not area then
		self:textDim(T('save.sem_area'))
		return
	end
	self:text(T('navi.titulo') .. '  (' .. T('editor.area_info', area.id, 750, 750) .. ')')
	self:text(T('nav.counts', #area.nodes, area.vehCount, #area.nodes - area.vehCount, #area.navis, 0))

	local total = #area.navis
	if total == 0 then
		self:textDim(T('navi.nenhum'))
	else
		local first, last = self:paginate('navis', total, 40)
		for i = first, last do
			local navi = area.navis[i]
			local selected = app.project.selection.navi == i and app.project.selection.area == area.id
			local label = string.format('%s  %s %d  %s %.1f, %.1f  %s', T('navi.nome_gerado', i - 1),
				T('nav.link'), navi.nodeID or -1, T('ui.at'), navi.x or 0, navi.y or 0,
				selected and ('<- ' .. T('hud.sel')) or '')
			if self:selectable(label, selected) then app:selectNavi(area.id, i) end
			if self:smallButton(T('act.ir') .. '##navi' .. i) then
				app:selectNavi(area.id, i)
				app:teleportToSelected()
			end
			self:sameLine()
			if self:smallButton(T('navi.apagar') .. '##navi' .. i) then
				app.project:removeNavi(area.id, i)
				app:changed(area.id)
				return
			end
		end
	end

	self:separator()
	self:textDim(T('navi.criar_desc'))
	if self:button(T('navi.gerar')) then
		local created, skipped = app:generateMissingNavis(area.id)
		app:setStatus(T('navi.gerado', created), created > 0 and 'info' or 'warn')
	end
	self:sameLine()
	if self:button(T('navi.remover_inuteis')) then
		local removed = app:removeOrphanNavis(area.id)
		app:setStatus(T('navi.removidos', removed), removed > 0 and 'info' or 'warn')
	end
	self:textDim(T('navi.todos_links'))
	self:textDim(T('navi.sem_link_ped'))
end

--------------------------------------------------------------------------------
-- Aba: criar / remover
--------------------------------------------------------------------------------

function M:draw_criar_tab()
	local app = self.app

	self:text(T('cr.novo_node'))
	local kinds = {
		{ id = 'veh', label = 'cr.novo_veh' },
		{ id = 'ped', label = 'cr.novo_ped' },
		{ id = 'boat', label = 'cr.novo_boat' },
		{ id = 'navi', label = 'cr.novo_navi' },
	}
	for i = 1, #kinds do
		local selected = app.newNodeKind == kinds[i].id
		if self:selectable((selected and '(*) ' or '( ) ') .. T(kinds[i].label), selected) then
			app.newNodeKind = kinds[i].id
		end
	end

	self:separator()
	self:text(T('cr.node_pos'))
	if self:button(T('cr.criar_na_mira')) then
		local ok, indexOrErr = app:createNode(app.newNodeKind, app:createPoint())
		if not ok then app:setStatus(tostring(indexOrErr), 'warn') end
	end
	self:sameLine()
	if self:button(T('cr.criar_no_player')) then
		local px, py, pz = nil, nil, nil
		if type(getCharCoordinates) == 'function' then
			local ok, x, y, z = pcall(getCharCoordinates, PLAYER_PED or 0)
			if ok then px, py, pz = x, y, z end
		end
		if px then
			local areaId = geo.areaFromCoords(px, py)
			if app.project:area(areaId) then
				local index, err = app.project:addNode(areaId, app.newNodeKind == 'boat' and 'boat' or app.newNodeKind, px, py, pz or 0)
				if index then app:changed(areaId) app:selectNode(areaId, index) else app:setStatus(err, 'warn') end
			else
				app:createNode(app.newNodeKind, px, py, pz)
			end
		else
			app:setStatus(T('act.falhou'), 'warn')
		end
	end

	self:separator()
	self:text(T('cr.links'))
	local modeRef = self:syncRef('int', 'criar_auto', app.linkMode == 'auto' and 0 or 1)
	local changed, index = self:combo(T('cr.link'), modeRef, { T('cr.link_auto'), T('cr.link_manual') })
	if changed then app.linkMode = (index == 2) and 'manual' or 'auto' end
	self:checkboxBinding(T('cfg.espelhar_links'), 'bool', 'cfg_mirror', app.settings.edicao.espelhar_links ~= false,
		function(v) app.settings.edicao.espelhar_links = v end)
	self:checkboxBinding(T('cfg.criar_navi_automatico'), 'bool', 'cfg_autonavi', app.settings.edicao.criar_navi_automatico == true,
		function(v) app.settings.edicao.criar_navi_automatico = v end)

	self:separator()
	self:text(T('cr.bloqueio'))
	self:textDim(T('cr.bloqueio_desc'))
	if self:button(T('cr.bloqueando_node')) then
		local ref = app:selectedRef()
		if ref then app:setLocked(ref.area, ref.index, true) end
	end
	self:sameLine()
	if self:button(T('cr.remover_bloqueio')) then
		local ref = app:selectedRef()
		if ref then app:setLocked(ref.area, ref.index, false) end
	end
	self:sameLine()
	if self:button(T('act.limpar')) then app.locked = {} end

	local lockedCount = 0
	for _ in pairs(app.locked) do lockedCount = lockedCount + 1 end
	self:text('%s: %d', T('cr.bloqueio_manual'), lockedCount)

	self:separator()
	self:text(T('cr.remover_node'))
	self:textDim(T('cr.deletar_desc'))
	if self:button(T('act.apagar')) then app:deleteSelected(false) end
	self:sameLine()
	if self:button(T('sel.descartar')) then app:unloadAll(true) end
end

--------------------------------------------------------------------------------
-- Aba: areas
--------------------------------------------------------------------------------

function M:draw_area_tab()
	local app = self.app
	local loaded = app.project:loadedAreas()
	self:text(T('nav.areas_carregadas') .. ' (%d)', #loaded)
	if self:button(T('nav.carregar')) then app:loadAroundPlayer() end
	self:sameLine()
	if self:button(T('act.recarregar')) then
		local ok, err = app:reload()
		if not ok then app:setStatus(err, 'warn') end
	end
	self:sameLine()
	if self:button(T('sel.descartar_tudo')) then app:unloadAll(true) end

	self:separator()
	for i = 1, #loaded do
		local id = loaded[i]
		local area = app.project:area(id)
		local stats = app.project:stats(id) or {}
		local info = app.sources:info(id) or {}
		local title = string.format('%s %d  -  %s: %d  %s: %d  navi: %d', T('sel.area'), id,
			T('nav.node'), stats.nodeCount or 0, T('nav.link'), stats.linkCount or 0, stats.naviCount or 0)
		if app.project:isDirty(id) then title = title .. '  (' .. T('hud.modificado') .. ')' end
		if self:collapsingHeader(title) then
			self:text('%s: %s', T('list.origem'), tostring(info.source or area.source or '?'))
			if info.path then self:text('%s', tostring(info.path)) end
			if info.conflict then self:textColored(M.CORES.warn, T('src.conflict', id, #(info.providers or {}))) end
			if info.source == 'img' then self:text(T('src.fallback_original')) end
			self:text(T('src.will_write', tostring(app.sources:targetPath(id))))
			if self:button(T('act.ir') .. '##area' .. id) then
				local cx, cy = geo.areaCenter(id)
				app:teleportTo(cx, cy, 20)
			end
			self:sameLine()
			if self:button(T('act.salvar') .. '##area' .. id) then app:saveArea(id, {}) end
			self:sameLine()
			if self:button(T('sel.descartar') .. '##area' .. id) then app:unloadArea(id, false) end
			self:sameLine()
			if self:button(T('sel.exportar') .. '##area' .. id) then
				local bytes = dat.serialize(area)
				if bytes then
					local ok = fs.writeAll(app.sources:exportPath(id), bytes)
					app:setStatus(ok and T('sel.exportado', app.sources:exportPath(id)) or T('act.falhou'), ok and 'info' or 'error')
				end
			end
		end
	end

	self:separator()
	self:text(T('ui.world') .. ' (0-63)')
	local total = M.AREA_COUNT or 64
	local first, last = self:paginate('areas', total, 16)
	for id = first - 1, last - 1 do
		local info = app.sources:info(id) or {}
		local area = app.project:area(id)
		local label = string.format('%s %d  %s  %s', T('sel.area'), id, tostring(info.source or '-'),
			area and '' or T('ui.ausentes'))
		self:text(label)
		self:sameLine()
		if area then
			if self:smallButton(T('sel.descartar') .. '##a' .. id) then app:unloadArea(id, true) end
		elseif info.exists then
			if self:smallButton(T('nav.carregar') .. '##a' .. id) then app:loadArea(id) end
		else
			self:textDim('-')
		end
	end
end

--------------------------------------------------------------------------------
-- Aba: salvar
--------------------------------------------------------------------------------

function M:draw_salvar_tab()
	local app = self.app
	self:text(T('save.titulo'))
	self:textDim(T('ui.s_aplica'))

	local diffs = app:diffAll()
	local changed = {}
	local ids = {}
	for id, diff in pairs(diffs) do
		ids[#ids + 1] = id
		if diff and not diff.identical then changed[#changed + 1] = id end
	end
	table.sort(ids)

	if #changed == 0 then
		self:textDim(T('save.nenhum_diff'))
	else
		for i = 1, #changed do
			local id = changed[i]
			local diff = diffs[id]
			self:text(T('save.alterado') .. ' nodes%d.dat', id)
			self:sameLine()
			self:textDim(string.format('%s: %d -> %d   navi: %d -> %d   %s: %d -> %d   +%d -%d   %s: %d',
				T('nav.node'), diff.nodesBefore or 0, diff.nodesAfter or 0,
				diff.navisBefore or 0, diff.navisAfter or 0,
				T('nav.link'), diff.linksBefore or 0, diff.linksAfter or 0,
				diff.added or 0, diff.removed or 0,
				T('act.desloc'), diff.moved or 0))
		end
	end

	self:separator()
	local report = app.report
	if report then
		local color = (report.errors > 0 and M.CORES.error) or (report.warns > 0 and M.CORES.warn) or M.CORES.good
		self:textColored(color, T('val.resumo', report.errors or 0, report.warns or 0, report.infos or 0, report.fixable or 0))
		if report.errors > 0 then
			self:textColored(M.CORES.error, T('val.erros_impedem', report.errors))
		end
	else
		self:textDim(T('act.nada'))
	end
	if self:button(T('val.revalidar')) then app:validate({}) end
	self:sameLine()
	if self:button(T('val.corrigir_tudo')) then app:applyFixes('1') end
	self:sameLine()
	if self:button(T('val.aba')) then self.tab = 'log' end

	self:separator()
	if self:button(T('ui.salvar_alteracoes')) then app:save({}) end
	self:sameLine()
	if self:button(T('val.salvar_mesmo')) then app:save({ force = true, confirmed = true }) end
	self:sameLine()
	if self:button(T('cfg.limpar_cache_modloader')) then app:clearModloaderCache() end
	self:sameLine()
	if self:button(T('ui.config')) then self.tab = 'config' end

	local save = app.lastSave
	if save then
		self:separator()
		if save.ok then
			self:textColored(M.CORES.good, T('save.salvo', tostring(save.written and save.written[1] or ''), #(save.written or {})))
		else
			for i = 1, #(save.errors or {}) do self:textColored(M.CORES.error, save.errors[i]) end
		end
		if save.written then
			for i = 1, #save.written do self:textDim(save.written[i]) end
		end
	end
	self:textDim(T('cfg.reiniciar_necessario'))
end

--------------------------------------------------------------------------------
-- Aba: camera / mapa
--------------------------------------------------------------------------------

function M:draw_camera_tab()
	local app = self.app
	local map = app.settings.map

	self:text(T('ui.world'))
	self:textDim(T('ui.importar'))
	if self:button(T('ui.importar')) then
		local x, y = app.render:playerPos()
		map.centro = { x = x, y = y }
		app:setStatus(string.format('%s: %.0f, %.0f', T('ui.de'), x, y), 'info')
	end
	self:checkboxBinding(T('ui.hud'), 'bool', 'map_ativo', map.ativo == true, function(v) map.ativo = v end)
	local changed, value = self:labeledSlider(T('hud.tamanho'), 'int', 'map_size', map.tamanho or 320, 120, 700, 1)
	if changed then map.tamanho = value end
	local changedR, radius = self:labeledSlider(T('cfg.distancia'), 'float', 'map_radius', map.raio or 200, 50, 3000, 1)
	if changedR then map.raio = radius end
	local modes = { T('ui.w_standard'), T('ui.w_mta') }
	local changedMode, index = self:combo(T('ui.mundo_atual'), self:syncRef('int', 'map_mode', map.modo == 'mta' and 1 or 0), modes)
	if changedMode then map.modo = (index == 2) and 'mta' or 'standard' end
	self:checkboxBinding(T('ui.de') .. ' (' .. T('hud.legenda') .. ')', 'bool', 'map_lado', map.lado == 'esquerda',
		function(v) map.lado = v and 'esquerda' or 'direita' end)

	self:separator()
	self:text(T('ui.visualizar'))
	self:checkboxBinding(T('cfg.mostrar_nodes'), 'bool', 'cam_mn', app.settings.render.mostrar_nodes ~= false, function(v) app.settings.render.mostrar_nodes = v end)
	self:checkboxBinding(T('cfg.mostrar_peds'), 'bool', 'cam_mp', app.settings.render.mostrar_peds ~= false, function(v) app.settings.render.mostrar_peds = v end)
	self:checkboxBinding(T('cfg.mostrar_barcos'), 'bool', 'cam_mb', app.settings.render.mostrar_barcos ~= false, function(v) app.settings.render.mostrar_barcos = v end)
	self:checkboxBinding(T('cfg.mostrar_navis'), 'bool', 'cam_mnavi', app.settings.render.mostrar_navis ~= false, function(v) app.settings.render.mostrar_navis = v end)
	local hChanged, height = self:labeledSlider(T('cfg.altura_nodes'), 'float', 'cam_altura', app.settings.render.altura_nodes or 1.0, 0, 5, 0.1)
	if hChanged then app.settings.render.altura_nodes = height end
	local sChanged, size = self:labeledSlider(T('cfg.tamanho_node'), 'float', 'cam_tam', app.settings.render.tamanho_node or 6.0, 2, 24, 0.5)
	if sChanged then app.settings.render.tamanho_node = size end

	self:separator()
	self:text(T('sel.carregar_area'))
	if self:button(T('sel.carregar_vizinhas')) then app:loadAroundPlayer() end
	self:sameLine()
	if self:button(T('act.ir')) then app:teleportToSelected() end
	local x, y = app.render:playerPos()
	self:textDim(string.format('%s: %.1f, %.1f  |  %s %d', T('hud.sel'), x, y, T('sel.area'), geo.areaFromCoords(x, y)))
end

--------------------------------------------------------------------------------
-- Aba: configuracoes
--------------------------------------------------------------------------------

local function keyLabel(name)
	local i18nKey = 'key.' .. name
	local label = T(i18nKey)
	if label == '[' .. i18nKey .. ']' then label = name end
	return label
end

function M:draw_config_tab()
	local app = self.app
	local settings = app.settings

	if self:collapsingHeader(T('cfg.geral'), self:ref('bool', 'chk_cfg_geral', true)) then
		local langs = { 'Portugues (BR)', 'English' }
		local langRef = self:syncRef('int', 'cfg_lang', (settings.geral.idioma == 'en') and 1 or 0)
		local changed, index = self:combo(T('cfg.idioma'), langRef, langs)
		if changed then
			local code = (index == 2) and 'en' or 'pt'
			settings.geral.idioma = code
			i18n.setLang(code)
			app:setStatus(T('misc.idioma_alterado'), 'info')
		end
		self:checkboxBinding(T('cfg.carregar_vizinhas'), 'bool', 'cfg_viz', settings.geral.carregar_vizinhas ~= false,
			function(v) settings.geral.carregar_vizinhas = v end)
		self:checkboxBinding(T('cfg.debug'), 'bool', 'cfg_debug', settings.geral.debug == true,
			function(v) settings.geral.debug = v log.debugEnabled = v end)
		self:text('%s: %s', T('cfg.areas_extras'), tostring(settings.geral.areas_extras or ''))
	end

	if self:collapsingHeader(T('cfg.render'), self:ref('bool', 'chk_cfg_render', false)) then
		self:checkboxBinding(T('cfg.ativo'), 'bool', 'cfg_ativo2', settings.render.ativo ~= false, function(v) settings.render.ativo = v end)
		local dChanged, distance = self:labeledSlider(T('cfg.distancia'), 'float', 'cfg_dist2', settings.render.distancia, 25, 1500, 1)
		if dChanged then settings.render.distancia = distance end
		local lChanged, lines = self:labeledSlider(T('cfg.max_linhas'), 'int', 'cfg_linhas', settings.render.max_linhas, 50, 4000, 10)
		if lChanged then settings.render.max_linhas = lines end
		local aChanged, altura = self:labeledSlider(T('cfg.altura_nodes'), 'float', 'cfg_altura', settings.render.altura_nodes, 0, 5, 0.1)
		if aChanged then settings.render.altura_nodes = altura end
		local tChanged, tamanho = self:labeledSlider(T('cfg.tamanho_node'), 'float', 'cfg_tamanho', settings.render.tamanho_node, 2, 24, 0.5)
		if tChanged then settings.render.tamanho_node = tamanho end
		self:textDim(T('cfg.cores'))
		local function colorBinding(label, key, field)
			local current = settings.render[field] or '#FFFFFF'
			self:text('%s: %s', label, tostring(current))
		end
		colorBinding(T('cfg.cor_veh'), 'cfg_cor_veh', 'cor_veh')
		colorBinding(T('cfg.cor_ped'), 'cfg_cor_ped', 'cor_ped')
		colorBinding(T('cfg.cor_boat'), 'cfg_cor_boat', 'cor_boat')
		colorBinding(T('cfg.cor_navi'), 'cfg_cor_navi', 'cor_navi')
		colorBinding(T('cfg.cor_selecionado'), 'cfg_cor_sel', 'cor_selecionado')
		colorBinding(T('cfg.cor_link'), 'cfg_cor_link', 'cor_link')
		colorBinding(T('cfg.cor_hover'), 'cfg_cor_hover', 'cor_hover')
	end

	if self:collapsingHeader(T('cfg.edicao'), self:ref('bool', 'chk_cfg_edicao', false)) then
		self:checkboxBinding(T('cfg.espelhar_links'), 'bool', 'cfg_esp', settings.edicao.espelhar_links ~= false,
			function(v) settings.edicao.espelhar_links = v end)
		self:checkboxBinding(T('cfg.recalcular_comprimentos'), 'bool', 'cfg_recalc', settings.edicao.recalcular_comprimentos ~= false,
			function(v) settings.edicao.recalcular_comprimentos = v end)
		self:checkboxBinding(T('cfg.travar_z'), 'bool', 'cfg_z', settings.edicao.travar_z == true,
			function(v) settings.edicao.travar_z = v end)
		local fChanged, fine = self:labeledSlider(T('cfg.passo_fino'), 'float', 'cfg_fino', settings.edicao.passo_fino, 0.01, 1, 0.01)
		if fChanged then settings.edicao.passo_fino = fine end
		local nChanged, normal = self:labeledSlider(T('cfg.passo_normal'), 'float', 'cfg_normal', settings.edicao.passo_normal, 0.1, 10, 0.1)
		if nChanged then settings.edicao.passo_normal = normal end
		local cChanged, coarse = self:labeledSlider(T('cfg.passo_grosso'), 'float', 'cfg_grosso', settings.edicao.passo_grosso, 1, 50, 1)
		if cChanged then settings.edicao.passo_grosso = coarse end
	end

	if self:collapsingHeader(T('cfg.salvar'), self:ref('bool', 'chk_cfg_salvar', false)) then
		self:text('%s: %s', T('cfg.pasta_img'), tostring(settings.salvar.pasta_img))
		self:text('%s: %s', T('cfg.pasta_export'), tostring(settings.salvar.pasta_export))
		self:text('%s: %s', T('cfg.pasta_backup'), tostring(settings.salvar.pasta_backup))
		self:checkboxBinding(T('cfg.escrever_img'), 'bool', 'cfg_wimg', settings.salvar.escrever_img ~= false,
			function(v) settings.salvar.escrever_img = v app.sources.writeImgFolder = v end)
		self:checkboxBinding(T('cfg.escrever_export'), 'bool', 'cfg_wexp', settings.salvar.escrever_export ~= false,
			function(v) settings.salvar.escrever_export = v app.sources.writeExport = v end)
		self:checkboxBinding(T('cfg.backup'), 'bool', 'cfg_backup', settings.salvar.backup ~= false,
			function(v) settings.salvar.backup = v app.sources.backup = v end)
		self:checkboxBinding(T('cfg.limpar_cache_modloader'), 'bool', 'cfg_cache', settings.salvar.limpar_cache_modloader ~= false,
			function(v) settings.salvar.limpar_cache_modloader = v end)
		self:checkboxBinding(T('cfg.tambem_gta3img_direto'), 'bool', 'cfg_direct', settings.salvar.tambem_gta3img_direto == true,
			function(v) settings.salvar.tambem_gta3img_direto = v app.sources.directImg = v end)
		self:textColored(M.CORES.warn, T('save.aviso_gtadir'))
		self:textDim(T('save.aviso_img'))
	end

	if self:collapsingHeader(T('cfg.teclas'), self:ref('bool', 'chk_cfg_teclas', false)) then
		for name, value in pairs(settings.teclas) do
			self:text('%s: %s  (%s)', keyLabel(name), tostring(value), name)
		end
		self:textDim(T('key.tecla'))
	end

	self:separator()
	if self:button(T('cfg.salvar_config')) then
		config.save(settings)
		app:setStatus(T('cfg.config_salva'), 'info')
	end
	self:sameLine()
	if self:button(T('cfg.restaurar_padrao')) then
		for section, values in pairs(config.defaults) do
			settings[section] = util.deepcopy(values)
		end
		config.save(settings)
		app:applySettings()
		app:setStatus(T('cfg.config_salva'), 'info')
	end
	self:sameLine()
	if self:button(T('cfg.abrir_pasta')) then
		fs.shell('explorer "' .. tostring(app.sources.modloaderDir) .. '"')
	end
	if self.bindingName then self:textDim('ImGui: ' .. tostring(self.bindingName) .. ' (' .. tostring(self.hook) .. ')') end
end

--------------------------------------------------------------------------------
-- Aba: log / historico
--------------------------------------------------------------------------------

function M:draw_log_tab()
	local app = self.app
	self:text(T('log.titulo'))
	if self:button(T('log.limpar')) then log.clear() end
	self:sameLine()
	if self:button(T('log.copiar')) then
		local lines = log.getLines()
		if type(setClipboardText) == 'function' then pcall(setClipboardText, table.concat(lines, '\n')) end
	end
	self:sameLine()
	if self:button(T('sel.desfazer')) then app:undo() end
	self:sameLine()
	if self:button(T('sel.refazer')) then app:redo() end
	if app.project:canUndo() then self:text('%s: %s', T('log.alteracoes'), tostring(app.project:undoLabel())) end

	self:separator()
	local lines = log.getLines()
	self:text(T('log.aba_erros') .. ' (' .. #lines .. ')')
	self:beginChild('log_list', 0, 260)
	local start = math.max(1, #lines - 300)
	for i = start, #lines do
		local line = tostring(lines[i])
		if line:find('ERROR') then self:textColored(M.CORES.error, line)
		elseif line:find('WARN') then self:textColored(M.CORES.warn, line)
		else self:textDim(line) end
	end
	if #lines == 0 then self:textDim(T('log.vazio')) end
	self:endChild()

	-- alteracoes pendentes
	self:separator()
	self:text(T('log.aba_alteracoes'))
	local dirty = app:changes()
	if #dirty == 0 then
		self:textDim(T('log.sem_alteracoes'))
	else
		local diffs = app:diffAll()
		for i = 1, #dirty do
			local diff = diffs[dirty[i]]
			if diff then
				self:text(string.format('nodes%d.dat: %s +%d -%d  %s %d  %s %d',
					dirty[i], T('nav.node'), diff.added or 0, diff.removed or 0,
					T('nav.navi'), (diff.navisAfter or 0) - (diff.navisBefore or 0),
					T('act.desloc'), diff.moved or 0))
			end
		end
	end
	self:textDim(T('log.limite', app.project.MAX_UNDO))
	self:textDim(T('log.memoria', #app.project:loadedAreas(), app.project:totalNodes()))
end

--------------------------------------------------------------------------------
-- Aba: ajuda
--------------------------------------------------------------------------------

function M:draw_ajuda_tab()
	local app = self.app
	local info = app:runtimeInfo()
	self:text(T('ui.menu_principal'))
	self:text('%s: %s   %s: %s', T('misc.versao'), tostring(info.version), T('ui.aba_log'), _VERSION)
	self:textDim(string.format('%s: %s  |  moonloader: %s  |  gta: %s', T('ui.painel'), tostring(info.gameDir),
		tostring(info.moonloader), tostring(info.game)))
	self:textDim(string.format('modloader: %s   gta3.img: %s', tostring(info.modloader), tostring(info.gta3img)))
	self:textDim(string.format('%s: %s', T('save.export_folder'), tostring(info.exportFolder)))

	self:separator()
	self:text(T('cfg.teclas'))
	for name, value in pairs(app.settings.teclas) do
		self:text('  %s - %s (%s)', tostring(value), keyLabel(name), name)
	end

	self:separator()
	self:text(T('ui.guia_edicao'))
	self:text(T('ui.nodes_hide'))
	self:text(T('sel.tipo_no_editor'))
	self:text(T('sel.ped_apos_veh'))
	self:text(T('val.correcao_manual'))
	self:text(T('val.correcao_manual_nota'))
	self:text(T('val.file_note', 0, tostring(info.gta3img and 'models/gta3.img' or '?')))
	self:separator()
	self:textDim(T('misc.desenvolvido_por'))
	self:separator()
	if self:button(T('act.pausar')) then self:setVisible(false) end
end

return M
