--[[
	Visual Path Editor - vpe.render
	Desenho dos nodes/links/navis na tela e o HUD.

	Todas as chamadas de render do MoonLoader valem por UM quadro, entao
	M:draw() precisa ser chamado a cada quadro (normalmente dentro de onDrawFrame
	ou no loop do script).

	O modulo nao conhece o MoonLoader diretamente: usa as funcoes globais, com
	guardas, para poder ser testado fora do jogo.
]]

local util = require 'vpe.util'
local dat = require 'vpe.dat'
local geo = require 'vpe.geometry'
local model = require 'vpe.model'
local i18n = require 'vpe.i18n'

local M = {}

local T = i18n.t

M.DEFAULT_COLORS = {
	veh = 0xFFFFFFFF,
	ped = 0xFF26E04D,
	boat = 0xFF3DA5FF,
	navi = 0xFF1BE4E4,
	selected = 0xFFFFD200,
	hover = 0xFFFF5A5A,
	link = 0xFF8C8C8C,
	linkPed = 0xFF1E7A2E,
	linkSelected = 0xFF806000,
	orphan = 0xFFFF0000,
	text = 0xFFFFFFFF,
	textDim = 0xB0FFFFFF,
	back = 0xB0000000,
}

local function argb(...) return util.argb(...) end

--- Numero utilizavel (nem nil, nem NaN, nem infinito).
local function finite(v)
	return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

--- Coordenada de mundo plausivel. Evita mandar lixo para as funcoes do jogo.
local function validPoint(x, y, z)
	if not finite(x) or not finite(y) then return false end
	if math.abs(x) > 6000 or math.abs(y) > 6000 then return false end
	if z ~= nil and (not finite(z) or math.abs(z) > 2000) then return false end
	return true
end

--- Coordenada de tela plausivel (o jogo pode devolver valores enormes quando o
--- ponto esta atras da camera).
local function validScreen(x, y)
	if not finite(x) or not finite(y) then return false end
	return math.abs(x) < 100000 and math.abs(y) < 100000
end

M.validPoint = validPoint
M.validScreen = validScreen

--- Confere se o valor recebido e mesmo uma fonte do MoonLoader.
--- (userdata no jogo, tabela no mock dos testes). Funcao/nil/numero NUNCA pode
--- chegar em renderFontDrawText/renderGetFontDrawTextLength.
local function isFontHandle(f)
	local t = type(f)
	return t == 'userdata' or t == 'table'
end

M.isFontHandle = isFontHandle

--------------------------------------------------------------------------------
-- Construtor
--------------------------------------------------------------------------------

function M.new(project, settings, options)
	options = options or {}
	local colors = util.deepcopy(M.DEFAULT_COLORS)

	local self = {
		project = project,
		settings = settings or {},
		colors = colors,
		fontRef = nil, -- fonte criada (nunca usar o nome 'font': colide com o metodo)
		fontFailed = false,
		lightFactor = 1.0,
		lightChanged = false,
		slowFrames = 0,
		readyReason = nil,
		phase = 'parado',
		stats = { lines = 0, nodes = 0, navis = 0, texts = 0, projects = 0, skipped = 0, ms = 0 },
		lastError = nil,
		now = options.now,
	}
	setmetatable(self, { __index = M })
	self:refreshColors()
	return self
end

M.argb = util.argb
M.toArgb = util.toArgb

--- Rele as cores da configuracao (chamado quando o usuario muda no menu).
function M:refreshColors()
	local colors = util.deepcopy(M.DEFAULT_COLORS)
	local conf = (self.settings and self.settings.render) or {}
	colors.veh = util.toArgb(conf.cor_veh, colors.veh)
	colors.ped = util.toArgb(conf.cor_ped, colors.ped)
	colors.boat = util.toArgb(conf.cor_boat, colors.boat)
	colors.navi = util.toArgb(conf.cor_navi, colors.navi)
	colors.selected = util.toArgb(conf.cor_selecionado, colors.selected)
	colors.link = util.toArgb(conf.cor_link, colors.link)
	colors.hover = util.toArgb(conf.cor_hover, colors.hover)
	self.colors = colors
	return colors
end

--------------------------------------------------------------------------------
-- Fontes
--------------------------------------------------------------------------------

