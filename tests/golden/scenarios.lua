-- Scenario definitions for the golden tests. Each scenario gets a fresh fake
-- mpv world, loads the built script, then runs its steps. The resulting
-- transcript is compared with expected/<name>.txt.

local function merge(base, extra)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- A paused local file with one selected video, audio and subtitle track.
-- Float-valued sub-* properties are given as mpv formats them ("%f").
local function base_props(extra)
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
	}, extra)
end

local function world(extra)
	extra = extra or {}
	return {
		platform = extra.platform,
		props = base_props(extra.props),
		osd_props = merge({ ["osd-ass-cc/0"] = "<ass>" }, extra.osd_props),
		files = merge({ ["/videos/My Clip.mkv"] = "source", ["/home/tester"] = true }, extra.files),
		env = extra.env or { HOME = "/home/tester" },
		conf = extra.conf,
		encoder_check = extra.encoder_check,
		curl = extra.curl,
		first_pass_status = extra.first_pass_status,
		encode_status = extra.encode_status,
		popen_lines = extra.popen_lines,
		upload = extra.upload,
		clipboard_property = extra.clipboard_property,
		file_size = extra.file_size,
		osd_w = extra.osd_w,
		osd_h = extra.osd_h,
	}
end

-- Synchronous, no progress page: the common setup for command goldens.
local SYNC = { display_progress = false }

local scenarios = {}
local function add(s)
	scenarios[#scenarios + 1] = s
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
		conf = {
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
	world = world({ conf = { display_progress = "no", output_format = "avc", twopass = "no" } }),
	steps = { { "range", 1.5, 4.25 }, { "encode" } },
})

add({
	name = "set_options_message",
	world = world(),
	steps = {
		{ "options", { output_format = "gif", twopass = false, target_filesize = 0, fps = 15 } },
		{ "dump_options" },
	},
})

-- Encode commands ---------------------------------------------------------

-- All defaults: webm-vp8, two pass, progress via popen, VP8 log patching.
add({
	name = "encode_default_vp8_twopass_progress",
	world = world(),
	steps = { { "range", 1.5, 4.25 }, { "encode" } },
})

add({
	name = "encode_vp8_bt709_colormatrix",
	world = world({ props = { ["video-params/colormatrix"] = "bt.709" } }),
	steps = { { "options", merge(SYNC, { twopass = false }) }, { "range", 0, 2 }, { "encode" } },
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
for _, id in ipairs(format_ids) do
	add({
		name = "format_" .. id,
		world = world(),
		steps = {
			{ "options", merge(SYNC, { output_format = id }) },
			{ "range", 1.5, 4.25 },
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
			merge(
				SYNC,
				{ output_format = "avc", twopass = false, scale_height = 720, fps = 30, target_filesize = 5000 }
			),
		},
		{ "range", 2, 6.5, { x = 100, y = 50, w = 640, h = 360 } },
		{ "encode" },
	},
})

add({
	name = "encode_avc_constant_quality",
	world = world(),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = true, target_filesize = 0, crf = 23 }) },
		{ "range", 1, 3 },
		{ "encode" },
	},
})

add({
	name = "encode_avc_strict_with_audio",
	world = world(),
	steps = {
		{
			"options",
			merge(SYNC, {
				output_format = "avc",
				twopass = false,
				strict_filesize_constraint = true,
				target_filesize = 3000,
				non_strict_additional_flags = "--ovcopts-add=qmin=10",
				additional_flags = "--ovcopts-add=preset=slow",
			}),
		},
		{ "range", 0, 7 },
		{ "encode" },
	},
})

add({
	name = "encode_mp3_bitrate",
	world = world(),
	steps = {
		{ "options", merge(SYNC, { output_format = "mp3", target_filesize = 1000 }) },
		{ "range", 0, 3 },
		{ "encode" },
		{ "options", { strict_filesize_constraint = true } },
		{ "encode" },
	},
})

