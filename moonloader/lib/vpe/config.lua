--[[
	Visual Path Editor - vpe.config
	Configuracao do mod (moonloader/config/VisualPathEditor.ini).
	Leitor/escritor de INI simples e proprio (nao depende de bibliotecas externas).
]]

local fs = require 'vpe.fs'
local util = require 'vpe.util'
local log = require 'vpe.log'

local M = {}

M.path = nil

M.defaults = {
	geral = {
		idioma = 'pt',
		debug = false,
		carregar_vizinhas = true,
		areas_extras = '',
	},
	render = {
		ativo = true,
		distancia = 250.0,
		max_linhas = 900,
		mostrar_nodes = true,
		mostrar_links = true,
		mostrar_navis = true,
		mostrar_peds = true,
		mostrar_barcos = true,
		mostrar_hud = true,
		altura_nodes = 1.0,
		tamanho_node = 6.0,
		cor_veh = '#FFFFFF',
		cor_ped = '#26E04D',
		cor_boat = '#3DA5FF',
		cor_navi = '#1BE4E4',
		cor_selecionado = '#FFD200',
		cor_link = '#8C8C8C',
		cor_hover = '#FF5A5A',
	},
	edicao = {
		espelhar_links = true,
		recalcular_comprimentos = true,
		criar_navi_automatico = false,
		passo_fino = 0.125,
		passo_normal = 1.0,
		passo_grosso = 8.0,
		angulo_navi_passo = 15,
		travar_z = false,
	},
	salvar = {
		pasta_export = 'modloader/VisualPath/export',
		pasta_img = 'modloader/VisualPath/gta3.img',
		pasta_backup = 'modloader/VisualPath/backup',
		escrever_img = true,
		escrever_export = true,
		backup = true,
		limpar_cache_modloader = true,
		tambem_gta3img_direto = false,
	},
	map = {
		ativo = false,
		tamanho = 320,
		raio = 200.0,
		lado = 'direita',
		modo = 'standard',
	},
	teclas = {
		abrir_menu = 'F7',
		ligar_render = 'F8',
		validar = 'F9',
		salvar = 'F5',
		recarregar = 'F6',
		desfazer = 'CTRL_Z',
		refazer = 'CTRL_Y',
		criar_node = 'INSERT',
		apagar_node = 'DELETE',
		ir_para_node = 'G',
		node_no_jogador = 'P',
		node_na_mira = 'L',
		snap_solo = 'K',
		proximo_node = 'TAB',
		criar_link = 'ENTER',
		marcar_origem = 'CTRL_L',
	},
}

local ORDER = { 'geral', 'render', 'edicao', 'salvar', 'map', 'teclas' }

--------------------------------------------------------------------------------
-- Leitura/escrita de INI
--------------------------------------------------------------------------------

local function parseIni(text)
	local ini = {}
	local section = 'geral'
	ini[section] = {}
	for line in tostring(text):gmatch('[^\r\n]+') do
		local trimmed = line:match('^%s*(.-)%s*$')
		if trimmed ~= '' and not trimmed:match('^[;%[]') then
			local header = trimmed:match('^%[([^%]]+)%]$')
			if header then
				section = header
				ini[section] = ini[section] or {}
			else
				local key, value = trimmed:match('^([^=]+)=(.*)$')
				if key then
					ini[section][key:match('^%s*(.-)%s*$')] = value:match('^%s*(.-)%s*$')
				end
			end
		end
	end
	return ini
end

