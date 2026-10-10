-- These tests pass only the fields the code under test reads.
---@diagnostic disable: missing-fields

local command = require("encode.command")
local fake_host = require("fake_host")
local formats_module = require("encode.formats")
local options_module = require("core.options")

local formats = formats_module.by_id

-- The selection every test encodes, in seconds.
local START_TIME = 1
local END_TIME = 3
-- The region the script uses for "no crop".
local WHOLE_FRAME = { x = -1, y = -1, w = -1, h = -1 }

local function base_properties(overrides)
	local properties = {
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
	for name, value in pairs(overrides or {}) do
		properties[name] = value
	end
	return properties
end

local function build(settings)
	settings = settings or {}
	local options = options_module.defaults()
	for name, value in pairs(settings.options or {}) do
		options[name] = value
	end
	local host = fake_host.new(base_properties(settings.properties), { environment = settings.environment })
	return command.build(host, options, {
		format = formats[options.output_format],
		region = settings.region,
		path = settings.path or "/videos/clip.mkv",
		is_stream = settings.is_stream or false,
		start_time = START_TIME,
		end_time = END_TIME,
		original_start_time = START_TIME,
		original_end_time = END_TIME,
	})
end

local function index_of(list, wanted)
	for index, value in ipairs(list) do
		if value == wanted then
			return index
		end
	end
end

local function last(list)
	return list[#list]
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

	it("converts to 8-bit nv12 for the VAAPI and AMF encoders", function()
		assert.are.same({ "format=nv12" }, formats["avc-vaapi"]:post_filters({}))
		assert.are.same({ "format=nv12" }, formats["hevc-vaapi"]:post_filters({}))
		assert.are.same({ "format=nv12" }, formats["avc-amf"]:post_filters({}))
	end)

	it("logs and falls back to bt.601 for an unknown raw colorspace", function()
		local logged = {}
		local context = {
			host = fake_host.new({ colormatrix = "weird" }),
			options = options_module.defaults(),
			log = function(level, text)
				logged[#logged + 1] = level .. ": " .. text
			end,
		}
		local filters = formats.raw:post_filters(context)
		local color_conversion_filter = filters[2]
		assert.are.equal("lavfi-scale=in_color_matrix=bt601", color_conversion_filter)
		assert.are.same({ "info: Warning, unknown colorspace weird detected, using bt.601." }, logged)
	end)
end)

describe("encode.command.build", function()
	it("writes tracks as video, audio, then subtitles", function()
		local plan = build({ options = { output_format = "avc", twopass = false } })
		local video_position = index_of(plan.command, "--vid=1")
		local audio_position = index_of(plan.command, "--aid=1")
		local subtitle_position = index_of(plan.command, "--sid=1")
		assert.is_true(video_position < audio_position and audio_position < subtitle_position)
	end)

	it("turns off tracks the format or the player isn't using", function()
		local plan = build({
			options = { output_format = "avc", twopass = false },
			properties = { mute = true, ["sub-visibility"] = false },
		})
		local video_position = index_of(plan.command, "--vid=1")
		local audio_position = index_of(plan.command, "--aid=no")
		local subtitle_position = index_of(plan.command, "--sid=no")
		assert.is_true(video_position < audio_position and audio_position < subtitle_position)
	end)

	it("crops to a valid region", function()
		local crop = { x = 10, y = 20, w = 300, h = 200 }
		local plan = build({ options = { output_format = "avc", twopass = false }, region = crop })
		local expected_filter = string.format("--vf-add=lavfi-crop=%d:%d:%d:%d", crop.w, crop.h, crop.x, crop.y)
		assert.is_truthy(index_of(plan.command, expected_filter))

		local uncropped = build({ options = { output_format = "avc", twopass = false }, region = WHOLE_FRAME })
		for _, argument in ipairs(uncropped.command) do
			assert.is_nil(argument:find("lavfi-crop", 1, true))
		end
	end)

	it("plans two passes with the right flags", function()
		local plan = build({ options = { output_format = "webm-vp8" } })
		assert.are.equal("--ovcopts-add=flags=+pass1", last(plan.first_pass))
		assert.are.equal("--ovcopts-add=flags=+pass2", last(plan.command))
		assert.is_true(plan.patch_vp8_log)
	end)

	it("skips two passes for streams, constant quality x264, and formats without it", function()
		local constant_quality = 0
		assert.is_nil(build({ options = { output_format = "avc" }, is_stream = true }).first_pass)
		assert.is_nil(build({ options = { output_format = "avc", target_filesize = constant_quality } }).first_pass)
		assert.is_nil(build({ options = { output_format = "avc-vaapi" } }).first_pass)
		local av1_plan = build({ options = { output_format = "av1" } })
		assert.is_truthy(av1_plan.first_pass)
		assert.is_false(av1_plan.patch_vp8_log)
	end)

	it("writes next to the source by default and into output_directory when set", function()
		local plan = build({ options = { output_format = "avc", twopass = false, output_template = "out" } })
		assert.are.equal("/videos/out.mp4", plan.out_path)
		assert.are.equal("--o=/videos/out.mp4", last(plan.command))
		local moved = build({
			options = { output_format = "avc", twopass = false, output_template = "out", output_directory = "~/clips" },
		})
		assert.are.equal("/home/me/clips/out.mp4", moved.out_path)
	end)

	it("queues a warning when the home directory can't be found", function()
		local plan = build({
			options = { output_format = "avc", twopass = false, output_directory = "~/clips" },
			environment = {},
		})
		assert.are.same({ { level = "warn", text = "Couldn't find home dir." } }, plan.messages)
	end)

	it("decodes on the GPU for GPU formats when hwdec is auto", function()
		local amf_plan = build({ options = { output_format = "avc-amf" } })
		assert.is_truthy(index_of(amf_plan.command, "--hwdec=auto-copy"))
		local x264_plan = build({ options = { output_format = "avc", twopass = false } })
		for _, argument in ipairs(x264_plan.command) do
			assert.is_nil(argument:match("^%-%-hwdec="))
		end
	end)

	it("uses an explicit hwdec for every format", function()
		local plan = build({ options = { output_format = "avc", twopass = false, hwdec = "no" } })
		assert.is_truthy(index_of(plan.command, "--hwdec=no"))
	end)

	it("picks hardware decoding from the format's device", function()
		local auto = { hwdec = "auto" }
		assert.are.equal("auto-copy", command.hardware_decoding(auto, formats["avc-amf"]))
		assert.are.equal("auto-copy", command.hardware_decoding(auto, formats["avc-nvenc"]))
		assert.are.equal("auto-copy", command.hardware_decoding(auto, formats["hevc-vaapi"]))
		assert.is_nil(command.hardware_decoding(auto, formats["webm-vp8"]))
		assert.is_nil(command.hardware_decoding({ hwdec = "" }, formats["avc-amf"]))
		assert.are.equal("vaapi-copy", command.hardware_decoding({ hwdec = "vaapi-copy" }, formats.gif))
	end)

	it("drops crf for webp, after the format sets its own quality", function()
		local crf = 4
		-- WebP maps crf to a 0 to 100 quality, 2.5 points per crf step.
		local expected_quality = 100 - crf * 2.5
		local plan = build({ options = { output_format = "webp", crf = crf } })
		assert.is_truthy(index_of(plan.command, "--ovcopts-add=qscale=" .. expected_quality))
		for _, argument in ipairs(plan.command) do
			assert.is_nil(argument:match("^%-%-ovcopts%-add=crf="))
		end
	end)
end)