add({
	name = "encode_gif_full",
	world = world({ props = { speed = 2, ["video-rotate"] = 90, deinterlace = "yes" } }),
	steps = {
		{ "options", merge(SYNC, { output_format = "gif", scale_height = 240, fps = 15 }) },
		{ "range", 61.25, 64.5, { x = 10, y = 20, w = 300, h = 200 } },
		{ "encode" },
	},
})

add({
	name = "encode_gif_sierra_rotations",
	world = world({ props = { ["video-rotate"] = 270 } }),
	steps = {
		{ "options", merge(SYNC, { output_format = "gif", gif_dither = 6 }) },
		{ "range", 0, 1 },
		{ "encode" },
		{ "set", "video-rotate", 180 },
		{ "encode" },
	},
})

add({
	name = "encode_webp_quality",
	world = world(),
	steps = {
		{ "options", merge(SYNC, { output_format = "webp", crf = 4 }) },
		{ "range", 0, 2 },
		{ "encode" },
		{ "options", { crf = 50 } },
		{ "encode" },
	},
})

add({
	name = "encode_raw_colorspaces",
	world = world(),
	steps = {
		{ "options", merge(SYNC, { output_format = "raw" }) },
		{ "range", 0, 1 },
		{ "encode" },
		{ "set", "colormatrix", "bt.2020" },
		{ "encode" },
		{ "set", "colormatrix", "weird" },
		{ "encode" },
	},
})

add({
	name = "encode_speed_and_subtitle_timing",
	world = world({ props = { speed = 0.2, ["sub-speed"] = 1.5, ["sub-delay"] = 0.5 } }),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 10, 12 },
		{ "encode" },
	},
})

