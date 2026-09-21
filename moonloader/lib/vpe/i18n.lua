--[[
	Visual Path Editor - vpe.i18n
	Internacionalizacao (PT-BR e EN). Todas as mensagens da interface e da
	validacao saem daqui, para que o idioma possa ser trocado no menu.
]]

local M = {}

M.languages = {
	{ code = 'pt', name = 'Portugues (BR)' },
	{ code = 'en', name = 'English' },
}

M.lang = 'pt'
M.dicts = {}
M._loaded = false

local function loadDictionaries()
	if M._loaded then return end
	M._loaded = true
	local okPt, pt = pcall(require, 'vpe.lang.pt')
	if okPt and type(pt) == 'table' then M.dicts.pt = pt else M.dicts.pt = {} end
	local okEn, en = pcall(require, 'vpe.lang.en')
	if okEn and type(en) == 'table' then M.dicts.en = en else M.dicts.en = {} end
end

--- Define o idioma ('pt' ou 'en').
function M.setLang(code)
	loadDictionaries()
	if not M.dicts[code] then return false end
	M.lang = code
	return true
end

function M.getLang()
	return M.lang
end

--- Traduz uma chave, aplicando string.format quando houver argumentos.
function M.t(key, ...)
	loadDictionaries()
	local dict = M.dicts[M.lang] or M.dicts.pt or {}
	local text = dict[key]
	if text == nil then
		text = (M.dicts.en or {})[key]
	end
	if text == nil then
		text = '[' .. tostring(key) .. ']'
	end
	if select('#', ...) > 0 then
		local ok, formatted = pcall(string.format, text, ...)
		if ok then return formatted end
	end
	return text
end

--- Lista de chaves ausentes em algum idioma (usada nos testes).
function M.missingKeys()
	loadDictionaries()
	local missing = {}
	for _, code in ipairs({ 'pt', 'en' }) do
		local dict = M.dicts[code] or {}
		for key, value in pairs(dict) do
			if type(value) ~= 'string' then
				missing[#missing + 1] = string.format('%s: valor invalido em %s', code, key)
			end
		end
	end
	local pt = M.dicts.pt or {}
	local en = M.dicts.en or {}
	for key in pairs(pt) do
		if en[key] == nil then missing[#missing + 1] = 'en: falta ' .. key end
	end
	for key in pairs(en) do
		if pt[key] == nil then missing[#missing + 1] = 'pt: falta ' .. key end
	end
	table.sort(missing)
	return missing
end

--- Todas as chaves conhecidas (para a tela de testes).
function M.keys()
	loadDictionaries()
	local list = {}
	for key in pairs(M.dicts.pt or {}) do list[#list + 1] = key end
	table.sort(list)
	return list
end

return M
