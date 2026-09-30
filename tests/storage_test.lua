local Storage = PinnedPanels.Storage

local MAIN = "pinnedpanels/layout.json"
local BAK = "pinnedpanels/layout_bak.json"

local function window(id, srcs, extra)
	local tabs = {}
	for i, src in ipairs(srcs) do tabs[i] = { src = src } end
	local w = { id = id, tabs = tabs, x = 10, y = 20, w = 300, h = 400, state = "normal" }
	for k, v in pairs(extra or {}) do w[k] = v end
	return w
end

local function useDocument(doc)
	PinnedPanels.Layout = { Document = function() return doc end }
end

local function countKeys(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

return {
	["Sanitize keeps a good window intact"] = function(t)
		local doc, summary = Storage.Sanitize({ windows = { window("w3", { "tool:weld", "creation:#spawnmenu.content_tab" }, {
			title = "Build", accent = { 255, 200, 60, 255 }, locked = true, opacity = 0.5, quickKey = 30,
			colors = { bg = { 1, 2, 3 } },
		}) } })
		local w = doc.windows[1]
		t.eq(summary.windows, 1)
		t.eq(summary.tabs, 2)
		t.eq(w.id, "w3")
		t.eq(doc.nextId, 4)
		t.eq(w.title, "Build")
		t.eq(w.accent.g, 200)
		t.eq(w.colors.bg.a, 255)
		t.eq(w.locked, true)
		t.eq(w.opacity, 0.5)
		t.eq(w.quickKey, 30)
	end,

	["Sanitize replaces wrong types and non-finite numbers (R2)"] = function(t)
		local doc = Storage.Sanitize({ windows = { {
			tabs = { { src = "tool:weld" } }, x = 0 / 0, y = "far", w = math.huge, h = -5,
			state = "exploded", locked = "yes", opacity = 7, active = 99, colors = "blue",
		} } })
		local w = doc.windows[1]
		t.eq(w.x, 120)
		t.eq(w.w, 280, "width falls back when the rect is invalid")
		t.eq(w.state, "normal")
		t.eq(w.locked, false)
		t.eq(w.opacity, 1)
		t.eq(w.active, 1)
		t.eq(w.id, "w1")
	end,

	["Sanitize drops unknown kinds, duplicate sources and tabless untitled windows"] = function(t)
		local doc, summary = Storage.Sanitize({ windows = {
			window("w1", { "tool:weld", "lua:RunString('x')", "tool:weld" }),
			window("w2", { "frame:old" }),
			window("w3", {}, { title = "Empty group" }),
			"not a window",
		} })
		t.eq(#doc.windows, 2)
		t.eq(#doc.windows[1].tabs, 1)
		t.eq(doc.windows[2].title, "Empty group")
		t.eq(summary.dropped, 5)
	end,

	["Sanitize caps windows, tabs and title length"] = function(t)
		local windows = {}
		for i = 1, 500 do windows[i] = window("w" .. i, { "tool:t" .. i }) end
		local tabs = {}
		for i = 1, 20 do tabs[i] = "tool:x" .. i end
		windows[1] = window("w1", tabs, { title = string.rep("é", 100) })
		local doc = Storage.Sanitize({ windows = windows })
		t.eq(#doc.windows, 64)
		t.eq(#doc.windows[1].tabs, 16)
		t.ok(#doc.windows[1].title <= 64)
		t.ok(doc.windows[1].title:find("[\192-\255]$") == nil, "no broken UTF-8 tail")
	end,

	["Sanitize reassigns duplicate or malformed ids"] = function(t)
		local doc = Storage.Sanitize({ windows = {
			window("w5", { "tool:a" }), window("w5", { "tool:b" }), window("bogus", { "tool:c" }),
		} })
		t.eq(doc.windows[1].id, "w5")
		t.eq(doc.windows[2].id, "w6")
		t.eq(doc.windows[3].id, "w7")
		t.eq(doc.nextId, 8)
	end,

	["Sanitize accepts junk and returns an empty document"] = function(t)
		t.eq(#Storage.Sanitize(nil).windows, 0)
		t.eq(#Storage.Sanitize({ windows = 5 }).windows, 0)
	end,

	["Encode and Sanitize round-trip, keeping unavailable sources (E1)"] = function(t)
		local doc = Storage.Sanitize({ screen = { w = 1920, h = 1080 }, windows = {
			window("w1", { "tool:from_disabled_addon" }, { accent = { 9, 8, 7, 6 } }),
		} })
		local back = Storage.Sanitize(util.JSONToTable(util.TableToJSON(Storage.Encode(doc))))
		t.eq(back.windows[1].tabs[1].src, "tool:from_disabled_addon")
		t.eq(back.windows[1].accent.a, 6)
		t.eq(back.screen.w, 1920)
	end,

	["writes are debounced (R9)"] = function(t)
		useDocument(Storage.Sanitize({ windows = { window("w1", { "tool:weld" }) } }))
		Storage.MarkDirty()
		Stub.Advance(0.3)
		Storage.MarkDirty()
		Stub.Advance(0.3)
		t.eq(Stub.Files()[MAIN], nil, "not written while changes keep coming")
		Stub.Advance(0.3)
		t.ok(Stub.Files()[MAIN] ~= nil)
	end,

	["each write keeps the previous file as the backup and leaves no temp file"] = function(t)
		local doc = Storage.Sanitize({ windows = { window("w1", { "tool:weld" }) } })
		useDocument(doc)
		Storage.MarkDirty()
		Storage.Flush()
		local first = Stub.Files()[MAIN]
		doc.windows[1].x = 999
		Storage.MarkDirty()
		Storage.Flush()
		t.eq(Stub.Files()[BAK], first)
		t.ok(Stub.Files()[MAIN]:find("999") ~= nil)
		t.eq(Stub.Files()["pinnedpanels/layout_tmp.json"], nil)
	end,

	["a failed write keeps the old file"] = function(t)
		Stub.Files()[MAIN] = "old"
		useDocument(Storage.Sanitize({}))
		Stub.Set("failWrites", true)
		Storage.MarkDirty()
		Storage.Flush()
		t.eq(Stub.Files()[MAIN], "old")
		t.eq(#Stub.Get("notifications"), 1)
	end,

	["Load reads the saved document"] = function(t)
		Stub.Files()[MAIN] = util.TableToJSON({ v = 2, windows = { window("w1", { "tool:weld" }) } })
		t.eq(Storage.Load().windows[1].tabs[1].src, "tool:weld")
		t.eq(#Stub.Get("notifications"), 0)
	end,

	["a missing file is a fresh start"] = function(t)
		t.eq(Storage.Load(), nil)
		t.eq(#Stub.Get("notifications"), 0)
	end,

	["a corrupt file is quarantined and the backup is used (E6, B2)"] = function(t)
		Stub.Files()[MAIN] = "{ this is not json"
		Stub.Files()[BAK] = util.TableToJSON({ v = 2, windows = { window("w1", { "tool:rope" }) } })
		local doc = Storage.Load()
		t.eq(doc.windows[1].tabs[1].src, "tool:rope")
		t.eq(Stub.Files()[MAIN], nil)
		local quarantined
		for name, data in pairs(Stub.Files()) do
			if name:find("layout_corrupt_", 1, true) then quarantined = data end
		end
		t.eq(quarantined, "{ this is not json")
		t.eq(#Stub.Get("notifications"), 1)
	end,

	["a corrupt file without a backup starts empty and is never overwritten"] = function(t)
		Stub.Files()[MAIN] = "garbage"
		t.eq(Storage.Load(), nil)
		useDocument(Storage.Sanitize({ windows = { window("w1", { "tool:weld" }) } }))
		Storage.MarkDirty()
		Storage.Flush()
		local kept = false
		for name, data in pairs(Stub.Files()) do
			if name:find("layout_corrupt_", 1, true) and data == "garbage" then kept = true end
		end
		t.ok(kept)
	end,

	["an interrupted write falls back to the backup"] = function(t)
		Stub.Files()[BAK] = util.TableToJSON({ v = 2, windows = { window("w1", { "tool:rope" }) } })
		t.eq(Storage.Load().windows[1].tabs[1].src, "tool:rope")
	end,

	["a file from a newer version is opened read-only"] = function(t)
		local newer = util.TableToJSON({ v = 3, windows = { window("w1", { "tool:weld" }) } })
		Stub.Files()[MAIN] = newer
		t.ok(Storage.Load() ~= nil)
		t.eq(Storage.readOnly, true)
		useDocument(Storage.Sanitize({}))
		Storage.MarkDirty()
		Storage.Flush()
		t.eq(Stub.Files()[MAIN], newer)
	end,

	["export and import round-trip"] = function(t)
		local doc = Storage.Sanitize({ windows = { window("w1", { "tool:weld", "tool:rope" }, { title = "Ropes" }) } })
		local s = Storage.Export(doc)
		t.eq(s:sub(1, 4), "PP2:")
		local back, summary = Storage.Import("  " .. s .. "\n")
		t.eq(back.windows[1].title, "Ropes")
		t.eq(summary.tabs, 2)
	end,

	["import rejects bad strings with a reason (E7)"] = function(t)
		local function reason(s) return select(2, Storage.Import(s)) end
		t.eq(reason(nil), "import.empty")
		t.eq(reason("   "), "import.empty")
		t.eq(reason("PP2:" .. string.rep("A", 70000)), "import.too_big")
		t.eq(reason(util.Base64Encode(util.Compress("{}"), true)), "import.not_v2", "a v1 string has no prefix")
		t.eq(reason("PP2:not*base64"), "import.decode")
		t.eq(reason("PP2:" .. util.Base64Encode("plain text", true)), "import.corrupt")
		t.eq(reason("PP2:" .. util.Base64Encode(util.Compress("[1,2]"), true)), "import.invalid")
		t.eq(reason("PP2:" .. util.Base64Encode(util.Compress('{"windows":[]}'), true)), "import.invalid")
	end,

	["import rejects a decompression bomb (R1)"] = function(t)
		local bomb = "PP2:" .. util.Base64Encode(util.Compress('{"windows":[],"x":"' .. string.rep("x", 5 * 1024 * 1024) .. '"}'), true)
		t.ok(#bomb < 1000)
		t.eq(select(2, Storage.Import(bomb)), "import.corrupt")
	end,

	["import rejects more than 15,000 keys (R1, G35)"] = function(t)
		local parts = {}
		for i = 1, 50000 do parts[i] = "1" end
		local json = '{"windows":[' .. table.concat(parts, ",") .. "]}"
		local packed = "PP2:" .. util.Base64Encode(util.Compress(json), true)
		t.ok(#packed < 64 * 1024, "fits the size cap, so the key limit is what rejects it")
		t.eq(select(2, Storage.Import(packed)), "import.invalid")
	end,

	["import sanitizes what it accepts"] = function(t)
		local json = util.TableToJSON({ windows = { window("w1", { "tool:weld", "evil:x" }, { x = "left" }) } })
		local doc, summary = Storage.Import("PP2:" .. util.Base64Encode(util.Compress(json), true))
		t.eq(#doc.windows[1].tabs, 1)
		t.eq(doc.windows[1].x, 120)
		t.eq(summary.dropped, 1)
		t.eq(countKeys(Stub.Files()), 0, "import writes nothing (R3)")
	end,
}
