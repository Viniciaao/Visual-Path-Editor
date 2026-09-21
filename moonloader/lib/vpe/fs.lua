--[[
	Visual Path Editor - vpe.fs
	Acesso a arquivos e pastas. Usa as funcoes do MoonLoader quando existem
	e cai para a biblioteca 'io' do Lua (que tambem esta disponivel no MoonLoader).

	Todas as funcoes sao defensivas: nunca lancam erro, devolvem nil/false + mensagem.
]]

local M = {}

--- Estamos no Windows? (no Windows package.config comeca com '\\')
M.IS_WINDOWS = type(package) == 'table' and type(package.config) == 'string'
	and package.config:sub(1, 1) == '\\'

--- "NUL" no Windows, /dev/null no resto: redirecionar para 'nul' no Linux
--- cria um arquivo chamado 'nul' na pasta atual.
local NULL_DEVICE = M.IS_WINDOWS and 'nul' or '/dev/null'

--- Escreve "... > NUL 2> NUL" (ou /dev/null) para silenciar um comando.
local function quiet()
	return ' > ' .. NULL_DEVICE .. ' 2> ' .. NULL_DEVICE
end

--------------------------------------------------------------------------------
-- Localizacao da pasta do jogo
--------------------------------------------------------------------------------

M._gameDir = nil

local function dirLooksLikeGame(dir)
	if type(dir) ~= 'string' or dir == '' then return false end
	local d = dir:gsub('\\', '/'):gsub('/+$', '')
	if d == '' then return false end
	local function probe(p)
		local full = d .. '/' .. p
		if type(doesFileExist) == 'function' then
			local ok, res = pcall(doesFileExist, full)
			if ok and res then return true end
		end
		local f = io.open(full, 'rb')
		if f then f:close() return true end
		return false
	end
	return probe('models/gta3.img') or probe('gta_sa.exe') or probe('moonloader')
end

