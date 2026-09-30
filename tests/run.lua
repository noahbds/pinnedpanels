-- Unit test runner: `luajit tests/run.lua` from the repository root (§25).
-- Each test file returns { ["name"] = function(t) ... end }; t.eq and t.ok record failures.

local FILES = {
	"tests/stub_test.lua",
}

dofile("tests/stub.lua")

local passed, failed = 0, 0

local function fmt(v)
	return type(v) == "string" and string.format("%q", v) or tostring(v)
end

for _, path in ipairs(FILES) do
	local tests = dofile(path)
	local names = {}
	for name in pairs(tests) do names[#names + 1] = name end
	table.sort(names)

	for _, name in ipairs(names) do
		local errors = {}
		local t = {}
		function t.ok(cond, msg)
			if not cond then errors[#errors + 1] = msg or "expected true" end
		end
		function t.eq(actual, expected, msg)
			if actual ~= expected then
				errors[#errors + 1] = (msg and msg .. ": " or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual)
			end
		end

		Stub.Reset()
		local ok, err = xpcall(tests[name], debug.traceback, t)
		if not ok then errors[#errors + 1] = err end

		if #errors == 0 then
			passed = passed + 1
		else
			failed = failed + 1
			print("FAIL " .. path .. " :: " .. name)
			for _, e in ipairs(errors) do print("  " .. e) end
		end
	end
end

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
