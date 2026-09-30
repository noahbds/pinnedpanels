-- Translation check (§23, B25): fails when code uses a key missing from English; warns about unused keys
-- and about other languages' missing or untranslated keys. Run from the repo root: luajit tools/check_lang.lua [-v]
-- A key in code is a string literal "area.thing" whose area exists in English (L("x.y"), notify("x.y"), reasons)
-- or a Derma label "#pinnedpanels.area.thing".

local verbose = arg[1] == "-v"
local ROOT = "resource/localization"

local function readProperties(path)
	local f = io.open(path)
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	local keys, first = {}, true
	for line in (text .. "\n"):gmatch("(.-)\r?\n") do
		if first and line ~= "" then return nil, "first line must be empty (G39)" end
		first = false
		local k, v = line:match("^pinnedpanels%.([^=]+)=(.*)$")
		if k then keys[k] = v end
	end
	return keys
end

local function list(cmd)
	local out = {}
	local p = io.popen(cmd)
	for line in p:lines() do out[#out + 1] = line end
	p:close()
	return out
end

local en, err = readProperties(ROOT .. "/en/pinnedpanels.properties")
if not en then
	print("check_lang: English: " .. (err or "missing"))
	os.exit(1)
end

local areas = {}
for k in pairs(en) do areas[k:match("^[^.]+")] = true end

local used, failed = {}, false
for _, path in ipairs(list("find lua -name '*.lua'")) do
	local f = io.open(path)
	local lineNo = 0
	for line in f:lines() do
		lineNo = lineNo + 1
		for lit in line:gmatch('"([^"]*)"') do
			local key = lit:match("^#pinnedpanels%.(.+)$")
			if not key and lit:match("^%l[%l_]*%.[%l_%.]+$") and areas[lit:match("^[^.]+")]
				and not lit:match("%.lua$") and not lit:match("%.json$") then
				key = lit
			end
			if key then
				used[key] = true
				if not en[key] then
					print(string.format("missing from en: %s (%s:%d)", key, path, lineNo))
					failed = true
				end
			end
		end
	end
	f:close()
end

local unused = {}
for k in pairs(en) do
	if not used[k] then unused[#unused + 1] = k end
end
table.sort(unused)
print(string.format("warning: %d English keys unused", #unused) .. (verbose and ":\n  " .. table.concat(unused, "\n  ") or " (-v lists them)"))

for _, dir in ipairs(list("ls " .. ROOT)) do
	if dir ~= "en" then
		local keys, e = readProperties(ROOT .. "/" .. dir .. "/pinnedpanels.properties")
		if not keys then
			print(string.format("%s: %s", dir, e or "no pinnedpanels.properties"))
			failed = failed or e ~= nil
		else
			local missing, same = 0, 0
			for k, v in pairs(en) do
				if not keys[k] then missing = missing + 1 elseif keys[k] == v then same = same + 1 end
			end
			print(string.format("warning: %s: %d keys missing (English shown), %d identical to English", dir, missing, same))
		end
	end
end

if failed then os.exit(1) end
print("check_lang: ok")
