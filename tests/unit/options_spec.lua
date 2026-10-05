local options = require("core.options")

describe("core.options", function()
	it("gives every option its default", function()
		local defaults = options.defaults()
		for _, definition in ipairs(options.definitions) do
			assert.are.equal(definition.default, defaults[definition.name])
		end
	end)

	it("has nothing in the defaults that is not defined", function()
		local defined = {}
		for _, definition in ipairs(options.definitions) do
			defined[definition.name] = true
		end
		local unknown = {}
		for name in pairs(options.defaults()) do
			if not defined[name] then
				unknown[#unknown + 1] = name
			end
		end
		assert.are.same({}, unknown)
	end)

	it("returns a new table each time", function()
		local first = options.defaults()
		first.output_format = "gif"
		assert.are.equal("webm-vp8", options.defaults().output_format)
	end)

	it("defines each option once", function()
		local seen, duplicates = {}, {}
		for _, definition in ipairs(options.definitions) do
			if seen[definition.name] then
				duplicates[#duplicates + 1] = definition.name
			end
			seen[definition.name] = true
		end
		assert.are.same({}, duplicates)
	end)

	-- mp.options can only read strings, numbers and booleans from webm.conf.
	it("only uses default types that mp.options can read", function()
		local allowed = { string = true, number = true, boolean = true }
		local bad = {}
		for _, definition in ipairs(options.definitions) do
			if not allowed[type(definition.default)] then
				bad[#bad + 1] = definition.name
			end
		end
		assert.are.same({}, bad)
	end)

	it("keeps comments as lists of single lines", function()
		local bad = {}
		for _, definition in ipairs(options.definitions) do
			for _, line in ipairs(definition.comment or {}) do
				if type(line) ~= "string" or line:find("\n") then
					bad[#bad + 1] = definition.name
				end
			end
		end
		assert.are.same({}, bad)
	end)
end)
