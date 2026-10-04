-- Shared technical contract: every subsystem uses these constants/conventions.
--  * World coordinates: studs, Y up. Lattice sample (i,j,k) sits at world (i*S, j*S, k*S).
--  * Chunk (cx,cy,cz) owns cells [c*N, c*N+N); it stores (N+1)^3 samples (border samples duplicated
--    in neighbours and always written together).
--  * Density sign: d > 0 solid, d < 0 air, surface at d = 0. Units ~ studs of signed distance.
--  * Material id 0 = Air/none; ids from Materials registry.
local Contracts = {}

Contracts.VERSION = {
	replication = 1,
	save = 1,
	generator = 1, -- bump when base generation output changes
}

Contracts.DEFAULT_CONFIG = {
	seed = 1,
	sampleSpacing = 2, -- S, studs per lattice step (quality tier dependent)
	chunkCells = 16, -- N, cells per chunk edge (chunk width = N*S)
	baseHeight = 24,
	heightAmplitude = 40,
	quality = "High",
}

Contracts.QUALITY = {
	Low = { sampleSpacing = 4 },
	Medium = { sampleSpacing = 3 },
	High = { sampleSpacing = 2 },
	Ultra = { sampleSpacing = 1 },
}

function Contracts.resolve(cfg)
	local c = {}
	for k, v in pairs(Contracts.DEFAULT_CONFIG) do c[k] = v end
	for k, v in pairs(cfg or {}) do c[k] = v end
	return c
end

function Contracts.chunkKey(cx, cy, cz)
	return cx .. ":" .. cy .. ":" .. cz
end

return Contracts
