-- Scenario definitions for the golden tests. Each scenario gets a fresh fake
-- mpv world, loads the built script, then runs its steps. The resulting
-- transcript is compared with expected/<name>.txt.

local function merge(base, overrides)
	local merged = {}
	for key, value in pairs(base) do
		merged[key] = value
	end
	for key, value in pairs(overrides or {}) do
		merged[key] = value
	end
	return merged
end

-- A paused local file with one selected video, audio and subtitle track.
-- Float-valued sub-* properties are given as mpv formats them ("%f").
local function base_properties(overrides)
	return merge({
		path = "/videos/My Clip.mkv",
		filename = "My Clip.mkv",
		["filename/no-ext"] = "My Clip",
		["media-title"] = "My Clip",
		["stream-open-filename"] = "/videos/My Clip.mkv",
		["demuxer-via-network"] = false,
		["file-format"] = "mkv",
		duration = 10,
		["time-pos"] = 1.5,
		pause = true,
		speed = 1,
		mute = false,
		aid = 1,
		height = 1080,
		["sub-visibility"] = true,
		["track-list"] = {
			{ id = 1, type = "video", selected = true, external = false },
			{ id = 1, type = "audio", selected = true, external = false },
			{ id = 1, type = "sub", selected = true, external = false },
		},
		vf = {},
		brightness = 0,
		contrast = 0,
		saturation = 0,
		["video-rotate"] = 0,
		["ytdl-format"] = "",
		deinterlace = "no",
		colormatrix = "bt.709",
		["video-params/colormatrix"] = "bt.601",
		["sub-speed"] = 1,
		["sub-delay"] = 0,
		["sub-ass-override"] = "scale",
		["sub-ass-style-overrides"] = "",
		["sub-ass-use-video-data"] = "all",
		["sub-auto"] = "exact",
		["sub-pos"] = "100.000000",
		["sub-scale"] = "1.000000",
		["sub-font"] = "sans-serif",
		["sub-font-size"] = "38.000000",
		["sub-bold"] = false,
		["sub-italic"] = false,
		["sub-color"] = "#FFFFFFFF",
		["sub-back-color"] = "#00000000",
		["sub-border-color"] = "#FF000000",
		["sub-border-size"] = "3.000000",
		["sub-shadow-color"] = "#80000000",
		["sub-shadow-offset"] = "0.000000",
		["sub-use-margins"] = true,
		["sub-margin-x"] = 25,
		["sub-margin-y"] = 22,
		["sub-align-x"] = "center",
		["sub-align-y"] = "bottom",
		["sub-spacing"] = "0.000000",
		["sub-justify"] = "auto",
		["sub-gauss"] = "0.000000",
		["sub-gray"] = false,
		["video-out-params"] = { w = 1920, h = 1080, dw = 1920, dh = 1080 },
		keepaspect = true,
		["video-unscaled"] = false,
		panscan = 0,
		["video-zoom"] = 0,
		["video-align-x"] = 0,
		["video-align-y"] = 0,
		["video-pan-x"] = 0,
		["video-pan-y"] = 0,
	}, overrides)
end

-- The settings fake_mpv.new takes, with the base file, properties and home
-- directory filled in. Directories in files are marked with true.
local function world(settings)
	settings = settings or {}
	return {
		platform = settings.platform,
		properties = base_properties(settings.properties),
		osd_properties = merge({ ["osd-ass-cc/0"] = "<ass>" }, settings.osd_properties),
		files = merge({ ["/videos/My Clip.mkv"] = "source", ["/home/tester"] = true }, settings.files),
		environment = settings.environment or { HOME = "/home/tester" },
		conf_file = settings.conf_file,
		encoder_check = settings.encoder_check,
		curl_check = settings.curl_check,
		first_pass_status = settings.first_pass_status,
		encode_status = settings.encode_status,
		encoder_output_lines = settings.encoder_output_lines,
		upload = settings.upload,
		clipboard_property = settings.clipboard_property,
		file_size = settings.file_size,
		osd_width = settings.osd_width,
		osd_height = settings.osd_height,
	}
end

-- Synchronous, no progress page: the common setup for command goldens.
local SYNCHRONOUS = { display_progress = false }

