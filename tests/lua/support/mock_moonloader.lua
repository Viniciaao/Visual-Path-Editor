--[[
	Mock do ambiente MoonLoader para rodar os testes fora do jogo.
	Trabalha em cima de uma pasta de jogo falsa (real, no disco) para que as
	funcoes de arquivo do mod sejam exercitadas de verdade.
]]

local M = {}

M.gameDir = os.getenv('VPE_TEST_GAME_DIR') or 'tests/tmp/game'
M.renderCalls = {}
M.keyState = {}
M.keyJustPressed = {}
M.screen = { width = 1920, height = 1080 }
M.playerPos = { x = 2495.0, y = -1684.0, z = 10.0 }
M.groundZ = 10.0
M.waterZ = -100.0
M.playerHandle = 0
M.playerPedHandle = 2495
M.pedExists = true
M.playerPlaying = true
M.gamePaused = false

local function fileExists(path)
	local f = io.open(path, 'rb')
	if f then f:close() return true end
	return false
end

local function dirExists(path)
	local ok, kind, code = os.execute('test -d "' .. tostring(path) .. '"')
	if type(code) == 'number' then return code == 0 end
	return ok == 0
end

local VK = {
	VK_LBUTTON = 0x01, VK_RBUTTON = 0x02, VK_BACK = 0x08, VK_TAB = 0x09, VK_RETURN = 0x0D,
	VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_PAUSE = 0x13, VK_ESCAPE = 0x1B,
	VK_SPACE = 0x20, VK_LEFT = 0x25, VK_UP = 0x26, VK_RIGHT = 0x27, VK_DOWN = 0x28,
	VK_INSERT = 0x2D, VK_DELETE = 0x2E, VK_NUMPAD0 = 0x60, VK_NUMPAD1 = 0x61, VK_NUMPAD2 = 0x62,
	VK_NUMPAD3 = 0x63, VK_NUMPAD4 = 0x64, VK_NUMPAD5 = 0x65, VK_NUMPAD6 = 0x66, VK_NUMPAD7 = 0x67,
	VK_NUMPAD8 = 0x68, VK_NUMPAD9 = 0x69,
	VK_F1 = 0x70, VK_F2 = 0x71, VK_F3 = 0x72, VK_F4 = 0x73, VK_F5 = 0x74, VK_F6 = 0x75,
	VK_F7 = 0x76, VK_F8 = 0x77, VK_F9 = 0x78, VK_F10 = 0x79, VK_F11 = 0x7A, VK_F12 = 0x7B,
	VK_0 = 0x30, VK_1 = 0x31, VK_2 = 0x32, VK_3 = 0x33, VK_4 = 0x34, VK_5 = 0x35,
	VK_6 = 0x36, VK_7 = 0x37, VK_8 = 0x38, VK_9 = 0x39,
	VK_A = 0x41, VK_B = 0x42, VK_C = 0x43, VK_D = 0x44, VK_E = 0x45, VK_F = 0x46,
	VK_G = 0x47, VK_H = 0x48, VK_I = 0x49, VK_J = 0x4A, VK_K = 0x4B, VK_L = 0x4C,
	VK_M = 0x4D, VK_N = 0x4E, VK_O = 0x4F, VK_P = 0x50, VK_Q = 0x51, VK_R = 0x52,
	VK_S = 0x53, VK_T = 0x54, VK_U = 0x55, VK_V = 0x56, VK_W = 0x57, VK_X = 0x58,
	VK_Y = 0x59, VK_Z = 0x5A,
}

