--[[
	Visual Path Editor (Lua) - editor visual de path nodes do GTA San Andreas
	----------------------------------------------------------------------------
	Inspirado no "SA WIP Visual Path Editor 1.0" (Lightvelox, CLEO), reescrito em
	Lua com Moon ImGui, validacao antes de gravar e gravacao em pasta de mod
	(o gta3.img original nunca e alterado).

	Requisitos:
	  * MoonLoader 0.26.x
	  * Moon ImGui 1.1.5 (opcional para o menu, mas recomendado)
	  * MoonAdditions nao e obrigatorio; o mod usa so a API do MoonLoader.

	Arquivos:
	  moonloader\VisualPathEditor.lua      (este script)
	  moonloader\lib\vpe\*.lua             (modulos)
	  moonloader\config\VisualPathEditor.ini (gerado no primeiro uso)
	  moonloader\VisualPathEditor.log      (log)

	Os arquivos nodes*.dat sao gravados em:
	  modloader\VisualPath\gta3.img\nodesN.dat   (o jogo carrega daqui)
	  modloader\VisualPath\export\nodesN.dat     (copia de conferencia)
	  modloader\VisualPath\backup\nodesN.dat     (backup do original)
]]

script_name('Visual Path Editor')
script_author('Viniciaao')
script_version('1.0.7')
script_description('Editor visual dos path nodes (nodes*.dat) com validacao antes de salvar.')

--------------------------------------------------------------------------------
-- Carregamento dos modulos
--------------------------------------------------------------------------------

local appModule, app, core
local loadError

local function tryLoad()
	local ok, mod = pcall(require, 'vpe.app')
	if not ok then
		loadError = tostring(mod)
		return false
	end
	appModule = mod

	local okUi, ui = pcall(require, 'vpe.ui')
	if okUi then core = ui end
	return true
end

if not tryLoad() then
	-- Sem os modulos nao ha o que fazer: avisa no console e no log.
	error('Visual Path Editor: falha ao carregar vpe.app (' .. tostring(loadError) .. ')', 0)
end

--------------------------------------------------------------------------------
-- Loop principal
--------------------------------------------------------------------------------

local lastClock = 0

function main()
	app = appModule.new({})
	local okInit, initErr = pcall(function() app:init() end)
	if not okInit then
		if printStringNow then printStringNow('~r~Visual Path Editor: falha ao iniciar (' .. tostring(initErr) .. ')', 8000) end
		error('Visual Path Editor: falha ao iniciar: ' .. tostring(initErr), 0)
	end

	if app.log then
		app.log.info('Visual Path Editor %s carregado (moonloader %s)', app.version,
			tostring(getMoonloaderVersion and getMoonloaderVersion() or '?'))
	end

	if not app.ui or not app.ui.binding then
		if printStringNow then printStringNow('~y~Visual Path Editor: ~w~Moon ImGui nao encontrado (menu desativado)', 5000) end
	end

	local failures = 0
	lastClock = os.clock()

	while true do
		wait(0)
		local now = os.clock()
		local dt = now - lastClock
		lastClock = now
		if dt < 0 or dt > 1 then dt = 1 / 30 end

		-- Uma falha na interface (teste de tecla, mouse, painel) nao pode levar
		-- o desenho dos nodes junto: cada parte roda no seu proprio pcall.
		local ok, err = pcall(function()
			app:update(dt)
			app:followPlayerTick()
		end)
		if not ok then
			failures = failures + 1
			if app.log then app.log.error('loop (update): %s', tostring(err)) end
		end

		local okDraw, errDraw = pcall(function()
			-- o desenho no mundo precisa ser chamado a cada quadro
			app:drawWorld()
		end)
		if not okDraw then
			failures = failures + 1
			if app.log then app.log.error('loop (desenho): %s', tostring(errDraw)) end
		end

		if ok and okDraw then
			failures = 0
		elseif failures >= 5 then
			if printStringNow then
				printStringNow('~r~Visual Path Editor: erro repetido. Log: moonloader/VisualPathEditor.log', 8000)
			end
			break
		end
	end

	if app and app.onExit then pcall(function() app:onExit() end) end
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------

function onScriptTerminate(scr, quitGame)
	if scr == thisScript() and app and app.onExit then
		pcall(function() app:onExit() end)
	end
end

--- Mostra o resultado do autoteste no jogo (usado pelo menu/depuracao).
function showSelfTest()
	if not app then return nil end
	local ok, selftest = pcall(require, 'vpe.selftest')
	if not ok then return nil end
	local result = selftest.run(app, { write = false })
	if printStringNow then
		local text = string.format('~%s~Autoteste: ~w~%d teste(s), %d falha(s)',
			result.ok and 'g' or 'r', result.total, result.failed)
		printStringNow(text, 6000)
	end
	if app.log then
		for i = 1, #result.lines do app.log.info('%s', result.lines[i]) end
	end
	return result
end
