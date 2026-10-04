-- Smooth isosurface extraction (Naive Surface Nets) over the global lattice.
-- Chunk c emits quads whose owner cell (min-corner cell) lies in its cell range; vertices are pure functions
-- of global samples, so neighbouring chunk meshes share identical boundary vertices (crack-free by position).
local Mesher = {}
local floor, sqrt = math.floor, math.sqrt

local CORNERS = {
	{ 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
}
local EDGES = {
	{ 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 }, { 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

-- Returns {positions={x,y,z,...}, normals={...}, materials={...per vertex}, indices={...}, triCount}
function Mesher.meshChunk(field, cx, cy, cz)
	local N, S = field.N, field.S
	local verts, normals, mats, indices = {}, {}, {}, {}
	local cache = {}
	local nv = 0

	local function gradient(i, j, k)
		local dx = field:get(i + 1, j, k) - field:get(i - 1, j, k)
		local dy = field:get(i, j + 1, k) - field:get(i, j - 1, k)
		local dz = field:get(i, j, k + 1) - field:get(i, j, k - 1)
		return dx, dy, dz
	end

	-- vertex index for cell (i,j,k) or nil if the cell does not straddle the surface
	local function cellVertex(i, j, k)
		local key = (i * 4096 + j) * 4096 + k
		local c = cache[key]
		if c ~= nil then return c or nil end
		local dv, mv = {}, {}
		local neg, pos = 0, 0
		for n = 1, 8 do
			local o = CORNERS[n]
			local d, m = field:get(i + o[1], j + o[2], k + o[3])
			dv[n], mv[n] = d, m
			if d > 0 then pos = pos + 1 else neg = neg + 1 end
		end
		if pos == 0 or neg == 0 then
			cache[key] = false
			return nil
		end
		local sx, sy, sz, cnt = 0, 0, 0, 0
		for e = 1, 12 do
			local a, b = EDGES[e][1], EDGES[e][2]
			local da, db = dv[a], dv[b]
			if (da > 0) ~= (db > 0) then
				local t = da / (da - db)
				local oa, ob = CORNERS[a], CORNERS[b]
				sx = sx + oa[1] + (ob[1] - oa[1]) * t
				sy = sy + oa[2] + (ob[2] - oa[2]) * t
				sz = sz + oa[3] + (ob[3] - oa[3]) * t
				cnt = cnt + 1
			end
		end
		local px, py, pz = (i + sx / cnt) * S, (j + sy / cnt) * S, (k + sz / cnt) * S
		-- gradient normal: trilinear blend of corner gradients at vertex local coords
		local lx, ly, lz = sx / cnt, sy / cnt, sz / cnt
		local gx, gy, gz = 0, 0, 0
		for n = 1, 8 do
			local o = CORNERS[n]
			local w = (o[1] == 1 and lx or 1 - lx) * (o[2] == 1 and ly or 1 - ly) * (o[3] == 1 and lz or 1 - lz)
			local ax, ay, az = gradient(i + o[1], j + o[2], k + o[3])
			gx, gy, gz = gx + ax * w, gy + ay * w, gz + az * w
		end
		local len = sqrt(gx * gx + gy * gy + gz * gz)
		if len < 1e-9 then gx, gy, gz, len = 0, 1, 0, 1 end
		-- material: the solid corner nearest the vertex (dominant material)
		local best, bm = 1e9, 0
		for n = 1, 8 do
			if dv[n] > 0 then
				local o = CORNERS[n]
				local dd = (o[1] - lx) ^ 2 + (o[2] - ly) ^ 2 + (o[3] - lz) ^ 2
				if dd < best then best, bm = dd, mv[n] end
			end
		end
		local vi = nv
		nv = nv + 1
		verts[#verts + 1], verts[#verts + 2], verts[#verts + 3] = px, py, pz
		-- density gradient points into solid; outward normal is its negation
		normals[#normals + 1], normals[#normals + 2], normals[#normals + 3] = -gx / len, -gy / len, -gz / len
		mats[nv] = bm
		cache[key] = vi
		return vi
	end

	local function quad(a, b, c, d, flip)
		if not (a and b and c and d) then return end
		if flip then a, b, c, d = a, d, c, b end
		indices[#indices + 1], indices[#indices + 2], indices[#indices + 3] = a, b, c
		indices[#indices + 1], indices[#indices + 2], indices[#indices + 3] = a, c, d
	end

	local i0, j0, k0 = cx * N, cy * N, cz * N
	for i = i0, i0 + N - 1 do
		for j = j0, j0 + N - 1 do
			for k = k0, k0 + N - 1 do
				-- edges leaving this cell's min corner along +x,+y,+z, crossing owned by this cell
				local d0 = field:get(i, j, k)
				local s0 = d0 > 0
				if (field:get(i + 1, j, k) > 0) ~= s0 then
					quad(cellVertex(i, j, k), cellVertex(i, j - 1, k), cellVertex(i, j - 1, k - 1), cellVertex(i, j, k - 1), not s0)
				end
				if (field:get(i, j + 1, k) > 0) ~= s0 then
					quad(cellVertex(i, j, k), cellVertex(i, j, k - 1), cellVertex(i - 1, j, k - 1), cellVertex(i - 1, j, k), not s0)
				end
				if (field:get(i, j, k + 1) > 0) ~= s0 then
					quad(cellVertex(i, j, k), cellVertex(i - 1, j, k), cellVertex(i - 1, j - 1, k), cellVertex(i, j - 1, k), not s0)
				end
			end
		end
	end
	return { positions = verts, normals = normals, materials = mats, indices = indices, vertexCount = nv, triCount = #indices / 3 }
end

return Mesher