function M.install()
	-- modulos que o MoonLoader fornece (moonloader, vkeys)
	local preload = package.preload
	preload['moonloader'] = preload['moonloader'] or function()
		return {
			font_flag = { BOLD = 1, ITALICS = 2, BORDER = 4, SHADOW = 8, UNDERLINE = 16, STRIKEOUT = 32 },
			script_name = 'VisualPathEditor',
			script_version = '1.0.0',
			VERSION = '026',
		}
	end
	preload['vkeys'] = preload['vkeys'] or function() return VK end

	_G.getWorkingDirectory = function() return M.gameDir end
	_G.doesFileExist = function(path) return fileExists(path) end
	_G.doesDirectoryExist = function(path) return dirExists(path) end
	_G.createDirectory = function(path) return os.execute('mkdir -p "' .. tostring(path) .. '"') end

	-- render (apenas registra chamadas)
	_G.renderDrawLine = function(x1, y1, x2, y2, w, c) M.renderCalls[#M.renderCalls + 1] = { 'line', x1, y1, x2, y2, w, c } end
	_G.renderDrawBox = function(x, y, w, h, c) M.renderCalls[#M.renderCalls + 1] = { 'box', x, y, w, h, c } end
	_G.renderDrawBoxWithBorder = function(x, y, w, h, c, bs, bc) M.renderCalls[#M.renderCalls + 1] = { 'boxb', x, y, w, h, c, bs, bc } end
	_G.renderDrawPolygon = function(x, y, sx, sy, sides, rot, c) M.renderCalls[#M.renderCalls + 1] = { 'poly', x, y, sx, sy, sides, rot, c } end
	_G.renderDrawTexture = function(tex, x, y, w, h, rot, c) M.renderCalls[#M.renderCalls + 1] = { 'tex', x, y, w, h, rot, c } end
	_G.renderBegin = function() end
	_G.renderEnd = function() end
	_G.renderVertex = function() end
	_G.renderCreateFont = function(name, size, flags) return { name = name, size = size, flags = flags } end
	-- o jogo real le a fonte como ponteiro: passar qualquer coisa que nao seja
	-- a fonte (nil, numero, FUNCAO) derruba o GTA com leitura em 0x4. O mock
	-- tambem recusa, para o erro aparecer no teste em vez de no jogo.
	local function checkFont(font)
		if type(font) ~= 'table' then
			error('fonte invalida passada para a api de texto: ' .. type(font), 2)
		end
		return font
	end
	M.checkFont = checkFont
	_G.renderFontDrawText = function(font, text, x, y, color)
		checkFont(font)
		M.renderCalls[#M.renderCalls + 1] = { 'text', text, x, y, color }
	end
	_G.renderGetFontDrawTextLength = function(font, text)
		checkFont(font)
		return #tostring(text) * 6
	end
	_G.renderGetFontDrawHeight = function(font) checkFont(font) return 12 end
	_G.getScreenResolution = function() return M.screen.width, M.screen.height end

	-- 3D -> 2D (projecao simples e deterministica, so para os testes).
	-- 'pixelsPerMeterZ' e 0 por padrao (projecao "ortografica" no plano XY);
	-- os testes que querem medir tamanho por distancia ligam esse termo.
	_G.convert3DCoordsToScreen = function(x, y, z)
		local sx = M.screen.width / 2 + (x - M.playerPos.x) * 2
		local sy = M.screen.height / 2 - (y - M.playerPos.y) * 2 - ((z or M.playerPos.z) - M.playerPos.z) * (M.pixelsPerMeterZ or 0)
		return sx, sy
	end
	_G.convertScreenCoordsToWorld3D = function(sx, sy, depth)
		local x = M.playerPos.x + (sx - M.screen.width / 2) / 2
		local y = M.playerPos.y - (sy - M.screen.height / 2) / 2
		local z = M.playerPos.z + depth * 100
		return x, y, z
	end
	_G.isPointOnScreen = function(x, y, z, radius) return true end

	-- camera e oclusao (usados para nao desenhar atraves de paredes)
	_G.getActiveCameraCoordinates = function()
		M.cameraCalls = (M.cameraCalls or 0) + 1
		local c = M.cameraPos or { M.playerPos.x, M.playerPos.y, M.playerPos.z + 1.0 }
		return c[1], c[2], c[3]
	end
	_G.getActiveCameraPointAt = function() return M.playerPos.x + 10.0, M.playerPos.y, M.playerPos.z end
	_G.isLineOfSightClear = function(x1, y1, z1, x2, y2, z2, buildings, vehicles, peds, objects, particles)
		M.lineOfSightCalls = (M.lineOfSightCalls or 0) + 1
		M.lastLineOfSight = { x1, y1, z1, x2, y2, z2, buildings, vehicles, peds, objects, particles }
		if M.lineOfSightClear then return M.lineOfSightClear(x1, y1, z1, x2, y2, z2) end
		return true
	end

	-- espaco de coordenadas "de jogo" (640x448) <-> pixels da janela
	_G.convertGameScreenCoordsToWindowScreenCoords = function(x, y)
		local k = M.gameSpaceScale or 1.0
		return x * k, y * k
	end
	_G.convertWindowScreenCoordsToGameScreenCoords = function(x, y)
		local k = M.gameSpaceScale or 1.0
		return x / k, y / k
	end

	-- jogador (o MoonLoader expoe estes globais)
	M.refreshPlayer()
	_G.doesCharExist = function(char)
		if not M.pedExists then return false end
		return char == M.playerPedHandle
	end
	_G.isPlayerPlaying = function(handle) return M.playerPlaying == true end
	_G.isGamePaused = function() return M.gamePaused == true end
	_G.getPlayerHandle = function() return M.playerHandle end
	_G.getPlayerPed = function() return M.playerPedHandle end

	-- mundo
	_G.getCharCoordinates = function(char)
		if char ~= nil and char ~= M.playerPedHandle then
			-- imita o jogo: handle invalido nao devolve coordenada
			M.badHandleCalls = (M.badHandleCalls or 0) + 1
			return 0, 0, 0
		end
		return M.playerPos.x, M.playerPos.y, M.playerPos.z
	end
	_G.setCharCoordinates = function(char, x, y, z) M.playerPos.x, M.playerPos.y, M.playerPos.z = x, y, z end
	_G.setPlayerCoordinates = _G.setCharCoordinates
	_G.getGroundZFor3dCoord = function() return M.groundZ end
	_G.getWaterHeightAtCoords = function() return M.waterZ end
	_G.loadScene = function() return true end
	_G.requestCollision = function() end
	_G.printStringNow = function(text)
		M.chatLines = M.chatLines or {}
		M.chatLines[#M.chatLines + 1] = tostring(text)
	end
	_G.printHelpString = function() end

	-- teclado
	_G.isKeyDown = function(key) return M.keyState[key] == true end
	_G.wasKeyPressed = function(key) return M.keyJustPressed[key] == true end
	_G.isKeyJustPressed = _G.wasKeyPressed
	_G.getCursorPos = function() return M.cursorX or 0, M.cursorY or 0 end

	-- eventos
	M.eventHandlers = {}
	_G.addEventHandler = function(name, fn)
		M.eventHandlers[name] = M.eventHandlers[name] or {}
		table.insert(M.eventHandlers[name], fn)
	end
	_G.lua_thread = {
		create = function(fn)
			M.threads = M.threads or {}
			table.insert(M.threads, coroutine.create(fn))
		end,
	}
	_G.wait = function() end
	_G.thisScript = function() return { path = M.gameDir .. '/moonloader/VisualPathEditor.lua', name = 'VisualPathEditor' } end

	-- metadados do script (registrados para os testes conferirem)
	M.scriptMeta = {}
	local function meta(name)
		return function(value)
			if value ~= nil then M.scriptMeta[name] = value end
			return M.scriptMeta[name]
		end
	end
	_G.script_name = meta('name')
	_G.script_author = meta('author')
	_G.script_version = meta('version')
	_G.script_description = meta('description')

	_G.getMoonloaderVersion = function() return 26 end
	_G.getGameVersion = function() return 1 end

	M.installImgui()
	return M
end

--------------------------------------------------------------------------------
-- Mock do Moon ImGui (o binding real usa ImBool/ImInt/... com campo .v)
--------------------------------------------------------------------------------

M.imguiCalls = {}
M.imguiPress = {}
M.imguiOpen = {}
M.imguiModal = nil
M.imguiInput = {}

function M.resetImgui()
	M.imguiCalls = {}
	M.imguiPress = {}
	M.imguiOpen = {}
	M.imguiModal = nil
	M.imguiDraw = nil
end

--- Limpa so o registro de chamadas (mantem o hook registrado pelo mod).
function M.clearUiLog()
	M.imguiCalls = {}
	M.imguiPress = {}
	M.imguiOpen = {}
	M.imguiModal = nil
	M.imguiInput = {}
	M.uiStack = {}
end

--- Quanto ficou aberto (0 = tudo balanceado) de um widget empilhado.
function M.stack(name)
	return (M.uiStack and M.uiStack[name]) or 0
end

--- Lista de widgets que ficaram desbalanceados no ultimo quadro.
function M.unbalanced()
	local out = {}
	for key, count in pairs(M.uiStack or {}) do
		if count ~= 0 then out[#out + 1] = key .. '=' .. count end
	end
	table.sort(out)
	return out
end

--- Digita um texto no proximo campo InputText com esse rotulo.
function M.typeText(label, text)
	M.imguiInput[tostring(label)] = tostring(text)
end

--- Marca um botao/selectable como clicado no proximo quadro.
function M.click(label)
	M.imguiPress[label] = true
end

function M.countCalls(name)
	local n = 0
	for i = 1, #M.imguiCalls do
		if M.imguiCalls[i][1] == name then n = n + 1 end
	end
	return n
end

--- Todo texto visivel desenhado no ultimo quadro (Text/TextColored/BulletText).
--- Ultima mensagem escrita no chat do jogo (printStringNow).
function M.lastChat()
	local lines = M.chatLines or {}
	return lines[#lines]
end

--- Alguma mensagem do chat contem o texto?
function M.chatHas(part)
	local lines = M.chatLines or {}
	for i = 1, #lines do
		if tostring(lines[i]):find(part, 1, true) then return true, lines[i] end
	end
	return false, nil
end

--[[
	io = tabela do ImGuiIO (lembrada entre quadros, como no ImGui de verdade).
	noIo = true faz GetIO() devolver nil; goodIo = false faz o campo
	FontGlobalScale nao guardar o valor (imita um binding que ignora a escrita).
]]
function M.setIo(opts)
	opts = opts or {}
	M.io = opts.io or { WantCaptureMouse = false, WantCaptureKeyboard = false }
	if opts.ignoreScale then
		local io = M.io
		M.io = setmetatable({}, {
			__index = function(_, k)
				if k == 'FontGlobalScale' then return 1.0 end
				return io[k]
			end,
			__newindex = function(t, k, v)
				if k == 'FontGlobalScale' then return end -- escrita ignorada
				rawset(t, k, v)
			end,
		})
	end
	M.noIo = opts.noIo and true or false
	return M.io
end

--- Rotulos dos Selectable desenhados no ultimo quadro (a lista de areas).
function M.selectables()
	local out = {}
	for i = 1, #M.imguiCalls do
		if M.imguiCalls[i][1] == 'Selectable' then
			local label = tostring(M.imguiCalls[i][2] or '')
			label = label:gsub('##.*$', '')
			out[#out + 1] = label
		end
	end
	return out
end

--- Todo texto visivel desenhado no ultimo quadro (Text/TextColored/BulletText).
function M.texts()
	local out = {}
	for i = 1, #M.imguiCalls do
		local name = M.imguiCalls[i][1]
		if name == 'Text' or name == 'TextColored' or name == 'BulletText' then
			out[#out + 1] = tostring(M.imguiCalls[i][2])
		end
	end
	return out
end

--- Roda o callback de desenho que o mod registrou.
function M.runUiFrame()
	if type(M.imguiDraw) == 'function' then return M.imguiDraw() end
	return false
end

function M.hasUiHook()
	return type(M.imguiDraw) == 'function'
end

function M.installImgui()
	local imgui = {}
	M.imgui = imgui
	M.imguiCalls = {}
	M.imguiPress = {}
	M.imguiModal = nil
	M.imguiDraw = nil
	-- Moon ImGui nao tem OnDrawFrame como funcao: o script ATRIBUI o campo.
	-- O metamethod guarda o callback para o teste conseguir rodar um quadro.
	setmetatable(imgui, {
		__newindex = function(t, key, value)
			if key == 'OnDrawFrame' then
				M.imguiDraw = value
			else
				rawset(t, key, value)
			end
		end,
	})

	-- Pilha do ImGui: um Begin/End (ou BeginChild/EndChild, TreeNode/TreePop...)
	-- desbalanceado derruba o jogo, entao o mock acompanha isso.
	local STACK_PAIRS = {
		Begin = { 'End', 1 },
		BeginChild = { 'EndChild', 1 },
		TreeNode = { 'TreePop', 1 },
		PushItemWidth = { 'PopItemWidth', 1 },
		PushStyleColor = { 'PopStyleColor', 1 },
		BeginTooltip = { 'EndTooltip', 1 },
		BeginPopupModal = { 'EndPopup', 1 },
	}

	local function record(name, ...)
		M.imguiCalls[#M.imguiCalls + 1] = { name, ... }
	end

	--- Ajusta a pilha do ImGui conforme o widget chamado.
	local function track(name, opened)
		M.uiStack = M.uiStack or {}
		local entry = STACK_PAIRS[name]
		if entry then
			if opened == false then return end
			M.uiStack[name] = (M.uiStack[name] or 0) + 1
			return
		end
		for key, pair in pairs(STACK_PAIRS) do
			if pair[1] == name then
				M.uiStack[key] = (M.uiStack[key] or 0) - 1
				return
			end
		end
	end
	M.trackStack = track
	-- ImGui formata a string no proprio widget (Text(fmt, ...)); o mock faz igual
	-- para os testes poderem conferir o texto final.
	local function fmtArgs(fmt, ...)
		if select('#', ...) > 0 then
			local ok, out = pcall(string.format, fmt, ...)
			if ok then return out end
		end
		return tostring(fmt)
	end

	local function pressed(label)
		if M.imguiPress[label] then
			M.imguiPress[label] = nil
			return true
		end
		-- tambem aceita clicar pelo rotulo visivel (sem o "##id" que o ImGui esconde)
		local visible = tostring(label):gsub('##.*$', '')
		if visible ~= label and M.imguiPress[visible] then
			M.imguiPress[visible] = nil
			return true
		end
		return false
	end

	imgui.Process = false
	imgui.LockPlayer = false
	imgui.ShowCursor = false
	imgui.Cond = { Always = 1, Once = 2, FirstUseEver = 4 }
	imgui.WindowFlags = { NoTitleBar = 1, NoResize = 2, NoMove = 4 }
	imgui.Col = { Text = 0, TextDisabled = 1, WindowBg = 2, Button = 3, FrameBg = 4 }

	--[[
		Fidelidade do binding: no Moon ImGui `imgui.ImBool` (e ImInt/ImFloat/
		ImVec2/ImVec4/ImBuffer) NAO e uma funcao - e um userdata com __call.
		O `type()` disso e 'userdata' (aqui, 'table' com __call, que e o que o
		Lua puro consegue imitar), nunca 'function'. O mock antigo expunha
		funcoes, entao a suite passava enquanto o painel real abria sem nenhum
		widget ligado (o log do jogo mostrou `ImBool=-, ImInt=-, ...`).
	]]
	local function callableCtor(build)
		return setmetatable({}, {
			__call = function(_, ...) return build(...) end,
		})
	end
	imgui.ImBool = callableCtor(function(v) return { v = v and true or false } end)
	imgui.ImInt = callableCtor(function(v) return { v = math.floor(tonumber(v) or 0) } end)
	imgui.ImFloat = callableCtor(function(v) return { v = tonumber(v) or 0 } end)
	imgui.ImDouble = imgui.ImFloat
	imgui.ImBuffer = callableCtor(function(size)
		size = tonumber(size) or 0
		return { size = size, v = string.rep('\0', size) }
	end)
	imgui.ImVec2 = callableCtor(function(x, y) return { x = tonumber(x) or 0, y = tonumber(y) or 0 } end)
	imgui.ImVec3 = callableCtor(function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end)
	imgui.ImVec4 = callableCtor(function(x, y, z, w) return { x = x or 0, y = y or 0, z = z or 0, w = w or 0 } end)

	imgui.GetIO = function()
		if M.noIo then return nil end
		local io = M.io or { WantCaptureMouse = false, WantCaptureKeyboard = false }
		M.io = io
		return io
	end
	imgui.SetWindowFontScale = function(scale) record('SetWindowFontScale', scale) end
	imgui.Begin = function(title) record('Begin', title) track('Begin') return true end
	imgui.End = function() record('End') track('End') end
	--[[
		No Moon ImGui o texto usa APENAS o primeiro argumento (a formatacao e do
		C): `imgui.Text('a=%d', n)` desenha literalmente "a=%d". O mock tem que
		fazer o mesmo, senao a suite nao ve o painel cheio de "%s" que o usuario
		tirou print.
	]]
	local function single(fmt) return tostring(fmt) end
	imgui.Text = function(fmt, ...) record('Text', single(fmt)) end
	imgui.TextColored = function(color, fmt, ...) record('TextColored', single(fmt)) end
	imgui.TextWrapped = function(fmt, ...) record('Text', single(fmt)) return true end
	imgui.TextDisabled = function(fmt, ...) record('Text', single(fmt)) end
	imgui.BulletText = function(fmt, ...) record('BulletText', single(fmt)) end
	imgui.Separator = function() record('Separator') end
	imgui.SameLine = function() record('SameLine') end
	imgui.Spacing = function() record('Spacing') end
	imgui.Dummy = function(size) record('Dummy', size and size.x or 0, size and size.y or 0) end
	imgui.Button = function(label) record('Button', tostring(label)) return pressed(tostring(label)) end
	imgui.SmallButton = function(label) record('SmallButton', tostring(label)) return pressed(tostring(label)) end
	imgui.Selectable = function(label, selected)
		record('Selectable', tostring(label), selected and true or false)
		return pressed(tostring(label))
	end
	imgui.Checkbox = function(label, ref) record('Checkbox', tostring(label)) return false end
	imgui.InputText = function(label, ref, flags)
		record('InputText', tostring(label))
		local wanted = M.imguiInput[tostring(label)]
		if wanted ~= nil then
			M.imguiInput[tostring(label)] = nil
			pcall(function() ref.v = wanted end)
			return true
		end
		return false
	end
	imgui.InputInt = function(label, ref) record('InputInt', tostring(label)) return false end
	imgui.InputFloat = function(label, ref) record('InputFloat', tostring(label)) return false end
	imgui.SliderInt = function(label, ref) record('SliderInt', tostring(label)) return false end
	imgui.SliderFloat = function(label, ref) record('SliderFloat', tostring(label)) return false end
	imgui.Combo = function(label, ref, items)
		record('Combo', tostring(label), items and #items or 0)
		return false, 1
	end
	imgui.CollapsingHeader = function(label, ref)
		record('CollapsingHeader', tostring(label))
		if M.imguiOpen[tostring(label)] == false then return false end
		return true
	end
	imgui.TreeNode = function(label) record('TreeNode', tostring(label)) track('TreeNode') return true end
	imgui.TreePop = function() record('TreePop') track('TreePop') end
	imgui.BeginChild = function(id, size, border) record('BeginChild', tostring(id)) track('BeginChild') return true end
	imgui.EndChild = function() record('EndChild') track('EndChild') end
	imgui.PushItemWidth = function(w) record('PushItemWidth', w) track('PushItemWidth') end
	imgui.PopItemWidth = function() record('PopItemWidth') track('PopItemWidth') end
	imgui.SetNextWindowSize = function(size, cond) record('SetNextWindowSize', size and size.x or 0) end
	imgui.SetNextWindowPos = function(pos, cond) record('SetNextWindowPos') end
	imgui.OpenPopup = function(name) record('OpenPopup', tostring(name)) M.imguiModal = tostring(name) end
	imgui.BeginPopupModal = function(name)
		record('BeginPopupModal', tostring(name))
		local open = M.imguiModal == tostring(name)
		track('BeginPopupModal', open)
		return open
	end
	imgui.EndPopup = function() record('EndPopup') track('EndPopup') end
	imgui.CloseCurrentPopup = function() record('CloseCurrentPopup') M.imguiModal = nil end
	imgui.ProgressBar = function(frac) record('ProgressBar', frac) end
	imgui.SetTooltip = function(fmt, ...) record('SetTooltip', tostring(fmt)) end
	imgui.BeginTooltip = function() record('BeginTooltip') track('BeginTooltip') return true end
	imgui.EndTooltip = function() record('EndTooltip') track('EndTooltip') end
	imgui.IsItemHovered = function() return false end
	imgui.GetContentRegionAvail = function() return imgui.ImVec2(400, 300) end
	imgui.CalcTextSize = function(text) return imgui.ImVec2(#tostring(text) * 7, 14) end
	imgui.PushStyleColor = function() record('PushStyleColor') track('PushStyleColor') end
	imgui.PopStyleColor = function() record('PopStyleColor') track('PopStyleColor') end
	imgui.ShowStyleEditor = function() end

	package.preload['imgui'] = function() return imgui end
	package.loaded['imgui'] = nil
	return imgui
end

--[[
	Deixa o binding no estilo mimgui: sem ImBool/ImInt/ImFloat/ImBuffer/ImVec2
	(nesse binding tudo isso e cdata de `imgui.new.*`). Devolve o que foi
	guardado para o teste poder restaurar.
]]
function M.useMimguiStyle()
	local imgui = M.imgui
	if not imgui then return nil end
	local saved = {}
	local names = { 'ImBool', 'ImInt', 'ImFloat', 'ImDouble', 'ImBuffer', 'ImVec2', 'ImVec3', 'ImVec4' }
	for i = 1, #names do
		saved[names[i]] = imgui[names[i]]
		imgui[names[i]] = nil
	end
	local function box(v) return { [0] = v } end
	imgui.new = {
		bool = function(v) return box(v and true or false) end,
		int = function(v) return box(math.floor(tonumber(v) or 0)) end,
		float = function(v) return box(tonumber(v) or 0) end,
		ImVec2 = function(x, y) return { x = x or 0, y = y or 0 } end,
		ImVec4 = function(r, g, b, a) return { x = r or 0, y = g or 0, z = b or 0, w = a or 0 } end,
	}
	return saved
end

--- Restaura o binding para o estilo Moon ImGui (Im* chamaveis, sem new.*).
function M.restoreImGuiStyle(saved)
	local imgui = M.imgui
	if not imgui or not saved then return end
	for name, value in pairs(saved) do imgui[name] = value end
	imgui.new = nil
end

--- Avanca o "tempo" do mock: aplica teclas pressionadas por um tick.
function M.pressKey(key)
	M.keyJustPressed[key] = true
	M.keyState[key] = true
end

function M.releaseKeys()
	M.keyJustPressed = {}
end

--- Atualiza os globais do jogador (o MoonLoader faz isso sozinho no jogo).
function M.refreshPlayer()
	_G.PLAYER_HANDLE = M.playerHandle
	_G.PLAYER_PED = M.playerPedHandle
	_G.PLAYER_ACTOR = M.playerPedHandle
	_G.PLAYER_CHAR = M.playerPedHandle
end

--- Simula a ausencia do jogador (jogo carregando, morto, etc).
function M.setPlayerPed(ped)
	M.playerPedHandle = ped
	M.refreshPlayer()
end

function M.reset()
	M.renderCalls = {}
	M.chatLines = {}
	M.keyState = {}
	M.keyJustPressed = {}
	M.resetImgui()
	M.uiStack = {}
	-- jogador de volta ao normal (os testes podem ter simulado ausencia)
	M.playerHandle = 0
	M.playerPedHandle = 2495
	M.pedExists = true
	M.playerPlaying = true
	M.gamePaused = false
	M.badHandleCalls = 0
	M.pixelsPerMeterZ = 0
	M.cameraPos = nil
	M.lineOfSightClear = nil
	M.lineOfSightCalls = 0
	M.cameraCalls = 0
	M.gameSpaceScale = 1.0
	M.refreshPlayer()
end

return M
