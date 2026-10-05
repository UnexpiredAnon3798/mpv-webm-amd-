-- Output filename templating (the output_template option).

local time = require("core.time")

local M = {}

---Expands ${prop}, ${=prop}, ${prop:fallback}, ${?prop:text}, ${!prop:text} and
---the ==value comparisons, the way mpv's property expansion does. The top-level
---call in a filename uses "%" as the magic character; nested fallbacks use "$".
---@param host webm.Host
---@param text string
---@param magic? string
---@return string
function M.expand_properties(host, text, magic)
	magic = magic or "$"
	for prefix, raw, prop, colon, fallback, closing in
		text:gmatch("%" .. magic .. "{([?!]?)(=?)([^}:]*)(:?)([^}]*)(}*)}")
	do
		local err
		local prop_value
		local compare_value
		local original_prop = prop
		local get_property = host.get_property_osd
		if raw == "=" then
			get_property = host.get_property
		end
		if prefix ~= "" then
			for actual_prop, compare in prop:gmatch("(.-)==(.*)") do
				prop = actual_prop
				compare_value = compare
			end
		end
		if colon == ":" then
			prop_value, err = get_property(prop, fallback)
		else
			prop_value, err = get_property(prop, "(error)")
		end
		prop_value = tostring(prop_value)
		if prefix == "?" then
			if compare_value == nil then
				prop_value = err == nil and fallback .. closing or ""
			else
				prop_value = prop_value == compare_value and fallback .. closing or ""
			end
			prefix = "%" .. prefix
		elseif prefix == "!" then
			if compare_value == nil then
				prop_value = err ~= nil and fallback .. closing or ""
			else
				prop_value = prop_value ~= compare_value and fallback .. closing or ""
			end
		else
			prop_value = prop_value .. closing
		end
		local escaped_prop = original_prop:gsub("%W", "%%%1")
		if colon == ":" then
			local escaped_fallback = fallback:gsub("%W", "%%%1")
			text = text:gsub(
				"%" .. magic .. "{" .. prefix .. raw .. escaped_prop .. ":" .. escaped_fallback .. closing .. "}",
				M.expand_properties(host, prop_value)
			)
		else
			text = text:gsub("%" .. magic .. "{" .. prefix .. raw .. escaped_prop .. closing .. "}", prop_value)
		end
	end
	return text
end

-- Sequence numbering for output_template: %n and %0Nn (e.g. %04n).
-- %n numbers 1, 2, 3, ...; %04n zero-pads to the requested width.
-- When the template holds a counter, format selects the first filename
-- (starting at 1) that is not already taken in the resolved output
-- directory. There is no persistent counter: deleting files frees their
-- numbers again, and two encodes racing each other (e.g. concurrent mpv
-- processes) may still pick the same name. Templates without a counter keep
-- the previous behavior.
local SEQUENCE_ESCAPE_PLACEHOLDER = string.char(31) .. "MPVWEBMESC" .. string.char(31)
local SEQUENCE_PLACEHOLDER_PREFIX = string.char(31) .. "MPVWEBMSEQ"

local function format_sequence_number(n, width)
	if width and width > 0 then
		return string.format("%0" .. tostring(width) .. "d", n)
	end
	return tostring(n)
end

