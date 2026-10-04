-- Seed-driven road network: anchors -> MST (+loops) -> cost-field A* -> smoothing -> grade-limited design profile.
local function req(n) if script then return require(script.Parent[n]) end return require("warblocks." .. n) end
local Rng = req("Rng")
local Contracts = req("Contracts")
local BaseTerrain = req("BaseTerrain")
local Hydrology = req("Hydrology")

local Planner = {}
local sqrt, floor, abs = math.sqrt, math.floor, math.abs

Planner.CLASSES = {
	Primary = { width = 8, shoulder = 2, maxPreferredGrade = 0.06, hardMaxGrade = 0.10, minTurnRadius = 24, cutSlope = 1.0, fillSlope = 0.8, layers = { 1, 2, 3 }, surface = "Asphalt", slopeWeight = 40 },
	Secondary = { width = 6, shoulder = 1.5, maxPreferredGrade = 0.09, hardMaxGrade = 0.14, minTurnRadius = 14, cutSlope = 1.2, fillSlope = 1.0, layers = { 1, 2, 3 }, surface = "Asphalt", slopeWeight = 25 },
	Track = { width = 4, shoulder = 1, maxPreferredGrade = 0.14, hardMaxGrade = 0.20, minTurnRadius = 8, cutSlope = 1.5, fillSlope = 1.2, layers = { 0.8, 1.5, 2 }, surface = "DirtTrack", slopeWeight = 10 },
}

-- Build the planning grid from the seed. cell = studs per planning cell.
function Planner.buildGrid(cfg, originX, originZ, w, h, cell)
	local heights = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			heights[y * w + x + 1] = BaseTerrain.height(cfg, originX + x * cell, originZ + y * cell)
		end
	end
	local hydro = Hydrology.compute(heights, w, h)
	local slope = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local function H(a, b)
				a = math.max(0, math.min(w - 1, a)); b = math.max(0, math.min(h - 1, b))
				return heights[b * w + a + 1]
			end
			local gx = (H(x + 1, y) - H(x - 1, y)) / (2 * cell)
			local gy = (H(x, y + 1) - H(x, y - 1)) / (2 * cell)
			slope[y * w + x + 1] = sqrt(gx * gx + gy * gy)
		end
	end
	return { w = w, h = h, cell = cell, ox = originX, oz = originZ, heights = heights, slope = slope, hydro = hydro }
end

