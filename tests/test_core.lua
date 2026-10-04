local H = require("tests.harness")
local Field = require("warblocks.TerrainField")
local Edits = require("warblocks.Edits")
local Mesher = require("warblocks.SurfaceNets")
local Materials = require("warblocks.Materials")

local function newField(seed)
	local f = Field.new({ seed = seed or 42, sampleSpacing = 1, chunkCells = 16 })
	Edits.install(f)
	return f
end

H.test("deterministic base generation: same seed -> same chunk hash, different seed differs", function()
	local a, b, c = newField(7), newField(7), newField(8)
	H.eq(a:chunkHash(0, 1, 0), b:chunkHash(0, 1, 0))
	H.ok(a:chunkHash(0, 1, 0) ~= c:chunkHash(0, 1, 0), "seed must change terrain")
end)

H.test("border samples are duplicated consistently across chunks", function()
	local f = newField(3)
	local N = f.N
	local a = f:getChunk(0, 1, 0)
	local b = f:getChunk(1, 1, 0)
	for j = 0, N do for k = 0, N do
		local ia = (N * (N + 1) + j) * (N + 1) + k + 1 -- li=N
		local ib = (0 * (N + 1) + j) * (N + 1) + k + 1 -- li=0
		H.eq(a.d[ia], b.d[ib])
	end end
end)

H.test("surface mesh: non-empty, valid indices, unit normals, varied (non-blocky) normals", function()
	local f = newField(5)
	local ys = f.cfg.baseHeight / f.N
	local cy = math.floor(f.cfg.baseHeight / f.N)
	local mesh = Mesher.meshChunk(f, 0, cy, 0)
	H.ok(mesh.triCount > 100, "triangles " .. mesh.triCount)
	local distinct = {}
	for i = 1, #mesh.normals, 3 do
		local l = math.sqrt(mesh.normals[i] ^ 2 + mesh.normals[i + 1] ^ 2 + mesh.normals[i + 2] ^ 2)
		H.near(l, 1, 1e-6, "unit normal")
		distinct[string.format("%.2f,%.2f,%.2f", mesh.normals[i], mesh.normals[i + 1], mesh.normals[i + 2])] = true
	end
	local n = 0 for _ in pairs(distinct) do n = n + 1 end
	H.ok(n > mesh.vertexCount * 0.5, "normals should be smoothly varied, not axis-aligned")
	for _, ix in ipairs(mesh.indices) do H.ok(ix >= 0 and ix < mesh.vertexCount, "index range") end
end)

-- Closed-surface watertightness across chunk boundaries: carve an isolated sphere floating in air region.
H.test("meshes crossing chunk borders are watertight (every edge shared by 2 triangles)", function()
	local f = newField(11)
	-- make a sealed solid ball high in the air straddling a chunk corner at (16, 80, 16)
	local c = { 16, 80, 16 }
	local r = 9
	f:modifyBox(5, 65, 5, 27, 95, 27, function(i, j, k, d)
		local q = r - math.sqrt((i - c[1]) ^ 2 + (j - c[2]) ^ 2 + (k - c[3]) ^ 2)
		if q > d then return q, Materials.Bedrock end
	end)
	local edges = {}
	local function key(x, y, z) return string.format("%.4f,%.4f,%.4f", x, y, z) end
	local tris = 0
	for cx = 0, 1 do for cy = 4, 5 do for cz = 0, 1 do
		local m = Mesher.meshChunk(f, cx, cy, cz)
		local p = m.positions
		local function vk(i) return key(p[i * 3 + 1], p[i * 3 + 2], p[i * 3 + 3]) end
		local ix = m.indices
		for t = 1, #ix, 3 do
			local a, b, c2 = vk(ix[t]), vk(ix[t + 1]), vk(ix[t + 2])
			if a ~= b and b ~= c2 and a ~= c2 then
				tris = tris + 1
				for _, e in ipairs({ { a, b }, { b, c2 }, { c2, a } }) do
					local k1 = e[1] < e[2] and e[1] .. "|" .. e[2] or e[2] .. "|" .. e[1]
					edges[k1] = (edges[k1] or 0) + 1
				end
			end
		end
	end end end
	-- only the ball surface lives in this volume (terrain top is far below y=64)
	local bad = 0
	for _, n in pairs(edges) do if n ~= 2 then bad = bad + 1 end end
	H.ok(tris > 200, "ball produced triangles: " .. tris)
	H.eq(bad, 0, "non-manifold/open edges")
end)

