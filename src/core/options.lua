-- Script options: names, defaults and the comments written to webm.conf.
--
-- The order here is the order of webm.conf. tools/build.lua generates that
-- file from these definitions.

---@class webm.Options
---@field keybind string
---@field output_directory string
---@field run_detached boolean
---@field output_template string
---@field scale_height number
---@field fps number
---@field target_filesize number
---@field strict_filesize_constraint boolean
---@field strict_bitrate_multiplier number
---@field strict_audio_bitrate number
---@field output_format string
---@field twopass boolean
---@field apply_current_filters boolean
---@field write_filename_on_metadata boolean
---@field threads number
---@field hwdec string
---@field additional_flags string
---@field crf number
---@field non_strict_additional_flags string
---@field display_progress string|boolean "auto", or a boolean set through the testing script-message
---@field font_size number
---@field margin number
---@field message_duration number
---@field gif_dither number
---@field force_square_pixels boolean
---@field completion_command string
---@field upload_host string
---@field litterbox_time string
---@field catbox_userhash string
---@field upload_curl_path string
---@field open_after_upload boolean

---@class webm.OptionDefinition
---@field name string
---@field default string|number|boolean
---@field comment? string[] lines written above the option in webm.conf

local M = {}

---@type webm.OptionDefinition[]
M.definitions = {
	{
		name = "keybind",
		default = "W",
		comment = {
			"Defaults to shift+w",
		},
	},
	{
		name = "output_directory",
		default = "",
		comment = {
			"If empty, saves on the same directory of the playing video.",
			'A starting "~" will be replaced by the home dir.',
			"This field is delimited by double-square-brackets - [[ and ]] - instead of",
			"quotes, because Windows users might run into a issue when using",
			"backslashes as a path separator. Examples of valid inputs for this field",
			"would be: [[]] (the default, empty value), [[C:\\Users\\John]] (on Windows),",
			"and [[/home/john]] (on Unix-like systems eg. Linux).",
			"The [[]] delimiter is not needed when using from a configuration file",
			"in the script-opts folder.",
		},
	},
	{
		name = "run_detached",
		default = false,
	},
	{
		name = "output_template",
		default = "%F-[%s-%e]%M",
		comment = {
			"Template string for the output file",
			"%f - Filename, with extension",
			"%F - Filename, without extension",
			"%T - Media title, if it exists, or filename, with extension (useful for some streams, such as YouTube).",
			"%s, %e - Start and end time, with milliseconds",
			"%S, %E - Start and end time, without milliseconds",
			'%M - "-audio", if audio is enabled, empty otherwise',
			"%R - \"-(height)p\", where height is the video's height, or scale_height, if it's enabled.",
			"%n - Sequence number (1, 2, 3, ...). The first filename (starting",
			"at 1) not already taken in the output directory is selected when",
			"formatting, so gaps left by deleted clips are filled. There is no",
			"persistent counter to reset; concurrent encodes may still race.",
			"Use %04n (or %02n, etc.) to zero-pad (clip_%04n -> clip_0001, ...).",
			"Templates without a counter keep the previous behavior (may overwrite).",
			"More specifiers are supported, see https://mpv.io/manual/master/#options-screenshot-template",
			"Property expansion is supported (with %{} at top level, ${} when nested), see https://mpv.io/manual/master/#property-expansion",
		},
	},
	{
		name = "scale_height",
		default = -1,
		comment = {
			"Scale video to a certain height, keeping the aspect ratio. -1 disables it.",
		},
	},
	{
		name = "fps",
		default = -1,
		comment = {
			"Change the FPS of the output video, dropping or duplicating frames as needed.",
			"-1 means the FPS will be unchanged from the source.",
		},
	},
	{
		name = "target_filesize",
		default = 2500,
		comment = {
			"Target filesize, in kB. This will be used to calculate the bitrate",
			"used on the encode. If this is set to <= 0, the video bitrate will be set",
			"to 0, which might enable constant quality modes, depending on the",
			"video codec that's used (VP8 and VP9, for example).",
		},
	},
	{
		name = "strict_filesize_constraint",
		default = false,
		comment = {
			"If true, will use stricter flags to ensure the resulting file doesn't",
			"overshoot the target filesize. Not recommended, as constrained quality",
			"mode should work well, unless you're really having trouble hitting",
			"the target size.",
		},
	},
	{
		name = "strict_bitrate_multiplier",
		default = 0.95,
	},
	{
		name = "strict_audio_bitrate",
		default = 64,
		comment = {
			"In kilobits.",
		},
	},
	{
		name = "output_format",
		default = "webm-vp8",
		comment = {
			"Sets the output format, from a few predefined ones.",
			"Currently we have:",
			"av1",
			"hevc",
			"webm-vp9 (libvpx-vp9/libopus)",
			"webp",
			"avc (h264/AAC)",
			"avc-nvenc (h264-NVENC/AAC)",
			"avc-vaapi (h264-VAAPI/AAC, AMD/Intel GPU Linux)",
			"hevc-vaapi (hevc-VAAPI/AAC, AMD/Intel GPU Linux)",
			"avc-amf (h264-AMF/AAC, AMD GPU Windows)",
			"webm-vp8 (libvpx/libvorbis)",
			"gif",
			"mp3 (libmp3lame)",
			"and raw (rawvideo/pcm_s16le).",
		},
	},
	{
		name = "twopass",
		default = true,
	},
	{
		name = "apply_current_filters",
		default = true,
		comment = {
			"If set, applies the video filters currently used on the playback to the encode.",
		},
	},
	{
		name = "write_filename_on_metadata",
		default = false,
		comment = {
			'If set, writes the video\'s filename to the "Title" field on the metadata.',
		},
	},
	{
		name = "threads",
		default = 4,
		comment = {
			"Set the number of encoding threads, for codecs libvpx and libvpx-vp9",
		},
	},
	{
		name = "hwdec",
		default = "auto",
		comment = {
			'Hardware decoding for the encoder. "auto" decodes on the GPU (--hwdec=auto-copy)',
			"when the output format encodes on a GPU, and leaves mpv's own setting alone for",
			"formats that encode on the CPU. Any other value, such as no or auto-copy, is",
			"used for every format.",
		},
	},
	{
		name = "additional_flags",
		default = "",
	},
	{
		name = "crf",
		default = 10,
		comment = {
			"Constant Rate Factor (CRF). The value meaning and limits may change,",
			"from codec to codec. Set to -1 to disable.",
		},
	},
	{
		name = "non_strict_additional_flags",
		default = "",
		comment = {
			"Useful for flags that may impact output filesize, such as qmin, qmax etc",
			"Won't be applied when strict_filesize_constraint is on.",
		},
	},
	{
		name = "display_progress",
		default = "auto",
		comment = {
			"Display the encode progress, in %, in the top left corner. The final pass",
			'shows no progress when it runs detached. "auto" displays it on every platform.',
		},
	},
	{
		name = "font_size",
		default = 28,
		comment = {
			"The font size used in the menu. Isn't used for the notifications (started encode, finished encode etc)",
		},
	},
	{
		name = "margin",
		default = 10,
	},
	{
		name = "message_duration",
		default = 5,
	},
	{
		name = "gif_dither",
		default = 2,
		comment = {
			"gif dither mode, 0-5 for bayer w/ bayer_scale 0-5, 6 for paletteuse default (sierra2_4a)",
		},
	},
	{
		name = "force_square_pixels",
		default = false,
		comment = {
			"Force square pixels on output video",
			"Some players like recent Firefox versions display videos with non-square pixels with wrong aspect ratio",
		},
	},
	{
		name = "completion_command",
		default = "",
		comment = {
			"MPV command to run upon successful encoding",
			"%{output} will be replaced with the path to the resulting file.",
		},
	},
	{
		name = "upload_host",
		default = "catbox",
		comment = {
			'Where "encode & upload" (u) sends the clip. Only the Catbox services are',
			'supported: "catbox" (permanent until 2 years of inactivity) or',
			'"litterbox" (temporary, expires after litterbox_time).',
		},
	},
	{
		name = "litterbox_time",
		default = "24h",
		comment = {
			"Expiry for litterbox uploads: 1h, 12h, 24h or 72h.",
		},
	},
	{
		name = "catbox_userhash",
		default = "",
		comment = {
			"Optional Catbox account hash. Account uploads are permanent and can be",
			"managed (deleted) from the Catbox account.",
		},
	},
	{
		name = "upload_curl_path",
		default = "curl",
		comment = {
			"curl executable used for the multipart upload.",
		},
	},
	{
		name = "open_after_upload",
		default = false,
		comment = {
			"Open the uploaded link in the browser as soon as it is ready.",
		},
	},
}

---Returns a new table with every option set to its default.
---@return webm.Options
function M.defaults()
	local options = {}
	for _, definition in ipairs(M.definitions) do
		options[definition.name] = definition.default
	end
	return options
end

return M
