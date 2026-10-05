local bundle = require("bundle")

-- Runs a bundled script in a fresh environment with its own package.preload,
-- the way mpv gives each script its own Lua state.
local function run_bundle(text)
	local chunk = assert(loadstring(text, "=bundle"))
	local preload = {}
	local loaded = {}
	local env = setmetatable({}, { __index = _G })
	env.package = { preload = preload, loaded = loaded, path = "", cpath = "" }
	env.require = function(name)
		if loaded[name] == nil then
			local loader = assert(preload[name], "no module " .. name)
			loaded[name] = loader(name)
		end
		return loaded[name]
	end
	setfenv(chunk, env)
	return chunk()
end

describe("bundle", function()
	it("makes modules available to the main chunk through require", function()
		local text = bundle.bundle({
			modules = {
				{ name = "core.math", source = "local M = {}\nfunction M.double(x) return x * 2 end\nreturn M" },
			},
			chunks = {
				{ name = "main", source = 'return require("core.math").double(21)' },
			},
		})
		assert.are.equal(42, run_bundle(text))
	end)

	it("lets modules require each other in any listing order", function()
		local text = bundle.bundle({
			modules = {
				{ name = "a", source = 'return { value = require("b").value + 1 }' },
				{ name = "b", source = "return { value = 1 }" },
			},
			chunks = { { name = "main", source = 'return require("a").value' } },
		})
		assert.are.equal(2, run_bundle(text))
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
			modules = { { name = "m", source = "local secret = 1\nreturn {}" } },
			chunks = { { name = "main", source = 'require("m")\nreturn secret' } },
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
				{ name = "a", source = "local x = 1 -- comment" },
				{ name = "b", source = "return x" },
			},
		})
		assert.are.equal(1, run_bundle(text))
	end)

	it("writes the header as comments", function()
		local text = bundle.bundle({ header = "line one\nline two", chunks = {} })
		assert.are.equal("-- line one\n-- line two\n", text:sub(1, #"-- line one\n-- line two\n"))
	end)

	it("rejects a module listed twice", function()
		assert.has_error(function()
			bundle.bundle({
				modules = { { name = "x", source = "" }, { name = "x", source = "" } },
			})
		end, "module listed twice: x")
	end)
end)