--- Fonte do HUD, criada uma unica vez.
--- ATENCAO: o campo NAO pode se chamar "font". Em Lua, `self.font = nil` apaga
--- a chave e a busca cai na metatable, devolvendo o METODO M.font - foi assim
--- que uma funcao Lua acabou sendo passada para renderFontDrawText (fonte
--- invalida = leitura em endereco 0x4 = crash 0xC0000005).
function M:font()
	if self.fontRef ~= nil then return self.fontRef end
	if self.fontFailed then return nil end
	if type(renderCreateFont) ~= 'function' then return nil end
	local flags = 0
	local ok, moonloader = pcall(require, 'moonloader')
	if ok and type(moonloader) == 'table' and moonloader.font_flag then
		flags = (moonloader.font_flag.BOLD or 0) + (moonloader.font_flag.SHADOW or 0)
	end
	local conf = self.settings.render or {}
	local size = tonumber(conf.fonte_tamanho) or 9
	if size < 6 or size > 40 then size = 9 end
	-- pcall: se a criacao falhar, marca "sem fonte" e nunca mais tenta
	-- (tentar de novo a cada quadro ja derrubou script de tanta chamada)
	local ok2, created = pcall(renderCreateFont, 'Arial', size, flags)
	if not ok2 or created == nil or created == false then
		self.fontFailed = true
		self.lastError = 'nao foi possivel criar a fonte'
		return nil
	end
	self.fontRef = created
	-- se a API devolver algo que nao e uma fonte, avisa e nao desenha texto
	-- (melhor HUD sem texto do que um ponteiro invalido no jogo)
	if not isFontHandle(created) then
		self.lastError = T('ui.fonte_invalida', type(created))
		self.fontRef = nil
		self.fontFailed = true
		return nil
	end
	return created
end

function M:text(text, x, y, color, font)
	local f = font or self:font()
	if not isFontHandle(f) or type(renderFontDrawText) ~= 'function' then return false end
	if not validScreen(x, y) then return false end
	local ok = pcall(renderFontDrawText, f, tostring(text), x, y, color or self.colors.text)
	if not ok then return false end
	self.stats.texts = self.stats.texts + 1
	return true
end

function M:textWidth(text, font)
	local f = font or self:font()
	if not isFontHandle(f) or type(renderGetFontDrawTextLength) ~= 'function' then
		return #tostring(text) * 6
	end
	local ok, width = pcall(renderGetFontDrawTextLength, f, tostring(text))
	if ok and finite(width) then return width end
	return #tostring(text) * 6
end

function M:screenSize()
	if type(getScreenResolution) == 'function' then
		local ok, w, h = pcall(getScreenResolution)
		if ok and type(w) == 'number' and w > 0 then return w, h end
	end
	return 1920, 1080
end

--------------------------------------------------------------------------------
-- Estado do jogo
--------------------------------------------------------------------------------

--- O jogo esta em condicoes de receber desenho/projecao?
--- Chamar convert3DCoordsToScreen/render* durante o carregamento, com o jogo
--- pausado ou sem jogador no mundo e uma das causas classicas de crash.
--- Devolve nil quando pode desenhar, ou o motivo quando nao pode.
function M:gameState()
	if (self.settings.render or {}).exigir_jogo_pronto == false then return nil end

	if type(isPlayerPlaying) == 'function' and type(PLAYER_HANDLE) == 'number' then
		local ok, playing = pcall(isPlayerPlaying, PLAYER_HANDLE)
		if ok and playing == false then return 'jogador fora do mundo' end
	end
	if type(isGamePaused) == 'function' then
		local ok, paused = pcall(isGamePaused)
		if ok and paused == true then return 'jogo pausado' end
	end
	-- sem handle valido nao ha o que projetar (e handle 0 derruba o jogo)
	if not util.playerPed() then return 'jogador indisponivel' end

	local x, y = self:playerPos()
	if not finite(x) or not finite(y) then return 'posicao do jogador invalida' end
	if math.abs(x) > 5000 or math.abs(y) > 5000 then return 'posicao do jogador fora do mundo' end
	if x == 0 and y == 0 then return 'jogo ainda carregando' end
	return nil
end

