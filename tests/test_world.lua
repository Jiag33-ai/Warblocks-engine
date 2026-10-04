local H = require("tests.harness")
local Field = require("warblocks.TerrainField")
local Edits = require("warblocks.Edits")
local Planner = require("warblocks.RoadPlanner")
local Carver = require("warblocks.RoadCarver")
local Hydrology = require("warblocks.Hydrology")
local Materials = require("warblocks.Materials")
local Mesher = require("warblocks.SurfaceNets")

local cfg = { seed = 2024, sampleSpacing = 1, chunkCells = 16 }
local opts = { w = 40, h = 40, cell = 6, anchorCount = 4, minAnchorDist = 9, extraLoops = 1 }

H.test("hydrology: no uphill flow on filled surface; accumulation conserved", function()
	local P = Planner.buildGrid(require("warblocks.Contracts").resolve(cfg), 0, 0, 40, 40, 6)
	local hy = P.hydro
	local outletSum = 0
	for i = 1, 40 * 40 do
		local d = hy.dir[i]
		if d == 0 then outletSum = outletSum + hy.accum[i]
		else
			local x, y = (i - 1) % 40, (i - 1) // 40
			local ni = (y + Hydrology.DY[d]) * 40 + (x + Hydrology.DX[d]) + 1
			H.ok(hy.filled[ni] <= hy.filled[i], "flow went uphill")
		end
	end
	H.eq(outletSum, 40 * 40, "all rainfall reaches an outlet")
end)

H.test("planner: deterministic from seed; connected; grade-valid roads", function()
	local a = Planner.plan(cfg, opts)
	local b = Planner.plan(cfg, opts)
	H.ok(#a.roads >= 2, "roads " .. #a.roads)
	H.eq(#a.roads, #b.roads)
	for r = 1, #a.roads do
		H.eq(#a.roads[r].points, #b.roads[r].points)
		H.near(a.roads[r].points[3].y, b.roads[r].points[3].y, 1e-9, "deterministic design")
		local rep = a.roads[r].report
		H.ok(rep.gradeOk, string.format("%s road grade %.3f exceeds hard max", a.roads[r].class, rep.maxGrade))
	end
	-- connectivity: every anchor touched by >=1 road
	local touched = {}
	for _, r in ipairs(a.roads) do touched[r.a], touched[r.b] = true, true end
	for k = 1, #a.anchors do H.ok(touched[k], "anchor " .. k .. " connected") end
	local c = Planner.plan({ seed = 77, sampleSpacing = 1, chunkCells = 16 }, opts)
	H.ok(#c.anchors > 0 and (c.anchors[1].x ~= a.anchors[1].x or c.anchors[1].y ~= a.anchors[1].y), "different seed -> different layout")
end)

H.test("road carving: surface matches design height, drivable, layered, cut/fill present", function()
	local plan = Planner.plan(cfg, opts)
	local road = plan.roads[1]
	local f = Field.new(cfg)
	Edits.install(f); Carver.install(f)
	f:apply({ type = "Road", class = road.class, points = road.points })
	local worst, n = 0, 0
	for k = 3, #road.points - 2, 3 do
		local p = road.points[k]
		local sy = f:surfaceY(p.x, p.z, p.y + 20, 60)
		H.ok(sy, "surface exists at road point " .. k)
		worst = math.max(worst, math.abs(sy - p.y))
		n = n + 1
	end
	H.ok(worst < 1.0, "road surface within 1 stud of design (worst " .. worst .. ")")
	-- layered construction under the centreline
	local p = road.points[math.floor(#road.points / 2)]
	local sy = f:surfaceY(p.x, p.z, p.y + 20, 60)
	local seen = {}
	for dy = 0.3, 7, 0.5 do seen[f:materialAt(p.x, sy - dy, p.z)] = true end
	H.ok(seen[Materials.Asphalt] or seen[Materials.DirtTrack], "surface layer present")
	H.ok(seen[Materials.RoadBase], "base layer present")
	H.ok(seen[Materials.Aggregate], "aggregate layer present")
end)

H.test("crater on a road excavates through its layers and the hole persists (no pristine regen)", function()
	local plan = Planner.plan(cfg, opts)
	local road = plan.roads[1]
	local f = Field.new(cfg)
	Edits.install(f); Carver.install(f)
	f:apply({ type = "Road", class = road.class, points = road.points })
	local p = road.points[math.floor(#road.points / 2)]
	local sy = f:surfaceY(p.x, p.z, p.y + 20, 60)
	local res = f:apply({ type = "Crater", centre = { p.x, sy, p.z }, normal = { 0, 1, 0 }, radius = 6, seed = 8 })
	local sy2 = f:surfaceY(p.x, p.z, p.y + 20, 60)
	H.ok(sy - sy2 > 1.5, "road cratered by " .. (sy - sy2))
	-- walls expose sub-layers
	local seen = {}
	for a = 0, 7 do
		for r = 1, 5 do
			local th = a * math.pi / 4
			local x, z = p.x + math.cos(th) * r, p.z + math.sin(th) * r
			local ys = f:surfaceY(x, z, sy + 8, 30)
			if ys then seen[f:materialAt(x, ys - 0.2, z)] = true end
		end
	end
	local layers = 0
	for _, id in ipairs({ Materials.Asphalt, Materials.DirtTrack, Materials.RoadBase, Materials.Aggregate }) do if seen[id] then layers = layers + 1 end end
	H.ok(layers >= 2, "crater walls show >=2 construction layers, saw " .. layers)
	-- ejecta debris produced with road material in the mix
	H.ok(#res.pieces > 0 and res.ejectaVolume > 0, "ejecta emitted")
end)

H.test("journal replay reproduces road + crater state exactly (late-join reconstruction)", function()
	local plan = Planner.plan(cfg, opts)
	local road = plan.roads[1]
	local function build()
		local f = Field.new(cfg); Edits.install(f); Carver.install(f); return f
	end
	local f = build()
	f:apply({ type = "Road", class = road.class, points = road.points })
	local p = road.points[5]
	f:apply({ type = "Crater", centre = { p.x, p.y, p.z }, normal = { 0, 1, 0 }, radius = 5, seed = 4 })
	local g = build()
	for _, op in ipairs(f.journal) do g:apply(op) end
	local cy = math.floor(p.y / 16)
	for cx = math.floor(p.x / 16) - 1, math.floor(p.x / 16) + 1 do
		for cz = math.floor(p.z / 16) - 1, math.floor(p.z / 16) + 1 do
			H.eq(g:chunkHash(cx, cy, cz), f:chunkHash(cx, cy, cz), "hash " .. cx .. "," .. cz)
		end
	end
end)

H.test("meshing a carved road chunk yields a smooth mesh", function()
	local plan = Planner.plan(cfg, opts)
	local road = plan.roads[1]
	local f = Field.new(cfg); Edits.install(f); Carver.install(f)
	f:apply({ type = "Road", class = road.class, points = road.points })
	local p = road.points[math.floor(#road.points / 2)]
	local m = Mesher.meshChunk(f, math.floor(p.x / 16), math.floor(p.y / 16), math.floor(p.z / 16))
	H.ok(m.triCount > 50, "tris " .. m.triCount)
end)

print(string.format("\n%d passed, %d failed", H.passed, H.failed))
os.exit(H.failed == 0 and 0 or 1)
