--[[
	Azure - LOADER
	================================================
	1. Put Azure.lua on GitHub (public repo) and paste its
	   RAW url below.
	2. Paste THIS whole file into your executor, hit Execute.
	3. Done - the hub opens.

	It tries in order: download -> cached copy -> local file,
	so it still works if your executor blocks HttpGet.
	================================================
]]

local URL = "https://raw.githubusercontent.com/YOUR-USERNAME/YOUR-REPO/main/Azure.lua"
local CACHE = "Azure_cached.lua"
local FAST_LOAD = false -- true = run cached copy, skip the download

local function log(msg) print("[Azure Loader] " .. tostring(msg)) end

local function fetch()
	local attempts = {
		function() return request({ Url = URL, Method = "GET" }).Body end,
		function() return http_request({ Url = URL, Method = "GET" }).Body end,
		function() return syn.request({ Url = URL, Method = "GET" }).Body end,
		function() return game:HttpGet(URL) end,
	}
	local errs = {}
	for _, attempt in ipairs(attempts) do
		local ok, res = pcall(attempt)
		if ok and type(res) == "string" and #res > 100
			and string.find(res, "Azure", 1, true) then
			return res -- looks like the real script, not a 404 page
		end
		errs[#errs + 1] = tostring(res):sub(1, 60)
	end
	return nil, table.concat(errs, " | ")
end

local function readFile(path)
	if typeof(readfile) ~= "function" then return nil end
	local ok, data = pcall(readfile, path)
	if ok and type(data) == "string" and #data > 100 then return data end
	return nil
end

local function writeFile(path, data)
	if typeof(writefile) ~= "function" then return end
	pcall(writefile, path, data)
end

-- pick source --------------------------------------------------------------
local src, where, err

if FAST_LOAD then src = readFile(CACHE) where = "cache" end

if not src then
	log("downloading Azure.lua ...")
	local body, fetchErr
	body, fetchErr = fetch()
	if body then
		src, where = body, "download"
		writeFile(CACHE, body) -- save for next time
	else
		err = fetchErr
	end
end

if not src then
	src = readFile(CACHE)
	if src then where = "cache" end
end

if not src then
	src = readFile("Azure.lua")
	if src then where = "local file" end
end

if not src then
	error("[Azure Loader] could not download or find the script. "
		.. "Check the URL / paste Azure.lua next to the loader. "
		.. tostring(err))
end

-- run it -------------------------------------------------------------------
local compiled, compileErr = loadstring(src, "@Azure.lua")
if not compiled then
	error("[Azure Loader] failed to compile: " .. tostring(compileErr))
end

local ok, hub = pcall(compiled)
if not ok then
	error("[Azure Loader] runtime error: " .. tostring(hub))
end

if type(hub) == "table" and hub.Version then
	log("Azure v" .. hub.Version .. " loaded (source: " .. where .. ")")
else
	log("script ran (source: " .. where .. ")")
end

return hub
