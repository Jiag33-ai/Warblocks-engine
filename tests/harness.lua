package.path = "./src/shared/?.lua;" .. package.path
package.loaded["warblocks"] = nil
-- map require("warblocks.X") -> src/shared/Warblocks/X.lua
table.insert(package.searchers, 2, function(name)
	local mod = name:match("^warblocks%.(.+)$")
	if not mod then return nil end
	local path = "./src/shared/Warblocks/" .. mod .. ".lua"
	local f = loadfile(path)
	if f then return f, path end
	return "\n\tno file " .. path
end)

local H = { passed = 0, failed = 0 }
function H.test(name, fn)
	local t0 = os.clock()
	local ok, err = pcall(fn)
	if ok then
		H.passed = H.passed + 1
		print(string.format("PASS  %s (%.2fs)", name, os.clock() - t0))
	else
		H.failed = H.failed + 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end
function H.eq(a, b, msg) if a ~= b then error((msg or "eq") .. ": expected " .. tostring(b) .. " got " .. tostring(a), 2) end end
function H.near(a, b, tol, msg) if math.abs(a - b) > tol then error((msg or "near") .. ": " .. a .. " vs " .. b .. " tol " .. tol, 2) end end
function H.ok(c, msg) if not c then error(msg or "assertion failed", 2) end end
return H
