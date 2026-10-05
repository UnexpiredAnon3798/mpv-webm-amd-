-- Quoting a command line for io.popen, used to read encode progress.

local M = {}

---@param args string[]
---@param is_windows boolean
---@return string
function M.escape(args, is_windows)
	local ret = {}
	for _, a in ipairs(args) do
		local s = tostring(a)
		if string.match(s, "[^A-Za-z0-9_/:=-]") then
			-- Single quotes for UNIX, double quotes for Windows.
			if is_windows then
				s = '"' .. string.gsub(s, '"', '"\\""') .. '"'
			else
				s = "'" .. string.gsub(s, "'", "'\\''") .. "'"
			end
		end
		ret[#ret + 1] = s
	end
	local concat = table.concat(ret, " ")
	if is_windows then
		-- cmd strips one pair of quotes around the whole command
		concat = '"' .. concat .. '"'
	end
	return concat
end

---The command to popen. stderr goes to stdout because mpv writes its status
---line there.
---@param args string[]
---@param is_windows boolean
---@return string
function M.popen_command(args, is_windows)
	return M.escape(args, is_windows) .. " 2>&1"
end

return M