--- Teto de cada categoria neste quadro (o modo leve reduz tudo de uma vez).
function M:budget()
	local conf = self.settings.render or {}
	local factor = self.lightFactor or 1.0
	return {
		lines = math.floor((conf.max_linhas or 900) * factor),
		nodes = math.floor((conf.max_nodes or 600) * factor),
		navis = math.floor((conf.max_navis or 300) * factor),
		factor = factor,
	}
end

--- Modo leve automatico: se o desenho estiver caro, corta o orcamento.
function M:measure(elapsed)
	local ms = (tonumber(elapsed) or 0) * 1000
	self.stats.ms = ms
	if (self.settings.render or {}).modo_leve == false then return end
	if ms > 9 then
		self.slowFrames = self.slowFrames + 1
		if self.slowFrames >= 20 and (self.lightFactor or 1) > 0.35 then
			self.lightFactor = 0.35
			self.lightChanged = true
			self.slowFrames = 0
		end
	elseif ms < 4 then
		self.slowFrames = 0
	end
end

--- Resumo do que foi desenhado (usado no HUD, no log e nos testes).
function M:statsLine()
	local st = self.stats
	return string.format('links=%d nodes=%d navis=%d textos=%d proj=%d ms=%.1f facil=%.0f%%',
		st.lines or 0, st.nodes or 0, st.navis or 0, st.texts or 0, st.projects or 0,
		st.ms or 0, (self.lightFactor or 1) * 100)
end

--------------------------------------------------------------------------------
-- Visibilidade
--------------------------------------------------------------------------------

function M:nodeColor(areaId, index, node, kind)
	local sel = self.project.selection
	if sel.area == areaId and sel.node == index then return self.colors.selected end
	local hov = self.project.hovered
	if hov.area == areaId and hov.node == index then return self.colors.hover end
	if self.project.multi and self.project.multi[self.project:multiKey(areaId, index)] then
		return self.colors.selected
	end
	if kind == 'ped' then return self.colors.ped end
	if kind == 'boat' then return self.colors.boat end
	return self.colors.veh
end

--- Decide se um node aparece (distancia, tipo, configuracao).
function M:shouldDrawNode(areaId, index, node, kind, distance, conf)
	if distance > (conf.distancia or 250.0) then return false end
	if kind == 'ped' then
		if conf.mostrar_peds == false then return false end
	elseif kind == 'boat' then
		if conf.mostrar_barcos == false then return false end
	else
		if conf.mostrar_nodes == false then return false end
	end
	return true
end

--------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------

--- Toda primitiva passa por aqui: valida os argumentos antes de chamar a API
--- do MoonLoader (argumento invalido em funcao nativa = crash, nao erro de Lua).
local function drawLine(x1, y1, x2, y2, width, color)
	if type(renderDrawLine) ~= 'function' then return false end
	if not validScreen(x1, y1) or not validScreen(x2, y2) then return false end
	if not finite(width) or width <= 0 then width = 1.0 end
	return pcall(renderDrawLine, x1, y1, x2, y2, width, color) and true or false
end

local function drawBox(x, y, w, h, color)
	if type(renderDrawBox) ~= 'function' then return false end
	if not validScreen(x, y) then return false end
	if not finite(w) or not finite(h) or w <= 0 or h <= 0 then return false end
	return pcall(renderDrawBox, x, y, w, h, color) and true or false
end

--- Desenha um "node" na tela. O poligono e mais bonito, mas a caixa e a funcao
--- mais antiga e testada do MoonLoader; por padrao usamos a caixa
--- (render.usar_poligonos = false).
local function drawCircle(x, y, radius, color, sides, usePolygon)
	if not finite(radius) or radius <= 0 then return false end
	usePolygon = usePolygon == true
	if usePolygon and type(renderDrawPolygon) == 'function' then
		local n = math.floor(tonumber(sides) or 4)
		if n < 3 then n = 3 elseif n > 12 then n = 12 end
		if validScreen(x, y) and pcall(renderDrawPolygon, x, y, radius * 2, radius * 2, n, 0, color) then
			return true
		end
	end
	return drawBox(x - radius, y - radius, radius * 2, radius * 2, color)
end

M.drawLine = drawLine
M.drawCircle = drawCircle

