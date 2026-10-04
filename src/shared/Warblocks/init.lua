-- Public entry point: builds a field with all edit handlers installed.
local function req(n) if script then return require(script[n]) end return require("warblocks." .. n) end
local Field = req("TerrainField")
local Edits = req("Edits")
local RoadCarver = req("RoadCarver")

local Warblocks = {
	Field = Field, Mesher = req("SurfaceNets"), Planner = req("RoadPlanner"), Materials = req("Materials"),
	Contracts = req("Contracts"), Hydrology = req("Hydrology"),
}

function Warblocks.newWorld(cfg)
	local f = Field.new(cfg)
	Edits.install(f)
	RoadCarver.install(f)
	return f
end

return Warblocks
