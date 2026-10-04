-- Deterministic pristine terrain: macro height + geological strata. Pure function of (seed, x, z, y).
local function req(n) if script then return require(script.Parent[n]) end return require("warblocks." .. n) end
local Noise = req("Noise")
local Materials = req("Materials")

local BaseTerrain = {}
local floor, sqrt, clamp = math.floor, math.sqrt, function(v, a, b) return v < a and a or (v > b and b or v) end

-- Macro surface height at (x,z) in studs.
function BaseTerrain.height(cfg, x, z)
	local seed = cfg.seed
	local wx, wz = Noise.warp2(x, z, seed, 60, 0.004)
	local rolling = Noise.fbm2(wx * 0.006, wz * 0.006, seed + 1, 4)
	local ridge = Noise.ridged2(wx * 0.004, wz * 0.004, seed + 2, 4)
	local valley = Noise.fbm2(wx * 0.0025, wz * 0.0025, seed + 3, 2)
	local plateau = clamp((valley + 0.15) * 3, 0, 1)
	local h = rolling * 0.55 + (ridge - 0.45) * 0.9 * plateau
	local micro = Noise.fbm2(x * 0.07, z * 0.07, seed + 4, 3) * 0.04
	return cfg.baseHeight + (h + micro) * cfg.heightAmplitude
end

-- Strata thickness varies spatially (topsoil, clay/sand, weathered rock); bedrock below.
function BaseTerrain.strata(cfg, x, z)
	local s = cfg.seed
	local top = 1.5 + (Noise.fbm2(x * 0.03, z * 0.03, s + 11, 2) * 0.5 + 0.5) * 3
	local mid = 3 + (Noise.fbm2(x * 0.02, z * 0.02, s + 12, 2) * 0.5 + 0.5) * 5
	local weathered = 4 + (Noise.fbm2(x * 0.015, z * 0.015, s + 13, 2) * 0.5 + 0.5) * 8
	local sandy = Noise.fbm2(x * 0.01, z * 0.01, s + 14, 2) > 0.25
	return top, mid, weathered, sandy
end

-- Material for a solid point `depth` studs under the pristine surface.
function BaseTerrain.materialAtDepth(cfg, x, z, depth)
	local top, mid, weathered, sandy = BaseTerrain.strata(cfg, x, z)
	if depth < top then return Materials.Topsoil end
	if depth < top + mid then return sandy and Materials.Sand or Materials.Clay end
	if depth < top + mid + weathered then return Materials.WeatheredRock end
	return Materials.Bedrock
end

local CLAMP = 16 -- density clamp (studs) keeps the field SDF-like and bounded

-- Column cache entry: height + slope normaliser. Returns h, invNorm
function BaseTerrain.column(cfg, x, z)
	local h = BaseTerrain.height(cfg, x, z)
	local e = 1.5
	local gx = (BaseTerrain.height(cfg, x + e, z) - BaseTerrain.height(cfg, x - e, z)) / (2 * e)
	local gz = (BaseTerrain.height(cfg, x, z + e) - BaseTerrain.height(cfg, x, z - e)) / (2 * e)
	return h, 1 / sqrt(1 + gx * gx + gz * gz)
end

function BaseTerrain.density(h, invNorm, y)
	return clamp((h - y) * invNorm, -CLAMP, CLAMP)
end

BaseTerrain.CLAMP = CLAMP
return BaseTerrain
