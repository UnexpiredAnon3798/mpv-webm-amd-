-- Encode progress, read from the child mpv's terminal output.

local M = {}

-- Makes the child mpv print its position on every status update.
M.STATUS_FLAG = "--term-status-msg=Encode time-pos: ${=time-pos}\\n"

---Whether to show the progress page. "auto" means everywhere but Windows,
---where the popen used for progress opens a console window.
---@param options webm.Options
---@param is_windows boolean
---@return any
function M.should_display(options, is_windows)
	if options.display_progress == "auto" then
		return not is_windows
	end
	return options.display_progress
end

---@class webm.ProgressTracker
---@field start_time number
---@field duration number
---@field current_time number
---@field finished boolean
---@field finished_reason? string
local Tracker = {}
Tracker.__index = Tracker

---@param start_time number encoder start time
---@param end_time number encoder end time
---@return webm.ProgressTracker
function M.new(start_time, end_time)
	return setmetatable({
		start_time = start_time,
		duration = end_time - start_time,
		current_time = start_time,
		finished = false,
	}, Tracker)
end

---Reads one line of the child's output.
---@param line string
function Tracker:parse_line(line)
	local match_time = string.match(line, "Encode time[-]pos: ([0-9.]+)")
	local match_exit = string.match(line, "Exiting... [(]([%a ]+)[)]")
	-- Sometimes we get timestamps older than before, so only move forward.
	if match_time ~= nil and tonumber(match_time) > self.current_time then
		self.current_time = tonumber(match_time) --[[@as number]]
	end
	if match_exit ~= nil then
		self.finished = true
		self.finished_reason = match_exit
	end
end

---@return string e.g. "45%"
function Tracker:percent_text()
	return string.format("%d%%", 100 * ((self.current_time - self.start_time) / self.duration))
end

---The child only reports "End of file" when it encoded the whole range.
---@return boolean
function Tracker:succeeded()
	return self.finished_reason == "End of file"
end

return M