---Builds the output filename (without directory) from options.output_template.
---@param host webm.Host
---@param options webm.Options
---@param start_time number
---@param end_time number
---@param format webm.Format
---@param out_dir? string directory used to find a free sequence number
---@return string
function M.format(host, options, start_time, end_time, format, out_dir)
	local has_audio_codec = format.audio_codec ~= ""
	local replace_first = {
		["%%mp"] = "%%mH.%%mM.%%mS",
		["%%mP"] = "%%mH.%%mM.%%mS.%%mT",
		["%%p"] = "%%wH.%%wM.%%wS",
		["%%P"] = "%%wH.%%wM.%%wS.%%wT",
	}
	local replace_table = {
		["%%wH"] = string.format("%02d", math.floor(start_time / (60 * 60))),
		["%%wh"] = string.format("%d", math.floor(start_time / (60 * 60))),
		["%%wM"] = string.format("%02d", math.floor(start_time / 60 % 60)),
		["%%wm"] = string.format("%d", math.floor(start_time / 60)),
		["%%wS"] = string.format("%02d", math.floor(start_time % 60)),
		["%%ws"] = string.format("%d", math.floor(start_time)),
		["%%wf"] = string.format("%s", start_time),
		["%%wT"] = string.sub(string.format("%.3f", start_time % 1), 3),
		["%%mH"] = string.format("%02d", math.floor(end_time / (60 * 60))),
		["%%mh"] = string.format("%d", math.floor(end_time / (60 * 60))),
		["%%mM"] = string.format("%02d", math.floor(end_time / 60 % 60)),
		["%%mm"] = string.format("%d", math.floor(end_time / 60)),
		["%%mS"] = string.format("%02d", math.floor(end_time % 60)),
		["%%ms"] = string.format("%d", math.floor(end_time)),
		["%%mf"] = string.format("%s", end_time),
		["%%mT"] = string.sub(string.format("%.3f", end_time % 1), 3),
		["%%s"] = time.to_path_element(start_time),
		["%%S"] = time.to_path_element(start_time, true),
		["%%e"] = time.to_path_element(end_time),
		["%%E"] = time.to_path_element(end_time, true),
		["%%M"] = (host.get_property_native("aid") and not host.get_property_native("mute") and has_audio_codec)
				and "-audio"
			or "",
		["%%R"] = (options.scale_height ~= -1) and "-" .. tostring(options.scale_height) .. "p"
			or "-" .. tostring(host.get_property_native("height")) .. "p",
		["%%mb"] = options.target_filesize / 1000,
		["%%t%%"] = "%%",
	}
	local media_table = {
		["%%f"] = host.get_property("filename"),
		["%%F"] = host.get_property("filename/no-ext"),
		["%%T"] = host.get_property("media-title"),
	}
	local filename = options.output_template

	-- Protect escaped percents (%%) so %%n stays a literal %n.
	filename = filename:gsub("%%%%", SEQUENCE_ESCAPE_PLACEHOLDER)

	-- Extract sequence counters before any other expansion, so counter-like
	-- text coming from media properties (%f/%F/%T/...) is never expanded.
	local seq_widths = {}
	filename = filename:gsub("%%(0?%d*)n", function(digits)
		seq_widths[#seq_widths + 1] = tonumber(digits) or 0
		return SEQUENCE_PLACEHOLDER_PREFIX .. tostring(#seq_widths) .. string.char(31)
	end)
	local has_seq = #seq_widths > 0

	-- Restore escaped percents right away; only real counters use placeholders.
	filename = filename:gsub(SEQUENCE_ESCAPE_PLACEHOLDER, function()
		return "%"
	end)

	for pattern, value in pairs(replace_first) do
		filename = filename:gsub(pattern, value)
	end
	for pattern, value in pairs(replace_table) do
		filename = filename:gsub(pattern, value)
	end
	-- Media-derived values use function replacements so % inside real
	-- filenames is inserted literally instead of acting as gsub syntax.
	for pattern, value in pairs(media_table) do
		if value ~= nil then
			filename = filename:gsub(pattern, function()
				return value
			end)
		end
	end

	if host.get_property_bool("demuxer-via-network", false) then
		filename = filename:gsub("%%X{([^}]*)}", "%1")
		filename = filename:gsub("%%x", "")
	else
		local x = string.gsub(
			host.get_property("stream-open-filename", "") --[[@as string]],
			string.gsub(host.get_property("filename", "") --[[@as string]], "%W", "%%%1") .. "$",
			""
		)
		filename = filename:gsub("%%X{[^}]*}", function()
			return x
		end)
		filename = filename:gsub("%%x", function()
			return x
		end)
	end

	filename = M.expand_properties(host, filename, "%")

	for specifier in filename:gmatch("%%t([aAbBcCdDeFgGhHIjmMnprRStTuUVwWxXyYzZ])") do
		filename = filename:gsub("%%t" .. specifier, host.date("%" .. specifier))
	end

	-- Remove invalid chars
	-- Windows: < > : " / \ | ? *
	-- Linux: /
	filename = filename:gsub('[<>:"/\\|?*]', "")

	local extension = tostring(format.output_extension)
	if not has_seq then
		return tostring(filename) .. "." .. extension
	end

	-- A conditional block (%X{...}, property fallback) may have swallowed
	-- every counter; then there is nothing to number and no search to run.
	if filename:find(SEQUENCE_PLACEHOLDER_PREFIX, 1, true) == nil then
		return tostring(filename) .. "." .. extension
	end

	local function apply_sequence(n)
		local name = filename
		for i, width in ipairs(seq_widths) do
			local placeholder = SEQUENCE_PLACEHOLDER_PREFIX .. tostring(i) .. string.char(31)
			name = name:gsub(placeholder, format_sequence_number(n, width))
		end
		return name
	end

	if out_dir == nil then
		return tostring(apply_sequence(1)) .. "." .. extension
	end

	-- An empty directory means the current one (bare video filename).
	local check_dir = out_dir == "" and "." or out_dir
	local n = 1
	while true do
		local candidate = tostring(apply_sequence(n)) .. "." .. extension
		if not host.file_exists(host.join_path(check_dir, candidate)) then
			return candidate
		end
		n = n + 1
	end
end

return M
