-- Sparse chunked volumetric field (density + material per lattice sample), edits via ordered journal.
-- NOTE: flat Lua arrays here for portability/testing; production swaps to `buffer` storage (same API).
local function req(n) if script then return require(script.Parent[n]) end return require("warblocks." .. n) end
local Contracts = req("Contracts")
local BaseTerrain = req("BaseTerrain")
local Materials = req("Materials")

local floor, ceil = math.floor, math.ceil
local M32 = 4294967296

local Field = {}
Field.__index = Field

function Field.new(cfg)
	local c = {}
	for k, v in pairs(Contracts.DEFAULT_CONFIG) do c[k] = v end
	for k, v in pairs(cfg or {}) do c[k] = v end
	return setmetatable({
		cfg = c,
		S = c.sampleSpacing,
		N = c.chunkCells,
		chunks = {},
		columns = {},
		journal = {},
		dirty = {}, -- chunk key -> {cx,cy,cz}: meshes needing rebuild
		handlers = {},
	}, Field)
end

local function ckey(cx, cy, cz) return ((cx + 32768) * 65536 + (cy + 32768)) * 65536 + (cz + 32768) end
Field.chunkKey = ckey

local function idx(N, li, lj, lk) return (li * (N + 1) + lj) * (N + 1) + lk + 1 end

function Field:_column(i, k)
	local key = i * 1000003 + k
	local col = self.columns[key]
	if not col then
		local h, inv = BaseTerrain.column(self.cfg, i * self.S, k * self.S)
		local top, mid, weathered, sandy = BaseTerrain.strata(self.cfg, i * self.S, k * self.S)
		col = { h, inv, top, mid, weathered, sandy }
		self.columns[key] = col
	end
	return col
end

function Field:getChunk(cx, cy, cz)
	local key = ckey(cx, cy, cz)
	local ch = self.chunks[key]
	if ch then return ch end
	local N, S = self.N, self.S
	local d, m = {}, {}
	for li = 0, N do
		for lk = 0, N do
			local col = self:_column(cx * N + li, cz * N + lk)
			local h, inv, top, mid, weathered, sandy = col[1], col[2], col[3], col[4], col[5], col[6]
			for lj = 0, N do
				local y = (cy * N + lj) * S
				local dd = BaseTerrain.density(h, inv, y)
				local i = idx(N, li, lj, lk)
				d[i] = dd
				if dd > 0 then
					local depth = h - y
					local mat
					if depth < top then mat = Materials.Topsoil
					elseif depth < top + mid then mat = sandy and Materials.Sand or Materials.Clay
					elseif depth < top + mid + weathered then mat = Materials.WeatheredRock
					else mat = Materials.Bedrock end
					m[i] = mat
				else
					m[i] = 0
				end
			end
		end
	end
	ch = { cx = cx, cy = cy, cz = cz, d = d, m = m, version = 0 }
	self.chunks[key] = ch
	return ch
end

-- Global lattice read (does not materialise chunks needlessly: reads through getChunk).
function Field:get(i, j, k)
	local N = self.N
	local cx, cy, cz = floor(i / N), floor(j / N), floor(k / N)
	local ch = self._last
	if not ch or ch.cx ~= cx or ch.cy ~= cy or ch.cz ~= cz then
		ch = self:getChunk(cx, cy, cz)
		self._last = ch
	end
	local ix = idx(N, i - cx * N, j - cy * N, k - cz * N)
	return ch.d[ix], ch.m[ix]
end

local function owners(N, i)
	local c = floor(i / N)
	local li = i - c * N
	if li == 0 then return c, c - 1, li, N end
	return c, nil, li, nil
end

-- Write a sample to every chunk that stores it (border duplication).
function Field:setSample(i, j, k, d, m)
	local N = self.N
	local cxa, cxb, lia, lib = owners(N, i)
	local cya, cyb, lja, ljb = owners(N, j)
	local cza, czb, lka, lkb = owners(N, k)
	local cxs = cxb and { { cxa, lia }, { cxb, lib } } or { { cxa, lia } }
	local cys = cyb and { { cya, lja }, { cyb, ljb } } or { { cya, lja } }
	local czs = czb and { { cza, lka }, { czb, lkb } } or { { cza, lka } }
	for _, x in ipairs(cxs) do
		for _, y in ipairs(cys) do
			for _, z in ipairs(czs) do
				local ch = self:getChunk(x[1], y[1], z[1])
				local ix = idx(N, x[2], y[2], z[2])
				ch.d[ix] = d
				ch.m[ix] = m
			end
		end
	end
end

function Field:occ(d) -- partial occupancy of a sample cell, 0..1
	local o = d / self.S + 0.5
	return o < 0 and 0 or (o > 1 and 1 or o)
