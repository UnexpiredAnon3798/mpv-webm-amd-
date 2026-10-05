-- Output formats. Each one sets the codecs and container and can add filters
-- and flags to the encode command, or rewrite the finished command.

local time = require("core.time")

---@class webm.FormatContext
---@field host webm.Host
---@field options webm.Options
---@field log fun(level: string, text: string) queue a log message

---@class webm.Format
---@field id string
---@field display_name string
---@field supports_twopass boolean
---@field video_codec string
---@field audio_codec string
---@field output_extension string
---@field accepts_bitrate boolean
---@field handles_speed_in_filter_graph? boolean applies speed trim/setpts itself
---@field renders_subtitles_in_source_time? boolean
local Format = {
	display_name = "Basic",
	supports_twopass = true,
	video_codec = "",
	audio_codec = "",
	output_extension = "",
	accepts_bitrate = true,
}
Format.__index = Format

---Filters applied before our own transformations (crop, scale).
---@param ctx webm.FormatContext
---@return string[]
function Format:pre_filters(ctx)
	return {}
end

---Filters applied after our own transformations.
---@param ctx webm.FormatContext
---@return string[]
function Format:post_filters(ctx)
	return {}
end

---Extra flags appended to the command line.
---@param ctx webm.FormatContext
---@return string[]
function Format:flags(ctx)
	return {}
end

