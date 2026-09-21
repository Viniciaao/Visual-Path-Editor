--[[
	Visual Path Editor - vpe.selftest
	Auto-verificacao do mod (roda no jogo e nos testes).

	O teste mais importante e o "round-trip": le o arquivo original, converte
	para a estrutura do editor, escreve de volta e compara BYTE A BYTE com o
	original. Se algo mudou sem o usuario ter editado nada, o editor esta
	corrompendo dados - e isso aparece no relatorio em vez de ir para o disco.
]]

local dat = require 'vpe.dat'
local fs = require 'vpe.fs'
local img = require 'vpe.img'
local log = require 'vpe.log'
local i18n = require 'vpe.i18n'

local M = {}

local T = i18n.t

local function add(report, name, ok, text)
	report.tests[#report.tests + 1] = { name = name, ok = ok and true or false, text = text }
	if not ok then report.failed = report.failed + 1 end
	if text and log then
		if ok then log.info('selftest %s: %s', name, text) else log.error('selftest %s: %s', name, text) end
	end
	return ok
end

--------------------------------------------------------------------------------
-- Testes
--------------------------------------------------------------------------------

function M.testEnvironment(app)
	local report = { tests = {}, failed = 0, checked = 0 }
	local gameDir = app.gameDir
	add(report, 'pasta do jogo', gameDir and fs.isDir(gameDir), tostring(gameDir))

	local imgPath = fs.gamePath('models', 'gta3.img')
	local imgOk = fs.exists(imgPath)
	local imgSize = (imgOk and fs.size(imgPath)) or 0
	add(report, 'gta3.img', imgOk, tostring(imgPath) .. (imgOk and '' or ' (nao encontrado)'))

	if imgOk then
		local archive, err = img.open(imgPath)
		if archive then
			local entries = #archive.entries
			add(report, 'leitura do gta3.img', true, string.format('%d entradas', entries))
			if entries == 0 then
				add(report, 'indice do gta3.img', true, 'arquivo sem entradas legiveis (imagem vazia?)')
			end
		elseif (imgSize or 0) < 40 then
			-- imagem vazia (8 bytes de cabecalho + nada): nao ha o que ler
			add(report, 'leitura do gta3.img', true, string.format('arquivo vazio (%d bytes) - ignorado', imgSize))
		else
			add(report, 'leitura do gta3.img', false, tostring(err))
		end
	end

	local modloaderDir = (app.sources and app.sources.modloaderDir) or fs.gamePath('modloader')
	add(report, 'pasta modloader', fs.isDir(modloaderDir), tostring(modloaderDir))
	return report
end

--- Confere que parse+serialize devolve exatamente os bytes originais.
function M.roundTrip(app, areaIds, options)
	options = options or {}
	local report = { tests = {}, failed = 0, checked = 0, mismatches = {} }
	local ids = areaIds or app.project:loadedAreas()

	for i = 1, #ids do
		local id = ids[i]
		local raw = app.originals and app.originals[id]
		if not raw then
			local data = app.sources:read(id)
			raw = data
		end
		if raw then
			report.checked = report.checked + 1
			local area, err = dat.parse(raw, id)
			if not area then
				add(report, 'area ' .. id, false, 'falha ao interpretar: ' .. tostring(err))
				report.mismatches[#report.mismatches + 1] = { id = id, reason = tostring(err) }
			else
				local bytes, serr = dat.serialize(area)
				if not bytes then
					add(report, 'area ' .. id, false, 'falha ao escrever: ' .. tostring(serr))
					report.mismatches[#report.mismatches + 1] = { id = id, reason = tostring(serr) }
				elseif bytes ~= raw then
					local sizeInfo = string.format('%d -> %d bytes', #raw, #bytes)
					add(report, 'area ' .. id, false, 'round-trip diferente (' .. sizeInfo .. ')')
					report.mismatches[#report.mismatches + 1] = { id = id, reason = sizeInfo, oldSize = #raw, newSize = #bytes }
				else
					add(report, 'area ' .. id, true, string.format('%d bytes identicos (%d nodes)', #bytes, #area.nodes))
					if options.write then M.testWrite(app, id, raw, report) end
				end
			end
		end
	end

	if report.checked == 0 then add(report, 'round-trip', false, 'nenhuma area carregada para testar') end
	return report
end

--- Grava uma copia de teste e le de volta (nao toca nos arquivos de destino).
function M.testWrite(app, areaId, bytes, report)
	local folder = fs.join(app.sources.exportFolder, '_selftest')
	fs.mkdir(folder)
	local path = fs.join(folder, 'nodes' .. tostring(areaId) .. '.dat')
	local ok, err = fs.writeAll(path, bytes)
	if not ok then
		add(report, 'gravacao ' .. areaId, false, tostring(err))
		return false
	end
	local back = fs.readAll(path)
	local same = back == bytes
	add(report, 'gravacao ' .. areaId, same, same and 'arquivo relido identico' or 'arquivo relido diferente')
	fs.remove(path)
	return same
end

--- Valida as areas carregadas e resume o relatorio.
function M.testValidation(app)
	local report = { tests = {}, failed = 0 }
	local rep = app:validate({ inGame = false, silent = true })
	local text = T('val.resumo', rep.errors, rep.warns, rep.infos, rep.fixable or 0)
	add(report, 'validacao', rep.errors == 0, text)
	return report
end

--- Roda tudo e devolve um resumo legivel.
function M.run(app, options)
	options = options or {}
	local report = M.testEnvironment(app)
	local parts = { report }
	if options.areas or #(app.project:loadedAreas()) > 0 then
		parts[#parts + 1] = M.roundTrip(app, options.areas, options)
		parts[#parts + 1] = M.testValidation(app)
	end

	local total, failed = 0, 0
	local lines = {}
	for i = 1, #parts do
		local part = parts[i]
		total = total + #part.tests
		failed = failed + (part.failed or 0)
		for t = 1, #part.tests do
			local test = part.tests[t]
			lines[#lines + 1] = string.format('[%s] %s: %s', test.ok and 'OK' or 'FALHOU', test.name, test.text or '')
		end
	end
	return {
		total = total, failed = failed, ok = failed == 0, lines = lines,
		parts = parts,
	}
end

function M.summaryText(result)
	local head = string.format('Visual Path Editor - autoteste: %d teste(s), %d falha(s)', result.total, result.failed)
	return head .. '\n' .. table.concat(result.lines, '\n')
end

return M
