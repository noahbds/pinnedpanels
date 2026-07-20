AddCSLuaFile("autorun/client/cl_pinnedpanels.lua")
AddCSLuaFile("pinnedpanels/filelist.lua")

for _, filePath in ipairs(include("pinnedpanels/filelist.lua")) do
	AddCSLuaFile(filePath)
end