--- Projeta um node e devolve (sx, sy) ou nil (ja validado).
function M:projectNode(node, height)
	if not node then return nil end
	local x, y, z = node.x, node.y, (node.z or 0) + (height or 0)
	if not validPoint(x, y, z) then return nil end
	self.stats.projects = self.stats.projects + 1
	local sx, sy = geo.project(x, y, z)
	if not validScreen(sx, sy) then return nil end
	return sx, sy
end

--- Desenha os links de todos os nodes carregados.
function M:drawLinks()
	local conf = self.settings.render or {}
	if conf.mostrar_links == false then return 0 end
	local project = self.project
	local playerX, playerY = self:playerPos()
	local budget = self:budget()
	local maxLines = budget.lines
	local maxProjects = math.max(50, math.floor(budget.nodes / 2))
	local drawn = 0
	local seen = {}
	local projects = 0

	for _, areaId in ipairs(project:loadedAreas()) do
		local area = project:area(areaId)
		if area then
			for i = 1, #area.nodes do
				if drawn >= maxLines or projects >= maxProjects then
					self.stats.skipped = self.stats.skipped + 1
				else
				local node = area.nodes[i]
				local kind = dat.nodeType(area, i)
				local distance = geo.distance2d(playerX, playerY, node.x, node.y)
				if self:shouldDrawNode(areaId, i, node, kind, distance, conf) then
					projects = projects + 1
					local x1, y1 = self:projectNode(node, conf.altura_nodes)
					if x1 then
						for j = 1, #(node.links or {}) do
							if drawn >= maxLines then
								self.stats.skipped = self.stats.skipped + 1
							else
								local link = node.links[j]
								local key = string.format('%d:%d>%d:%d', areaId, i - 1, link.area, link.node)
								-- chave vista do outro lado (o NodeID e sempre 0-based)
								local reverse = string.format('%d:%d>%d:%d', link.area, link.node, areaId, i - 1)
								if not seen[key] then
									seen[key] = true
									local targetArea = project:area(link.area)
									local target = targetArea and targetArea.nodes[link.node + 1]
									if target then
										local x2, y2 = self:projectNode(target, conf.altura_nodes)
										if x2 then
											local color = self.colors.link
											if kind == 'ped' then color = self.colors.linkPed end
											local sel = project.selection
											if (sel.area == areaId and sel.node == i) or (sel.area == link.area and sel.node == link.node + 1) then
												color = self.colors.linkSelected
											end
											-- so desenha um lado de cada par
											if not seen[reverse] then
												if drawLine(x1, y1, x2, y2, 1.2, color) then
													drawn = drawn + 1
												end
											end
										end
									end
								end
							end
						end
					end
				end
				end
			end
		end
	end
	self.stats.lines = drawn
	return drawn
end

--- Desenha os nodes.
function M:drawNodes()
	local conf = self.settings.render or {}
	local project = self.project
	local playerX, playerY = self:playerPos()
	local size = conf.tamanho_node or 6.0
	local maxNodes = self:budget().nodes
	local drawn = 0

	for _, areaId in ipairs(project:loadedAreas()) do
		local area = project:area(areaId)
		if area then
			for i = 1, #area.nodes do
				if drawn >= maxNodes then
					self.stats.skipped = self.stats.skipped + 1
				else
				local node = area.nodes[i]
				local kind = dat.nodeType(area, i)
				local distance = geo.distance2d(playerX, playerY, node.x, node.y)
				if self:shouldDrawNode(areaId, i, node, kind, distance, conf) then
					local sx, sy = self:projectNode(node, conf.altura_nodes)
					if sx then
						local color = self:nodeColor(areaId, i, node, kind)
						local radius = size
						local selected = project.selection.area == areaId and project.selection.node == i
						if selected then radius = size * 1.6 end
						local sides = (kind == 'ped') and 3 or 4
						if drawCircle(sx, sy, radius, color, sides, conf.usar_poligonos) then
							drawn = drawn + 1
						end
					end
				end
				end
			end
		end
	end
	self.stats.nodes = drawn
	return drawn
end

