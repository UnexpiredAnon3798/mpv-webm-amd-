local fake_host = require("fake_host")
local filename = require("core.filename")
local formats = require("encode.formats").by_id
local options_module = require("core.options")

local function props(extra)
	local p = {
		filename = "My Clip.mkv",
		["filename/no-ext"] = "My Clip",
		["media-title"] = "Title",
		["stream-open-filename"] = "/videos/My Clip.mkv",
		aid = 1,
		mute = false,
		height = 1080,
		pause = true,
	}
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function format_with(template, opts)
	opts = opts or {}
	local options = options_module.defaults()
	options.output_template = template
	for k, v in pairs(opts.options or {}) do
		options[k] = v
	end
	local host = fake_host.new(props(opts.props), { files = opts.files })
	return filename.format(
		host,
		options,
		opts.start_time or 1.5,
		opts.end_time or 4.25,
		opts.format or formats.avc,
		opts.dir
	)
end

describe("core.filename.format", function()
	it("uses the default template", function()
		assert.are.equal("My Clip-[00.01.500-00.04.250]-audio.mp4", format_with("%F-[%s-%e]%M"))
	end)

	it("leaves -audio out when muted or the format has no audio", function()
		assert.are.equal(".mp4", format_with("%M", { props = { mute = true } }))
		assert.are.equal(".gif", format_with("%M", { format = formats.gif }))
	end)

	it("uses scale_height for %R when set", function()
		assert.are.equal("-1080p.mp4", format_with("%R"))
		assert.are.equal("-720p.mp4", format_with("%R", { options = { scale_height = 720 } }))
	end)

	it("expands properties and conditionals", function()
		assert.are.equal("My Clip.mp4", format_with("%{filename/no-ext}"))
		assert.are.equal("paused.mp4", format_with("%{?pause:paused}%{!pause:playing}"))
		assert.are.equal("fallback.mp4", format_with("%{missing:fallback}"))
	end)

	it("expands %t date specifiers", function()
		assert.are.equal("2024-03-09.mp4", format_with("%tY-%tm-%td"))
	end)

	it("removes characters that are invalid in filenames", function()
		assert.are.equal("abcdefghij.mp4", format_with('a<b>c:d"e/f\\g|h?i*j'))
	end)

	it("picks the first free sequence number in the output directory", function()
		local files = { ["/videos/clip_0001.mp4"] = true, ["/videos/clip_0002.mp4"] = true }
		assert.are.equal("clip_0003.mp4", format_with("clip_%04n", { files = files, dir = "/videos/" }))
		assert.are.equal("clip_1.mp4", format_with("clip_%n"))
	end)

	it("keeps %%n literal", function()
		assert.are.equal("literal %n.mp4", format_with("literal %%n", { dir = "/videos/" }))
	end)
end)
