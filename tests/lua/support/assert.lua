--[[
	Mini framework de testes (sem dependencias externas).
	Uso:
		local t = require 'support.assert'
		t.describe('modulo', function()
			t.test('faz algo', function()
				t.eq(1 + 1, 2)
			end)
		end)
]]

local M = {}

M.results = {}
M.currentSuite = '?'
M.passed = 0
M.failed = 0
M.errors = {}

local function record(ok, suite, name, message)
	M.results[#M.results + 1] = { ok = ok, suite = suite, name = name, message = message }
	if ok then
		M.passed = M.passed + 1
		io.write(string.format('  [ok]   %s :: %s\n', suite, name))
	else
		M.failed = M.failed + 1
		M.errors[#M.errors + 1] = string.format('%s :: %s -> %s', suite, name, tostring(message))
		io.write(string.format('  [FAIL] %s :: %s -> %s\n', suite, name, tostring(message)))
	end
	io.flush()
end

function M.describe(name, fn)
	local previous = M.currentSuite
	M.currentSuite = name
	io.write(string.format('\n== %s ==\n', name))
	local ok, err = pcall(fn)
	if not ok then record(false, name, '(suíte)', err) end
	M.currentSuite = previous
end

function M.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		record(true, M.currentSuite, name)
	else
		record(false, M.currentSuite, name, err)
	end
end

function M.fail(message)
	error(message or 'falha forcada', 2)
end

function M.ok(cond, message)
	if not cond then error('esperado valor verdadeiro: ' .. tostring(message or ''), 2) end
end

function M.eq(actual, expected, message)
	if actual ~= expected then
		error(string.format('%s esperado %s, obtido %s', message and (message .. ':') or 'valor', tostring(expected), tostring(actual)), 2)
	end
end

function M.near(actual, expected, tolerance, message)
	tolerance = tolerance or 0.0001
	if type(actual) ~= 'number' then error('nao e numero: ' .. tostring(actual), 2) end
	if math.abs(actual - expected) > tolerance then
		error(string.format('%s esperado ~%s, obtido %s', message and (message .. ':') or 'valor', tostring(expected), tostring(actual)), 2)
	end
end

function M.contains(haystack, needle, message)
	if type(haystack) ~= 'string' or not haystack:find(needle, 1, true) then
		error(string.format('%s texto nao contem "%s"', message and (message .. ':') or 'valor', tostring(needle)), 2)
	end
end

function M.summary()
	return {
		passed = M.passed,
		failed = M.failed,
		errors = M.errors,
		total = M.passed + M.failed,
	}
end

return M
