local bundle = require("bundle")

-- Runs a bundled script in a fresh environment with its own package.preload,
-- the way mpv gives each script its own Lua state.
local function run_bundle(text)
	local chunk = assert(loadstring(text, "=bundle"))
	local preload = {}
	local loaded = {}
	local environment = setmetatable({}, { __index = _G })
	environment.package = { preload = preload, loaded = loaded, path = "", cpath = "" }
	environment.require = function(name)
		if loaded[name] == nil then
			local loader = assert(preload[name], "no module " .. name)
			loaded[name] = loader(name)
		end
		return loaded[name]
	end
	setfenv(chunk, environment)
	return chunk()
end

describe("bundle", function()
	it("makes modules available to the main chunk through require", function()
		local number = 21
		local text = bundle.bundle({
			modules = {
				{
					name = "core.math",
					source = "local math_module = {}\n"
						.. "function math_module.double(number) return number * 2 end\n"
						.. "return math_module",
				},
			},
			chunks = {
				{ name = "main", source = 'return require("core.math").double(' .. number .. ")" },
			},
		})
		assert.are.equal(number * 2, run_bundle(text))
	end)

	it("lets modules require each other in any listing order", function()
		local text = bundle.bundle({
			modules = {
				{ name = "counter", source = 'return { value = require("base").value + 1 }' },
				{ name = "base", source = "return { value = 1 }" },
			},
			chunks = { { name = "main", source = 'return require("counter").value' } },
		})
		local base_value_plus_one = 2
		assert.are.equal(base_value_plus_one, run_bundle(text))
	end)

	it("passes the module name to the module, like require does", function()
		local text = bundle.bundle({
			modules = { { name = "ui.page", source = "return (...)" } },
			chunks = { { name = "main", source = 'return require("ui.page")' } },
		})
		assert.are.equal("ui.page", run_bundle(text))
	end)

	it("keeps module locals out of the main chunk", function()
		local text = bundle.bundle({
			modules = { { name = "private", source = "local secret = true\nreturn {}" } },
			chunks = { { name = "main", source = 'require("private")\nreturn secret' } },
		})
		assert.is_nil(run_bundle(text))
	end)

	it("runs the main chunks in order, sharing one scope", function()
		local text = bundle.bundle({
			chunks = {
				{ name = "first", source = "local log = {}\nlog[#log + 1] = 'first'" },
				{ name = "second", source = "log[#log + 1] = 'second'\nreturn table.concat(log, ',')" },
			},
		})
		assert.are.equal("first,second", run_bundle(text))
	end)

	it("handles chunks without a trailing newline", function()
		local text = bundle.bundle({
			chunks = {
				{ name = "first", source = "local shared = 'kept' -- comment" },
				{ name = "second", source = "return shared" },
			},
		})
		assert.are.equal("kept", run_bundle(text))
	end)

	it("writes the header as comments", function()
		local expected_start = "-- line one\n-- line two\n"
		local text = bundle.bundle({ header = "line one\nline two", chunks = {} })
		assert.are.equal(expected_start, text:sub(1, #expected_start))
	end)

	it("rejects a module listed twice", function()
		assert.has_error(function()
			bundle.bundle({
				modules = { { name = "duplicate", source = "" }, { name = "duplicate", source = "" } },
			})
		end, "module listed twice: duplicate")
	end)
end)
