-- Loader (D12): the server only sends the client files (G1); the client includes them in order.
-- Files listed here must exist and be non-empty; order is load order.

local FILES = {
}

if SERVER then
	for _, path in ipairs(FILES) do
		AddCSLuaFile("pinnedpanels/" .. path)
	end
	return
end

PinnedPanels = PinnedPanels or {}
PinnedPanels.VERSION = "2.0.0"

for _, path in ipairs(FILES) do
	include("pinnedpanels/" .. path)
end

hook.Run("PinnedPanelsLoaded")
print("Pinned Panels " .. PinnedPanels.VERSION .. " loaded")
