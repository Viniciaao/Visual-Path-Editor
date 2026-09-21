--[[
	Visual Path Editor - vpe.geometry
	Matematica de coordenadas, quadrantes (areas) e projecao para a tela.

	Cada arquivo nodes*.dat cobre um quadrado de 750x750 unidades. Os 64 arquivos
	comecam no canto sudoeste (-3000, -3000) e seguem ordem "row-major":
	    area = linha * 8 + coluna
	    linha = floor((y + 3000) / 750)
	    coluna = floor((x + 3000) / 750)
]]

local M = {}

M.AREA_SIZE = 750
M.AREA_GRID = 8
M.AREA_COUNT = 64
M.WORLD_MIN = -3000
M.WORLD_MAX = 3000

--------------------------------------------------------------------------------
-- Areas
--------------------------------------------------------------------------------

--- Converte coordenadas do mundo para o id da area (0..63) e o resto.
function M.areaFromCoords(x, y)
	x = tonumber(x) or 0
	y = tonumber(y) or 0
	local col = math.floor((x - M.WORLD_MIN) / M.AREA_SIZE)
	local row = math.floor((y - M.WORLD_MIN) / M.AREA_SIZE)
	col = math.max(0, math.min(M.AREA_GRID - 1, col))
	row = math.max(0, math.min(M.AREA_GRID - 1, row))
	return row * M.AREA_GRID + col, row, col
end

--- Posicao (linha/coluna) de uma area.
function M.areaRowCol(area)
	local row = math.floor(area / M.AREA_GRID)
	local col = area % M.AREA_GRID
	return row, col
end

--- Retorna minX, minY, maxX, maxY da area.
function M.areaBounds(area)
	local row, col = M.areaRowCol(area)
	local minX = M.WORLD_MIN + col * M.AREA_SIZE
	local minY = M.WORLD_MIN + row * M.AREA_SIZE
	return minX, minY, minX + M.AREA_SIZE, minY + M.AREA_SIZE
end

--- Centro da area (util para teleportes/visualizacao).
function M.areaCenter(area)
	local minX, minY, maxX, maxY = M.areaBounds(area)
	return (minX + maxX) / 2, (minY + maxY) / 2
end

--- Direcao cardinal de uma area em relacao a outra (para exibicao).
function M.areaRelation(fromArea, toArea)
	local fr, fc = M.areaRowCol(fromArea)
	local tr, tc = M.areaRowCol(toArea)
	local dr = tr - fr
	local dc = tc - fc
	local ns = dr > 0 and 'N' or (dr < 0 and 'S' or '')
	local ew = dc > 0 and 'L' or (dc < 0 and 'O' or '') -- Leste/Oeste
	return ns .. ew
end

--- Todas as coordenadas de um node caem dentro do quadrado do arquivo?
function M.areaContains(area, x, y, margin)
	margin = margin or 0
	local minX, minY, maxX, maxY = M.areaBounds(area)
	return x >= (minX - margin) and x <= (maxX + margin) and y >= (minY - margin) and y <= (maxY + margin)
end

