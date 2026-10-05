-- Path helpers that depend on the user's environment.

local M = {}

---Replaces a leading "~" with the home directory. Uses HOME, then USERPROFILE,
---then HOMEDRIVE plus HOMEPATH. If none is set, "~" becomes "" and a warning
---is returned for the caller to log.
---@param host webm.Host
---@param dir string
---@return string dir
---@return string? warning
function M.expand_home(host, dir)
	local warning
	local home_dir = host.getenv("HOME")
	if not home_dir then
		home_dir = host.getenv("USERPROFILE")
	end
	if not home_dir then
		local drive = host.getenv("HOMEDRIVE")
		local path = host.getenv("HOMEPATH")
		if drive and path then
			home_dir = host.join_path(drive, path)
		else
			warning = "Couldn't find home dir."
			home_dir = ""
		end
	end
	return (dir:gsub("^~", home_dir)), warning
end

return M
