-- Encode progress. The encoder mpv loads a small script that writes its
-- position to a file every half second, and the player reads that file.

local M = {}

-- The script the encoder runs. It reads the file path from its script-opts.
M.ENCODER_SCRIPT = [[
local path = mp.get_opt("webm-progress-file")
mp.add_periodic_timer(0.5, function()
	local position = mp.get_property_number("time-pos")
	local file = position and io.open(path, "w")
	if file then
		file:write(position)
		file:close()
	end
end)
]]

---Whether to show progress. "auto" shows it everywhere.
---@param options webm.Options
---@return any
function M.should_display(options)
	if options.display_progress == "auto" then
		return true
	end
	return options.display_progress
end

---Arguments that make the encoder report its position.
---@param script_path string where ENCODER_SCRIPT was written
---@param position_path string the file the encoder writes to
---@return string[]
function M.encoder_arguments(script_path, position_path)
	return { "--script=" .. script_path, "--script-opts-append=webm-progress-file=" .. position_path }
end

---How far the encode is, from 0 to 100.
---@param position_text? string what the encoder wrote, the position in seconds
---@param start_time number encoder start time
---@param end_time number encoder end time
---@return integer
function M.percent(position_text, start_time, end_time)
	local position = tonumber(position_text or "")
	if not position or end_time <= start_time then
		return 0
	end
	local percent = math.floor(100 * (position - start_time) / (end_time - start_time))
	return math.max(0, math.min(100, percent))
end

return M