add({
	name = "encode_current_filters",
	world = world({
		props = {
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
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "encode" },
		{ "note", "same filters, apply_current_filters off" },
		{ "options", { apply_current_filters = false } },
		{ "encode" },
		{ "note", "same filters through the GIF graph" },
		{ "options", { apply_current_filters = true, output_format = "gif" } },
		{ "encode" },
	},
})

add({
	name = "encode_square_pixels_and_metadata",
	world = world(),
	steps = {
		{
			"options",
			merge(SYNC, {
				output_format = "avc",
				twopass = false,
				force_square_pixels = true,
				scale_height = 480,
				write_filename_on_metadata = true,
				crf = -1,
				completion_command = "show-text '%{output}'",
			}),
		},
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_tracks_external_and_mixed_audio",
	world = world({
		props = {
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
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_long_external_filename",
	world = world({
		props = {
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
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_muted_without_subs",
	world = world({ props = { mute = true, ["sub-visibility"] = false } }),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_hls_stream",
	world = world({
		props = {
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
		{ "options", { output_format = "webm-vp8", display_progress = false } },
		{ "range", 30, 35 },
		{ "encode" },
	},
})

add({
	name = "encode_plain_stream",
	world = world({
		props = {
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
		{ "options", { output_format = "avc", display_progress = false, output_template = "%T-%X{net}%x" } },
		{ "range", 3, 5 },
		{ "encode" },
	},
})

add({
	name = "encode_run_detached",
	world = world(),
	steps = {
		{ "options", { output_format = "avc", twopass = false, run_detached = true } },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_output_directory_tilde",
	world = world(),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false, output_directory = "~/clips" }) },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_windows_progress",
	world = world({
		platform = "windows",
		props = {
			path = 'C:\\Videos\\It\'s "ok".mkv',
			filename = 'It\'s "ok".mkv',
			["filename/no-ext"] = 'It\'s "ok"',
			["stream-open-filename"] = 'C:\\Videos\\It\'s "ok".mkv',
		},
		files = { ['C:\\Videos\\It\'s "ok".mkv'] = "source" },
		env = { USERPROFILE = "C:\\Users\\tester" },
	}),
	steps = {
		{ "options", { output_format = "avc", twopass = false, display_progress = true, output_template = "%F" } },
		{ "range", 0, 2 },
		{ "encode" },
		{ "note", "display_progress=auto is off on Windows" },
		{ "options", { display_progress = "auto", output_directory = "~" } },
		{ "encode" },
	},
})

add({
	name = "encode_progress_failure",
	world = world({ popen_lines = { "Encode time-pos: 1.000000", "Exiting... (Errors when loading file)" } }),
	steps = {
		{ "options", { output_format = "avc", twopass = false, display_progress = true } },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_failures",
	world = world({ encode_status = 1 }),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_first_pass_fails",
	world = world({ first_pass_status = 1 }),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc" }) },
		{ "range", 0, 2 },
		{ "encode" },
	},
})

add({
	name = "encode_encoder_missing",
	world = world({ encoder_check = { status = -3, stdout = "", error_string = "init" } }),
	steps = { { "range", 0, 2 }, { "encode" } },
})

add({
	name = "encode_encoder_broken",
	world = world({ encoder_check = { status = 2, stdout = "oops", stderr = "bad", error_string = "" } }),
	steps = { { "range", 0, 2 }, { "encode" } },
})

add({
	name = "encode_invalid_output_format",
	world = world({ conf = { output_format = "h264" } }),
	steps = { { "options", SYNC }, { "range", 0, 2 }, { "encode" } },
})

add({
	name = "encode_no_file",
	world = world({ props = { path = false } }),
	steps = { { "set", "path", nil }, { "range", 0, 2 }, { "encode" } },
})

-- Output filenames ------------------------------------------------------------

local filename_world = world({
	props = { ["media-title"] = "Title: 100% <Live>", height = 1080 },
	files = { ["/videos/clip_0001.mp4"] = "x", ["/videos/clip_0002.mp4"] = "x", ["/videos/seq 1.mp4"] = "x" },
})

add({
	name = "filename_templates",
	world = filename_world,
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 3723.4567, 3725.0015 },
		{ "filename", "%F-[%s-%e]%M" },
		{ "filename", "%f" },
		{ "filename", "%T" },
		{ "filename", "%S_%E" },
		{ "filename", "%wH:%wM:%wS.%wT" },
		{ "filename", "%wh %wm %ws %wf" },
		{ "filename", "%mH-%mM-%mS-%mT %mh %mm %ms %mf" },
		{ "filename", "%p_%P" },
		{ "filename", "%mp_%mP" },
		{ "filename", "%R" },
		{ "filename", "%mb" },
		{ "filename", "100%t%" },
		{ "filename", "%tY-%tm-%td %tH.%tM" },
		{ "filename", "%x|%X{dir}" },
		{ "filename", "%{filename/no-ext}" },
		{ "filename", "%{?pause:paused}%{!pause:playing}" },
		{ "filename", "%{?pause==yes:Y}%{!pause==yes:N}" },
		{ "filename", "%{missing:fallback}" },
		{ "filename", "%{missing:${filename/no-ext}}" },
		{ "filename", 'a<b>c:d"e/f\\g|h?i*j' },
		{ "filename", "clip_%04n" },
		{ "filename", "clip_%04n" },
		{ "filename", "seq %n" },
		{ "filename", "seq %n-%02n" },
		{ "filename", "literal %%n" },
		{ "filename", "%{?missing:%n}none" },
	},
})

add({
	name = "filename_audio_and_scale_markers",
	world = world(),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "filename", "%M%R" },
		{ "options", { scale_height = 720 } },
		{ "filename", "%M%R" },
		{ "set", "mute", true },
		{ "filename", "%M" },
		{ "set", "mute", false },
		{ "set", "aid", false },
		{ "filename", "%M" },
		{ "set", "aid", 1 },
		{ "options", { output_format = "gif" } },
		{ "filename", "%M" },
	},
})

-- Media-derived values are substituted with function replacements, so a %
-- in the media filename is inserted literally. This pins what happens when
-- such a value looks like another specifier.
add({
	name = "filename_media_values_with_specifiers",
	world = world({
		props = {
			path = "/videos/50%Foo ${pause}.mkv",
			filename = "50%Foo ${pause}.mkv",
			["filename/no-ext"] = "50%Foo ${pause}",
			["media-title"] = "%f %s",
			["stream-open-filename"] = "/videos/50%Foo ${pause}.mkv",
		},
		files = { ["/videos/50%Foo ${pause}.mkv"] = "source" },
	}),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "filename", "%f" },
		{ "filename", "%F" },
		{ "filename", "%T" },
	},
})

-- UI pages ------------------------------------------------------------------

add({
	name = "ui_main_page",
	world = world({ curl = { status = 1, stdout = "", error_string = "" } }),
	steps = {
		{ "key", "W" },
		{ "bindings" },
		{ "set", "time-pos", 2.25 },
		{ "key", "1" },
		{ "set", "time-pos", 3725.5 },
		{ "key", "2" },
		{ "key", "!" },
		{ "key", "@" },
		{ "key", "u" },
		{ "key", "ESC" },
		{ "bindings" },
		{ "key", "W" },
		{ "key", "W" },
	},
})

add({
	name = "ui_main_page_upload_available",
	world = world(),
	steps = { { "key", "W" } },
})

add({
	name = "ui_file_loaded_resets_range",
	world = world(),
	steps = {
		{ "event", "file-loaded" },
		{ "state" },
		{ "set", "duration", nil },
		{ "key", "W" },
		{ "event", "file-loaded" },
		{ "state" },
	},
})

add({
	name = "ui_encode_validation",
	world = world(),
	steps = {
		{ "options", SYNC },
		{ "range", -1, 2 },
		{ "key", "W" },
		{ "key", "e" },
		{ "range", 1, -1 },
		{ "key", "W" },
		{ "key", "e" },
		{ "range", 3, 2 },
		{ "key", "W" },
		{ "key", "e" },
		{ "range", 2, 2 },
		{ "key", "W" },
		{ "key", "u" },
	},
})

add({
	name = "ui_options_page",
	world = world(),
	steps = {
		{ "key", "W" },
		{ "key", "o" },
		{ "bindings" },
		{ "key", "RIGHT" },
		{ "key", "RIGHT" },
		{ "note", "gif selected, so GIF Dither Type is visible" },
		{ "key", "DOWN" },
		{ "key", "LEFT" },
		{ "key", "DOWN" },
		{ "key", "LEFT" },
		{ "key", "DOWN" },
		{ "key", "RIGHT" },
		{ "key", "DOWN" },
		{ "key", "RIGHT" },
		{ "key", "DOWN" },
		{ "key", "DOWN" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "DOWN" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "LEFT" },
		{ "key", "DOWN" },
		{ "key", "RIGHT" },
		{ "key", "DOWN" },
		{ "key", "RIGHT" },
		{ "key", "DOWN" },
		{ "key", "RIGHT" },
		{ "key", "DOWN" },
		{ "key", "UP" },
		{ "key", "ENTER" },
		{ "dump_options" },
	},
})

add({
	name = "ui_options_page_cancel_and_hidden_rows",
	world = world({ curl = { status = 1, stdout = "", error_string = "" } }),
	steps = {
		{ "options", { scale_height = 333, output_format = "nope" } },
		{ "key", "W" },
		{ "key", "o" },
		{ "key", "LEFT" },
		{ "key", "DOWN" },
		{ "key", "RIGHT" },
		{ "key", "ESC" },
		{ "dump_options" },
	},
})

add({
	name = "ui_crop_page",
	world = world(),
	steps = {
		{ "key", "W" },
		{ "key", "c" },
		{ "bindings" },
		{ "mouse", 100, 50 },
		{ "key", "1" },
		{ "mouse", 1279, 719 },
		{ "key", "2" },
		{ "mouse", 2000, -5 },
		{ "key", "2" },
		{ "key", "r" },
		{ "mouse", 640, 360 },
		{ "key", "2" },
		{ "key", "ENTER" },
		{ "state" },
		{ "key", "c" },
		{ "key", "ESC" },
		{ "state" },
	},
})

add({
	name = "ui_crop_page_letterboxed_rotated",
	world = world({
		osd_w = 1280,
		osd_h = 1024,
		props = { ["video-out-params"] = { w = 1920, h = 800, dw = 1920, dh = 800 }, ["video-rotate"] = 90 },
	}),
	steps = {
		{ "key", "W" },
		{ "key", "c" },
		{ "mouse", 300, 10 },
		{ "key", "1" },
		{ "mouse", 900, 1000 },
		{ "key", "2" },
		{ "key", "ENTER" },
		{ "state" },
	},
})

add({
	name = "ui_preview_page",
	world = world({ props = { vf = { { name = "hflip" } } } }),
	steps = {
		{ "range", 2, 4, { x = 0, y = 10, w = 100, h = 50 } },
		{ "key", "W" },
		{ "key", "p" },
		{ "bindings" },
		{ "key", "ESC" },
	},
})

-- Uploads -----------------------------------------------------------------

add({
	name = "upload_catbox_success",
	world = world({ file_size = 3456789 }),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false, catbox_userhash = "abc123" }) },
		{ "range", 0, 2 },
		{ "key", "W" },
		{ "key", "u" },
		{ "bindings" },
		{ "file", "/tmp/lua_tmp2", "##          12.0%\r#####        45.5%" },
		{ "timers" },
		{ "timers" },
		{ "async" },
		{ "key", "c" },
		{ "key", "o" },
		{ "key", "ESC" },
	},
})

