---@meta mp.utils

---@class mp.utils
local utils = {}

---@class mp.utils.FileInfo
---@field mode integer
---@field size integer
---@field atime integer
---@field mtime integer
---@field ctime integer
---@field is_file boolean
---@field is_dir boolean

---@param path string
---@return mp.utils.FileInfo|nil info
---@return string? err
function utils.file_info(path) end

---@param path string
---@return string dir
---@return string name
function utils.split_path(path) end

---Joins two paths. Returns `p2` unchanged when it is absolute.
---@param p1 string
---@param p2 string
---@return string
function utils.join_path(p1, p2) end

---@class mp.utils.SubprocessArgs
---@field args string[]
---@field cancellable? boolean renamed to playback_only by the wrapper
---@field playback_only? boolean
---@field max_size? integer renamed to capture_size by the wrapper
---@field capture_size? integer
---@field capture_stdout? boolean
---@field capture_stderr? boolean
---@field stdin_data? string
---@field env? string[]
---@field detach? boolean

---@class mp.utils.SubprocessResult
---@field status integer exit code, negative if the process could not run
---@field stdout? string
---@field stderr? string
---@field error_string string "" on success, "killed" or "init" otherwise
---@field error? string copy of error_string when it is not empty
---@field killed_by_us boolean

---Legacy wrapper around the `subprocess` command. Waits for the process to exit.
---@param t mp.utils.SubprocessArgs
---@return mp.utils.SubprocessResult
function utils.subprocess(t) end

---Start a process and let it run on its own.
---@param t { args: string[] }
function utils.subprocess_detached(t) end

---@param str string
---@param trail? boolean
---@return any value
---@return string? err
---@return string? trail
function utils.parse_json(str, trail) end

---@param v any
---@return string|nil json
---@return string? err
function utils.format_json(v) end

---@return string|nil cwd
---@return string? err
function utils.getcwd() end

---@return integer
function utils.getpid() end

return utils
