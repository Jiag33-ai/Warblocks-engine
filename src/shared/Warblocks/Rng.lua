-- Deterministic integer hash + PRNG. Arithmetic stays below 2^53 so Luau (doubles) and Lua 5.4 agree.
local Rng = {}
local M32 = 4294967296

function Rng.hash(a, b, c, seed)
	local h = (a * 73856093 + b * 19349663 + c * 83492791 + seed * 2654435761) % M32
	h = (h * 1664525 + 1013904223) % M32
	h = (h + math.floor(h / 65536)) % M32
	h = (h * 1664525 + 1013904223) % M32
	h = (h + math.floor(h / 8192)) % M32
	return math.floor(h)
end

function Rng.hashUnit(a, b, c, seed)
	return Rng.hash(a, b, c, seed) / M32
end

-- Stateful PRNG (LCG with output mixing); deterministic from seed.
local PRNG = {}
PRNG.__index = PRNG

function Rng.new(seed)
	return setmetatable({ s = Rng.hash(seed % M32, 17, 31, 7) }, PRNG)
end

function PRNG:next()
	self.s = (self.s * 1664525 + 1013904223) % M32
	local h = (self.s + math.floor(self.s / 65536)) % M32
	return h / M32
end

function PRNG:range(lo, hi)
	return lo + (hi - lo) * self:next()
end

function PRNG:int(lo, hi)
	return lo + math.floor(self:next() * (hi - lo + 1))
end

return Rng
