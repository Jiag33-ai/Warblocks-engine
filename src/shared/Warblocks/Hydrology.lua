-- Planning-scale hydrology: priority-flood depression filling, D8 flow direction, flow accumulation.
local Hydrology = {}

local DX = { 1, 1, 0, -1, -1, -1, 0, 1 }
local DY = { 0, 1, 1, 1, 0, -1, -1, -1 }
Hydrology.DX, Hydrology.DY = DX, DY

-- binary min-heap keyed by value
local function heapPush(h, key, v)
	local n = #h + 1
	h[n] = { key, v }
	while n > 1 do
		local p = n // 2
		if h[p][1] <= h[n][1] then break end
		h[p], h[n] = h[n], h[p]
		n = p
	end
end
local function heapPop(h)
	local top = h[1]
	local last = table.remove(h)
	if #h > 0 then
		h[1] = last
		local n, sz = 1, #h
		while true do
			local l, r, s = n * 2, n * 2 + 1, n
			if l <= sz and h[l][1] < h[s][1] then s = l end
			if r <= sz and h[r][1] < h[s][1] then s = r end
			if s == n then break end
			h[s], h[n] = h[n], h[s]
			n = s
		end
	end
	return top
end

-- heights: flat array, index = y*w + x + 1. Returns {filled, dir (0 = outlet, 1..8), accum, w, h}
function Hydrology.compute(heights, w, h)
	local filled, closed, heap = {}, {}, {}
	local eps = 1e-4
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x + 1
			filled[i] = heights[i]
			if x == 0 or y == 0 or x == w - 1 or y == h - 1 then
				closed[i] = true
				heapPush(heap, heights[i], i)
			end
		end
	end
	while #heap > 0 do
		local top = heapPop(heap)
		local i = top[2]
		local x, y = (i - 1) % w, (i - 1) // w
		for d = 1, 8 do
			local nx, ny = x + DX[d], y + DY[d]
			if nx >= 0 and ny >= 0 and nx < w and ny < h then
				local ni = ny * w + nx + 1
				if not closed[ni] then
					closed[ni] = true
					local fh = filled[i] + eps
					if heights[ni] > fh then fh = heights[ni] end
					filled[ni] = fh
					heapPush(heap, fh, ni)
				end
			end
		end
	end
	local dir, order = {}, {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x + 1
			order[#order + 1] = i
			local best, bd = 0, 0
			for d = 1, 8 do
				local nx, ny = x + DX[d], y + DY[d]
				if nx >= 0 and ny >= 0 and nx < w and ny < h then
					local drop = (filled[i] - filled[ny * w + nx + 1]) / ((DX[d] ~= 0 and DY[d] ~= 0) and 1.4142 or 1)
					if drop > bd then bd, best = drop, d end
				end
			end
			dir[i] = best
		end
	end
	table.sort(order, function(a, b) return filled[a] > filled[b] end)
	local accum = {}
	for i = 1, w * h do accum[i] = 1 end
	for _, i in ipairs(order) do
		local d = dir[i]
		if d ~= 0 then
			local x, y = (i - 1) % w, (i - 1) // w
			local ni = (y + DY[d]) * w + (x + DX[d]) + 1
			accum[ni] = accum[ni] + accum[i]
		end
	end
	return { filled = filled, dir = dir, accum = accum, w = w, h = h }
end

return Hydrology
