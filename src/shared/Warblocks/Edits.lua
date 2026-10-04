-- Destruction operations on the volumetric field: spheres, craters (bowl + irregular rim + ejecta ledger).
local function req(n) if script then return require(script.Parent[n]) end return require("warblocks." .. n) end
local Noise = req("Noise")
local Rng = req("Rng")
local Materials = req("Materials")

local Edits = {}
local sqrt, cos, sin, atan2, floor, abs, pi = math.sqrt, math.cos, math.sin, math.atan2 or math.atan, math.floor, math.abs, math.pi

local function norm(v)
	local l = sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
	if l < 1e-9 then return { 0, 1, 0 } end
	return { v[1] / l, v[2] / l, v[3] / l }
end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end

-- Simple sphere subtraction. op = {type="Sphere", centre={}, radius}
local function sphere(field, op)
	local c, r = op.centre, op.radius
	local i0, j0, k0, i1, j1, k1 = field:boxFromWorld({ c[1] - r, c[2] - r, c[3] - r }, { c[1] + r, c[2] + r, c[3] + r })
	local S = field.S
	local removed = field:modifyBox(i0, j0, k0, i1, j1, k1, function(i, j, k, d)
		local dist = sqrt((i * S - c[1]) ^ 2 + (j * S - c[2]) ^ 2 + (k * S - c[3]) ^ 2)
		local q = dist - r
		if q < d then return q end
	end)
	return { removedVolume = -removed }
end

-- Crater op: {type="Crater", centre, normal, dir, radius, strength, seed}
local function craterCutter(op, res)
	local c = op.centre
	local n = norm(op.normal or { 0, 1, 0 })
	local ref = abs(n[2]) < 0.9 and { 0, 1, 0 } or { 1, 0, 0 }
	local u = norm(cross(ref, n))
	local v = cross(n, u)
	-- directional elongation along the projectile's tangent component
	local dirv = op.dir or { 0, -1, 0 }
	local dt = { dirv[1] - dot(dirv, n) * n[1], dirv[2] - dot(dirv, n) * n[2], dirv[3] - dot(dirv, n) * n[3] }
	local dl = sqrt(dot(dt, dt))
	local elong = math.min(0.6, dl) * 0.5
	local ea = dl > 1e-6 and atan2(dot(dt, v), dot(dt, u)) or 0
	local R = op.radius / (res ^ 0.5) * (op.strength or 1)
	local depth = R * 0.5 / (res ^ 0.6)
	local seed = op.seed or 0
	local irr = 0.22
	local rough = 0.12 * R / res
	return {
		R = R, depth = depth, n = n, u = u, v = v, c = c, seed = seed,
		-- cutter value (positive = removed) and polar quantities at world point
		eval = function(px, py, pz)
			local rx, ry, rz = px - c[1], py - c[2], pz - c[3]
			local h = rx * n[1] + ry * n[2] + rz * n[3]
			local a, b = rx * u[1] + ry * u[2] + rz * u[3], rx * v[1] + ry * v[2] + rz * v[3]
			local th = atan2(b, a)
			local rh = sqrt(a * a + b * b)
			local Rt = R * (1 + irr * Noise.perlin2(cos(th) * 1.3 + seed * 0.37, sin(th) * 1.3 + 11.3, seed))
			Rt = Rt * (1 + elong * cos(th - ea))
			return h, rh, Rt
		end,
		bowl = function(t) -- t = r/Rt in [0,1)
			local s = 1 - t * t
			return depth * s * s
		end,
		rough = rough,
	}
end

