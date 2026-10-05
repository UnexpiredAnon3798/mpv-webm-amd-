-- Script-messages the script sends about what it is doing. The integration
-- tests wait for these, and other scripts can listen for them too.

local mp = require("mp")

local M = {}

---Sends "webm-<name>" with the given arguments.
---@param name string
---@param ... string
function M.emit(name, ...)
	mp.commandv("script-message", "webm-" .. name, ...)
end

return M