local scenarios = {}
local function add(scenario)
	scenarios[#scenarios + 1] = scenario
end

-- Loading and options ---------------------------------------------------------

add({
	name = "load_defaults",
	world = world(),
	steps = { { "dump_options" } },
})

add({
	name = "options_from_conf",
	world = world({
		conf_file = {
			output_format = "avc",
			twopass = "no",
			target_filesize = "5000",
			scale_height = "720",
			fps = "thirty",
			apply_current_filters = "maybe",
			display_progress = "no",
			output_directory = "~/clips",
			additional_flags = "--ovcopts-add=preset=slow --no-sub",
			not_an_option = "1",
		},
	}),
	steps = { { "dump_options" } },
})

-- display_progress has a string default ("auto"), so "no" in webm.conf stays
-- the string "no". This pins how that value currently behaves.
add({
	name = "conf_display_progress_no",
	world = world({ conf_file = { display_progress = "no", output_format = "avc", twopass = "no" } }),
	steps = { { "range", start_time = 1.5, end_time = 4.25 }, { "encode" } },
})

add({
	name = "set_options_message",
	world = world(),
	steps = {
		{ "options", values = { output_format = "gif", twopass = false, target_filesize = 0, fps = 15 } },
		{ "dump_options" },
	},
})

-- Encode commands ---------------------------------------------------------

-- All defaults: webm-vp8, two pass, progress via popen, VP8 log patching.
add({
	name = "encode_default_vp8_twopass_progress",
	world = world(),
	steps = { { "range", start_time = 1.5, end_time = 4.25 }, { "encode" } },
})

add({
	name = "encode_vp8_bt709_colormatrix",
	world = world({ properties = { ["video-params/colormatrix"] = "bt.709" } }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

local format_ids = {
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
for _, format_id in ipairs(format_ids) do
	add({
		name = "format_" .. format_id,
		world = world(),
		steps = {
			{ "options", values = merge(SYNCHRONOUS, { output_format = format_id }) },
			{ "range", start_time = 1.5, end_time = 4.25 },
			{ "encode" },
		},
	})
end

add({
	name = "encode_avc_crop_scale_fps",
	world = world(),
	steps = {
		{
			"options",
			values = merge(
				SYNCHRONOUS,
				{ output_format = "avc", twopass = false, scale_height = 720, fps = 30, target_filesize = 5000 }
			),
		},
		{ "range", start_time = 2, end_time = 6.5, region = { x = 100, y = 50, w = 640, h = 360 } },
		{ "encode" },
	},
})

add({
	name = "encode_avc_constant_quality",
	world = world(),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, { output_format = "avc", twopass = true, target_filesize = 0, crf = 23 }),
		},
		{ "range", start_time = 1, end_time = 3 },
		{ "encode" },
	},
})

add({
	name = "encode_avc_strict_with_audio",
	world = world(),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, {
				output_format = "avc",
				twopass = false,
				strict_filesize_constraint = true,
				target_filesize = 3000,
				non_strict_additional_flags = "--ovcopts-add=qmin=10",
				additional_flags = "--ovcopts-add=preset=slow",
			}),
		},
		{ "range", start_time = 0, end_time = 7 },
		{ "encode" },
	},
})

add({
	name = "encode_mp3_bitrate",
	world = world(),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "mp3", target_filesize = 1000 }) },
		{ "range", start_time = 0, end_time = 3 },
		{ "encode" },
		{ "options", values = { strict_filesize_constraint = true } },
		{ "encode" },
	},
})

add({
	name = "encode_gif_full",
	world = world({ properties = { speed = 2, ["video-rotate"] = 90, deinterlace = "yes" } }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "gif", scale_height = 240, fps = 15 }) },
		{ "range", start_time = 61.25, end_time = 64.5, region = { x = 10, y = 20, w = 300, h = 200 } },
		{ "encode" },
	},
})

add({
	name = "encode_gif_sierra_rotations",
	world = world({ properties = { ["video-rotate"] = 270 } }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "gif", gif_dither = 6 }) },
		{ "range", start_time = 0, end_time = 1 },
		{ "encode" },
		{ "set", name = "video-rotate", value = 180 },
		{ "encode" },
	},
})

add({
	name = "encode_webp_quality",
	world = world(),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "webp", crf = 4 }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
		{ "options", values = { crf = 50 } },
		{ "encode" },
	},
})

add({
	name = "encode_raw_colorspaces",
	world = world(),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "raw" }) },
		{ "range", start_time = 0, end_time = 1 },
		{ "encode" },
		{ "set", name = "colormatrix", value = "bt.2020" },
		{ "encode" },
		{ "set", name = "colormatrix", value = "weird" },
		{ "encode" },
	},
})

