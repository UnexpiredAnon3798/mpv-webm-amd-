-- Running processes and talking to the desktop: subprocesses, the clipboard,
-- the browser, and the curl check for uploads.

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")

local host = require("mpv.host")
local options = require("mpv.options")

local M = {}

M.is_windows = host.is_windows
M.is_macos = host.file_exists("/Applications") and not M.is_windows

---Runs a process and waits for it. Returns true when it exited with status 0.
---@param params mp.utils.SubprocessArgs
---@return boolean
function M.run(params)
	local res = utils.subprocess(params)
	msg.verbose("Command stdout: ")
	msg.verbose(res.stdout)
	if res.status ~= 0 then
		msg.verbose("Command failed! Reason: ", res.error, " Killed by us? ", res.killed_by_us and "yes" or "no")
		return false
	end
	return true
end

---@param path string
---@return string?
function M.read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

-- curl is the only external tool uploads need. Probe it once and cache.
local upload_available = nil

---@return boolean
function M.is_upload_available()
	if upload_available == nil then
		local res = utils.subprocess({ args = { options.upload_curl_path, "--version" }, playback_only = false })
		upload_available = res ~= nil and res.status == 0
	end
	return upload_available
end

---Prefer mpv's own clipboard property; fall back to the platform tool when the
---running mpv is too old to accept writes to clipboard/text. Those tools keep
---running to own the selection, so they are launched without waiting.
---@param text string
---@return boolean
function M.copy_to_clipboard(text)
	local ok, written = pcall(function()
		return mp.set_property("clipboard/text", text)
	end)
	if ok and written then
		return true
	end

	local candidates
	if M.is_windows then
		candidates = { { "clip" } }
	elseif M.is_macos then
		candidates = { { "pbcopy" } }
	else
		candidates = { { "wl-copy" }, { "xclip", "-selection", "clipboard" }, { "xsel", "--clipboard", "--input" } }
	end

	for _, args in ipairs(candidates) do
		local handle = mp.command_native_async({
			name = "subprocess",
			args = args,
			stdin_data = text,
			playback_only = false,
		}, function() end)
		if handle then
			return true
		end
	end
	return false
end

---@param url string
function M.open_url(url)
	if M.is_windows then
		utils.subprocess_detached({ args = { "cmd", "/c", "start", "", url } })
	elseif M.is_macos then
		utils.subprocess_detached({ args = { "open", url } })
	else
		utils.subprocess_detached({ args = { "xdg-open", url } })
	end
end

return M
