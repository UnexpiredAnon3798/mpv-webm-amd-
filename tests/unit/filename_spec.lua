local fake_host = require("fake_host")
local filename = require("core.filename")
local formats = require("encode.formats").by_id
local options_module = require("core.options")

-- The default selection, in seconds: 1.5 to 4.25.
local DEFAULT_START_TIME = 1.5
local DEFAULT_END_TIME = 4.25
local VIDEO_HEIGHT = 1080

local function properties_with(overrides)
	local properties = {
		filename = "My Clip.mkv",
		["filename/no-ext"] = "My Clip",
		["media-title"] = "Title",
		["stream-open-filename"] = "/videos/My Clip.mkv",
		aid = 1,
		mute = false,
		height = VIDEO_HEIGHT,
		pause = true,
	}
	for name, value in pairs(overrides or {}) do
		properties[name] = value
	end
	return properties
end

local function format_with(template, settings)
	settings = settings or {}
	local options = options_module.defaults()
	options.output_template = template
	for name, value in pairs(settings.options or {}) do
		options[name] = value
	end
	local host = fake_host.new(properties_with(settings.properties), { files = settings.files })
	return filename.format(
		host,
		options,
		settings.start_time or DEFAULT_START_TIME,
		settings.end_time or DEFAULT_END_TIME,
		settings.format or formats.avc,
		settings.directory
	)
end

describe("core.filename.format", function()
	it("uses the default template", function()
		assert.are.equal("My Clip-[00.01.500-00.04.250]-audio.mp4", format_with("%F-[%s-%e]%M"))
	end)

	it("leaves -audio out when muted or the format has no audio", function()
		assert.are.equal(".mp4", format_with("%M", { properties = { mute = true } }))
		assert.are.equal(".gif", format_with("%M", { format = formats.gif }))
	end)

	it("uses scale_height for %R when set", function()
		assert.are.equal("-" .. VIDEO_HEIGHT .. "p.mp4", format_with("%R"))
		local scaled_height = 720
		assert.are.equal(
			"-" .. scaled_height .. "p.mp4",
			format_with("%R", { options = { scale_height = scaled_height } })
		)
	end)

	it("expands properties and conditionals", function()
		assert.are.equal("My Clip.mp4", format_with("%{filename/no-ext}"))
		assert.are.equal("paused.mp4", format_with("%{?pause:paused}%{!pause:playing}"))
		assert.are.equal("fallback.mp4", format_with("%{missing:fallback}"))
	end)

	it("expands %t date specifiers", function()
		-- The fake host's clock is fixed at 2024-03-09.
		assert.are.equal("2024-03-09.mp4", format_with("%tY-%tm-%td"))
	end)

	it("removes characters that are invalid in filenames", function()
		assert.are.equal("abcdefghij.mp4", format_with('a<b>c:d"e/f\\g|h?i*j'))
	end)

	it("picks the first free sequence number in the output directory", function()
		local taken = { ["/videos/clip_0001.mp4"] = true, ["/videos/clip_0002.mp4"] = true }
		assert.are.equal("clip_0003.mp4", format_with("clip_%04n", { files = taken, directory = "/videos/" }))
		assert.are.equal("clip_1.mp4", format_with("clip_%n"))
	end)

	it("keeps %%n literal", function()
		assert.are.equal("literal %n.mp4", format_with("literal %%n", { directory = "/videos/" }))
	end)
end)
