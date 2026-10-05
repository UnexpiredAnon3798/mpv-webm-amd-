-- Works out what to encode from: the playing file, or a dump of the stream
-- cache for HLS streams.

local paths = require("core.paths")
local time = require("core.time")

local M = {}

---@class webm.EncodeSource
---@field path string
---@field is_stream boolean the path is not a local file
---@field is_temporary boolean delete path after encoding
---@field start_time number selection start within path
---@field end_time number
---@field dump_cache? any[] mpv command to run before encoding
---@field warning? string to log before running dump_cache

---Returns nil when nothing is playing.
---@param host webm.Host
---@param start_time number
---@param end_time number
---@return webm.EncodeSource?
function M.resolve(host, start_time, end_time)
	local path = host.get_property("path")
	if not path then
		return nil
	end

	local source = {
		path = path,
		is_stream = not host.file_exists(path),
		is_temporary = false,
		start_time = start_time,
		end_time = end_time,
	}

	if source.is_stream and host.get_property("file-format") == "hls" then
		-- Attempt to dump the stream cache into a temporary file
		local home, warning = paths.expand_home(host, "~")
		source.warning = warning
		source.path = host.join_path(home, "cache_dump.ts")
		source.dump_cache = {
			"dump_cache",
			time.to_time_string(start_time, false, true),
			time.to_time_string(end_time + 5, false, true),
			source.path,
		}
		source.end_time = end_time - start_time
		source.start_time = 0
		source.is_temporary = true
	end

	return source
end

return M