local function crater(field, op)
	local c = op.centre
	-- resistance from the material at/under the impact point
	local sy = field:surfaceY(c[1], c[3], c[2] + 2, 12) or c[2]
	local m0 = field:materialAt(c[1], sy - 0.6 * field.S, c[3])
	local def = Materials.byId[m0] or Materials.byId[1]
	local res = def.blastResistance > 0 and def.blastResistance or 1
	local cut = craterCutter(op, res)
	local ext = cut.R * 1.5 + cut.depth + 2
	local box = { c[1] - ext, c[2] - ext, c[3] - ext }
	local boxMax = { c[1] + ext, c[2] + ext, c[3] + ext }
	local i0, j0, k0, i1, j1, k1 = field:boxFromWorld(box, boxMax)
	local S = field.S
	local cap = cut.R * 0.8

	local before = field:totalVolume(i0, j0, k0, i1, j1, k1)
	local topMat = field:materialAt(c[1], sy - 0.5 * S, c[3])

	field:modifyBox(i0, j0, k0, i1, j1, k1, function(i, j, k, d, m)
		local h, rh, Rt = cut.eval(i * S, j * S, k * S)
		if rh >= Rt then return end
		local t = rh / Rt
		local q = math.min(Rt - rh, h + cut.bowl(t), cap - h)
		-- fracture roughness: 3D noise gouges, scaled by material hardness
		q = q + Noise.perlin3(i * S * 0.35, j * S * 0.35, k * S * 0.35, cut.seed + 5) * cut.rough
		if -q < d then return -q end
	end)
	local after = field:totalVolume(i0, j0, k0, i1, j1, k1)
	local removed = before - after

	-- Mass ledger: dust is lost, ejecta leaves as debris, remainder rebuilds the rim.
	local dust = removed * def.dustFraction
	local ejecta = removed * def.ejectionBias * (1 - def.dustFraction) * 0.6
	local rimTarget = removed - dust - ejecta

	local rimMat = (topMat ~= 0 and topMat) or Materials.Rubble
	-- Rim = extra solid thickness raised on the local ground (never fills natural lows): gather once, solve amplitude.
	local cands = {}
	for i = i0, i1 do for j = j0, j1 do for k = k0, k1 do
		local h, rh, Rt = cut.eval(i * S, j * S, k * S)
		if rh >= Rt * 0.98 and rh <= Rt * 1.9 then
			local d = field:get(i, j, k)
			if d < 6 and d > -cut.R then
				local t = (rh - Rt) / (Rt * 0.9)
				if t < 0 then t = 0 end
				local shape = sin(pi * t) ^ 1.5 * (1 + 0.35 * Noise.perlin2(i * S * 0.2, k * S * 0.2, cut.seed + 9))
				cands[#cands + 1] = { i, j, k, d, shape }
			end
		end
	end end end
	local v3 = S ^ 3
	local function rimVol(amp)
		local v = 0
		for n = 1, #cands do
			local c2 = cands[n]
			local nd = c2[4] + amp * c2[5]
			v = v + (field:occ(nd) - field:occ(c2[4])) * v3
		end
		return v
	end
	local lo, hi = 0, cut.R * 0.7
	for _ = 1, 12 do
		local mid = (lo + hi) / 2
		if rimVol(mid) < rimTarget then lo = mid else hi = mid end
	end
	local amp = (lo + hi) / 2
	local rimAdded = field:modifyBox(i0, j0, k0, i1, j1, k1, function(i, j, k, d, m)
		-- only candidate samples change; recompute shape through the same cutter
		local h, rh, Rt = cut.eval(i * S, j * S, k * S)
		if rh < Rt * 0.98 or rh > Rt * 1.9 or d >= 6 or d <= -cut.R then return end
		local t = (rh - Rt) / (Rt * 0.9)
		if t < 0 then t = 0 end
		local shape = sin(pi * t) ^ 1.5 * (1 + 0.35 * Noise.perlin2(i * S * 0.2, k * S * 0.2, cut.seed + 9))
		local nd = d + amp * shape
		if nd > d then return nd, (d <= 0 and nd > 0) and rimMat or nil end
	end)

	-- Ejecta chunks (volumes + launch direction) for debris/rubble spawning; deterministic from op seed.
	local rng = Rng.new(cut.seed + 77)
	local pieces, count = {}, math.max(1, math.min(24, floor(ejecta / (S ^ 3 * 2)) + 1))
	for p = 1, count do
		local ang = rng:range(0, 2 * pi)
		local spd = rng:range(0.5, 1) * cut.R
		pieces[p] = {
			volume = ejecta / count,
			material = rimMat,
			origin = { c[1], c[2] + 0.5, c[3] },
			velocity = {
				cut.n[1] * spd * 1.2 + (cos(ang) * cut.u[1] + sin(ang) * cut.v[1]) * spd,
				cut.n[2] * spd * 1.2 + (cos(ang) * cut.u[2] + sin(ang) * cut.v[2]) * spd,
				cut.n[3] * spd * 1.2 + (cos(ang) * cut.u[3] + sin(ang) * cut.v[3]) * spd,
			},
		}
	end
	return { removedVolume = removed, rimVolume = rimAdded, ejectaVolume = ejecta, dustVolume = dust, pieces = pieces,
		radius = cut.R, depth = cut.depth, material = m0 }
end

function Edits.install(field)
	field:registerOp("Sphere", sphere)
	field:registerOp("Crater", crater)
end

return Edits
