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

return M