---@return string[]
function Format:codec_flags()
	local codecs = {}
	if self.video_codec ~= "" then
		codecs[#codecs + 1] = "--ovc=" .. self.video_codec
	end
	if self.audio_codec ~= "" then
		codecs[#codecs + 1] = "--oac=" .. self.audio_codec
	end
	return codecs
end

---Changes the final command line just before it runs.
---@param command string[]
---@param times webm.EncodeTimes
---@param ctx webm.FormatContext
---@return string[]
function Format:post_command(command, times, ctx)
	return command
end

local function define(fields)
	return setmetatable(fields, Format)
end

local function threads_flag(ctx)
	return "--ovcopts-add=threads=" .. tostring(ctx.options.threads)
end

local M = {}

---@type table<string, webm.Format>
M.by_id = {}

local function add(format)
	M.by_id[format.id] = format
	return format
end

local raw = add(define({
	id = "raw",
	display_name = "Raw",
	supports_twopass = false,
	video_codec = "rawvideo",
	audio_codec = "pcm_s16le",
	output_extension = "avi",
	accepts_bitrate = false,
}))

-- This is very similar to the colormatrix mapping in webm-vp8. Maybe we
-- could find a way to unify them?
function raw:colorspace(ctx)
	local csp = ctx.host.get_property("colormatrix")
	if csp == "bt.601" then
		return "bt601"
	elseif csp == "bt.709" then
		return "bt709"
	elseif csp == "bt.2020" then
		return "bt2020"
	elseif csp == "smpte-240m" then
		return "smpte240m"
	end
	-- Probably using the OSD right now isn't very useful, as it will probably
	-- be used to print the "Encoding..." message really soon.
	ctx.log("info", "Warning, unknown colorspace " .. tostring(csp) .. " detected, using bt.601.")
	return "bt601"
end

function raw:post_filters(ctx)
	return { "format=yuv444p16", "lavfi-scale=in_color_matrix=" .. self:colorspace(ctx), "format=bgr24" }
end

local webm_vp8 = add(define({
	id = "webm-vp8",
	display_name = "WebM",
	supports_twopass = true,
	video_codec = "libvpx",
	audio_codec = "libvorbis",
	output_extension = "webm",
	accepts_bitrate = true,
}))

function webm_vp8:pre_filters(ctx)
	local colormatrix_filter = {
		["bt.709"] = "bt709",
		["bt.2020"] = "bt2020",
		["smpte-240m"] = "smpte240m",
	}
	-- vp8 only supports bt.601, so add a conversion filter
	-- thanks anon
	local colormatrix = ctx.host.get_property_native("video-params/colormatrix")
	if colormatrix_filter[colormatrix] then
		return { "lavfi-colormatrix=" .. colormatrix_filter[colormatrix] .. ":bt601" }
	end
	return {}
end

function webm_vp8:flags(ctx)
	return {
		threads_flag(ctx),
		"--ovcopts-add=auto-alt-ref=1",
		"--ovcopts-add=lag-in-frames=25",
		"--ovcopts-add=quality=good",
		"--ovcopts-add=cpu-used=0",
	}
end

local webm_vp9 = add(define({
	id = "webm-vp9",
	display_name = "WebM (VP9)",
	supports_twopass = false,
	video_codec = "libvpx-vp9",
	audio_codec = "libopus",
	output_extension = "webm",
	accepts_bitrate = true,
}))

function webm_vp9:flags(ctx)
	return { threads_flag(ctx) }
end

local avc = add(define({
	id = "avc",
	display_name = "AVC (h264/AAC)",
	supports_twopass = true,
	video_codec = "libx264",
	audio_codec = "aac",
	output_extension = "mp4",
	accepts_bitrate = true,
}))

function avc:flags(ctx)
	return { threads_flag(ctx) }
end

local avc_nvenc = add(define({
	id = "avc-nvenc",
	display_name = "AVC (h264-NVENC/AAC)",
	supports_twopass = true,
	video_codec = "h264_nvenc",
	audio_codec = "aac",
	output_extension = "mp4",
	accepts_bitrate = true,
}))

function avc_nvenc:flags(ctx)
	return { "--ovcopts-add=bf=0" }
end

-- VAAPI encoders reject most input pixel formats, so convert to nv12 first.
local function nv12_post_filters()
	return { "format=nv12" }
end

local avc_vaapi = add(define({
	id = "avc-vaapi",
	display_name = "AVC (h264-VAAPI/AAC, AMD/Intel GPU Linux)",
	supports_twopass = false,
	video_codec = "h264_vaapi",
	audio_codec = "aac",
	output_extension = "mp4",
	accepts_bitrate = true,
}))
avc_vaapi.post_filters = nv12_post_filters

add(define({
	id = "avc-amf",
	display_name = "AVC (h264-AMF/AAC, AMD GPU Windows)",
	supports_twopass = false,
	video_codec = "h264_amf",
	audio_codec = "aac",
	output_extension = "mp4",
	accepts_bitrate = true,
}))

local av1 = add(define({
	id = "av1",
	display_name = "AV1",
	supports_twopass = true,
	video_codec = "libaom-av1",
	audio_codec = "aac",
	output_extension = "mp4",
	accepts_bitrate = true,
}))

function av1:flags(ctx)
	return { threads_flag(ctx) }
end

local hevc = add(define({
	id = "hevc",
	display_name = "HEVC",
	supports_twopass = true,
	video_codec = "libx265",
	audio_codec = "aac",
	output_extension = "mp4",
	accepts_bitrate = true,
}))

function hevc:flags(ctx)
	return { threads_flag(ctx) }
end

local hevc_vaapi = add(define({
	id = "hevc-vaapi",
	display_name = "HEVC (VAAPI/AAC, AMD/Intel GPU Linux)",
	supports_twopass = false,
	video_codec = "hevc_vaapi",
	audio_codec = "aac",
	output_extension = "mp4",
	accepts_bitrate = true,
}))
hevc_vaapi.post_filters = nv12_post_filters

add(define({
	id = "mp3",
	display_name = "MP3 (libmp3lame)",
	supports_twopass = false,
	video_codec = "",
	audio_codec = "libmp3lame",
	output_extension = "mp3",
	accepts_bitrate = true,
}))

local gif = add(define({
	id = "gif",
	display_name = "GIF",
	supports_twopass = false,
	video_codec = "gif",
	audio_codec = "",
	output_extension = "gif",
	accepts_bitrate = false,
	-- GIF builds its own video filter graph, so it applies the speed
	-- trim/setpts itself; encode then skips the generic video speed flags.
	handles_speed_in_filter_graph = true,
	-- The sub filter runs after the graph retimes the video, so it needs
	-- encoder-domain subtitle speed/delay, just like other video formats.
	renders_subtitles_in_source_time = false,
}))

function gif:post_command(command, times, ctx)
	local new_command = {}

	local start_ts = time.to_time_string(times.sourceStart, false, true)
	local end_ts = time.to_time_string(times.sourceEnd, false, true)
	-- Escape hell...
	start_ts = start_ts:gsub(":", "\\\\:")
	end_ts = end_ts:gsub(":", "\\\\:")

	-- Need to use both trim and --start/--end
	local cfilter = "[in]trim=start=" .. start_ts .. ":end=" .. end_ts .. "[vidtmp];"

	-- Mirror the default trim -> setpts order inside the graph.
	if times.speed ~= 1 then
		cfilter = cfilter
			.. "[vidtmp]setpts=(PTS-"
			.. tostring(times.sourceStart)
			.. "/TB)/"
			.. tostring(times.speed)
			.. "[vidtmp];"
		cfilter = cfilter .. "[vidtmp]setpts=PTS+" .. tostring(times.sourceStart) .. "/TB[vidtmp];"
	end

	-- We iterate over commands in the order they are.
	-- The order is OK except for deinterlace which needs to be applied first:
	if ctx.host.get_property("deinterlace") == "yes" then
		cfilter = cfilter .. "[vidtmp]yadif=mode=1[vidtmp];"
	end

	-- Remove vf-add commands and prepare a complex filter
	for _, v in ipairs(command) do
		-- Other possible vf commands may be OK, but only convert fps, scale, crop, rotate and eq for now
		if
			v:match("^%-%-vf%-add=lavfi%-scale")
			or v:match("^%-%-vf%-add=lavfi%-crop")
			or v:match("^%-%-vf%-add=fps")
			or v:match("^%-%-vf%-add=lavfi%-eq")
		then
			local n = v:gsub("^%-%-vf%-add=", ""):gsub("^lavfi%-", "")
			cfilter = cfilter .. "[vidtmp]" .. n .. "[vidtmp];"
		elseif v:match("^%-%-video%-rotate=90") then
			cfilter = cfilter .. "[vidtmp]transpose=1[vidtmp];"
		elseif v:match("^%-%-video%-rotate=270") then
			cfilter = cfilter .. "[vidtmp]transpose=2[vidtmp];"
		elseif v:match("^%-%-video%-rotate=180") then
			cfilter = cfilter .. "[vidtmp]transpose=1[vidtmp];[vidtmp]transpose=1[vidtmp];"
		elseif not v:match("^%-%-deinterlace=") then
			-- Copy rest of the commands as they are (some might break palette use).
			-- The deinterlace option is dropped, the yadif filter added above replaces it.
			new_command[#new_command + 1] = v
		end
	end

	-- Finish the video filter graph before rendering subtitles. This matches
	-- normal mpv playback, where subtitles are rendered over the cropped
	-- and scaled video rather than being cropped with the source frame.
	cfilter = cfilter .. "[vidtmp]null[out]"
	new_command[#new_command + 1] = "--vf-add=lavfi=[" .. cfilter .. "]"
	new_command[#new_command + 1] = "--vf-add=sub"

	-- Generate the palette after subtitles have been rendered so subtitle
	-- colors are represented in the GIF palette.
	local palette_filter = "[in]split[topal][vidf];"
	palette_filter = palette_filter .. "[topal]palettegen[pal];"
	palette_filter = palette_filter .. "[vidf][pal]paletteuse=diff_mode=rectangle"
	if ctx.options.gif_dither ~= 6 then
		palette_filter = palette_filter .. ":dither=bayer:bayer_scale=" .. tostring(ctx.options.gif_dither)
	end
	palette_filter = palette_filter .. "[out]"
	new_command[#new_command + 1] = "--vf-add=lavfi=[" .. palette_filter .. "]"

	return new_command
end

local webp = add(define({
	id = "webp",
	display_name = "WebP",
	supports_twopass = false,
	video_codec = "libwebp",
	audio_codec = "",
	output_extension = "webp",
	accepts_bitrate = false,
}))

function webp:flags(ctx)
	local qscale = math.max(0, math.min(100, 100 - (ctx.options.crf * 2.5)))
	return {
		threads_flag(ctx),
		"--ovcopts-add=compression_level=6",
		"--ovcopts-add=qscale=" .. tostring(qscale),
		"--ofopts-add=loop=0",
	}
end

function webp:post_command(command, times, ctx)
	local new_command = {}
	for _, v in ipairs(command) do
		if not v:match("^%-%-ovcopts%-add=crf=") then
			new_command[#new_command + 1] = v
		end
	end
	return new_command
end

-- The order formats are listed in on the options page.
M.ids = {
	"av1",
	"hevc",
	"webm-vp9",
	"avc",
	"avc-nvenc",
	"avc-vaapi",
	"hevc-vaapi",
	"avc-amf",
	"webm-vp8",
	"webp",
	"gif",
	"mp3",
	"raw",
}

return M