--- Descobre a pasta raiz do GTA. Tenta varias estrategias e valida o resultado.
function M.gameDir()
	if M._gameDir then return M._gameDir end

	local candidates = {}
	if type(getWorkingDirectory) == 'function' then
		local ok, dir = pcall(getWorkingDirectory)
		if ok and type(dir) == 'string' then candidates[#candidates + 1] = dir end
	end
	if type(getGameDirectory) == 'function' then
		local ok, dir = pcall(getGameDirectory)
		if ok and type(dir) == 'string' then candidates[#candidates + 1] = dir end
	end
	if type(thisScript) == 'function' then
		local ok, s = pcall(thisScript)
		if ok and type(s) == 'table' and type(s.path) == 'string' then
			local dir = s.path:match('^(.*)[\\/][^\\/]*$')
			if dir then
				-- <jogo>/moonloader/vpe.lua -> <jogo>
				local parent = dir:match('^(.*)[\\/][^\\/]*$')
				if parent and dir:lower():find('moonloader') then
					candidates[#candidates + 1] = parent
				end
				candidates[#candidates + 1] = dir
			end
		end
	end
	candidates[#candidates + 1] = '.'
	candidates[#candidates + 1] = '..'

	for i = 1, #candidates do
		if dirLooksLikeGame(candidates[i]) then
			M._gameDir = (candidates[i]:gsub('\\', '/'):gsub('/+$', ''))
			if M._gameDir == '' then M._gameDir = '.' end
			return M._gameDir
		end
	end

	-- ultimo recurso: pasta atual
	M._gameDir = '.'
	return M._gameDir
end

--- Caminho absoluto a partir de um caminho relativo ao jogo.
function M.gamePath(...)
	return M.join(M.gameDir(), ...)
end

--------------------------------------------------------------------------------
-- Manipulacao de caminhos
--------------------------------------------------------------------------------

function M.join(a, b, ...)
	if b == nil then return (tostring(a or ''):gsub('\\', '/')) end
	local left = tostring(a or ''):gsub('\\', '/'):gsub('[/]+$', '')
	local right = tostring(b or ''):gsub('\\', '/'):gsub('^[/]+', '')
	local out
	if left == '' then out = right else out = left .. '/' .. right end
	if select('#', ...) > 0 then return M.join(out, ...) end
	return out
end

function M.basename(path)
	return (tostring(path or ''):match('[^/\\]+$')) or ''
end

function M.dirname(path)
	local p = tostring(path or ''):gsub('[/\\]+$', '')
	return (p:match('^(.*)[/\\][^/\\]*$')) or '.'
end

function M.extension(path)
	return (tostring(path or ''):match('%.([%w]+)$')) or ''
end

-------------------------------------------------------------------------------
-- Consultas
-------------------------------------------------------------------------------

--- Roda um comando no shell. Devolve true/false (false tambem quando o shell
--- nao esta disponivel), aceitando tanto o retorno do Lua 5.1 (numero) quanto
--- o do Lua 5.2+ (ok, "exit", codigo).
function M.shell(command)
	local status = M.shellStatus(command)
	return status == true
end

--- Igual a M.shell, mas devolve nil quando nao existe shell nenhum
--- (assim da para diferenciar "o comando respondeu nao" de "nao deu para perguntar").
function M.shellStatus(command)
	if command == nil or type(os.execute) ~= 'function' then return nil end
	local ok, kind, code = os.execute(command)
	if type(ok) == 'number' then return ok == 0 end      -- Lua 5.1
	if type(code) == 'number' then return code == 0 end   -- Lua 5.2+
	if ok == nil and kind == nil then return nil end
	return ok == true
end

function M.exists(path)
	if type(doesFileExist) == 'function' then
		local ok, res = pcall(doesFileExist, path)
		if ok and res then return true end
	end
	local f = io.open(path, 'rb')
	if f then f:close() return true end
	return false
end

--- Diz se o caminho e uma pasta. Tenta a API do MoonLoader e, se ela nao
--- existir (ou falhar), pergunta ao shell; por ultimo tenta listar o conteudo.
function M.isDir(path)
	if path == nil or path == '' then return false end
	local normalized = tostring(path):gsub('\\', '/'):gsub('/+$', '')

	local looksWindows = normalized:find('\\') ~= nil or normalized:match('^%a:') ~= nil

	if type(doesDirectoryExist) == 'function' then
		local ok, res = pcall(doesDirectoryExist, normalized)
		if ok and res then return true end
	end

	-- Windows: "<pasta>\NUL" so existe quando o caminho e uma pasta
	if looksWindows then
		local status = M.shellStatus(string.format('if exist "%s\\NUL" (exit 0) else (exit 1)', path))
		if status ~= nil then return status end
	else
		-- POSIX (usado no desenvolvimento e nos testes)
		local status = M.shellStatus(string.format('test -d "%s"', normalized))
		if status ~= nil then return status end
	end

	-- ultimo recurso (sem shell): se a API de listagem responder, e uma pasta
	if type(getDirectoryFiles) == 'function' then
		local ok, res = pcall(getDirectoryFiles, normalized)
		if ok and type(res) == 'table' then return true end
	end

	return false
end

function M.size(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local ok, size = pcall(function()
		f:seek('end')
		return f:seek()
	end)
	f:close()
	if not ok then return nil end
	return size
end

function M.mtime(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	f:close()
	-- Lua puro nao expoe mtime; usamos o horario atual como referencia
	return os.time()
end

-------------------------------------------------------------------------------
-- Leitura / escrita
-------------------------------------------------------------------------------

function M.readAll(path)
	local f, err = io.open(path, 'rb')
	if not f then return nil, tostring(err) end
	local data, rerr = f:read('*a')
	f:close()
	if not data then return nil, tostring(rerr) end
	return data
end

--- Le apenas 'size' bytes a partir de 'offset' (1-based offset).
function M.readBytes(path, offset, size)
	local f, err = io.open(path, 'rb')
	if not f then return nil, tostring(err) end
	if offset and offset > 0 then f:seek('set', offset) end
	local data = f:read(size or '*a')
	f:close()
	if not data then return nil, 'leitura falhou' end
	return data
end

function M.writeAll(path, data)
	local dir = M.dirname(path)
	if dir and dir ~= '' and dir ~= '.' then M.mkdir(dir) end
	local f, err = io.open(path, 'wb')
	if not f then return false, tostring(err) end
	local ok, werr = f:write(data)
	f:close()
	if not ok then return false, tostring(werr) end
	return true
end

function M.appendLine(path, line)
	local dir = M.dirname(path)
	if dir and dir ~= '' and dir ~= '.' then M.mkdir(dir) end
	local f, err = io.open(path, 'a')
	if not f then return false, tostring(err) end
	f:write(line .. '\n')
	f:close()
	return true
end

function M.remove(path)
	local ok = os.remove and os.remove(path)
	return ok ~= nil and ok ~= false
end

function M.rename(from, to)
	if not os.rename then return false, 'os.rename indisponivel' end
	M.mkdir(M.dirname(to))
	local ok, err = os.rename(from, to)
	if not ok then return false, tostring(err) end
	return true
end

function M.copy(from, to)
	local data, err = M.readAll(from)
	if not data then return false, err end
	return M.writeAll(to, data)
end

--- Cria pastas recursivamente ("a/b/c").
function M.mkdir(path)
	if path == nil or path == '' or path == '.' then return true end
	local normalized = tostring(path):gsub('\\', '/'):gsub('/+$', '')
	if normalized == '' or normalized == '/' then return true end
	if M.isDir(normalized) then return true end

	-- 1) API do MoonLoader
	if type(createDirectory) == 'function' then
		pcall(createDirectory, normalized)
		if M.isDir(normalized) then return true end
	end

	-- 2) shell: no POSIX "-p" cria os niveis; no Windows o "mkdir" do cmd tambem
	if M.shell('mkdir -p "' .. normalized .. '" >/dev/null 2>&1') and M.isDir(normalized) then
		return true
	end
	local winPath = normalized:gsub('/', '\\')
	if M.shell('mkdir "' .. winPath .. '"' .. quiet()) and M.isDir(normalized) then
		return true
	end

	-- 3) nivel por nivel
	local prefix = ''
	local pos = 1
	if normalized:match('^%a:') then
		prefix = normalized:sub(1, 2)
		pos = 3
	elseif normalized:sub(1, 1) == '/' then
		prefix = '/'
		pos = 2
	end
	local current = prefix
	while pos <= #normalized do
		local part = normalized:sub(pos):match('^([^/]*)')
		pos = pos + #part + 1
		if part ~= '' then
			current = (current == '/' and '/' or (current == '' and '' or current .. '/')) .. part
			if not M.isDir(current) then
				if type(createDirectory) == 'function' then pcall(createDirectory, current) end
				M.shell('mkdir -p "' .. current .. '" >/dev/null 2>&1')
			end
		end
	end
	if M.isDir(normalized) then return true end
	return false, 'nao foi possivel criar a pasta ' .. tostring(path)
end

-------------------------------------------------------------------------------
-- Listagem de diretorios
-------------------------------------------------------------------------------

local OK_MARKER = '__VPE_LIST_OK__'

local function tempPath()
	local name
	if type(os.tmpname) == 'function' then
		local ok, result = pcall(os.tmpname)
		if ok and type(result) == 'string' and result ~= '' then name = result end
	end
	if not name then
		name = M.join(M.gamePath('moonloader', 'VisualPath'), 'list_tmp.txt')
		M.mkdir(M.dirname(name))
	end
	return name
end

--- Lista o conteudo de um diretorio: array de {name=, path=, isDir=} ou nil.
--- 'quick' evita resolver isDir de cada filho (usado por M.isDir, sem recursao).
--- Estrategias: getDirectoryFiles (MoonLoader) -> shell com redirecionamento.
function M.listDir(path, quick)
	if path == nil or path == '' then return nil end
	path = tostring(path):gsub('\\', '/'):gsub('/+$', '')
	if path == '' then path = '.' end

	if type(getDirectoryFiles) == 'function' then
		local ok, res = pcall(getDirectoryFiles, path)
		if ok and type(res) == 'table' and #res > 0 then
			local out = {}
			for i = 1, #res do
				local name = tostring(res[i])
				if name ~= '.' and name ~= '..' then
					local full = M.join(path, name)
					local isDirFlag2 = nil
					if not quick then isDirFlag2 = M.isDir(full) end
					out[#out + 1] = { name = name, path = full, isDir = isDirFlag2 }
				end
			end
			if #out > 0 then return out end
		end
	end

	local tmp = tempPath()
	local winPath = path:gsub('/', '\\')
	local ls = 'ls -1p "' .. path .. '" > "' .. tmp .. '" 2> ' .. NULL_DEVICE .. ' && echo ' .. OK_MARKER .. ' >> "' .. tmp .. '"'
	local dir = 'dir /b /a "' .. winPath .. '" > "' .. tmp .. '" 2> ' .. NULL_DEVICE .. ' && echo ' .. OK_MARKER .. ' >> "' .. tmp .. '"'
	-- a ordem muda conforme a plataforma (o comando nativo vem primeiro)
	local commands = M.IS_WINDOWS and { dir, ls } or { ls, dir }
	for i = 1, #commands do
		if M.shell(commands[i]) then
			local text = M.readAll(tmp)
			M.remove(tmp)
			if text then
				local out = {}
				local found = false
				for line in text:gmatch('[^\r\n]+') do
					if line == OK_MARKER then
						found = true
					else
						local name = line:match('^%s*(.-)%s*$')
						local isDirFlag = name:sub(-1) == '/'
						if isDirFlag then name = name:sub(1, -2) end
						if name ~= '' and name ~= '.' and name ~= '..' then
							local full = M.join(path, name)
							local isDirRes = isDirFlag and true or nil
							if isDirRes == nil and not quick then isDirRes = M.isDir(full) end
							out[#out + 1] = { name = name, path = full, isDir = isDirRes }
						end
					end
				end
				if found then return out end
			end
		end
	end

	return nil
end

--- Percorre a arvore de 'root' procurando por arquivos que casem com 'matcher'.
--- matcher(path, name) -> true/false. Limite de profundidade evita varrer o jogo inteiro.
function M.walk(root, depth, matcher, out, visited)
	if depth < 0 then return out or {} end
	out = out or {}
	visited = visited or {}
	local entries = M.listDir(root)
	if not entries then return out end
	for i = 1, #entries do
		local e = entries[i]
		if e.isDir then
			if depth > 0 and not visited[e.path] then
				visited[e.path] = true
				M.walk(e.path, depth - 1, matcher, out, visited)
			end
		else
			if matcher(e.path, e.name) then out[#out + 1] = e.path end
		end
	end
	return out
end

return M