--- Lista as 8 areas vizinhas + a propria (mesma ordem usada pelo editor CLEO:
--- 1..8 vizinhas, 9 = area atual), apenas as que existem no mapa 8x8.
function M.areaNeighborhood(area)
	local row, col = M.areaRowCol(area)
	local out = {}
	for dr = 1, -1, -1 do
		for dc = -1, 1 do
			if not (dr == 0 and dc == 0) then
				local r, c = row + dr, col + dc
				if r >= 0 and r < M.AREA_GRID and c >= 0 and c < M.AREA_GRID then
					out[#out + 1] = r * M.AREA_GRID + c
				end
			end
		end
	end
	out[#out + 1] = area
	return out
end

--------------------------------------------------------------------------------
-- Vetores
--------------------------------------------------------------------------------

function M.distance2d(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return math.sqrt(dx * dx + dy * dy)
end

function M.distance3d(x1, y1, z1, x2, y2, z2)
	local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.normalize2d(x, y)
	local len = math.sqrt(x * x + y * y)
	if len < 0.00001 then return 0, 0, 0 end
	return x / len, y / len, len
end

--- Distancia de um ponto ao segmento AB (usado para validar navi nodes).
function M.pointSegmentDistance(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local lenSq = dx * dx + dy * dy
	if lenSq < 0.000001 then return M.distance2d(px, py, ax, ay) end
	local t = ((px - ax) * dx + (py - ay) * dy) / lenSq
	t = math.max(0, math.min(1, t))
	return M.distance2d(px, py, ax + t * dx, ay + t * dy)
end

--- Angulo (heading em graus, padrao GTA) do vetor (x,y).
function M.headingFromVector(x, y)
	local angle = math.deg(math.atan2(-x, y))
	if angle < 0 then angle = angle + 360 end
	return angle
end

--- Converte um vetor unitario em bytes de direcao do navi node (INT8 -127..127).
function M.vectorToNaviBytes(x, y)
	local nx, ny, len = M.normalize2d(x, y)
	if len == 0 then return 0, 100 end
	local bx = math.floor(nx * 100 + 0.5)
	local by = math.floor(ny * 100 + 0.5)
	bx = math.max(-127, math.min(127, bx))
	by = math.max(-127, math.min(127, by))
	return bx, by
end

--------------------------------------------------------------------------------
-- Projecao para a tela (usa funcoes do MoonLoader; se nao existirem, devolve nil)
--------------------------------------------------------------------------------

--- Projeta coordenadas 3D para a tela.
--- Trata as duas convencoes de retorno existentes no MoonLoader.
function M.project(x, y, z)
	if type(convert3DCoordsToScreen) ~= 'function' then return nil end
	local ok, r1, r2, r3 = pcall(convert3DCoordsToScreen, x, y, z)
	if not ok then return nil end

	local sx, sy
	if type(r1) == 'boolean' then
		if not r1 then return nil end
		sx, sy = r2, r3
	else
		sx, sy = r1, r2
	end
	if type(sx) ~= 'number' or type(sy) ~= 'number' then return nil end
	if sx ~= sx or sy ~= sy then return nil end -- NaN
	return sx, sy
end

--- Projeta marcando tambem se o ponto esta na frente da camera.
function M.projectChecked(x, y, z)
	local sx, sy = M.project(x, y, z)
	if not sx then return nil end
	if type(isPointOnScreen) == 'function' then
		local ok, onScreen = pcall(isPointOnScreen, x, y, z, 0.05)
		if ok and not onScreen then
			return nil
		end
	end
	return sx, sy
end

--- Devolve dois pontos do raio que sai da camera pelo pixel informado.
--- Nao depende de nenhuma funcao de camera especifica.
function M.screenRay(screenX, screenY)
	if type(convertScreenCoordsToWorld3D) ~= 'function' then return nil end
	local ok1, ax, ay, az = pcall(convertScreenCoordsToWorld3D, screenX, screenY, 0.0)
	if not ok1 or type(ax) ~= 'number' then return nil end
	local ok2, bx, by, bz = pcall(convertScreenCoordsToWorld3D, screenX, screenY, 1.0)
	if not ok2 or type(bx) ~= 'number' then return nil end
	if ax ~= ax or bx ~= bx then return nil end
	return ax, ay, az, bx, by, bz
end

--- Interseccao do raio (A->B) com o plano horizontal z = planeZ.
function M.rayPlaneZ(ax, ay, az, bx, by, bz, planeZ)
	local dz = bz - az
	if math.abs(dz) < 0.00001 then return nil end
	local t = (planeZ - az) / dz
	if t < 0 then t = 0 end
	return ax + (bx - ax) * t, ay + (by - ay) * t
end

--- Interseccao do raio com um plano vertical (usado para mover no eixo Z).
--- planeNormal = (nx, ny, nz) normalizada; (px, py, pz) ponto do plano.
function M.rayPlane(ax, ay, az, bx, by, bz, px, py, pz, nx, ny, nz)
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local denom = dx * nx + dy * ny + dz * nz
	if math.abs(denom) < 0.00001 then return nil end
	local t = ((px - ax) * nx + (py - ay) * ny + (pz - az) * nz) / denom
	return ax + dx * t, ay + dy * t, az + dz * t, t
end

--------------------------------------------------------------------------------
-- Altura do solo / agua
--------------------------------------------------------------------------------

function M.groundZ(x, y, fromZ)
	if type(getGroundZFor3dCoord) ~= 'function' then return nil end
	local ok, z = pcall(getGroundZFor3dCoord, x, y, fromZ or 1000.0)
	if ok and type(z) == 'number' and z > -100 then return z end
	return nil
end

function M.waterZ(x, y)
	if type(getWaterHeightAtCoords) ~= 'function' then return nil end
	local ok, z = pcall(getWaterHeightAtCoords, x, y, true)
	if ok and type(z) == 'number' and z > -100 then return z end
	return nil
end

--- Melhor altura para apoiar um node (solo ou agua, o que for mais alto).
function M.surfaceZ(x, y, fromZ)
	local ground = M.groundZ(x, y, fromZ) or 0.0
	local water = M.waterZ(x, y)
	if water and water > ground then return water, 'water' end
	return ground, 'ground'
end

return M
