local command = require("encode.command")
local fake_host = require("fake_host")
local formats_module = require("encode.formats")
local options_module = require("core.options")

local formats = formats_module.by_id

local function base_props(extra)
	local p = {
		filename = "clip.mkv",
		["filename/no-ext"] = "clip",
		["media-title"] = "clip",
		["stream-open-filename"] = "/videos/clip.mkv",
		speed = 1,
		mute = false,
		aid = 1,
		height = 720,
		["sub-visibility"] = true,
		["track-list"] = {
			{ id = 1, type = "video", selected = true },
			{ id = 1, type = "audio", selected = true },
			{ id = 1, type = "sub", selected = true },
		},
		vf = {},
	}
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function build(opts)
	opts = opts or {}
	local options = options_module.defaults()
	for k, v in pairs(opts.options or {}) do
		options[k] = v
	end
	local host = fake_host.new(base_props(opts.props), { env = opts.env })
	return command.build(host, options, {
		format = formats[options.output_format],
		region = opts.region,
		path = opts.path or "/videos/clip.mkv",
		is_stream = opts.is_stream or false,
		start_time = 1,
		end_time = 3,
		original_start_time = 1,
		original_end_time = 3,
	})
end

local function index_of(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
end

describe("encode.formats", function()
	it("lists every format exactly once", function()
		local listed = {}
		for _, id in ipairs(formats_module.ids) do
			assert.is_truthy(formats[id])
			listed[id] = true
		end
		for id in pairs(formats) do
			assert.is_true(listed[id])
		end
	end)

	it("adds codec flags only for the codecs a format has", function()
		assert.are.same({ "--ovc=libx264", "--oac=aac" }, formats.avc:codec_flags())
		assert.are.same({ "--oac=libmp3lame" }, formats.mp3:codec_flags())
		assert.are.same({ "--ovc=gif" }, formats.gif:codec_flags())
	end)

	it("converts to nv12 for the VAAPI encoders", function()
		assert.are.same({ "format=nv12" }, formats["avc-vaapi"]:post_filters({}))
		assert.are.same({ "format=nv12" }, formats["hevc-vaapi"]:post_filters({}))
	end)

	it("logs and falls back to bt.601 for an unknown raw colorspace", function()
		local logged = {}
		local ctx = {
			host = fake_host.new({ colormatrix = "weird" }),
			options = options_module.defaults(),
			log = function(level, text)
				logged[#logged + 1] = level .. ": " .. text
			end,
		}
		assert.are.equal("lavfi-scale=in_color_matrix=bt601", formats.raw:post_filters(ctx)[2])
		assert.are.same({ "info: Warning, unknown colorspace weird detected, using bt.601." }, logged)
	end)
end)

describe("encode.command.build", function()
	it("writes tracks as video, audio, then subtitles", function()
		local plan = build({ options = { output_format = "avc", twopass = false } })
		local vid, aid, sid =
			index_of(plan.command, "--vid=1"), index_of(plan.command, "--aid=1"), index_of(plan.command, "--sid=1")
		assert.is_true(vid < aid and aid < sid)
	end)

	it("turns off tracks the format or the player isn't using", function()
		local plan = build({
			options = { output_format = "avc", twopass = false },
			props = { mute = true, ["sub-visibility"] = false },
		})
		local vid, aid, sid =
			index_of(plan.command, "--vid=1"), index_of(plan.command, "--aid=no"), index_of(plan.command, "--sid=no")
		assert.is_true(vid < aid and aid < sid)
	end)

	it("crops to a valid region", function()
		local plan = build({
			options = { output_format = "avc", twopass = false },
			region = { x = 10, y = 20, w = 300, h = 200 },
		})
		assert.is_truthy(index_of(plan.command, "--vf-add=lavfi-crop=300:200:10:20"))
		local whole =
			build({ options = { output_format = "avc", twopass = false }, region = { x = -1, y = -1, w = -1, h = -1 } })
		for _, arg in ipairs(whole.command) do
			assert.is_nil(arg:find("lavfi-crop", 1, true))
		end
	end)

	it("plans two passes with the right flags", function()
		local plan = build({ options = { output_format = "webm-vp8" } })
		assert.are.equal("--ovcopts-add=flags=+pass1", plan.first_pass[#plan.first_pass])
		assert.are.equal("--ovcopts-add=flags=+pass2", plan.command[#plan.command])
		assert.is_true(plan.patch_vp8_log)
	end)

	it("skips two passes for streams, constant quality x264, and formats without it", function()
		assert.is_nil(build({ options = { output_format = "avc" }, is_stream = true }).first_pass)
		assert.is_nil(build({ options = { output_format = "avc", target_filesize = 0 } }).first_pass)
		assert.is_nil(build({ options = { output_format = "avc-vaapi" } }).first_pass)
		local av1 = build({ options = { output_format = "av1" } })
		assert.is_truthy(av1.first_pass)
		assert.is_false(av1.patch_vp8_log)
	end)

	it("writes next to the source by default and into output_directory when set", function()
		local plan = build({ options = { output_format = "avc", twopass = false, output_template = "out" } })
		assert.are.equal("/videos/out.mp4", plan.out_path)
		assert.are.equal("--o=/videos/out.mp4", plan.command[#plan.command])
		local moved = build({
			options = { output_format = "avc", twopass = false, output_template = "out", output_directory = "~/clips" },
		})
		assert.are.equal("/home/me/clips/out.mp4", moved.out_path)
	end)

	it("queues a warning when the home directory can't be found", function()
		local plan = build({
			options = { output_format = "avc", twopass = false, output_directory = "~/clips" },
			env = {},
		})
		assert.are.same({ { level = "warn", text = "Couldn't find home dir." } }, plan.messages)
	end)

	it("drops crf for webp, after the format sets its own quality", function()
		local plan = build({ options = { output_format = "webp", crf = 4 } })
		assert.is_truthy(index_of(plan.command, "--ovcopts-add=qscale=90"))
		for _, arg in ipairs(plan.command) do
			assert.is_nil(arg:match("^%-%-ovcopts%-add=crf="))
		end
	end)
end)
