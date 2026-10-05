local conf = require("conf")

-- Options use -1 for "not set".
local UNSET = -1

describe("conf.generate", function()
	it("writes comments, then the option", function()
		local output = conf.generate({
			{ name = "keybind", default = "W", comment = { "Defaults to shift+w", "Second line" } },
		})
		assert.are.equal("# Defaults to shift+w\n# Second line\nkeybind=W\n", output)
	end)

	it("writes booleans as yes and no", function()
		local output = conf.generate({
			{ name = "twopass", default = true },
			{ name = "run_detached", default = false },
		})
		assert.are.equal("twopass=yes\nrun_detached=no\n", output)
	end)

	it("writes numbers and strings as they are", function()
		local multiplier = 0.95
		local output = conf.generate({
			{ name = "scale_height", default = UNSET },
			{ name = "strict_bitrate_multiplier", default = multiplier },
			{ name = "output_directory", default = "" },
			{ name = "output_template", default = "%F-[%s-%e]%M" },
		})
		assert.are.equal(
			"scale_height="
				.. UNSET
				.. "\nstrict_bitrate_multiplier="
				.. multiplier
				.. "\noutput_directory=\noutput_template=%F-[%s-%e]%M\n",
			output
		)
	end)

	it("writes an empty comment line as a bare #", function()
		local output = conf.generate({ { name = "fps", default = UNSET, comment = { "first", "", "third" } } })
		assert.are.equal("# first\n#\n# third\nfps=" .. UNSET .. "\n", output)
	end)

	it("keeps the definition order", function()
		local output = conf.generate({
			{ name = "listed_first", default = "one" },
			{ name = "listed_second", default = "two" },
		})
		assert.are.equal("listed_first=one\nlisted_second=two\n", output)
	end)
end)
