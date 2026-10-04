-- Seeded gradient noise, fBm, ridged noise, domain warping.
local function req(n) if script then return require(script.Parent[n]) end return require("warblocks." .. n) end
local Rng = req("Rng")

local Noise = {}
local floor, sqrt, cos, sin = math.floor, math.sqrt, math.cos, math.sin

local function fade(t) return t * t * t * (t * (t * 6 - 15) + 10) end

local function grad2(ix, iy, seed, dx, dy)
	local a = Rng.hashUnit(ix, iy, 0, seed) * 6.283185307179586
	return cos(a) * dx + sin(a) * dy
end

function Noise.perlin2(x, y, seed)
	local x0, y0 = floor(x), floor(y)
	local fx, fy = x - x0, y - y0
	local u, v = fade(fx), fade(fy)
	local n00 = grad2(x0, y0, seed, fx, fy)
	local n10 = grad2(x0 + 1, y0, seed, fx - 1, fy)
	local n01 = grad2(x0, y0 + 1, seed, fx, fy - 1)
	local n11 = grad2(x0 + 1, y0 + 1, seed, fx - 1, fy - 1)
	local a = n00 + (n10 - n00) * u
	local b = n01 + (n11 - n01) * u
	return (a + (b - a) * v) * 1.4142 -- ~[-1,1]
end

local G3 = {
	{ 1, 1, 0 }, { -1, 1, 0 }, { 1, -1, 0 }, { -1, -1, 0 }, { 1, 0, 1 }, { -1, 0, 1 },
	{ 1, 0, -1 }, { -1, 0, -1 }, { 0, 1, 1 }, { 0, -1, 1 }, { 0, 1, -1 }, { 0, -1, -1 },
}
local function grad3(ix, iy, iz, seed, dx, dy, dz)
	local g = G3[Rng.hash(ix, iy, iz, seed) % 12 + 1]
	return g[1] * dx + g[2] * dy + g[3] * dz
end

function Noise.perlin3(x, y, z, seed)
	local x0, y0, z0 = floor(x), floor(y), floor(z)
	local fx, fy, fz = x - x0, y - y0, z - z0
	local u, v, w = fade(fx), fade(fy), fade(fz)
	local function lerp(a, b, t) return a + (b - a) * t end
	local n000 = grad3(x0, y0, z0, seed, fx, fy, fz)
	local n100 = grad3(x0 + 1, y0, z0, seed, fx - 1, fy, fz)
	local n010 = grad3(x0, y0 + 1, z0, seed, fx, fy - 1, fz)
	local n110 = grad3(x0 + 1, y0 + 1, z0, seed, fx - 1, fy - 1, fz)
	local n001 = grad3(x0, y0, z0 + 1, seed, fx, fy, fz - 1)
	local n101 = grad3(x0 + 1, y0, z0 + 1, seed, fx - 1, fy, fz - 1)
	local n011 = grad3(x0, y0 + 1, z0 + 1, seed, fx, fy - 1, fz - 1)
	local n111 = grad3(x0 + 1, y0 + 1, z0 + 1, seed, fx - 1, fy - 1, fz - 1)
	return lerp(
		lerp(lerp(n000, n100, u), lerp(n010, n110, u), v),
		lerp(lerp(n001, n101, u), lerp(n011, n111, u), v),
		w
	)
end

function Noise.fbm2(x, y, seed, octaves, lacunarity, gain)
	local sum, amp, freq, norm = 0, 1, 1, 0
	for o = 1, octaves or 4 do
		sum = sum + amp * Noise.perlin2(x * freq, y * freq, seed + o * 101)
		norm = norm + amp
		amp = amp * (gain or 0.5)
		freq = freq * (lacunarity or 2)
	end
	return sum / norm
end

function Noise.ridged2(x, y, seed, octaves)
	local sum, amp, freq, norm = 0, 1, 1, 0
	for o = 1, octaves or 4 do
		local n = 1 - math.abs(Noise.perlin2(x * freq, y * freq, seed + o * 211))
		sum = sum + amp * n * n
		norm = norm + amp
		amp = amp * 0.5
		freq = freq * 2
	end
	return sum / norm
end

function Noise.warp2(x, y, seed, strength, scale)
	local wx = x + Noise.fbm2(x * scale, y * scale, seed + 1000, 2) * strength
	local wy = y + Noise.fbm2(x * scale + 37.1, y * scale - 11.7, seed + 2000, 2) * strength
	return wx, wy
end

return Noise