add({
	name = "encode_speed_and_subtitle_timing",
	world = world({ properties = { speed = 0.2, ["sub-speed"] = 1.5, ["sub-delay"] = 0.5 } }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 10, end_time = 12 },
		{ "encode" },
	},
})

add({
	name = "encode_current_filters",
	world = world({
		properties = {
			vf = {
				{
					name = "lavfi-crop",
					enabled = true,
					params = { ["@0"] = "320", ["@1"] = "100", ["@2"] = "0", ["@3"] = "40" },
				},
				{ name = "lavfi", params = { graph = "hflip" } },
				{ name = "lavfi-eq", params = { contrast = "1.5", saturation = "1.2" } },
				{ name = "scale", params = { w = "640" } },
				{ name = "hflip", enabled = false },
				{ name = "vflip" },
			},
			brightness = 10,
			contrast = -20,
			saturation = 30,
		},
	}),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
		{ "note", text = "same filters, apply_current_filters off" },
		{ "options", values = { apply_current_filters = false } },
		{ "encode" },
		{ "note", text = "same filters through the GIF graph" },
		{ "options", values = { apply_current_filters = true, output_format = "gif" } },
		{ "encode" },
	},
})

add({
	name = "encode_square_pixels_and_metadata",
	world = world(),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, {
				output_format = "avc",
				twopass = false,
				force_square_pixels = true,
				scale_height = 480,
				write_filename_on_metadata = true,
				crf = -1,
				completion_command = "show-text '%{output}'",
			}),
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_tracks_external_and_mixed_audio",
	world = world({
		properties = {
			["track-list"] = {
				{ id = 1, type = "video", selected = true, external = false },
				{ id = 1, type = "audio", selected = true, external = false },
				{ id = 2, type = "audio", selected = true, external = false },
				{
					id = 3,
					type = "audio",
					selected = true,
					external = true,
					["external-filename"] = "/videos/commentary.ogg",
				},
				{ id = 4, type = "audio", selected = false, external = false },
				{
					id = 2,
					type = "sub",
					selected = true,
					external = true,
					["external-filename"] = "/videos/My Clip.en.srt",
				},
			},
		},
	}),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_long_external_filename",
	world = world({
		properties = {
			["track-list"] = {
				{ id = 1, type = "video", selected = true, external = false },
				{
					id = 5,
					type = "sub",
					selected = true,
					external = true,
					["external-filename"] = "https://x/" .. string.rep("a", 2050),
				},
			},
		},
	}),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_muted_without_subs",
	world = world({ properties = { mute = true, ["sub-visibility"] = false } }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_hls_stream",
	world = world({
		properties = {
			path = "https://example.com/live/index.m3u8",
			filename = "index.m3u8",
			["filename/no-ext"] = "index",
			["media-title"] = "Live Stream",
			["stream-open-filename"] = "https://example.com/live/index.m3u8",
			["demuxer-via-network"] = true,
			["file-format"] = "hls",
		},
	}),
	steps = {
		{ "options", values = { output_format = "webm-vp8", display_progress = false } },
		{ "range", start_time = 30, end_time = 35 },
		{ "encode" },
	},
})

add({
	name = "encode_plain_stream",
	world = world({
		properties = {
			path = "https://example.com/video.mp4",
			filename = "video.mp4",
			["filename/no-ext"] = "video",
			["media-title"] = "Some Video",
			["stream-open-filename"] = "https://example.com/video.mp4",
			["demuxer-via-network"] = true,
			["file-format"] = "mp4",
			["ytdl-format"] = "bestvideo+bestaudio",
		},
	}),
	steps = {
		{ "options", values = { output_format = "avc", display_progress = false, output_template = "%T-%X{net}%x" } },
		{ "range", start_time = 3, end_time = 5 },
		{ "encode" },
	},
})

add({
	name = "encode_run_detached",
	world = world(),
	steps = {
		{ "options", values = { output_format = "avc", twopass = false, run_detached = true } },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_output_directory_tilde",
	world = world(),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false, output_directory = "~/clips" }),
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_windows_progress",
	world = world({
		platform = "windows",
		properties = {
			path = 'C:\\Videos\\It\'s "ok".mkv',
			filename = 'It\'s "ok".mkv',
			["filename/no-ext"] = 'It\'s "ok"',
			["stream-open-filename"] = 'C:\\Videos\\It\'s "ok".mkv',
		},
		files = { ['C:\\Videos\\It\'s "ok".mkv'] = "source" },
		environment = { USERPROFILE = "C:\\Users\\tester" },
	}),
	steps = {
		{
			"options",
			values = { output_format = "avc", twopass = false, display_progress = true, output_template = "%F" },
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
		{ "note", text = "display_progress=auto is off on Windows" },
		{ "options", values = { display_progress = "auto", output_directory = "~" } },
		{ "encode" },
	},
})

