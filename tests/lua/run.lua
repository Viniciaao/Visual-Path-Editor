--[[
	Runner dos testes em Lua. Executado pelo tests/run.py (via lupa),
	mas tambem pode ser executado em um Lua comum:
		lua tests/lua/run.lua
]]

local T = require 'support.assert'
local mock = require 'support.mock_moonloader'
mock.install()

local suites = {
	'test_util',
	'test_fs',
	'test_geometry',
	'test_dat',
	'test_model',
	'test_validate',
	'test_img',
	'test_sources',
	'test_render',
	'test_gizmo',
	'test_app',
	'test_entry',
	'test_i18n',
}

local filter = os.getenv('VPE_TEST_FILTER')
local luaDir = VPE_TEST_LUA_DIR or 'tests/lua'

--- Suite ainda nao escrita: nao conta como falha.
local function suiteExists(name)
	local fh = io.open(luaDir .. '/' .. name .. '.lua', 'r')
	if fh then fh:close() return true end
	return false
end

local skipped = {}
for i = 1, #suites do
	local name = suites[i]
	local selected = (not filter) or filter == '' or name:find(filter, 1, true)
	if selected then
		if suiteExists(name) then
			local ok, err = pcall(require, name)
			if not ok then
				T.describe(name, function()
					T.test('carrega modulo de teste', function()
						error(err, 0)
					end)
				end)
			end
		else
			skipped[#skipped + 1] = name
		end
	end
end

if #skipped > 0 then
	io.write(string.format('\n[--] suites ainda sem arquivo: %s\n', table.concat(skipped, ', ')))
end

local summary = T.summary()
io.write(string.format('\n=========================================\n'))
io.write(string.format('Testes: %d | OK: %d | FALHAS: %d\n', summary.total, summary.passed, summary.failed))
if summary.failed > 0 then
	io.write('\nFalhas:\n')
	for i = 1, #summary.errors do
		io.write('  - ' .. summary.errors[i] .. '\n')
	end
end
io.write('=========================================\n')

TEST_RESULT = summary
return summary
