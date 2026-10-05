-- Video filters added to the encode command (without the --vf-add= prefix).

local M = {}

---@param options webm.Options
---@return string[]
function M.scale(options)
	local filters = {}
	if options.force_square_pixels then
		filters[#filters + 1] = "lavfi-scale=iw*sar:ih"
	end
	if options.scale_height > 0 then
		filters[#filters + 1] = "lavfi-scale=-2:" .. tostring(options.scale_height)
	end
	return filters
end

---@param options webm.Options
---@return string[]
function M.fps(options)
	if options.fps > 0 then
		return { "fps=" .. tostring(options.fps) }
	end
	return {}
end

---Maps mpv's brightness, contrast and saturation properties to an eq filter.
---@param brightness number
---@param contrast number
---@param saturation number
---@return string[]
function M.color_adjustments(brightness, contrast, saturation)
	if brightness == 0 and contrast == 0 and saturation == 0 then
		-- Default values, no need to change anything.
		return {}
	end

	-- We have to map mpv's contrast/brightness/saturation values to the ones used by the eq filter.
	-- From what I've gathered from looking at ffmpeg's source, the contrast value is used to multiply the luma
	-- channel, while the saturation one multiplies both chroma channels. On mpv, it seems that contrast multiplies
	-- both luma and chroma (?); but I don't really know a lot about how things work internally. This might cause some
	-- weird interactions, but for now I guess it's fine.
	local eq_saturation = (saturation + 100) / 100.0
	local eq_contrast = (contrast + 100) / 100.0

	-- For brightness, this should work I guess... For some reason, contrast is factored into how the luma offset is
	-- calculated on the eq filter, so we need to offset it in a way that the effective offset added is the same.
	-- Also, on mpv's side, we add it after the conversion to RGB; I'm not sure how that affects things but hopefully
	-- it ends in the same result.
	local eq_brightness = (brightness / 50.0 + eq_contrast - 1) / 2.0

	return {
		"lavfi-eq=contrast="
			.. tostring(eq_contrast)
			.. ":saturation="
			.. tostring(eq_saturation)
			.. ":brightness="
			.. tostring(eq_brightness),
	}
end

-- Wrap a filter parameter in mpv's raw string syntax so property expansion
-- can't interpret anything inside it.
local function quote_param(value)
	return "%" .. tostring(string.len(value)) .. "%" .. tostring(value)
end

---mpv exposes libavfilter bridge filters as "lavfi-<name>" and reports their
---arguments as positional placeholders (@0, @1, ...) or as regular option
---names. The placeholder form is only understood by mpv's own option parser,
---so turn it into a libavfilter-style argument list. Values are left unquoted
---because the GIF format embeds these filters in a raw graph, where mpv's
---property expansion (and with it the %N% raw string syntax) does not run.
---@param filter table an entry of the vf property
---@return string
function M.serialize_lavfi(filter)
	local name = filter["name"]
	local params = filter["params"] or {}

	if name == "lavfi" then
		local graph = params["graph"]
		return graph and tostring(name) .. "=[" .. tostring(graph) .. "]" or name
	end

	local positional = {}
	local named = {}
	for key, value in pairs(params) do
		local index = key:match("^@(%d+)$")
		if index then
			positional[tonumber(index) + 1] = value
		else
			named[key] = value
		end
	end

	local args = {}
	if #positional > 0 then
		for i = 1, #positional do
			args[#args + 1] = positional[i]
		end
	else
		local keys = {}
		for key in pairs(named) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			args[#args + 1] = tostring(key) .. "=" .. tostring(named[key])
		end
	end

	return #args > 0 and tostring(name) .. "=" .. table.concat(args, ":") or name
end

---The filters currently applied to playback (the vf property), as filter strings.
---@param vf table[] value of the vf property
---@return string[]
function M.current(vf)
	local filters = {}
	for _, filter in ipairs(vf) do
		-- This might seem like a redundant check (if not filter["enabled"] would achieve the same result),
		-- but the enabled field isn't guaranteed to exist... and if it's nil, "not filter['enabled']"
		-- would achieve a different outcome.
		if filter["enabled"] ~= false then
			local str = filter["name"]
			local params = filter["params"] or {}
			if str == "lavfi" or str:match("^lavfi%-") then
				str = M.serialize_lavfi(filter)
			else
				for k, v in pairs(params) do
					str = str .. ":" .. tostring(k) .. "=" .. quote_param(v)
				end
			end
			filters[#filters + 1] = str
		end
	end
	return filters
end

return M