add({
	name = "encode_progress_failure",
	world = world({ encoder_output_lines = { "Encode time-pos: 1.000000", "Exiting... (Errors when loading file)" } }),
	steps = {
		{ "options", values = { output_format = "avc", twopass = false, display_progress = true } },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_failures",
	world = world({ encode_status = 1 }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_first_pass_fails",
	world = world({ first_pass_status = 1 }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc" }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "encode" },
	},
})

add({
	name = "encode_encoder_missing",
	world = world({ encoder_check = { status = -3, stdout = "", error_string = "init" } }),
	steps = { { "range", start_time = 0, end_time = 2 }, { "encode" } },
})

add({
	name = "encode_encoder_broken",
	world = world({ encoder_check = { status = 2, stdout = "oops", stderr = "bad", error_string = "" } }),
	steps = { { "range", start_time = 0, end_time = 2 }, { "encode" } },
})

add({
	name = "encode_invalid_output_format",
	world = world({ conf_file = { output_format = "h264" } }),
	steps = { { "options", values = SYNCHRONOUS }, { "range", start_time = 0, end_time = 2 }, { "encode" } },
})

add({
	name = "encode_no_file",
	world = world({ properties = { path = false } }),
	steps = { { "set", name = "path", value = nil }, { "range", start_time = 0, end_time = 2 }, { "encode" } },
})

-- Output filenames ------------------------------------------------------------

local filename_world = world({
	properties = { ["media-title"] = "Title: 100% <Live>", height = 1080 },
	files = { ["/videos/clip_0001.mp4"] = "x", ["/videos/clip_0002.mp4"] = "x", ["/videos/seq 1.mp4"] = "x" },
})

add({
	name = "filename_templates",
	world = filename_world,
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 3723.4567, end_time = 3725.0015 },
		{ "filename", template = "%F-[%s-%e]%M" },
		{ "filename", template = "%f" },
		{ "filename", template = "%T" },
		{ "filename", template = "%S_%E" },
		{ "filename", template = "%wH:%wM:%wS.%wT" },
		{ "filename", template = "%wh %wm %ws %wf" },
		{ "filename", template = "%mH-%mM-%mS-%mT %mh %mm %ms %mf" },
		{ "filename", template = "%p_%P" },
		{ "filename", template = "%mp_%mP" },
		{ "filename", template = "%R" },
		{ "filename", template = "%mb" },
		{ "filename", template = "100%t%" },
		{ "filename", template = "%tY-%tm-%td %tH.%tM" },
		{ "filename", template = "%x|%X{dir}" },
		{ "filename", template = "%{filename/no-ext}" },
		{ "filename", template = "%{?pause:paused}%{!pause:playing}" },
		{ "filename", template = "%{?pause==yes:Y}%{!pause==yes:N}" },
		{ "filename", template = "%{missing:fallback}" },
		{ "filename", template = "%{missing:${filename/no-ext}}" },
		{ "filename", template = 'a<b>c:d"e/f\\g|h?i*j' },
		{ "filename", template = "clip_%04n" },
		{ "filename", template = "clip_%04n" },
		{ "filename", template = "seq %n" },
		{ "filename", template = "seq %n-%02n" },
		{ "filename", template = "literal %%n" },
		{ "filename", template = "%{?missing:%n}none" },
	},
})

add({
	name = "filename_audio_and_scale_markers",
	world = world(),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "filename", template = "%M%R" },
		{ "options", values = { scale_height = 720 } },
		{ "filename", template = "%M%R" },
		{ "set", name = "mute", value = true },
		{ "filename", template = "%M" },
		{ "set", name = "mute", value = false },
		{ "set", name = "aid", value = false },
		{ "filename", template = "%M" },
		{ "set", name = "aid", value = 1 },
		{ "options", values = { output_format = "gif" } },
		{ "filename", template = "%M" },
	},
})

