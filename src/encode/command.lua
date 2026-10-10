-- Builds the mpv command lines for an encode. Nothing here runs anything:
-- the caller gets the commands, the output path and any messages to log.

local bitrate = require("core.bitrate")
local filename = require("core.filename")
local filters = require("core.filters")
local paths = require("core.paths")
local speed = require("core.speed")
local time = require("core.time")

local M = {}

-- Tracks are always written in this order.
local TRACK_TYPES = { "video", "audio", "sub" }

local EXTERNAL_FLAG = { audio = "audio-file", sub = "sub-file" }
local INTERNAL_FLAG = { video = "vid", audio = "aid", sub = "sid" }

local PLAYBACK_PROPERTIES = { "video-rotate", "ytdl-format", "deinterlace" }

local SUBTITLE_PROPERTIES = {
	"sub-ass-override",
	"sub-ass-style-overrides",
	"sub-ass-use-video-data",
	"sub-auto",
	"sub-pos",
	"sub-scale",
	"sub-font",
	"sub-font-size",
	"sub-bold",
	"sub-italic",
	"sub-color",
	"sub-back-color",
	"sub-border-color",
	"sub-border-size",
	"sub-shadow-color",
	"sub-shadow-offset",
	"sub-use-margins",
	"sub-margin-x",
	"sub-margin-y",
	"sub-align-x",
	"sub-align-y",
	"sub-spacing",
	"sub-justify",
	"sub-gauss",
	"sub-gray",
}

