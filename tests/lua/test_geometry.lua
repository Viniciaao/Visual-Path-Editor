local t = require 'support.assert'
local geo = require 'vpe.geometry'

t.describe('geometry - areas', function()
	t.test('mapeia coordenadas para area (row-major a partir de -3000,-3000)', function()
		t.eq(geo.areaFromCoords(-3000, -3000), 0)
		t.eq(geo.areaFromCoords(-2250.001, -3000), 0) -- limite superior da coluna 0
		t.eq(geo.areaFromCoords(-2250, -3000), 1)     -- comeca a coluna 1
		t.eq(geo.areaFromCoords(-2249.999, -3000), 1)
		t.eq(geo.areaFromCoords(-3000, -2250.001), 0)
		t.eq(geo.areaFromCoords(-3000, -2250), 8)
		t.eq(geo.areaFromCoords(2999, 2999), 63)
		t.eq(geo.areaFromCoords(0, 0), 4 * 8 + 4)
	end)

	t.test('Grove Street fica na area 15 (LS sudeste)', function()
		local area = geo.areaFromCoords(2495, -1684)
		t.eq(area, 15)
	end)

	t.test('limites da area', function()
		local minX, minY, maxX, maxY = geo.areaBounds(15)
		t.eq(minX, 2250)
		t.eq(minY, -2250)
		t.eq(maxX, 3000)
		t.eq(maxY, -1500)
		t.ok(geo.areaContains(15, 2400, -1600))
		t.ok(not geo.areaContains(15, 2400, -1000))
	end)

	t.test('vizinhas de uma area', function()
		local list = geo.areaNeighborhood(9)
		t.eq(#list, 9)
		t.eq(list[9], 9)
		local found = {}
		for _, a in ipairs(list) do found[a] = true end
		t.ok(found[0] and found[1] and found[2])
		t.ok(found[8] and found[16] and found[17] and found[18])
		t.ok(not found[24], 'nao deve incluir areas distantes')
	end)

	t.test('vizinhas nas bordas do mapa', function()
		local list = geo.areaNeighborhood(0)
		t.eq(#list, 4) -- direita, cima, diagonal, propria
		t.eq(list[#list], 0)
	end)
end)

t.describe('geometry - vetores', function()
	t.test('distancias', function()
		t.near(geo.distance2d(0, 0, 3, 4), 5)
		t.near(geo.distance3d(0, 0, 0, 1, 2, 2), 3)
	end)

	t.test('normalizacao', function()
		local x, y, len = geo.normalize2d(10, 0)
		t.near(x, 1)
		t.near(y, 0)
		t.near(len, 10)
		local zx, zy, zlen = geo.normalize2d(0, 0)
		t.eq(zlen, 0)
	end)

	t.test('distancia ponto-segmento', function()
		t.near(geo.pointSegmentDistance(5, 5, 0, 0, 10, 0), 5)
		t.near(geo.pointSegmentDistance(-5, 0, 0, 0, 10, 0), 5)
		t.near(geo.pointSegmentDistance(0, 0, 0, 0, 0, 0), 0)
	end)

	t.test('direcao do navi em bytes', function()
		local bx, by = geo.vectorToNaviBytes(100, 0)
		t.eq(bx, 100)
		t.eq(by, 0)
		local cx, cy = geo.vectorToNaviBytes(0, -50)
		t.eq(cx, 0)
		t.eq(cy, -100)
	end)
end)

t.describe('geometry - projecao', function()
	t.test('projeta ponto e devolve coordenadas de tela', function()
		local sx, sy = geo.project(2495, -1684, 10)
		t.ok(sx, 'deveria projetar')
		t.near(sx, 960)
	end)

	t.test('raio da tela e interseccao com plano', function()
		local ax, ay, az, bx, by, bz = geo.screenRay(960, 540)
		t.ok(ax ~= nil)
		local x, y = geo.rayPlaneZ(ax, ay, az, bx, by, bz, 0)
		t.ok(x ~= nil, 'interseccao com o plano z=0')
		-- o mock projeta o raio a partir do jogador
		t.near(x, 2495, 1)
	end)
end)

return true