-- Media-derived values are substituted with function replacements, so a %
-- in the media filename is inserted literally. This pins what happens when
-- such a value looks like another specifier.
add({
	name = "filename_media_values_with_specifiers",
	world = world({
		properties = {
			path = "/videos/50%Foo ${pause}.mkv",
			filename = "50%Foo ${pause}.mkv",
			["filename/no-ext"] = "50%Foo ${pause}",
			["media-title"] = "%f %s",
			["stream-open-filename"] = "/videos/50%Foo ${pause}.mkv",
		},
		files = { ["/videos/50%Foo ${pause}.mkv"] = "source" },
	}),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "filename", template = "%f" },
		{ "filename", template = "%F" },
		{ "filename", template = "%T" },
	},
})

-- UI pages ------------------------------------------------------------------

add({
	name = "ui_main_page",
	world = world({ curl_check = { status = 1, stdout = "", error_string = "" } }),
	steps = {
		{ "key", key = "W" },
		{ "bindings" },
		{ "set", name = "time-pos", value = 2.25 },
		{ "key", key = "1" },
		{ "set", name = "time-pos", value = 3725.5 },
		{ "key", key = "2" },
		{ "key", key = "!" },
		{ "key", key = "@" },
		{ "key", key = "u" },
		{ "key", key = "ESC" },
		{ "bindings" },
		{ "key", key = "W" },
		{ "key", key = "W" },
	},
})

add({
	name = "ui_main_page_upload_available",
	world = world(),
	steps = { { "key", key = "W" } },
})

add({
	name = "ui_file_loaded_resets_range",
	world = world(),
	steps = {
		{ "event", name = "file-loaded" },
		{ "state" },
		{ "set", name = "duration", value = nil },
		{ "key", key = "W" },
		{ "event", name = "file-loaded" },
		{ "state" },
	},
})

add({
	name = "ui_encode_validation",
	world = world(),
	steps = {
		{ "options", values = SYNCHRONOUS },
		{ "range", start_time = -1, end_time = 2 },
		{ "key", key = "W" },
		{ "key", key = "e" },
		{ "range", start_time = 1, end_time = -1 },
		{ "key", key = "W" },
		{ "key", key = "e" },
		{ "range", start_time = 3, end_time = 2 },
		{ "key", key = "W" },
		{ "key", key = "e" },
		{ "range", start_time = 2, end_time = 2 },
		{ "key", key = "W" },
		{ "key", key = "u" },
	},
})

add({
	name = "ui_options_page",
	world = world(),
	steps = {
		{ "key", key = "W" },
		{ "key", key = "o" },
		{ "bindings" },
		{ "key", key = "RIGHT" },
		{ "key", key = "RIGHT" },
		{ "note", text = "gif selected, so GIF Dither Type is visible" },
		{ "key", key = "DOWN" },
		{ "key", key = "LEFT" },
		{ "key", key = "DOWN" },
		{ "key", key = "LEFT" },
		{ "key", key = "DOWN" },
		{ "key", key = "RIGHT" },
		{ "key", key = "DOWN" },
		{ "key", key = "RIGHT" },
		{ "key", key = "DOWN" },
		{ "key", key = "DOWN" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "DOWN" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "LEFT" },
		{ "key", key = "DOWN" },
		{ "key", key = "RIGHT" },
		{ "key", key = "DOWN" },
		{ "key", key = "RIGHT" },
		{ "key", key = "DOWN" },
		{ "key", key = "RIGHT" },
		{ "key", key = "DOWN" },
		{ "key", key = "UP" },
		{ "key", key = "ENTER" },
		{ "dump_options" },
	},
})

add({
	name = "ui_options_page_cancel_and_hidden_rows",
	world = world({ curl_check = { status = 1, stdout = "", error_string = "" } }),
	steps = {
		{ "options", values = { scale_height = 333, output_format = "nope" } },
		{ "key", key = "W" },
		{ "key", key = "o" },
		{ "key", key = "LEFT" },
		{ "key", key = "DOWN" },
		{ "key", key = "RIGHT" },
		{ "key", key = "ESC" },
		{ "dump_options" },
	},
})

add({
	name = "ui_crop_page",
	world = world(),
	steps = {
		{ "key", key = "W" },
		{ "key", key = "c" },
		{ "bindings" },
		{ "mouse", x = 100, y = 50 },
		{ "key", key = "1" },
		{ "mouse", x = 1279, y = 719 },
		{ "key", key = "2" },
		{ "mouse", x = 2000, y = -5 },
		{ "key", key = "2" },
		{ "key", key = "r" },
		{ "mouse", x = 640, y = 360 },
		{ "key", key = "2" },
		{ "key", key = "ENTER" },
		{ "state" },
		{ "key", key = "c" },
		{ "key", key = "ESC" },
		{ "state" },
	},
})

