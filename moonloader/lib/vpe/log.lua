--[[
	Visual Path Editor - vpe.log
	Log em arquivo + buffer em memoria (mostrado na janela "Log" do mod).
	Nunca lanca erro: se nao conseguir gravar, apenas ignora.
]]

local M = {}

local MAX_LINES = 800

M.path = nil
M.lines = {}
M.count = 0
M.debugEnabled = false

local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
local LEVEL_TAG = { DEBUG = '[dbg]', INFO = '[inf]', WARN = '[AVS]', ERROR = '[ERR]' }

--- Define o arquivo de log e escreve o cabecalho da sessao.
function M.init(path, version)
	M.path = path
	M.lines = {}
	M.count = 0
	M.write('INFO', '==================== Visual Path Editor v%s ====================', tostring(version or '?'))
	M.write('INFO', 'Dia: %s', os.date('%Y-%m-%d %H:%M:%S'))
end

local function pushLine(text)
	M.lines[#M.lines + 1] = text
	if #M.lines > MAX_LINES then
		table.remove(M.lines, 1)
	end
end

function M.write(level, fmt, ...)
	level = LEVELS[level] and level or 'INFO'
	if level == 'DEBUG' and not M.debugEnabled then return end

	local message
	if select('#', ...) > 0 then
		local ok, formatted = pcall(string.format, fmt, ...)
		message = ok and formatted or tostring(fmt)
	else
		message = tostring(fmt)
	end

	local line = string.format('%s %s %s', os.date('%H:%M:%S'), LEVEL_TAG[level], message)
	pushLine(line)
	M.count = M.count + 1

	if M.path then
		pcall(function()
			local f = io.open(M.path, 'a')
			if f then
				f:write(line .. '\n')
				f:close()
			end
		end)
	end

	-- espelho no console do MoonLoader (apenas avisos e erros, sem acentos)
	if level == 'WARN' or level == 'ERROR' then
		pcall(print, '[VPE] ' .. tostring(message))
	end
	return line
end

function M.debug(fmt, ...) M.write('DEBUG', fmt, ...) end
function M.info(fmt, ...) M.write('INFO', fmt, ...) end
function M.warn(fmt, ...) M.write('WARN', fmt, ...) end
function M.error(fmt, ...) M.write('ERROR', fmt, ...) end

function M.getLines()
	return M.lines
end

function M.clear()
	M.lines = {}
end

--- Grava um bloco multilinha (usado nos relatorios de salvamento).
function M.writeBlock(level, header, bodyLines)
	M.write(level, header)
	for i = 1, #bodyLines do
		M.write(level, '    %s', bodyLines[i])
	end
end

return M