--- Desenha os navi nodes (losango + tracinho na direcao).
function M:drawNavis()
	local conf = self.settings.render or {}
	if conf.mostrar_navis == false then return 0 end
	local project = self.project
	local playerX, playerY = self:playerPos()
	local size = (conf.tamanho_node or 6.0) * 0.8
	local maxNavis = self:budget().navis
	local drawn = 0

	for _, areaId in ipairs(project:loadedAreas()) do
		local area = project:area(areaId)
		if area then
			for i = 1, #area.navis do
				if drawn >= maxNavis then
					self.stats.skipped = self.stats.skipped + 1
				else
				local navi = area.navis[i]
				local distance = geo.distance2d(playerX, playerY, navi.x, navi.y)
				if distance <= (conf.distancia or 250.0) then
					local sx, sy = self:projectNode(navi, (conf.altura_nodes or 1.0) + 0.5)
					if sx then
						local color = self.colors.navi
						local sel = project.selection.area == areaId and project.selection.navi == i
						if sel then color = self.colors.selected end
						if drawCircle(sx, sy, size, color, nil, conf.usar_poligonos) then
							drawn = drawn + 1
						end
						-- direcao
						local dirLength = math.sqrt((navi.dirX or 0) ^ 2 + (navi.dirY or 0) ^ 2)
						if dirLength > 1 then
							local nx, ny = (navi.dirX or 0) / dirLength, (navi.dirY or 0) / dirLength
							local tx, ty = navi.x + nx * 4.0, navi.y + ny * 4.0
							if validPoint(tx, ty, navi.z) then
								local ex, ey = geo.project(tx, ty, (conf.altura_nodes or 1.0) + 0.5)
								if validScreen(ex, ey) then drawLine(sx, sy, ex, ey, 1.0, color) end
							end
						end
					end
				end
				end
			end
		end
	end
	self.stats.navis = drawn
	return drawn
end

--- Atualiza a posicao do jogador (uma vez por quadro, evita varias chamadas).
function M:update(dt)
	self.stats = {
		lines = 0, nodes = 0, navis = 0, texts = 0,
		projects = (self.stats and self.stats.projects or 0),
		skipped = 0, ms = (self.stats and self.stats.ms or 0),
	}
end

--- Desenha tudo (links, nodes, navi e HUD).
--- Nao desenha (nem projeta nada) quando o jogo nao esta em condicoes.
function M:draw()
	if (self.settings.render or {}).ativo == false then
		self.phase = 'desligado'
		return false
	end
	local reason = self:gameState()
	self.readyReason = reason
	if reason then
		self.phase = 'esperando'
		self.stats = { lines = 0, nodes = 0, navis = 0, texts = 0, projects = 0, skipped = 0, ms = self.stats.ms }
		return false
	end

	local started = os.clock()
	self:update()
	self.phase = 'links'
	self:drawLinks()
	self.phase = 'nodes'
	self:drawNodes()
	self.phase = 'navis'
	self:drawNavis()
	if (self.settings.render or {}).mostrar_hud ~= false then
		self.phase = 'hud'
		self:drawHud()
	end
	if (self.settings.map or {}).ativo == true then
		self.phase = 'minimapa'
		self:drawMinimap()
	end
	self.phase = 'fim'
	self:measure(os.clock() - started)
	return true
end

--------------------------------------------------------------------------------
-- Picking (clicar/selecionar com o mouse)
--------------------------------------------------------------------------------

--- Node mais proximo do pixel (x, y) dentro de 'radius' pixels.
--- Devolve { area, index, distance, sx, sy } ou nil.
--- Posicao do jogador (cache do quadro). Nunca passa handle invalido ao jogo.
function M:playerPos()
	local x, y = util.playerCoords()
	if x then
		self._px, self._py = x, y
		return x, y
	end
	return self._px or 0, self._py or 0
end

function M:pick(x, y, radius)
	local conf = self.settings.render or {}
	radius = radius or 14
	if not finite(x) or not finite(y) then return nil end
	local allowed = self:budget().nodes
	local best
	local playerX, playerY = self:playerPos()
	for _, areaId in ipairs(self.project:loadedAreas()) do
		local area = self.project:area(areaId)
		if area then
			for i = 1, #area.nodes do
				local node = area.nodes[i]
				local kind = dat.nodeType(area, i)
				local distance = geo.distance2d(playerX, playerY, node.x, node.y)
				if distance <= (conf.distancia or 250.0) then
					local sx, sy = self:projectNode(node, conf.altura_nodes)
					if sx then
						local d = math.sqrt((sx - x) ^ 2 + (sy - y) ^ 2)
						if d <= radius and (not best or d < best.distance) then
							best = { area = areaId, index = i, distance = d, sx = sx, sy = sy, kind = kind }
						end
					end
				end
			end
		end
	end
	return best