add({
	name = "ui_crop_page_letterboxed_rotated",
	world = world({
		osd_width = 1280,
		osd_height = 1024,
		properties = { ["video-out-params"] = { w = 1920, h = 800, dw = 1920, dh = 800 }, ["video-rotate"] = 90 },
	}),
	steps = {
		{ "key", key = "W" },
		{ "key", key = "c" },
		{ "mouse", x = 300, y = 10 },
		{ "key", key = "1" },
		{ "mouse", x = 900, y = 1000 },
		{ "key", key = "2" },
		{ "key", key = "ENTER" },
		{ "state" },
	},
})

add({
	name = "ui_preview_page",
	world = world({ properties = { vf = { { name = "hflip" } } } }),
	steps = {
		{ "range", start_time = 2, end_time = 4, region = { x = 0, y = 10, w = 100, h = 50 } },
		{ "key", key = "W" },
		{ "key", key = "p" },
		{ "bindings" },
		{ "key", key = "ESC" },
	},
})

-- Uploads -----------------------------------------------------------------

add({
	name = "upload_catbox_success",
	world = world({ file_size = 3456789 }),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false, catbox_userhash = "abc123" }),
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "key", key = "W" },
		{ "key", key = "u" },
		{ "bindings" },
		{ "file", path = "/tmp/lua_tmp2", content = "##          12.0%\r#####        45.5%" },
		{ "timers" },
		{ "timers" },
		{ "run_pending_commands" },
		{ "key", key = "c" },
		{ "key", key = "o" },
		{ "key", key = "ESC" },
	},
})

add({
	name = "upload_litterbox_failure_retry_options",
	world = world({
		properties = {
			path = "/videos/a,b;c.mkv",
			filename = "a,b;c.mkv",
			["filename/no-ext"] = "a,b;c",
			["stream-open-filename"] = "/videos/a,b;c.mkv",
		},
		files = { ["/videos/a,b;c.mkv"] = "source" },
		upload = { status = 0, http = "412", body = "No expire time specified.\n\n  Try again." },
	}),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, {
				output_format = "avc",
				twopass = false,
				upload_host = "litterbox",
				litterbox_time = "72h",
				catbox_userhash = "ignored",
				upload_curl_path = "/opt/curl",
			}),
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "upload" },
		{ "run_pending_commands" },
		{ "key", key = "c" },
		{ "key", key = "r" },
		{ "run_pending_commands" },
		{ "key", key = "o" },
	},
})

add({
	name = "upload_cancel",
	world = world(),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false, open_after_upload = true }),
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "upload" },
		{ "key", key = "ESC" },
		{ "run_pending_commands" },
		{ "timers" },
	},
})

add({
	name = "upload_done_open_and_clipboard_fallback",
	world = world({ clipboard_property = false }),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false, open_after_upload = true }),
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "upload" },
		{ "run_pending_commands" },
		{ "key", key = "c" },
	},
})

add({
	name = "upload_windows_clipboard_fallback",
	world = world({
		platform = "windows",
		clipboard_property = false,
		properties = {
			path = "C:\\Videos\\clip.mkv",
			filename = "clip.mkv",
			["filename/no-ext"] = "clip",
			["stream-open-filename"] = "C:\\Videos\\clip.mkv",
		},
		files = { ["C:\\Videos\\clip.mkv"] = "source" },
		environment = { USERPROFILE = "C:\\Users\\tester" },
	}),
	steps = {
		{
			"options",
			values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false, open_after_upload = true }),
		},
		{ "range", start_time = 0, end_time = 2 },
		{ "upload" },
		{ "run_pending_commands" },
	},
})

add({
	name = "upload_curl_missing",
	world = world({ curl_check = { status = -3, stdout = "", error_string = "init" } }),
	steps = { { "range", start_time = 0, end_time = 2 }, { "upload" } },
})

add({
	name = "upload_encode_fails",
	world = world({ encode_status = 1 }),
	steps = {
		{ "options", values = merge(SYNCHRONOUS, { output_format = "avc", twopass = false }) },
		{ "range", start_time = 0, end_time = 2 },
		{ "upload" },
	},
})

return scenarios
