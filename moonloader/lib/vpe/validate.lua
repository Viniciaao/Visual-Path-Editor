--[[
	Visual Path Editor - vpe.validate
	Validador de paths. Roda antes de salvar e tambem sob demanda.

	Niveis:
	  error -> impede o salvamento (o jogo pode travar com esses dados)
	  warn  -> permite salvar, mas pede confirmacao
	  info  -> apenas informativo

	Regra de ouro: so acusa link/navi quebrado quando da para PROVAR que ele
	esta quebrado. Areas que nao estao carregadas e que nao tem metadados ficam
	apenas como 'info' (conferencia limitada) - quem chama pode passar
	options.probe(areaId) -> counts para conferir o cabecalho do arquivo sem
	carregar a area inteira.
]]

local util = require 'vpe.util'
local dat = require 'vpe.dat'
local geo = require 'vpe.geometry'
local i18n = require 'vpe.i18n'

local M = {}

local T = i18n.t

M.MAX_AREA = 63

--------------------------------------------------------------------------------
-- Relatorio
--------------------------------------------------------------------------------

function M.newReport()
	return { entries = {}, errors = 0, warns = 0, infos = 0, fixable = 0, byArea = {}, canSave = true }
end

local function add(report, entry)
	report.entries[#report.entries + 1] = entry
	if entry.level == 'error' then report.errors = report.errors + 1
	elseif entry.level == 'warn' then report.warns = report.warns + 1
	else report.infos = report.infos + 1 end
	if entry.fix then report.fixable = report.fixable + 1 end
	local key = tostring(entry.area)
	report.byArea[key] = (report.byArea[key] or 0) + 1
	return entry
end

M.add = add

--- Se a area alvo de um link/navi node tem dados confiaveis.
--- Devolve { known, exists, count, area, navis }
local function targetInfo(project, areaId, options)
	if areaId == nil or areaId < 0 or areaId > M.MAX_AREA then
		return { known = true, exists = false, count = 0, invalidId = true }
	end
	local area = project.area and project:area(areaId)
	if area then
		return { known = true, exists = true, count = #area.nodes, navis = #area.navis, area = area }
	end
	local meta = project:metaOf(areaId)
	if meta and meta.exists ~= nil then
		return {
			known = true,
			exists = meta.exists,
			count = meta.counts and meta.counts.nodeCount,
			navis = meta.counts and meta.counts.naviCount,
		}
	end
	local probe = options and options.probe
	if probe then
		local counts = probe(areaId)
		if counts then
			return { known = true, exists = true, count = counts.nodeCount, navis = counts.naviCount }
		end
	end
	return { known = false }
end

--------------------------------------------------------------------------------
-- Localizacao de links na hora de corrigir
-- (os indices do relatorio podem ficar velhos quando outra correcao ja
--  removeu um link, entao as correcoes procuram o link pelo valor)
--------------------------------------------------------------------------------

local function findLinkIndex(node, targetArea, targetNode)
	if not node then return nil end
	local links = node.links or {}
	for i = 1, #links do
		if links[i].area == targetArea and links[i].node == targetNode then return i end
	end
	return nil
end

local function removeLinkByTarget(project, areaId, index, targetArea, targetNode)
	local node = project:node(areaId, index)
	local pos = findLinkIndex(node, targetArea, targetNode)
	if not pos then return false end
	return project:removeLink(areaId, index, pos)
end

local function setLinkNaviByTarget(project, areaId, index, targetArea, targetNode, naviArea, naviId)
	local node = project:node(areaId, index)
	local pos = findLinkIndex(node, targetArea, targetNode)
	if not pos then return false end
	return project:setLinkNavi(areaId, index, pos, naviArea, naviId)
end

--------------------------------------------------------------------------------
-- Nodes
--------------------------------------------------------------------------------

local function validateNodeFlags(report, project, area, index, node, kind)
	local flags = node.flags or 0
	local highBits = util.getBits(flags, 24, 8)
	if highBits ~= 0 then
		add(report, {
			level = 'warn', code = 'FLAGS_HIGH_BITS', area = area.id, node = index,
			text = T('val.flags_high_bits', index - 1, highBits),
			fix = function()
				project:setNodeField(area.id, index, 'flags', util.setBits(flags, 24, 8, 0))
				return true
			end,
			fixLabel = T('val.fix_clear_high_bits'),
		})
	end

	if kind ~= 'ped' then
		local isHighway = util.hasBit(flags, 13)
		local isRoad = util.hasBit(flags, 12)
		if isHighway and isRoad then
			add(report, {
				level = 'warn', code = 'FLAGS_HIGHWAY_CONFLICT', area = area.id, node = index,
				text = T('val.highway_conflict', index - 1),
				fix = function()
					project:setNodeField(area.id, index, 'flags', util.setBit(flags, 12, false))
					return true
				end,
				fixLabel = T('val.fix_normal_road'),
			})
		elseif not isHighway and not isRoad then
			add(report, {
				level = 'info', code = 'FLAGS_NO_HIGHWAY_KIND', area = area.id, node = index,
				text = T('val.no_highway_kind', index - 1),
				fix = function()
					project:setNodeField(area.id, index, 'flags', util.setBit(flags, 12, true))
					return true
				end,
				fixLabel = T('val.fix_normal_road'),
			})
		end
	end

	local boat = util.hasBit(flags, 7)
	if kind == 'ped' and boat then
		add(report, {
			level = 'warn', code = 'FLAGS_BOAT_ON_PED', area = area.id, node = index,
			text = T('val.boat_on_ped', index - 1),
			fix = function()
				project:setNodeField(area.id, index, 'flags', util.setBit(flags, 7, false))
				return true
			end,
			fixLabel = T('val.fix_remove_boat'),
		})
	elseif kind == 'veh' and boat then
		add(report, {
			level = 'warn', code = 'FLAGS_BOAT_ON_LAND_NODE', area = area.id, node = index,
			text = T('val.boat_flag_land', index - 1),
		})
	end

	if dat.getNodeFlag(flags, 'SPAWN_PROBABILITY') == 0 and kind ~= 'ped' then
		add(report, {
			level = 'info', code = 'SPAWN_PROBABILITY_ZERO', area = area.id, node = index,
			text = T('val.spawn_zero', index - 1),
		})
	end
end

local function validateNodePosition(report, area, index, node)
	local x, y, z = node.x or 0, node.y or 0, node.z or 0
	local ix, iy, iz = dat.coordToInt(x), dat.coordToInt(y), dat.coordToInt(z)
	if ix < -32768 or ix > 32767 or iy < -32768 or iy > 32767 or iz < -32768 or iz > 32767 then
		add(report, {
			level = 'error', code = 'POS_OUT_OF_RANGE', area = area.id, node = index,
			text = T('val.pos_out_of_range', index - 1),
		})
		return
	end
	if not geo.areaContains(area.id, x, y, 32) then
		add(report, {
			level = 'warn', code = 'POS_OUTSIDE_AREA', area = area.id, node = index,
			text = T('val.pos_outside_area', index - 1, area.id),
		})
	end
	if z < -120 or z > 500 then
		add(report, {
			level = 'warn', code = 'POS_Z_WEIRD', area = area.id, node = index,
			text = T('val.pos_z_weird', index - 1, z),
		})
	end
end

local function validateNodeLinks(report, project, area, index, node, kind, options)
	local links = node.links or {}
	if #links == 0 then
		add(report, {
			level = 'warn', code = 'NODE_ISOLATED', area = area.id, node = index,
			text = T('val.node_isolated', index - 1),
		})
	elseif #links == 1 then
		add(report, {
			level = 'info', code = 'NODE_SINGLE_LINK', area = area.id, node = index,
			text = T('val.node_single_link', index - 1),
		})
	end
	if #links > dat.MAX_LINKS_PER_NODE then
		add(report, {
			level = 'error', code = 'TOO_MANY_LINKS', area = area.id, node = index,
			text = T('val.too_many_links', index - 1, #links, dat.MAX_LINKS_PER_NODE),
		})
	end

	local seen = {}
	for li = 1, #links do
		local link = links[li]
		local key = tostring(link.area) .. ':' .. tostring(link.node)
		if seen[key] then
			add(report, {
				level = 'warn', code = 'LINK_DUPLICATED', area = area.id, node = index, link = li,
				text = T('val.link_duplicated', index - 1, link.area, link.node),
				fix = function()
					return removeLinkByTarget(project, area.id, index, link.area, link.node)
				end,
				fixLabel = T('val.fix_remove_duplicate'),
			})
		end
		seen[key] = true

		if link.area == area.id and link.node == (index - 1) then
			add(report, {
				level = 'error', code = 'LINK_SELF', area = area.id, node = index, link = li,
				text = T('val.link_self', index - 1),
				fix = function()
					return removeLinkByTarget(project, area.id, index, link.area, link.node)
				end,
				fixLabel = T('val.fix_remove_link'),
			})
		elseif link.area == area.id and link.node >= #area.nodes then
			add(report, {
				level = 'error', code = 'LINK_TARGET_MISSING', area = area.id, node = index, link = li,
				text = T('val.link_target_missing', index - 1, link.area, link.node, #area.nodes),
				fix = function()
					return removeLinkByTarget(project, area.id, index, link.area, link.node)
				end,
				fixLabel = T('val.fix_remove_link'),
			})
		elseif link.area == area.id and link.node < 0 then
			add(report, {
				level = 'error', code = 'LINK_TARGET_MISSING', area = area.id, node = index, link = li,
				text = T('val.link_target_missing', index - 1, link.area, link.node, #area.nodes),
			})
		else
			local info = targetInfo(project, link.area, options)
			local targetNode = info.area and info.area.nodes[link.node + 1]

			if info.invalidId or (info.known and not info.exists) then
				add(report, {
					level = 'error', code = 'LINK_AREA_MISSING', area = area.id, node = index, link = li,
					text = T('val.link_area_missing', index - 1, link.area, link.node),
					fix = function()
						return removeLinkByTarget(project, area.id, index, link.area, link.node)
					end,
					fixLabel = T('val.fix_remove_link'),
				})
			elseif info.known and info.count and link.node >= info.count then
				add(report, {
					level = 'error', code = 'LINK_TARGET_MISSING', area = area.id, node = index, link = li,
					text = T('val.link_target_missing', index - 1, link.area, link.node, info.count),
					fix = function()
						return removeLinkByTarget(project, area.id, index, link.area, link.node)
					end,
					fixLabel = T('val.fix_remove_link'),
				})
			elseif not info.known then
				add(report, {
					level = 'info', code = 'LINK_NOT_LOADED', area = area.id, node = index, link = li,
					text = T('val.link_not_loaded', index - 1, link.area, link.node),
				})
			elseif targetNode then
				-- link reciproco
				if not project:findLink(targetNode, area.id, index - 1) then
					add(report, {
						level = 'warn', code = 'LINK_NOT_RECIPROCAL', area = area.id, node = index, link = li,
						text = T('val.link_not_reciprocal', index - 1, link.area, link.node),
						fix = function()
							return project:addLink(area.id, index, link.area, link.node + 1)
						end,
						fixLabel = T('val.fix_add_reverse'),
					})
				end
				-- tipos de node
				local targetKind = dat.nodeType(info.area, link.node + 1)
				if kind == 'ped' and targetKind ~= 'ped' then
					add(report, {
						level = 'warn', code = 'LINK_TYPE_MISMATCH', area = area.id, node = index, link = li,
						text = T('val.link_ped_to_vehicle', index - 1, link.area, link.node),
					})
				elseif kind ~= 'ped' and targetKind == 'ped' then
					add(report, {
						level = 'warn', code = 'LINK_TYPE_MISMATCH', area = area.id, node = index, link = li,
						text = T('val.link_vehicle_to_ped', index - 1, link.area, link.node),
					})
				elseif kind == 'boat' and targetKind == 'veh' then
					add(report, {
						level = 'warn', code = 'LINK_BOAT_TO_CAR', area = area.id, node = index, link = li,
						text = T('val.link_boat_to_land', index - 1, link.area, link.node),
					})
				end
				-- comprimento gravado x distancia real
				local real = geo.distance2d(node.x, node.y, targetNode.x, targetNode.y)
				local declared = link.length or 0
				if real < 255 and math.abs(real - declared) > 3.0 then
					add(report, {
						level = 'warn', code = 'LINK_LENGTH_WRONG', area = area.id, node = index, link = li,
						text = T('val.link_length_wrong', index - 1, link.area, link.node, declared, real),
						fix = function()
							project:recomputeLengths(area.id)
							return true
						end,
						fixLabel = T('val.fix_recompute_lengths'),
					})
				end
			end
		end

		-- nodes de pedestre nao usam navi link
		if kind == 'ped' and dat.naviLinkIsSet(link) then
			add(report, {
				level = 'warn', code = 'NAVI_LINK_ON_PED', area = area.id, node = index, link = li,
				text = T('val.navi_link_on_ped', index - 1),
				fix = function()
					return setLinkNaviByTarget(project, area.id, index, link.area, link.node, 0, 0)
				end,
				fixLabel = T('val.fix_clear_navi_link'),
			})
		end

		-- navi link aponta para um navi node existente?
		if dat.naviLinkIsSet(link) then
			local info = targetInfo(project, link.naviArea, options)
			if info.invalidId or (info.known and not info.exists) then
				add(report, {
					level = 'error', code = 'NAVI_LINK_AREA_MISSING', area = area.id, node = index, link = li,
					text = T('val.navi_link_area_missing', index - 1, link.naviID or 0, link.naviArea),
					fix = function()
						return setLinkNaviByTarget(project, area.id, index, link.area, link.node, 0, 0)
					end,
					fixLabel = T('val.fix_clear_navi_link'),
				})
			elseif info.known and info.navis and (link.naviID or 0) >= info.navis then
				add(report, {
					level = 'error', code = 'NAVI_LINK_OUT_OF_RANGE', area = area.id, node = index, link = li,
					text = T('val.navi_link_out_of_range', index - 1, link.naviID or 0, link.naviArea, info.navis),
					fix = function()
						return setLinkNaviByTarget(project, area.id, index, link.area, link.node, 0, 0)
					end,
					fixLabel = T('val.fix_clear_navi_link'),
				})
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Navi nodes
--------------------------------------------------------------------------------

local function validateNavi(report, project, area, naviIndex, navi, referencedNavis, options)
	local idx = naviIndex - 1
	local info = targetInfo(project, navi.areaID, options)
	local targetNode = (info.area and navi.nodeID < 0xFFFF) and info.area.nodes[navi.nodeID + 1] or nil

	if navi.nodeID == 0xFFFF or navi.nodeID >= 0xFFFF then
		add(report, {
			level = 'error', code = 'NAVI_NOT_CONNECTED', area = area.id, navi = naviIndex,
			text = T('val.navi_not_connected', idx),
			fix = function()
				return M.fixNaviConnectNearest(project, area.id, naviIndex)
			end,
			fixLabel = T('val.fix_navi_connect_nearest'),
			fix2 = function()
				return project:removeNavi(area.id, naviIndex)
			end,
			fix2Label = T('val.fix_remove_navi'),
		})
	elseif info.invalidId or (info.known and not info.exists) then
		add(report, {
			level = 'error', code = 'NAVI_TARGET_AREA_MISSING', area = area.id, navi = naviIndex,
			text = T('val.navi_target_area_missing', idx, navi.areaID, navi.nodeID),
			fix = function()
				return M.fixNaviConnectNearest(project, area.id, naviIndex)
			end,
			fixLabel = T('val.fix_navi_connect_nearest'),
			fix2 = function()
				return project:removeNavi(area.id, naviIndex)
			end,
			fix2Label = T('val.fix_remove_navi'),
		})
	elseif info.known and info.count and navi.nodeID >= info.count then
		add(report, {
			level = 'error', code = 'NAVI_TARGET_MISSING', area = area.id, navi = naviIndex,
			text = T('val.navi_target_missing', idx, navi.areaID, navi.nodeID, info.count),
			fix = function()
				return M.fixNaviConnectNearest(project, area.id, naviIndex)
			end,
			fixLabel = T('val.fix_navi_connect_nearest'),
			fix2 = function()
				return project:removeNavi(area.id, naviIndex)
			end,
			fix2Label = T('val.fix_remove_navi'),
		})
	elseif not info.known then
		add(report, {
			level = 'info', code = 'NAVI_TARGET_NOT_LOADED', area = area.id, navi = naviIndex,
			text = T('val.navi_target_not_loaded', idx, navi.areaID, navi.nodeID),
		})
	elseif targetNode and navi.areaID == area.id and navi.nodeID >= area.vehCount then
		add(report, {
			level = 'warn', code = 'NAVI_TARGET_IS_PED', area = area.id, navi = naviIndex,
			text = T('val.navi_target_is_ped', idx, navi.areaID, navi.nodeID),
			fix = function()
				return M.fixNaviConnectNearest(project, area.id, naviIndex)
			end,
			fixLabel = T('val.fix_navi_connect_nearest'),
		})
	end

	-- direcao
	local dirLength = math.sqrt((navi.dirX or 0) ^ 2 + (navi.dirY or 0) ^ 2)
	if dirLength < 1 then
		add(report, {
			level = 'warn', code = 'NAVI_DIRECTION_ZERO', area = area.id, navi = naviIndex,
			text = T('val.navi_direction_zero', idx),
			fix = function()
				return M.fixNaviDirection(project, area.id, naviIndex)
			end,
			fixLabel = T('val.fix_navi_direction'),
		})
	elseif targetNode and geo.distance2d(navi.x, navi.y, targetNode.x, targetNode.y) > 1.5 then
		local dot = (targetNode.x - navi.x) * (navi.dirX or 0) + (targetNode.y - navi.y) * (navi.dirY or 0)
		if dot < 0 then
			add(report, {
				level = 'warn', code = 'NAVI_DIRECTION_WRONG', area = area.id, navi = naviIndex,
				text = T('val.navi_direction_wrong', idx),
				fix = function()
					return M.fixNaviDirection(project, area.id, naviIndex)
				end,
				fixLabel = T('val.fix_navi_direction'),
			})
		elseif math.abs(dirLength - 100) > 20 then
			add(report, {
				level = 'info', code = 'NAVI_DIRECTION_LENGTH', area = area.id, navi = naviIndex,
				text = T('val.navi_direction_length', idx, dirLength),
				fix = function()
					return M.fixNaviDirection(project, area.id, naviIndex)
				end,
				fixLabel = T('val.fix_navi_direction'),
			})
		end
	end

	-- esta associado a algum link?
	if not referencedNavis[naviIndex - 1] then
		add(report, {
			level = 'warn', code = 'NAVI_NOT_LINKED', area = area.id, navi = naviIndex,
			text = T('val.navi_not_linked', idx),
		})
	end

	-- largura deve acompanhar o path width do node alvo
	if targetNode then
		local naviWidth = dat.getNaviFlag(navi.flags or 0, 'WIDTH')
		if naviWidth ~= (targetNode.pathWidth or 0) then
			add(report, {
				level = 'info', code = 'NAVI_WIDTH_MISMATCH', area = area.id, navi = naviIndex,
				text = T('val.navi_width_mismatch', idx, naviWidth, targetNode.pathWidth or 0),
				fix = function()
					local flags = dat.setNaviFlag(navi.flags or 0, 'WIDTH', targetNode.pathWidth or 0)
					return project:setNaviField(area.id, naviIndex, 'flags', flags)
				end,
				fixLabel = T('val.fix_navi_width'),
			})
		end
	end

	local left = dat.getNaviFlag(navi.flags or 0, 'LEFT_LANES')
	local right = dat.getNaviFlag(navi.flags or 0, 'RIGHT_LANES')
	if left == 0 and right == 0 then
		add(report, {
			level = 'warn', code = 'NAVI_NO_LANES', area = area.id, navi = naviIndex,
			text = T('val.navi_no_lanes', idx),
			fix = function()
				local flags = dat.setNaviFlag(navi.flags or 0, 'LEFT_LANES', 1)
				flags = dat.setNaviFlag(flags, 'RIGHT_LANES', 1)
				return project:setNaviField(area.id, naviIndex, 'flags', flags)
			end,
			fixLabel = T('val.fix_navi_lanes'),
		})
	end
end

--------------------------------------------------------------------------------
-- Correcoes automaticas
--------------------------------------------------------------------------------

--- Conecta um navi node ao node de veiculo mais proximo de (x, y).
function M.fixNaviConnectNearest(project, areaId, naviIndex)
	local area = project:area(areaId)
	local navi = area and area.navis[naviIndex]
	if not navi then return false, 'navi inexistente' end
	local best = project:nearestNode(areaId, navi.x, navi.y, 60.0, 'vehicle')
	if not best then return false, T('val.fix_navi_no_nearby') end
	project:setNaviField(areaId, naviIndex, 'areaID', areaId)
	project:setNaviField(areaId, naviIndex, 'nodeID', best.index - 1)
	M.fixNaviDirection(project, areaId, naviIndex)
	return true
end

--- Recalcula o vetor de direcao do navi node, apontando para o alvo.
function M.fixNaviDirection(project, areaId, naviIndex)
	local area = project:area(areaId)
	local navi = area and area.navis[naviIndex]
	if not navi then return false, 'navi inexistente' end
	local targetArea = project:area(navi.areaID)
	local target = targetArea and (navi.nodeID < 0xFFFF) and targetArea.nodes[navi.nodeID + 1]
	local dx, dy = 0, 1
	if target then
		dx, dy = target.x - navi.x, target.y - navi.y
	end
	local bx, by = geo.vectorToNaviBytes(dx, dy)
	project:setNaviField(areaId, naviIndex, 'dirX', bx)
	project:setNaviField(areaId, naviIndex, 'dirY', by)
	return true
end

--------------------------------------------------------------------------------
-- Validacao de areas
--------------------------------------------------------------------------------

function M.validateArea(project, areaId, options)
	options = options or {}
	local report = options.report or M.newReport()
	local area = project:area(areaId)
	if not area then
		add(report, {
			level = 'info', code = 'AREA_NOT_LOADED', area = areaId,
			text = T('val.area_not_loaded', areaId),
		})
		return report
	end

	local meta = project:metaOf(areaId)
	if meta and meta.exists == false then
		add(report, {
			level = 'warn', code = 'AREA_FILE_MISSING', area = areaId,
			text = T('val.area_file_missing', areaId),
		})
	end

	if #area.nodes > dat.MAX_NODES then
		add(report, {
			level = 'error', code = 'TOO_MANY_NODES', area = areaId,
			text = T('val.too_many_nodes', areaId, #area.nodes, dat.MAX_NODES),
		})
	end
	if #area.navis > dat.MAX_NAVI_NODES then
		add(report, {
			level = 'error', code = 'TOO_MANY_NAVIS', area = areaId,
			text = T('val.too_many_navis', areaId, #area.navis, dat.MAX_NAVI_NODES),
		})
	end
	if area.vehCount > #area.nodes then
		add(report, {
			level = 'error', code = 'VEH_COUNT_INVALID', area = areaId,
			text = T('val.veh_count_invalid', areaId, area.vehCount, #area.nodes),
			fix = function()
				project:refreshMeta(areaId)
				return true
			end,
			fixLabel = T('val.fix_fix_counts'),
		})
	end

	-- quais navi nodes estao referenciados por algum link (secao 5)
	local referencedNavis = {}
	for i = 1, #area.nodes do
		local links = area.nodes[i].links or {}
		for j = 1, #links do
			local link = links[j]
			if dat.naviLinkIsSet(link) and ((link.naviArea or 0) == 0 or (link.naviArea or 0) == areaId) then
				referencedNavis[link.naviID] = true
			end
		end
	end

	-- nodes
	local positions = {}
	for i = 1, #area.nodes do
		local node = area.nodes[i]
		local kind = dat.nodeType(area, i)
		validateNodePosition(report, area, i, node)
		validateNodeFlags(report, project, area, i, node, kind)
		validateNodeLinks(report, project, area, i, node, kind, options)

		local key = string.format('%.1f:%.1f', node.x or 0, node.y or 0)
		if positions[key] then
			add(report, {
				level = 'warn', code = 'NODE_OVERLAP', area = areaId, node = i,
				text = T('val.node_overlap', i - 1, positions[key] - 1, node.x, node.y),
				fix = function()
					local target = positions[key]
					return project:removeNode(areaId, target > i and i or target)
				end,
				fixLabel = T('val.fix_remove_duplicate_node'),
			})
		else
			positions[key] = i
		end
	end

	-- navi nodes
	for i = 1, #area.navis do
		validateNavi(report, project, area, i, area.navis[i], referencedNavis, options)
	end

	-- observacoes gravadas pelo parser (arquivo truncado, etc.)
	if options.includeNotes ~= false then
		for _, note in ipairs(area.notes or {}) do
			add(report, {
				level = 'info', code = 'AREA_FILE_NOTE', area = areaId,
				text = T('val.file_note', areaId, note.text),
			})
		end
	end

	return report
end

--- Relatorio completo das areas carregadas (a ordem comeca pelos erros).
function M.validateAll(project, options)
	local report = M.newReport()
	report.probe = options and options.probe
	local areas = project:loadedAreas()
	for i = 1, #areas do
		report = M.validateArea(project, areas[i], {
			report = report,
			probe = options and options.probe,
			includeNotes = options and options.includeNotes,
		})
	end
	table.sort(report.entries, function(a, b)
		local order = { error = 1, warn = 2, info = 3 }
		local la, lb = order[a.level] or 4, order[b.level] or 4
		if la ~= lb then return la < lb end
		if (a.area or 0) ~= (b.area or 0) then return (a.area or 0) < (b.area or 0) end
		return (a.node or a.navi or 0) < (b.node or b.navi or 0)
	end)
	report.canSave = report.errors == 0
	return report
end

--- Aplica todas as correcoes disponiveis. Devolve aplicadas, falhas.
function M.applyAllFixes(project, report, which, maxPasses)
	local applied, failures = 0, 0
	which = which or '1'
	maxPasses = maxPasses or 6
	local passes = 0
	local changed = true
	while changed and passes < maxPasses do
		passes = passes + 1
		changed = false
		local seen = {}
		for _, entry in ipairs(report.entries) do
			local fn = (which == '2') and entry.fix2 or entry.fix
			if fn then
				local key = tostring(entry.code) .. ':' .. tostring(entry.area) .. ':' .. tostring(entry.node)
					.. ':' .. tostring(entry.navi) .. ':' .. tostring(entry.link) .. ':' .. which
				if not seen[key] then
					seen[key] = true
					local ok = fn()
					if ok then
						applied = applied + 1
						changed = true
					else
						failures = failures + 1
					end
				end
			end
		end
		if changed then
			-- uma correcao pode invalidar os indices das outras: valida de novo
			report = M.validateAll(project, { probe = report.probe })
		end
	end
	return applied, failures, report
end

--------------------------------------------------------------------------------
-- Checagens que precisam do jogo rodando (altura em relacao ao solo)
--------------------------------------------------------------------------------

function M.checkInGame(project, areaId, options)
	options = options or {}
	local report = options.report or M.newReport()
	local area = project:area(areaId)
	if not area then return report end

	local maxDistance = options.maxDistance or 200.0
	local px, py = options.px or 0, options.py or 0
	if options.px == nil and type(getCharCoordinates) == 'function' then
		local cx, cy = util.playerCoords()
		if cx then px, py = cx, cy end
	end

	for i = 1, #area.nodes do
		local node = area.nodes[i]
		if geo.distance2d(px, py, node.x, node.y) <= maxDistance then
			local ground = geo.surfaceZ(node.x, node.y, node.z + 3)
			if ground then
				local diff = node.z - ground
				if diff > 3.0 then
					add(report, {
						level = 'warn', code = 'NODE_FLOATING', area = areaId, node = i,
						text = T('val.node_floating', i - 1, diff),
						fix = function()
							return project:setNodePosition(areaId, i, node.x, node.y, ground + 0.5)
						end,
						fixLabel = T('val.fix_snap_ground'),
					})
				elseif diff < -4.0 then
					add(report, {
						level = 'warn', code = 'NODE_UNDERGROUND', area = areaId, node = i,
						text = T('val.node_underground', i - 1, -diff),
						fix = function()
							return project:setNodePosition(areaId, i, node.x, node.y, ground + 0.5)
						end,
						fixLabel = T('val.fix_snap_ground'),
					})
				end
			end
		end
	end
	return report
end

return M