end

--- Navi node mais proximo do pixel.
function M:pickNavi(x, y, radius)
	radius = radius or 14
	local conf = self.settings.render or {}
	local best
	for _, areaId in ipairs(self.project:loadedAreas()) do
		local area = self.project:area(areaId)
		if area then
			for i = 1, #area.navis do
				local navi = area.navis[i]
				local sx, sy = geo.project(navi.x, navi.y, (conf.altura_nodes or 1.0) + 0.5)
				if sx then
					local d = math.sqrt((sx - x) ^ 2 + (sy - y) ^ 2)
					if d <= radius and (not best or d < best.distance) then
						best = { area = areaId, navi = i, distance = d, sx = sx, sy = sy }
					end
				end
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

function M:hudLines()
	local project = self.project
	local lines = {}
	local sel = project.selection
	if sel.area then
		local area = project:area(sel.area)
		if area then
			local stats = project:stats(sel.area) or {}
			if sel.navi then
				lines[#lines + 1] = T('hud.area', sel.area) .. '  ' .. T('navi.nome_gerado', (sel.navi or 1) - 1)
			elseif sel.node then
				local kind = dat.nodeType(area, sel.node)
				local kindKey = (kind == 'ped' and 'hud.ped') or (kind == 'boat' and 'hud.boat') or 'hud.veh'
				lines[#lines + 1] = T('hud.node_sel', (sel.node or 1) - 1, T(kindKey))
			end
			lines[#lines + 1] = string.format('%s: %d  %s: %d  %s: %d',
				T('nav.node_count'), stats.nodeCount or 0,
				T('nav.navi'), stats.naviCount or 0,
				T('nav.link_count'), stats.linkCount or 0)
		end
	else
		lines[#lines + 1] = T('hud.no')
	end

	if #project:dirtyAreas() > 0 then
		lines[#lines + 1] = T('hud.modificado') .. ': ' .. table.concat(project:dirtyAreas(), ', ')
	end

	if ((self.settings or {}).geral or {}).debug then
		lines[#lines + 1] = T('hud.desempenho', self:statsLine())
		if (self.lightFactor or 1) < 1 or (self.settings.render or {}).modo_leve == false then
			lines[#lines + 1] = T('hud.modo_leve', math.floor((self.lightFactor or 1) * 100))
		end
	end

	if self.lastError then
		lines[#lines + 1] = self.lastError
	end
	return lines
end

function M:drawHud()
	local w, h = self:screenSize()
	local lines = self:hudLines()
	local font = self:font()
	local y = 8
	if type(renderDrawBox) == 'function' and #lines > 0 then
		local maxw = 0
		for i = 1, #lines do
			local lw = self:textWidth(lines[i], font)
			if lw > maxw then maxw = lw end
		end
		-- dimensoes sempre sanitizadas: NaN/infinito aqui derruba o jogo
		if not finite(maxw) or maxw < 0 then maxw = w end
		if w > 0 and h > 0 and (maxw + 16) < w and (#lines * 14 + 8) < h then
			drawBox(w / 2 - maxw / 2 - 8, y - 4, maxw + 16, #lines * 14 + 8, self.colors.back)
		end
	end
	for i = 1, #lines do
		local lw = self:textWidth(lines[i], font)
		self:text(lines[i], w / 2 - lw / 2, y, self.colors.text, font)
		y = y + 14
	end
	return #lines
end

--------------------------------------------------------------------------------
-- Minimapa (visao de cima do mundo, em coordenadas do jogo)
--------------------------------------------------------------------------------

--- Retangulo do minimapa na tela.
function M:minimapRect()
	local conf = self.settings.map or {}
	if conf.ativo ~= true then return nil end
	local w, h = self:screenSize()
	local size = conf.tamanho or 320
	local margin = 12
	local x = (conf.lado == 'esquerda') and margin or (w - size - margin)
	local y = margin
	return x, y, size, size
end

--- Retangulo do mundo que o minimapa mostra (centrado no jogador ou na area).
function M:minimapWorld()
	local conf = self.settings.map or {}
	local raio = conf.raio or 200.0
	local cx, cy = self:playerPos()
	if conf.modo == 'mta' then
		-- visao geral: mundo inteiro (8x8 areas de 750 unidades)
		return -3000, -3000, 6000, 6000
	end
	if conf.centro then cx, cy = conf.centro.x or cx, conf.centro.y or cy end
	return cx - raio, cy - raio, raio * 2, raio * 2
end

--- Converte um ponto do mundo para o pixel do minimapa.
function M:minimapPoint(wx, wy)
	local rect = { self:minimapRect() }
	if not rect[1] then return nil end
	local x, y, size = rect[1], rect[2], rect[3]
	local wx0, wy0, ww, wh = self:minimapWorld()
	local px = x + (wx - wx0) / ww * size
	local py = y + size - (wy - wy0) / wh * size
	return px, py
end

--- Converte um pixel do minimapa para o mundo.
function M:minimapToWorld(px, py)
	local rect = { self:minimapRect() }
	if not rect[1] then return nil end
	local x, y, size = rect[1], rect[2], rect[3]
	if px < x or px > x + size or py < y or py > y + size then
		return nil, 'fora do minimapa'
	end
	local wx0, wy0, ww, wh = self:minimapWorld()
	return wx0 + (px - x) / size * ww, wy0 + (1 - (py - y) / size) * wh
end

--- Desenha o minimapa: grade das areas, nodes das areas carregadas e o jogador.
function M:drawMinimap()
	local rect = { self:minimapRect() }
	if not rect[1] then return false end
	local x, y, size = rect[1], rect[2], rect[3]
	if type(renderDrawBox) ~= 'function' then return false end
	if not validScreen(x, y) or not finite(size) or size <= 0 then return false end

	drawBox(x, y, size, size, self.colors.back)
	drawBox(x, y, size, 1, self.colors.textDim)
	drawBox(x, y + size - 1, size, 1, self.colors.textDim)
	drawBox(x, y, 1, size, self.colors.textDim)
	drawBox(x + size - 1, y, 1, size, self.colors.textDim)

	-- linhas das areas (a cada 750 unidades)
	local wx0, wy0, ww, wh = self:minimapWorld()
	local step = (ww > 1500) and 750 or 250
	local guard = 0
	local gx = math.floor(wx0 / step) * step
	while gx <= wx0 + ww and guard < 200 do
		guard = guard + 1
		local px = self:minimapPoint(gx, 0)
		if px then
			local major = (math.floor(gx / 750) * 750 == gx)
			drawLine(px, y, px, y + size, 1.0, major and self.colors.textDim or self.colors.back)
		end
		gx = gx + step
	end
	guard = 0
	local gy = math.floor(wy0 / step) * step
	while gy <= wy0 + wh and guard < 200 do
		guard = guard + 1
		local _, py = self:minimapPoint(0, gy)
		if py then drawLine(x, py, x + size, py, 1.0, self.colors.back) end
		gy = gy + step
	end

	-- nodes
	local conf = self.settings.render or {}
	local maxNodes = conf.max_minimapa or 4000
	local drawn = 0
	for _, areaId in ipairs(self.project:loadedAreas()) do
		local area = self.project:area(areaId)
		if area then
			for i = 1, #area.nodes do
				if drawn >= maxNodes then break end
				local node = area.nodes[i]
				local px, py = self:minimapPoint(node.x, node.y)
				if px and px >= x and px <= x + size and py >= y and py <= y + size then
					local kind = dat.nodeType(area, i)
					local color = self:nodeColor(areaId, i, node, kind)
					if drawBox(px - 1, py - 1, 2.5, 2.5, color) then drawn = drawn + 1 end
				end
			end
		end
	end

	-- jogador
	local px, py = self:minimapPoint(self:playerPos())
	if px and py then drawBox(px - 2, py - 2, 5, 5, self.colors.selected) end

	self.stats.minimap = drawn
	return true
end


return M
