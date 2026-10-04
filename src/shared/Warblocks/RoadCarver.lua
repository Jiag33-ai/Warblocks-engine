-- Carves a planned road into the volumetric field: cut/fill, side slopes, layered construction materials.
local function req(n) if script then return require(script.Parent[n]) end return require("warblocks." .. n) end
local Materials = req("Materials")
local Planner = req("RoadPlanner")
local Carver = {}
local sqrt, floor, ceil = math.sqrt, math.floor, math.ceil

-- op = {type="Road", class="Primary", points={{x,z,y}...}}
local function carve(field, op)
	local cls = Planner.CLASSES[op.class]
	local S = field.S
	local hw = cls.width / 2
	local reach = hw + cls.shoulder
	local surfMat = Materials[cls.surface]
	local l1, l2, l3 = cls.layers[1], cls.layers[1] + cls.layers[2], cls.layers[1] + cls.layers[2] + cls.layers[3]
	local touched = 0
	for s = 2, #op.points do
		local a, b = op.points[s - 1], op.points[s]
		local dx, dz = b.x - a.x, b.z - a.z
		local len2 = dx * dx + dz * dz
		if len2 > 1e-9 then
			local maxRise = math.max(math.abs(a.y - a.terrainY), math.abs(b.y - b.terrainY)) + 6
			local slopeRun = reach + maxRise / math.min(cls.cutSlope, cls.fillSlope)
			local minX, maxX = math.min(a.x, b.x) - slopeRun, math.max(a.x, b.x) + slopeRun
			local minZ, maxZ = math.min(a.z, b.z) - slopeRun, math.max(a.z, b.z) + slopeRun
			local yMin, yMax = math.min(a.y, b.y, a.terrainY, b.terrainY) - 16, math.max(a.y, b.y, a.terrainY, b.terrainY) + 16
			local i0, j0, k0, i1, j1, k1 = field:boxFromWorld({ minX, yMin, minZ }, { maxX, yMax, maxZ })
			field:modifyBox(i0, j0, k0, i1, j1, k1, function(i, j, k, d, m)
				local px, pz, py = i * S, k * S, j * S
				-- nearest-segment ownership among neighbours so bends/joints never overwrite each other
				local bestS, bestD, bt = s, math.huge, 0
				for q = math.max(2, s - 4), math.min(#op.points, s + 4) do
					local qa, qb = op.points[q - 1], op.points[q]
					local qx, qz = qb.x - qa.x, qb.z - qa.z
					local ql = qx * qx + qz * qz
					if ql > 1e-9 then
						local qt = ((px - qa.x) * qx + (pz - qa.z) * qz) / ql
						if qt < 0 then qt = 0 elseif qt > 1 then qt = 1 end
						local ddx, ddz = px - (qa.x + qx * qt), pz - (qa.z + qz * qt)
						local dd = ddx * ddx + ddz * ddz
						if dd < bestD - 1e-9 then bestS, bestD, bt = q, dd, qt end
					end
				end
				if bestS ~= s then return end
				local t = bt
				local dist = sqrt(bestD)
				local H = a.y + (b.y - a.y) * t
				local col = field:_column(i, k)
				local th = col[1]
				local target
				if dist <= reach then
					target = H
					if dist > hw then -- shoulder falls slightly toward ditch
						target = H - (dist - hw) * 0.08
					end
				else
					local run = dist - reach
					if th > H then target = math.min(th, H + cls.cutSlope * run) else target = math.max(th, H - cls.fillSlope * run) end
				end
				if dist > reach and math.abs(target - th) < 0.02 then return end
				local depth = target - py
				if depth < -16 or depth > 16 then
					return
				end
				local nd = depth
				if nd <= 0 then return nd end
				local nm = m
				if dist <= hw then
					if depth < l1 then nm = surfMat elseif depth < l2 then nm = Materials.RoadBase elseif depth < l3 then nm = Materials.Aggregate end
				elseif depth < 1 then
					nm = Materials.Topsoil
				elseif m == 0 then
					nm = Materials.Aggregate
				end
				return nd, nm
			end)
			touched = touched + 1
		end
	end
	return { segments = touched }
end

function Carver.install(field)
	field:registerOp("Road", carve)
end

return Carver