local function serializeIni(cfg)
	local out = {}
	out[#out + 1] = '; Visual Path Editor - configuracao'
	out[#out + 1] = '; As cores usam o formato #RRGGBB. Distancias em unidades do jogo.'
	out[#out + 1] = ''
	local sections = {}
	for name in pairs(cfg) do sections[#sections + 1] = name end
	table.sort(sections, function(a, b)
		local ia = util.indexOf(ORDER, a) or 99
		local ib = util.indexOf(ORDER, b) or 99
		if ia ~= ib then return ia < ib end
		return a < b
	end)
	for _, name in ipairs(sections) do
		out[#out + 1] = string.format('[%s]', name)
		local keys = util.sortedKeys(cfg[name])
		for _, key in ipairs(keys) do
			local value = cfg[name][key]
			if type(value) == 'boolean' then value = value and 'true' or 'false' end
			out[#out + 1] = string.format('%s = %s', key, tostring(value))
		end
		out[#out + 1] = ''
	end
	return table.concat(out, '\n')
end

local function coerce(value, default)
	if type(default) == 'number' then
		return tonumber(value) or default
	elseif type(default) == 'boolean' then
		local v = tostring(value):lower()
		if v == 'true' or v == '1' or v == 'sim' then return true end
		if v == 'false' or v == '0' or v == 'nao' then return false end
		return default
	end
	return tostring(value)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function M.load()
	local cfg = util.deepcopy(M.defaults)
	M.path = fs.gamePath('moonloader', 'config', 'VisualPathEditor.ini')
	local text = fs.readAll(M.path)
	if text then
		local ini = parseIni(text)
		for section, values in pairs(ini) do
			cfg[section] = cfg[section] or {}
			for key, value in pairs(values) do
				local default = cfg[section][key]
				if default == nil then default = M.defaults[section] and M.defaults[section][key] end
				if default ~= nil then
					cfg[section][key] = coerce(value, default)
				else
					cfg[section][key] = value
				end
			end
		end
	else
		log.info('config: arquivo nao encontrado, criando padrao em %s', tostring(M.path))
		M.save(cfg)
	end
	M.current = cfg
	return cfg
end

function M.save(cfg)
	cfg = cfg or M.current
	if not cfg then return false end
	M.current = cfg
	M.path = M.path or fs.gamePath('moonloader', 'config', 'VisualPathEditor.ini')
	local ok, err = fs.writeAll(M.path, serializeIni(cfg))
	if not ok then log.warn('config: falha ao salvar: %s', tostring(err)) end
	return ok
end

function M.get(section, key, fallback)
	local cfg = M.current or M.load()
	local s = cfg[section]
	if not s then return fallback end
	local v = s[key]
	if v == nil then return fallback end
	return v
end

function M.set(section, key, value)
	local cfg = M.current or M.load()
	cfg[section] = cfg[section] or {}
	cfg[section][key] = value
end

--- Codigos VK usados quando a biblioteca 'vkeys' do MoonLoader nao esta disponivel.
M.VK_FALLBACK = {
	VK_LBUTTON = 1, VK_RBUTTON = 2, VK_BACK = 8, VK_TAB = 9, VK_RETURN = 13, VK_SHIFT = 16,
	VK_CONTROL = 17, VK_MENU = 18, VK_PAUSE = 19, VK_ESCAPE = 27, VK_SPACE = 32,
	VK_LEFT = 37, VK_UP = 38, VK_RIGHT = 39, VK_DOWN = 40, VK_INSERT = 45, VK_DELETE = 46,
	VK_NUMPAD0 = 96, VK_NUMPAD1 = 97, VK_NUMPAD2 = 98, VK_NUMPAD3 = 99, VK_NUMPAD4 = 100,
	VK_NUMPAD5 = 101, VK_NUMPAD6 = 102, VK_NUMPAD7 = 103, VK_NUMPAD8 = 104, VK_NUMPAD9 = 105,
	VK_F1 = 112, VK_F2 = 113, VK_F3 = 114, VK_F4 = 115, VK_F5 = 116, VK_F6 = 117,
	VK_F7 = 118, VK_F8 = 119, VK_F9 = 120, VK_F10 = 121, VK_F11 = 122, VK_F12 = 123,
	VK_0 = 48, VK_1 = 49, VK_2 = 50, VK_3 = 51, VK_4 = 52, VK_5 = 53, VK_6 = 54,
	VK_7 = 55, VK_8 = 56, VK_9 = 57,
	VK_A = 65, VK_B = 66, VK_C = 67, VK_D = 68, VK_E = 69, VK_F = 70, VK_G = 71, VK_H = 72,
	VK_I = 73, VK_J = 74, VK_K = 75, VK_L = 76, VK_M = 77, VK_N = 78, VK_O = 79, VK_P = 80,
	VK_Q = 81, VK_R = 82, VK_S = 83, VK_T = 84, VK_U = 85, VK_V = 86, VK_W = 87, VK_X = 88,
	VK_Y = 89, VK_Z = 90,
}

--- Converte o valor de uma tecla ("F7", "CTRL_Z", "CTRL_L") em codigo VK.
function M.keyCode(value, vkeys)
	local name = tostring(value):upper():gsub('%s', '')
	local ctrl = false
	local alt = false
	local shift = false
	name = name:gsub('^CTRL%+', function() ctrl = true return '' end)
	name = name:gsub('^ALT%+', function() alt = true return '' end)
	name = name:gsub('^SHIFT%+', function() shift = true return '' end)
	if name == '' then name = 'F7' end

	local vk = (vkeys and vkeys['VK_' .. name]) or M.VK_FALLBACK['VK_' .. name]
	if not vk and #name == 1 then
		vk = string.byte(name)
	end
	if not vk and tonumber(name) then
		vk = tonumber(name)
	end
	return vk, { ctrl = ctrl, alt = alt, shift = shift }
end

return M
