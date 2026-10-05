-- Time formatting for the OSD, mpv's --start/--end options and filenames.

local M = {}

---Formats seconds as [H:]MM:SS[.mmm]. Negative values mean "not set".
---Milliseconds are truncated, not rounded.
---@param seconds number
---@param no_ms? boolean leave out the milliseconds
---@param full? boolean always include the hours
---@return string
function M.to_time_string(seconds, no_ms, full)
	if seconds < 0 then
		return "unknown"
	end
	local ret = ""
	if not no_ms then
		ret = string.format(".%03d", seconds * 1000 % 1000)
	end
	ret = string.format("%02d:%02d%s", math.floor(seconds / 60) % 60, math.floor(seconds) % 60, ret)
	if full or seconds > 3600 then
		ret = string.format("%d:%s", math.floor(seconds / 3600), ret)
	end
	return ret
end

---Like to_time_string, with dots instead of colons so it works in filenames.
---@param seconds number
---@param no_ms? boolean
---@param full? boolean
---@return string
function M.to_path_element(seconds, no_ms, full)
	return (M.to_time_string(seconds, no_ms, full):gsub(":", "."))
end

return M
