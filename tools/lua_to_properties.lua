-- One-off converter (§23): a v1 translation table → a .properties file with v2 keys.
-- v1 key "ctx_lock" becomes "pinnedpanels.ctx.lock" (first "_" → "."); newlines are written as \n.
-- Usage: git show legacy/v1:lua/pinnedpanels/lang/fr.lua > /tmp/fr.lua
--        luajit tools/lua_to_properties.lua /tmp/fr.lua resource/localization/fr/pinnedpanels.properties

local input, output = arg[1], arg[2]
if not (input and output) then
	io.stderr:write("usage: luajit tools/lua_to_properties.lua <v1 lang.lua> <out.properties>\n")
	os.exit(2)
end

PinnedPanels = { Lang = {} }
dofile(input)
local code, strings = next(PinnedPanels.Lang)
if not strings then
	io.stderr:write("no PinnedPanels.Lang table in " .. input .. "\n")
	os.exit(1)
end

local lines = {}
for key, value in pairs(strings) do
	local v2 = "pinnedpanels." .. key:gsub("_", ".", 1)
	lines[#lines + 1] = v2 .. "=" .. value:gsub("\n", "\\n")
end
table.sort(lines)

local f = assert(io.open(output, "w"))
f:write("\n", table.concat(lines, "\n"), "\n")
f:close()
print(string.format("%s: %d strings → %s", code, #lines, output))