add({
	name = "upload_litterbox_failure_retry_options",
	world = world({
		props = {
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
			merge(SYNC, {
				output_format = "avc",
				twopass = false,
				upload_host = "litterbox",
				litterbox_time = "72h",
				catbox_userhash = "ignored",
				upload_curl_path = "/opt/curl",
			}),
		},
		{ "range", 0, 2 },
		{ "upload" },
		{ "async" },
		{ "key", "c" },
		{ "key", "r" },
		{ "async" },
		{ "key", "o" },
	},
})

add({
	name = "upload_cancel",
	world = world(),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false, open_after_upload = true }) },
		{ "range", 0, 2 },
		{ "upload" },
		{ "key", "ESC" },
		{ "async" },
		{ "timers" },
	},
})

add({
	name = "upload_done_open_and_clipboard_fallback",
	world = world({ clipboard_property = false }),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false, open_after_upload = true }) },
		{ "range", 0, 2 },
		{ "upload" },
		{ "async" },
		{ "key", "c" },
	},
})

add({
	name = "upload_windows_clipboard_fallback",
	world = world({
		platform = "windows",
		clipboard_property = false,
		props = {
			path = "C:\\Videos\\clip.mkv",
			filename = "clip.mkv",
			["filename/no-ext"] = "clip",
			["stream-open-filename"] = "C:\\Videos\\clip.mkv",
		},
		files = { ["C:\\Videos\\clip.mkv"] = "source" },
		env = { USERPROFILE = "C:\\Users\\tester" },
	}),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false, open_after_upload = true }) },
		{ "range", 0, 2 },
		{ "upload" },
		{ "async" },
	},
})

add({
	name = "upload_curl_missing",
	world = world({ curl = { status = -3, stdout = "", error_string = "init" } }),
	steps = { { "range", 0, 2 }, { "upload" } },
})

add({
	name = "upload_encode_fails",
	world = world({ encode_status = 1 }),
	steps = {
		{ "options", merge(SYNC, { output_format = "avc", twopass = false }) },
		{ "range", 0, 2 },
		{ "upload" },
	},
})

return scenarios