local function append(list, items)
	for _, item in ipairs(items) do
		list[#list + 1] = item
	end
	return list
end

local function region_is_valid(region)
	return region and region.x > -1 and region.y > -1 and region.w > -1 and region.h > -1
end

---Selected tracks that should be encoded, by type. Muted audio and hidden
---subtitles are left out.
local function active_tracks(host)
	local accepted = {
		video = true,
		audio = not host.get_property_bool("mute"),
		sub = host.get_property_bool("sub-visibility"),
	}
	local active = { video = {}, audio = {}, sub = {} }
	for _, track in ipairs(host.get_property_native("track-list")) do
		if track["selected"] and accepted[track["type"]] then
			local list = active[track["type"]]
			list[#list + 1] = track
		end
	end
	return active
end

local function supported_tracks(active, format)
	local has_video_codec = format.video_codec ~= ""
	local has_audio_codec = format.audio_codec ~= ""
	return {
		video = has_video_codec and active["video"] or {},
		audio = has_audio_codec and active["audio"] or {},
		sub = has_video_codec and active["sub"] or {},
	}
end

local function track_flag(track)
	-- The external tracks rely on the behavior that, when using
	-- audio-file/sub-file only once, the track is selected by default.
	-- Also, for some reason, ytdl-hook produces external tracks with absurdly long
	-- filenames; this breaks our command line. Try to keep it sane, under 2048 characters.
	if track["external"] and string.len(track["external-filename"]) <= 2048 then
		return "--" .. tostring(EXTERNAL_FLAG[track["type"]]) .. "=" .. tostring(track["external-filename"])
	end
	return "--" .. tostring(INTERNAL_FLAG[track["type"]]) .. "=" .. tostring(track["id"])
end

local function audio_track_flags(tracks)
	-- Several audio tracks can be selected at once. Only internal tracks can be
	-- mixed reliably, so external ones are passed as they are and the internal
	-- ones are mixed with lavfi-complex when there is more than one.
	local flags = {}
	local internal_tracks = {}
	for _, track in ipairs(tracks) do
		if track["external"] then
			flags[#flags + 1] = track_flag(track)
		else
			internal_tracks[#internal_tracks + 1] = track
		end
	end
	if #internal_tracks > 1 then
		local filter_string = ""
		for _, track in ipairs(internal_tracks) do
			filter_string = filter_string .. "[aid" .. tostring(track["id"]) .. "]"
		end
		flags[#flags + 1] = "--lavfi-complex=" .. filter_string .. "amix[ao]"
	elseif #internal_tracks == 1 then
		flags[#flags + 1] = track_flag(internal_tracks[1])
	end
	return flags
end

local function track_flags(supported)
	local flags = {}
	for _, track_type in ipairs(TRACK_TYPES) do
		local tracks = supported[track_type]
		if track_type == "audio" then
			append(flags, audio_track_flags(tracks))
		else
			for _, track in ipairs(tracks) do
				flags[#flags + 1] = track_flag(track)
			end
		end
	end
	for _, track_type in ipairs(TRACK_TYPES) do
		if #supported[track_type] == 0 then
			flags[#flags + 1] = "--" .. INTERNAL_FLAG[track_type] .. "=no"
		end
	end
	return flags
end

-- Copies the current value of each property as --name=value, if it has one.
local function property_flags(host, names)
	local flags = {}
	for _, name in ipairs(names) do
		local value = host.get_property(name)
		if value and value ~= "" then
			flags[#flags + 1] = "--" .. name .. "=" .. tostring(value)
		end
	end
	return flags
end

local function video_filters(ctx, format, region)
	local host, options = ctx.host, ctx.options
	local list = {}
	append(list, format:pre_filters(ctx))
	if options.apply_current_filters then
		append(list, filters.current(host.get_property_native("vf")))
	end
	if region_is_valid(region) then
		list[#list + 1] = "lavfi-crop="
			.. tostring(region.w)
			.. ":"
			.. tostring(region.h)
			.. ":"
			.. tostring(region.x)
			.. ":"
			.. tostring(region.y)
	end
	append(list, filters.scale(options))
	append(list, filters.fps(options))
	if options.apply_current_filters then
		append(
			list,
			filters.color_adjustments(
				host.get_property_number("brightness", 0) --[[@as number]],
				host.get_property_number("contrast", 0) --[[@as number]],
				host.get_property_number("saturation", 0) --[[@as number]]
			)
		)
	end
	append(list, format:post_filters(ctx))
	return list
end

local function video_flags(ctx, format, region, times)
	local host = ctx.host
	local flags = {}
	append(flags, property_flags(host, PLAYBACK_PROPERTIES))
	append(flags, property_flags(host, SUBTITLE_PROPERTIES))
	for _, filter in ipairs(video_filters(ctx, format, region)) do
		flags[#flags + 1] = "--vf-add=" .. filter
	end
	if not format.handles_speed_in_filter_graph then
		append(flags, speed.video_flags(times))
	end
	append(
		flags,
		speed.subtitle_flags(
			times,
			host.get_property_number("sub-speed", 1) --[[@as number]],
			host.get_property_number("sub-delay", 0) --[[@as number]],
			format.renders_subtitles_in_source_time
		)
	)
	return flags
end

local function bitrate_flags(options, format, supported, times)
	if not format.accepts_bitrate then
		return {}
	end
	local kind = format.video_codec ~= "" and "ovc" or "oac"
	if options.target_filesize <= 0 then
		-- Set the bitrate to 0. This might enable constant quality, or some
		-- other encoding modes, depending on the codec.
		return { "--" .. kind .. "opts-add=b=0" }
	end

	local flags = {}
	local video_bitrate, audio_bitrate = bitrate.calculate(options, format, #supported["audio"], times.outputDuration)
	if video_bitrate then
		flags[#flags + 1] = "--ovcopts-add=b=" .. tostring(video_bitrate) .. "k"
	end
	if audio_bitrate then
		flags[#flags + 1] = "--oacopts-add=b=" .. tostring(audio_bitrate) .. "k"
	end
	if options.strict_filesize_constraint then
		local strict_bitrate = format.video_codec ~= "" and video_bitrate or audio_bitrate
		flags[#flags + 1] = "--" .. kind .. "opts-add=minrate=" .. tostring(strict_bitrate) .. "k"
		flags[#flags + 1] = "--" .. kind .. "opts-add=maxrate=" .. tostring(strict_bitrate) .. "k"
	end
	return flags
end

---The --hwdec value for the encoder, or nil to leave mpv's own setting.
---With options.hwdec "auto", formats that encode on a GPU also decode on it.
---The -copy mode is needed because the encoder takes frames from main memory.
---@param options webm.Options
---@param format webm.Format
---@return string?
function M.hardware_decoding(options, format)
	if options.hwdec == "auto" then
		return format.device ~= "cpu" and "auto-copy" or nil
	end
	if options.hwdec == "" then
		return nil
	end
	return options.hwdec
end

local function user_flags(options)
	local flags = {}
	-- split the user-passed settings on whitespace
	for token in string.gmatch(options.additional_flags, "[^%s]+") do
		flags[#flags + 1] = token
	end
	if not options.strict_filesize_constraint then
		for token in string.gmatch(options.non_strict_additional_flags, "[^%s]+") do
			flags[#flags + 1] = token
		end
		-- Also add CRF here, as it used to be a part of the non-strict flags.
		-- This might change in the future, I don't know.
		if options.crf >= 0 then
			flags[#flags + 1] = "--ovcopts-add=crf=" .. tostring(options.crf)
		end
	end
	return flags
end

---@class webm.EncodeRequest
---@field format webm.Format
---@field region? {x: number, y: number, w: number, h: number}
---@field path string file to encode from (a cache dump for HLS streams)
---@field is_stream boolean
---@field start_time number selection start in `path`
---@field end_time number
---@field original_start_time number selection start in the playing file, for the filename
---@field original_end_time number

---@class webm.EncodePlan
---@field command string[] the final encode command
---@field first_pass? string[] run this first when encoding in two passes
---@field patch_vp8_log boolean fix the libvpx pass log between the passes
---@field out_path string
---@field pass_log_path string libvpx/libaom first-pass log
---@field cleanup_paths string[] remove these once the encode is over
---@field times webm.EncodeTimes
---@field messages {level: string, text: string}[] to log, in order

---@param host webm.Host
---@param options webm.Options
---@param request webm.EncodeRequest
---@return webm.EncodePlan
function M.build(host, options, request)
	local format = request.format
	local messages = {}
	local ctx = {
		host = host,
		options = options,
		log = function(level, text)
			messages[#messages + 1] = { level = level, text = text }
		end,
	}

	local times = speed.encode_times(request.start_time, request.end_time, host.get_property_native("speed") or 1)

	-- An unknown output_format fails here, on the first use of the format.
	local command = append({
		"mpv",
		request.path,
		"--start=" .. time.to_time_string(times.encoderStart, false, true),
		"--end=" .. time.to_time_string(times.encoderEnd, false, true),
		-- When loop-file=inf, the encode won't end. Set this to override.
		"--loop-file=no",
		-- Same thing with --pause
		"--no-pause",
	}, format:codec_flags())

	local hardware_decoding = M.hardware_decoding(options, format)
	if hardware_decoding then
		command[#command + 1] = "--hwdec=" .. hardware_decoding
	end

	local supported = supported_tracks(active_tracks(host), format)
	append(command, track_flags(supported))

	if format.video_codec ~= "" then
		-- All those are only valid for video codecs.
		append(command, video_flags(ctx, format, request.region, times))
	end
	if format.audio_codec ~= "" then
		append(command, speed.audio_flags(times))
	end
	append(command, format:flags(ctx))
	if options.write_filename_on_metadata then
		local title = host.get_property("filename/no-ext") --[[@as string]]
		command[#command + 1] = "--oset-metadata=title=%" .. tostring(string.len(title)) .. "%" .. tostring(title)
	end
	append(command, bitrate_flags(options, format, supported, times))
	append(command, user_flags(options))

	local function expand_home(path)
		local expanded, warning = paths.expand_home(host, path)
		if warning then
			ctx.log("warn", warning)
		end
		return expanded
	end

	local dir
	if request.is_stream then
		dir = expand_home("~")
	else
		dir = host.split_path(request.path)
	end
	if options.output_directory ~= "" then
		dir = expand_home(options.output_directory)
	end
	local out_name = filename.format(host, options, request.original_start_time, request.original_end_time, format, dir)
	local out_path = host.join_path(dir, out_name)
	command[#command + 1] = "--o=" .. out_path

	-- The current x264/x265 settings cannot use a second pass in constant-quality mode.
	-- Other encoders, including libvpx and libaom, can still use two passes.
	-- Two passes don't work on streams.
	local constant_quality_x26x = options.target_filesize <= 0
		and (format.video_codec == "libx264" or format.video_codec == "libx265")
	local first_pass
	if options.twopass and format.supports_twopass and not constant_quality_x26x and not request.is_stream then
		first_pass = append(append({}, command), { "--ovcopts-add=flags=+pass1" })
		command[#command + 1] = "--ovcopts-add=flags=+pass2"
	end

	return {
		command = format:post_command(command, times, ctx),
		first_pass = first_pass,
		patch_vp8_log = first_pass ~= nil and format.video_codec == "libvpx",
		out_path = out_path,
		pass_log_path = out_path .. "-video-pass1.log",
		-- x264 writes its pass log to the working directory.
		cleanup_paths = { out_path .. "-video-pass1.log", "x264_2pass.log", "x264_2pass.log.mbtree" },
		times = times,
		messages = messages,
	}
end

return M
