# Warblocks-engine
Procedural destruction / generation engine for WARBLOCKS (Roblox, Luau).

Spec: the WARBLOCKS master prompt (procedural, fully destructible world). This repo started empty, so the
engine-agnostic core is built first and verified outside Studio (`tests/run_all.sh`, Lua 5.4; source is Luau-compatible).

## Implemented (tested)
| Module | What |
|---|---|
| `Contracts` | coordinate/chunk/density-sign/version conventions, quality tiers |
| `Rng`, `Noise` | deterministic hash/PRNG (doubles-safe), Perlin 2D/3D, fBm, ridged, domain warp |
| `Materials` | material registry (soil, rock, road layers, rubble) with blast/dust/ejection params |
| `BaseTerrain` | seed-driven macro height + spatially varying geological strata |
| `TerrainField` | sparse chunked density+material field, border-duplicated samples, ordered edit journal, chunk hashes, dirty tracking |
| `SurfaceNets` | smooth isosurface meshing with gradient normals; crack-free across chunk borders (watertight test) |
| `Edits` | sphere + crater ops: irregular/directional craters, material-dependent size, rim deposition, mass ledger (rim+ejecta+dust = removed), ejecta pieces |
| `Hydrology` | priority-flood fill, D8 flow, accumulation |
| `RoadPlanner` | seeded anchors -> MST + loops -> cost-field A* -> smoothing -> grade-limited design profile + validation |
| `RoadCarver` | cut/fill + side slopes + layered construction (surface/base/aggregate) written into the field; craters expose layers |

Determinism: journal replay reproduces chunk hashes exactly (late-join reconstruction model).

## Not yet built (needs Roblox Studio / existing game)
No existing WARBLOCKS Roblox project was in this repo, so these remain: EditableMesh/MeshPart adapter, collision proxies
and the Spike B-D measurements, buffer-backed storage, replication/streaming, vegetation, settlement/building grammar,
structural collapse + rubble lifecycle, LOD, intersections geometry, bridges/culverts, in-engine profiling.
Claims like "fully procedural" are not yet earned; the above are the open gates.