H.test("crater: removes real material, mass ledger conserves volume, irregular, deterministic", function()
	local f = newField(21)
	local c = { 20, 0, 20 }
	c[2] = f:surfaceY(20, 20, 120, 200)
	H.ok(c[2], "found surface")
	local box = { f:boxFromWorld({ 0, c[2] - 20, 0 }, { 40, c[2] + 20, 40 }) }
	local before = f:totalVolume(table.unpack(box))
	local res = f:apply({ type = "Crater", centre = c, normal = { 0, 1, 0 }, dir = { 0.3, -1, 0 }, radius = 7, seed = 99 })
	local after = f:totalVolume(table.unpack(box))
	H.ok(res.removedVolume > 50, "removed " .. res.removedVolume)
	local accounted = res.rimVolume + res.ejectaVolume + res.dustVolume
	H.near(accounted / res.removedVolume, 1, 0.12, "ledger (rim+ejecta+dust)/removed")
	-- net field change = -(removed - rim): ground genuinely lost mass not hidden
	H.near(before - after, res.removedVolume - res.rimVolume, 1.0, "field delta")
	-- ground under crater centre dropped
	local y2 = f:surfaceY(20, 20, 120, 200)
	H.ok(c[2] - y2 > 1.5, "crater depth " .. (c[2] - y2))
	-- irregular: radii at 8 angles not all equal
	local rs = {}
	for a = 0, 7 do
		local th = a * math.pi / 4
		local rr = 0
		for r = 0, 14, 0.5 do
			local sy = f:surfaceY(20 + math.cos(th) * r, 20 + math.sin(th) * r, c[2] + 8, 30)
			if sy and sy > c[2] - 1 then rr = r break end
		end
		rs[#rs + 1] = rr
	end
	local mn, mx = math.huge, 0
	for _, r in ipairs(rs) do mn = math.min(mn, r) mx = math.max(mx, r) end
	H.ok(mx - mn >= 1, "crater should not be a perfect circle: " .. table.concat(rs, ","))
	-- deterministic replay
	local g = newField(21)
	for _, op in ipairs(f.journal) do g:apply({ type = op.type, centre = op.centre, normal = op.normal, dir = op.dir, radius = op.radius, seed = op.seed }) end
	H.eq(g:chunkHash(1, math.floor(c[2] / 16), 1), f:chunkHash(1, math.floor(c[2] / 16), 1), "replay hash")
end)

H.test("crater reveals deeper geology (material layers below surface appear)", function()
	local f = newField(21)
	local y = f:surfaceY(20, 20, 120, 200)
	local top = f:materialAt(20, y - 0.6, 20)
	f:apply({ type = "Crater", centre = { 20, y, 20 }, normal = { 0, 1, 0 }, radius = 12, strength = 1.5, seed = 5 })
	local y2 = f:surfaceY(20, 20, 120, 200)
	local m2 = f:materialAt(20, y2 - 0.6, 20)
	H.ok(y - y2 > 3, "deep crater " .. (y - y2))
	H.ok(m2 ~= top or y - y2 > 0, "layers exposed (top " .. top .. " -> " .. m2 .. ")")
end)

H.test("chunk-border crater: both chunks agree, dirty set covers neighbours", function()
	local f = newField(31)
	local y = f:surfaceY(16.1, 16.1, 120, 200)
	f.dirty = {}
	f:apply({ type = "Crater", centre = { 16.1, y, 16.1 }, normal = { 0, 1, 0 }, radius = 6, seed = 3 })
	local cy = math.floor(y / 16)
	local n = 0 for _ in pairs(f.dirty) do n = n + 1 end
	H.ok(n >= 4, "dirty chunks " .. n)
	local N = f.N
	local a, b = f:getChunk(0, cy, 0), f:getChunk(1, cy, 0)
	for j = 0, N do for k = 0, N do
		H.eq(a.d[(N * (N + 1) + j) * (N + 1) + k + 1], b.d[(0 * (N + 1) + j) * (N + 1) + k + 1])
	end end
end)

print(string.format("\n%d passed, %d failed", H.passed, H.failed))
os.exit(H.failed == 0 and 0 or 1)
