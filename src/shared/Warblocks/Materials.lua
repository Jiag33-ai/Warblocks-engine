-- Material registry. Numeric ids are part of the save/replication contract; never renumber.
local Materials = { byId = {}, byName = {} }

local function def(d)
	Materials.byId[d.id] = d
	Materials.byName[d.name] = d
	Materials[d.name] = d.id
end

-- ejectionBias/dustFraction: share of excavated volume sent airborne / lost as dust (rest -> rim+rubble)
-- blastResistance scales crater depth/radius down (higher = shallower craters)
def({ id = 0, name = "Air", density = 0, blastResistance = 0, dustFraction = 0, ejectionBias = 0, color = { 0, 0, 0 } })
def({ id = 1, name = "Topsoil", density = 1.3, blastResistance = 0.8, dustFraction = 0.12, ejectionBias = 0.5, color = { 0.28, 0.22, 0.14 }, vegetationAffinity = 1 })
def({ id = 2, name = "Clay", density = 1.8, blastResistance = 1.1, dustFraction = 0.05, ejectionBias = 0.3, color = { 0.45, 0.32, 0.22 }, vegetationAffinity = 0.5 })
def({ id = 3, name = "Sand", density = 1.5, blastResistance = 0.6, dustFraction = 0.25, ejectionBias = 0.7, color = { 0.76, 0.68, 0.45 }, vegetationAffinity = 0.2 })
def({ id = 4, name = "WeatheredRock", density = 2.2, blastResistance = 1.6, dustFraction = 0.1, ejectionBias = 0.4, color = { 0.5, 0.47, 0.43 }, vegetationAffinity = 0.1 })
def({ id = 5, name = "Bedrock", density = 2.7, blastResistance = 2.6, dustFraction = 0.04, ejectionBias = 0.2, color = { 0.36, 0.36, 0.38 }, vegetationAffinity = 0 })
def({ id = 6, name = "Asphalt", density = 2.3, blastResistance = 1.4, dustFraction = 0.05, ejectionBias = 0.35, color = { 0.13, 0.13, 0.14 }, vegetationAffinity = 0 })
def({ id = 7, name = "RoadBase", density = 2.0, blastResistance = 1.2, dustFraction = 0.1, ejectionBias = 0.4, color = { 0.4, 0.38, 0.35 }, vegetationAffinity = 0 })
def({ id = 8, name = "Aggregate", density = 1.9, blastResistance = 1.0, dustFraction = 0.12, ejectionBias = 0.5, color = { 0.55, 0.5, 0.45 }, vegetationAffinity = 0 })
def({ id = 9, name = "Rubble", density = 1.6, blastResistance = 0.7, dustFraction = 0.15, ejectionBias = 0.6, color = { 0.45, 0.42, 0.4 }, vegetationAffinity = 0.1 })
def({ id = 10, name = "DirtTrack", density = 1.6, blastResistance = 0.8, dustFraction = 0.15, ejectionBias = 0.5, color = { 0.4, 0.3, 0.2 }, vegetationAffinity = 0.05 })

return Materials