-- Deterministic blue-noise anchor selection on suitable (flat, dry) cells.
function Planner.anchors(grid, seed, count, minDist)
	local rng = Rng.new(seed + 4242)
	local list, tries = {}, 0
	local maxAccum = grid.w * grid.h * 0.02
	while #list < count and tries < count * 400 do
		tries = tries + 1
		local x, y = rng:int(3, grid.w - 4), rng:int(3, grid.h - 4)
		local i = y * grid.w + x + 1
		if grid.slope[i] < 0.12 and grid.hydro.accum[i] < maxAccum then
			local ok = true
			for _, a in ipairs(list) do
				if sqrt((a.x - x) ^ 2 + (a.y - y) ^ 2) < minDist then ok = false break end
			end
			if ok then list[#list + 1] = { x = x, y = y } end
		end
	end
	return list
end

-- MST (Prim) + a few extra shortest non-tree edges for loops. Returns edges {a,b,class}.
function Planner.graph(anchors, seed, extraLoops)
	local n = #anchors
	local function dist(a, b) return sqrt((anchors[a].x - anchors[b].x) ^ 2 + (anchors[a].y - anchors[b].y) ^ 2) end
	local inTree, edges, used = { [1] = true }, {}, {}
	for _ = 2, n do
		local best, ba, bb = math.huge, nil, nil
		for a = 1, n do
			if inTree[a] then
				for b = 1, n do
					if not inTree[b] then
						local d = dist(a, b)
						if d < best then best, ba, bb = d, a, b end
					end
				end
			end
		end
		if not bb then break end
		inTree[bb] = true
		edges[#edges + 1] = { a = ba, b = bb, len = best }
		used[ba .. "-" .. bb], used[bb .. "-" .. ba] = true, true
	end
	local cands = {}
	for a = 1, n do for b = a + 1, n do
		if not used[a .. "-" .. b] then cands[#cands + 1] = { a = a, b = b, len = dist(a, b) } end
	end end
	table.sort(cands, function(p, q) return p.len < q.len end)
	local rng = Rng.new(seed + 99)
	for k = 1, math.min(extraLoops, #cands) do
		local c = cands[k]
		if c.len < 2.2 * (edges[1] and edges[1].len or c.len) or rng:next() < 0.5 then edges[#edges + 1] = c end
	end
	-- hierarchy: longest-spanning/central edges Primary, the rest Secondary/Track by length rank
	table.sort(edges, function(p, q) return p.len > q.len end)
	for k, e in ipairs(edges) do
		e.class = (k <= math.max(1, floor(#edges * 0.4))) and "Primary" or ((k <= floor(#edges * 0.8)) and "Secondary" or "Track")
	end
	return edges
end

-- A* over the cost field. reuse = set of cells already roaded (cheap to follow -> merges/junctions).
function Planner.route(grid, a, b, class, reuse)
	local cls = Planner.CLASSES[class]
	local w, h, cell = grid.w, grid.h, grid.cell
	local DX, DY = Hydrology.DX, Hydrology.DY
	local function idx(x, y) return y * w + x + 1 end
	local goal = idx(b.x, b.y)
	local open, g, came, closed = {}, {}, {}, {}
	local function push(i, f)
		local n = #open + 1
		open[n] = { f, i }
		while n > 1 do
			local p = n // 2
			if open[p][1] <= open[n][1] then break end
			open[p], open[n] = open[n], open[p]
			n = p
		end
	end
	local function pop()
		local top = open[1]
		local last = table.remove(open)
		if #open > 0 then
			open[1] = last
			local n, sz = 1, #open
			while true do
				local l, r, s = n * 2, n * 2 + 1, n
				if l <= sz and open[l][1] < open[s][1] then s = l end
				if r <= sz and open[r][1] < open[s][1] then s = r end
				if s == n then break end
				open[s], open[n] = open[n], open[s]
				n = s
			end
		end
		return top
	end
	local start = idx(a.x, a.y)
	g[start] = 0
	push(start, 0)
	local wetLimit = w * h * 0.01
	while #open > 0 do
		local top = pop()
		local i = top[2]
		if i == goal then break end
		if not closed[i] then
			closed[i] = true
			local x, y = (i - 1) % w, (i - 1) // w
			for d = 1, 8 do
				local nx, ny = x + DX[d], y + DY[d]
				if nx >= 0 and ny >= 0 and nx < w and ny < h then
					local ni = idx(nx, ny)
					local step = ((DX[d] ~= 0 and DY[d] ~= 0) and 1.4142 or 1) * cell
					local grade = abs(grid.heights[ni] - grid.heights[i]) / step
					if grade <= cls.hardMaxGrade * 1.8 and not closed[ni] then -- raw terrain grade; earthworks flatten the rest
						local pen = 1 + cls.slopeWeight * grade * grade
						if grade > cls.maxPreferredGrade then pen = pen + (grade - cls.maxPreferredGrade) * 30 end
						if grid.hydro.accum[ni] > wetLimit then pen = pen + 4 end -- avoid channels unless crossing is cheap
						if reuse[ni] then pen = pen * 0.35 end
						local ng = g[i] + step * pen
						if not g[ni] or ng < g[ni] then
							g[ni] = ng
							came[ni] = i
							local hx = sqrt((nx - b.x) ^ 2 + (ny - b.y) ^ 2) * cell
							push(ni, ng + hx)
						end
					end
				end
			end
		end
	end
	if not came[goal] and goal ~= start then return nil end
	local path, i = {}, goal
	while i do
		table.insert(path, 1, { (i - 1) % w, (i - 1) // w })
		i = came[i]
	end
	return path
end

-- Smooth the path in XZ, resample, build grade-limited design profile. Returns points {x,z,y,terrainY}.
function Planner.design(cfg, grid, path, class)
	local cls = Planner.CLASSES[class]
	local pts = {}
	for k, p in ipairs(path) do pts[k] = { grid.ox + p[1] * grid.cell, grid.oz + p[2] * grid.cell } end
	for _ = 1, 4 do -- moving-average smoothing, endpoints pinned
		local nxt = { pts[1] }
		for k = 2, #pts - 1 do
			nxt[k] = { (pts[k - 1][1] + 2 * pts[k][1] + pts[k + 1][1]) / 4, (pts[k - 1][2] + 2 * pts[k][2] + pts[k + 1][2]) / 4 }
		end
		nxt[#pts] = pts[#pts]
		pts = nxt
	end
	-- resample at ~cell/2 spacing
	local step = grid.cell * 0.5
	local out = { { pts[1][1], pts[1][2] } }
	local acc = 0
	for k = 2, #pts do
		local ax, az, bx, bz = pts[k - 1][1], pts[k - 1][2], pts[k][1], pts[k][2]
		local seg = sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local t = step - acc
		while t <= seg do
			out[#out + 1] = { ax + (bx - ax) * t / seg, az + (bz - az) * t / seg }
			t = t + step
		end
		acc = seg - (t - step)
	end
	local last = pts[#pts]
	local lo = out[#out]
	if sqrt((lo[1] - last[1]) ^ 2 + (lo[2] - last[2]) ^ 2) > 0.5 then out[#out + 1] = { last[1], last[2] } end
	for _, p in ipairs(out) do p[4] = BaseTerrain.height(cfg, p[1], p[2]); p[3] = p[4] end
	-- smooth design profile (longitudinal), then enforce preferred grade by forward/backward clamping
	for _ = 1, 6 do
		for k = 2, #out - 1 do out[k][3] = (out[k - 1][3] + 2 * out[k][3] + out[k + 1][3]) / 4 end
	end
	local function seg(k) return sqrt((out[k][1] - out[k - 1][1]) ^ 2 + (out[k][2] - out[k - 1][2]) ^ 2) end
	local g = cls.maxPreferredGrade
	for _ = 1, 3 do
		for k = 2, #out do
			local lim = g * seg(k)
			local dh = out[k][3] - out[k - 1][3]
			if dh > lim then out[k][3] = out[k - 1][3] + lim elseif dh < -lim then out[k][3] = out[k - 1][3] - lim end
		end
		for k = #out - 1, 1, -1 do
			local lim = g * seg(k + 1)
			local dh = out[k][3] - out[k + 1][3]
			if dh > lim then out[k][3] = out[k + 1][3] + lim elseif dh < -lim then out[k][3] = out[k + 1][3] - lim end
		end
	end
	local pts3 = {}
	for k, p in ipairs(out) do pts3[k] = { x = p[1], z = p[2], y = p[3], terrainY = p[4] } end
	return pts3
end

-- Validate a designed road: max grade, min turning radius (3-point circumradius), earthwork depth.
function Planner.validate(points, class)
	local cls = Planner.CLASSES[class]
	local maxGrade, minR, maxCut = 0, math.huge, 0
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local s = sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		if s > 1e-6 then maxGrade = math.max(maxGrade, abs(b.y - a.y) / s) end
		maxCut = math.max(maxCut, abs(b.y - b.terrainY))
	end
	for k = 2, #points - 1 do
		local a, b, c = points[k - 1], points[k], points[k + 1]
		local ab = sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local bc = sqrt((c.x - b.x) ^ 2 + (c.z - b.z) ^ 2)
		local ca = sqrt((a.x - c.x) ^ 2 + (a.z - c.z) ^ 2)
		local area2 = abs((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x))
		if area2 > 1e-6 then minR = math.min(minR, ab * bc * ca / (2 * area2)) end
	end
	return { maxGrade = maxGrade, minRadius = minR, maxEarthwork = maxCut,
		gradeOk = maxGrade <= cls.hardMaxGrade + 1e-6, radiusOk = minR >= cls.minTurnRadius * 0.5 }
end

-- Full pipeline from seed. Returns {grid, anchors, edges, roads, junctions}.
function Planner.plan(cfg, opts)
	cfg = Contracts.resolve(cfg)
	local grid = Planner.buildGrid(cfg, opts.originX or 0, opts.originZ or 0, opts.w, opts.h, opts.cell)
	local anchors = Planner.anchors(grid, cfg.seed, opts.anchorCount or 5, opts.minAnchorDist or 10)
	local edges = Planner.graph(anchors, cfg.seed, opts.extraLoops or 1)
	local reuse, roads, deg = {}, {}, {}
	table.sort(edges, function(p, q) return p.class < q.class end) -- Primary first so others merge into them
	for _, e in ipairs(edges) do
		local path = Planner.route(grid, anchors[e.a], anchors[e.b], e.class, reuse)
		if path then
			for _, p in ipairs(path) do
				local i = p[2] * grid.w + p[1] + 1
				reuse[i] = true
				deg[i] = (deg[i] or 0) + 1
			end
			local pts = Planner.design(cfg, grid, path, e.class)
			roads[#roads + 1] = { class = e.class, points = pts, a = e.a, b = e.b, report = Planner.validate(pts, e.class) }
		end
	end
	local junctions = {}
	for i, dcount in pairs(deg) do
		if dcount >= 3 then junctions[#junctions + 1] = { x = grid.ox + ((i - 1) % grid.w) * grid.cell, z = grid.oz + ((i - 1) // grid.w) * grid.cell, roads = dcount } end
	end
	table.sort(junctions, function(p, q) return p.x == q.x and p.z < q.z or p.x < q.x end)
	return { grid = grid, anchors = anchors, edges = edges, roads = roads, junctions = junctions }
end

return Planner
