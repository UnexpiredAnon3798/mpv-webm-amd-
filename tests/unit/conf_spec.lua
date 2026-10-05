local conf = require("conf")

describe("conf.generate", function()
	it("writes comments, then the option", function()
		local out = conf.generate({
			{ name = "keybind", default = "W", comment = { "Defaults to shift+w", "Second line" } },
		})
		assert.are.equal("# Defaults to shift+w\n# Second line\nkeybind=W\n", out)
	end)

	it("writes booleans as yes and no", function()
		local out = conf.generate({
			{ name = "twopass", default = true },
			{ name = "run_detached", default = false },
		})
		assert.are.equal("twopass=yes\nrun_detached=no\n", out)
	end)

	it("writes numbers and strings as they are", function()
		local out = conf.generate({
			{ name = "scale_height", default = -1 },
			{ name = "strict_bitrate_multiplier", default = 0.95 },
			{ name = "output_directory", default = "" },
			{ name = "output_template", default = "%F-[%s-%e]%M" },
		})
		assert.are.equal(
			"scale_height=-1\nstrict_bitrate_multiplier=0.95\noutput_directory=\noutput_template=%F-[%s-%e]%M\n",
			out
		)
	end)

	it("writes an empty comment line as a bare #", function()
		local out = conf.generate({ { name = "fps", default = -1, comment = { "a", "", "b" } } })
		assert.are.equal("# a\n#\n# b\nfps=-1\n", out)
	end)

	it("keeps the definition order", function()
		local out = conf.generate({
			{ name = "b", default = 1 },
			{ name = "a", default = 2 },
		})
		assert.are.equal("b=1\na=2\n", out)
	end)
end)