end

-- Visit every lattice sample in an index box; fn(i,j,k,d,m) -> nd, nm | nil. dry=true only returns volume delta.
function Field:modifyBox(i0, j0, k0, i1, j1, k1, fn, dry)
	local S = self.S
	local vol = 0
	local v3 = S * S * S
	for i = i0, i1 do
		for j = j0, j1 do
			for k = k0, k1 do
				local d, m = self:get(i, j, k)
				local nd, nm = fn(i, j, k, d, m)
				if nd ~= nil then
					local lim = BaseTerrain.CLAMP
					if nd > lim then nd = lim elseif nd < -lim then nd = -lim end
					nm = nm or m
					if nd <= 0 then nm = 0 elseif nm == 0 then nm = m ~= 0 and m or Materials.Rubble end
					vol = vol + (self:occ(nd) - self:occ(d)) * v3
					if not dry and (nd ~= d or nm ~= m) then self:setSample(i, j, k, nd, nm) end
				end
			end
		end
	end
	if not dry then self:_markDirty(i0, j0, k0, i1, j1, k1) end
	return vol
end

function Field:_markDirty(i0, j0, k0, i1, j1, k1)
	local N = self.N
	local function rng(a, b) return floor((a - 2) / N), floor((b + 2) / N) end
	local xa, xb = rng(i0, i1)
	local ya, yb = rng(j0, j1)
	local za, zb = rng(k0, k1)
	for x = xa, xb do
		for y = ya, yb do
			for z = za, zb do
				local key = ckey(x, y, z)
				self.dirty[key] = { x, y, z }
				local ch = self.chunks[key]
				if ch then ch.version = ch.version + 1 end
			end
		end
	end
end

function Field:boxFromWorld(minV, maxV)
	local S = self.S
	return floor(minV[1] / S) - 1, floor(minV[2] / S) - 1, floor(minV[3] / S) - 1,
		ceil(maxV[1] / S) + 1, ceil(maxV[2] / S) + 1, ceil(maxV[3] / S) + 1
end

function Field:totalVolume(i0, j0, k0, i1, j1, k1)
	local v = 0
	for i = i0, i1 do for j = j0, j1 do for k = k0, k1 do
		local d = self:get(i, j, k)
		v = v + self:occ(d)
	end end end
	return v * self.S ^ 3
end

-- Trilinear density at a world position.
function Field:sampleWorld(x, y, z)
	local S = self.S
	local fx, fy, fz = x / S, y / S, z / S
	local i, j, k = floor(fx), floor(fy), floor(fz)
	local tx, ty, tz = fx - i, fy - j, fz - k
	local acc = 0
	for a = 0, 1 do for b = 0, 1 do for c = 0, 1 do
		local d = self:get(i + a, j + b, k + c)
		local w = (a == 1 and tx or 1 - tx) * (b == 1 and ty or 1 - ty) * (c == 1 and tz or 1 - tz)
		acc = acc + d * w
	end end end
	return acc
end

function Field:materialAt(x, y, z)
	local S = self.S
	local _, m = self:get(floor(x / S + 0.5), floor(y / S + 0.5), floor(z / S + 0.5))
	return m
end

-- Highest solid world Y below/at a start point (searches downward); nil if none within maxDrop.
function Field:surfaceY(x, z, startY, maxDrop)
	local S = self.S
	local y = startY
	local prev = self:sampleWorld(x, y, z)
	local steps = floor((maxDrop or 200) / (S * 0.5))
	for _ = 1, steps do
		local ny = y - S * 0.5
		local d = self:sampleWorld(x, ny, z)
		if prev <= 0 and d > 0 or (prev < 0 and d >= 0) then
			local t = prev / (prev - d)
			return y - t * S * 0.5
		end
		prev, y = d, ny
	end
	return nil
end

function Field:registerOp(typeName, handler) self.handlers[typeName] = handler end

-- Authoritative edit entry: append to journal then execute. Returns handler result.
function Field:apply(op)
	local h = self.handlers[op.type]
	assert(h, "unknown op type " .. tostring(op.type))
	op.id = op.id or (#self.journal + 1)
	self.journal[#self.journal + 1] = op
	return h(self, op)
end

-- FNV-style hash over quantised samples of one chunk (divergence debugging).
function Field:chunkHash(cx, cy, cz)
	local ch = self:getChunk(cx, cy, cz)
	local h = 2166136261
	local d, m = ch.d, ch.m
	for i = 1, (self.N + 1) ^ 3 do
		local q = floor(d[i] * 16 + 0.5) + 4096
		h = (h * 1664525 + q * 31 + m[i] + 1) % M32
	end
	return h
end

return Field
