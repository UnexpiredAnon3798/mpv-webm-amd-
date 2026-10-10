-- The encoder startup check. The same executable is probed before any launch
-- mode runs (including the progress shell and detached mode, which otherwise
-- hide spawn failures).

local M = {}

M.ENCODER_ARGS = { "mpv", "--no-config", "--version" }

---Explains a failed check, or returns nil when the encoder started fine.
---@param result mp.utils.SubprocessResult
---@return string?
function M.encoder_problem(result)
	if result.status == 0 then
		return nil
	end
	if result.status and result.status > 0 then
		return "The mpv encoder failed its startup check. Run mpv --version and check the logs for details."
	end
	return "Cannot start the mpv encoder. Add the folder containing mpv to PATH, then restart the player. "
		.. "See README: Encoder executable."
end

-- How many lines of the encoder's output to keep for the log.
local MAX_DETAIL_LINES = 6
-- Words that mark a line of encoder output as an error worth showing.
local ERROR_WORDS = { "error", "fail", "unable", "cannot", "can't", "could not", "not supported", "invalid", "no such" }

local function looks_like_error(line)
	-- mpv's closing "Exiting... (Interrupted by error)" says nothing about why.
	if line:find("^Exiting%.%.%.") then
		return false
	end
	local lower = line:lower()
	for _, word in ipairs(ERROR_WORDS) do
		if lower:find(word, 1, true) then
			return true
		end
	end
	return false
end

---The lines of a failed encoder's output that explain the failure: the first
---ones that mention an error, or else the last few lines. The first error is
---the cause; the ones after it usually follow from it.
---@param result? {stdout?: string, stderr?: string, error_string?: string}
---@return string[]
function M.failure_details(result)
	local lines = {}
	for _, output in ipairs({ result and result.stdout or "", result and result.stderr or "" }) do
		for line in output:gmatch("[^\r\n]+") do
			line = line:match("^%s*(.-)%s*$")
			if line ~= "" then
				lines[#lines + 1] = line
			end
		end
	end

	local errors = {}
	for _, line in ipairs(lines) do
		if looks_like_error(line) then
			errors[#errors + 1] = line
		end
	end
	local details = {}
	if #errors > 0 then
		for index = 1, math.min(#errors, MAX_DETAIL_LINES) do
			details[#details + 1] = errors[index]
		end
	else
		for index = math.max(1, #lines - MAX_DETAIL_LINES + 1), #lines do
			details[#details + 1] = lines[index]
		end
	end

	if #details == 0 and result and result.error_string and result.error_string ~= "" then
		details[1] = "the encoder process ended with: " .. result.error_string
	end
	return details
end

return M
