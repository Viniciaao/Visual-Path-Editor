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
	_G.renderFontDrawText = function(font, text, x, y, color) M.renderCalls[#M.renderCalls + 1] = { 'text', text, x, y, color } end
	_G.renderGetFontDrawTextLength = function(font, text) return #tostring(text) * 6 end
	_G.renderGetFontDrawHeight = function(font) return 12 end
	_G.getScreenResolution = function() return M.screen.width, M.screen.height end

	-- 3D -> 2D (projecao simples e deterministica, so para os testes)
	_G.convert3DCoordsToScreen = function(x, y, z)
		local sx = M.screen.width / 2 + (x - M.playerPos.x) * 2
		local sy = M.screen.height / 2 - (y - M.playerPos.y) * 2
		return sx, sy
	end
	_G.convertScreenCoordsToWorld3D = function(sx, sy, depth)
		local x = M.playerPos.x + (sx - M.screen.width / 2) / 2
		local y = M.playerPos.y - (sy - M.screen.height / 2) / 2
		local z = M.playerPos.z + depth * 100
		return x, y, z
	end
	_G.isPointOnScreen = function(x, y, z, radius) return true end

	-- mundo
	_G.getCharCoordinates = function() return M.playerPos.x, M.playerPos.y, M.playerPos.z end
	_G.setCharCoordinates = function(char, x, y, z) M.playerPos.x, M.playerPos.y, M.playerPos.z = x, y, z end
	_G.setPlayerCoordinates = _G.setCharCoordinates
	_G.getGroundZFor3dCoord = function() return M.groundZ end
	_G.getWaterHeightAtCoords = function() return M.waterZ end
	_G.loadScene = function() return true end
	_G.requestCollision = function() end
	_G.printStringNow = function() end
	_G.printHelpString = function() end

	-- teclado
	_G.isKeyDown = function(key) return M.keyState[key] == true end
	_G.wasKeyPressed = function(key) return M.keyJustPressed[key] == true end
	_G.isKeyJustPressed = _G.wasKeyPressed
	_G.getCursorPos = function() return M.cursorX or 0, M.cursorY or 0 end
	_G.convertWindowScreenCoordsToGameScreenCoords = function(x, y) return x, y end
	_G.convertGameScreenCoordsToWindowScreenCoords = function(x, y) return x, y end

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
		return false
	end

	imgui.Process = false
	imgui.LockPlayer = false
	imgui.ShowCursor = false
	imgui.Cond = { Always = 1, Once = 2, FirstUseEver = 4 }
	imgui.WindowFlags = { NoTitleBar = 1, NoResize = 2, NoMove = 4 }
	imgui.Col = { Text = 0, TextDisabled = 1, WindowBg = 2, Button = 3, FrameBg = 4 }

	imgui.ImBool = function(v) return { v = v and true or false } end
	imgui.ImInt = function(v) return { v = math.floor(tonumber(v) or 0) } end
	imgui.ImFloat = function(v) return { v = tonumber(v) or 0 } end
	imgui.ImDouble = imgui.ImFloat
	imgui.ImBuffer = function(size) return { size = tonumber(size) or 0, v = string.rep('\0', tonumber(size) or 0) } end
	imgui.ImVec2 = function(x, y) return { x = tonumber(x) or 0, y = tonumber(y) or 0 } end
	imgui.ImVec3 = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
	imgui.ImVec4 = function(x, y, z, w) return { x = x or 0, y = y or 0, z = z or 0, w = w or 0 } end

	imgui.GetIO = function() return { WantCaptureMouse = false, WantCaptureKeyboard = false } end
	imgui.Begin = function(title) record('Begin', title) track('Begin') return true end
	imgui.End = function() record('End') track('End') end
	imgui.Text = function(fmt, ...) record('Text', fmtArgs(fmt, ...)) end
	imgui.TextColored = function(color, fmt, ...) record('TextColored', fmtArgs(fmt, ...)) end
	imgui.TextWrapped = function(fmt, ...) record('Text', fmtArgs(fmt, ...)) return true end
	imgui.TextDisabled = function(fmt, ...) record('Text', fmtArgs(fmt, ...)) end
	imgui.BulletText = function(fmt, ...) record('BulletText', fmtArgs(fmt, ...)) end
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
	imgui.SetTooltip = function(fmt, ...) record('SetTooltip', fmtArgs(fmt, ...)) end
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

--- Avanca o "tempo" do mock: aplica teclas pressionadas por um tick.
function M.pressKey(key)
	M.keyJustPressed[key] = true
	M.keyState[key] = true
end

function M.releaseKeys()
	M.keyJustPressed = {}
end

function M.reset()
	M.renderCalls = {}
	M.keyState = {}
	M.keyJustPressed = {}
	M.resetImgui()
	M.uiStack = {}
end

return M
