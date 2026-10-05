-- Shows encode progress. Not really a page the user navigates, but it reuses
-- the page plumbing: it runs the encode through io.popen so the child's
-- output can be read while it encodes.

local assdraw = require("mp.assdraw")
local mp = require("mp")
local msg = require("mp.msg")

local osd = require("ui.osd")
local Page = require("ui.page")
local progress = require("encode.progress")
local shell = require("encode.shell")
local system = require("mpv.system")

---@class webm.EncodeProgressPage: webm.Page
---@field tracker webm.ProgressTracker
local EncodeProgressPage = Page.extend({})

---@param start_time number encoder start time
---@param end_time number encoder end time
---@return webm.EncodeProgressPage
function EncodeProgressPage.new(start_time, end_time)
	local self = setmetatable({}, EncodeProgressPage)
	self.tracker = progress.new(start_time, end_time)
	return self
end

function EncodeProgressPage:draw()
	local window_w, window_h = mp.get_osd_size()
	local ass = assdraw.ass_new()
	ass:new_event()
	osd.setup_text(ass)
	ass:append("Encoding (" .. osd.bold(self.tracker:percent_text()) .. ")\\N")
	mp.set_osd_ass(window_w, window_h, ass.text)
end

---Runs the encode and returns whether it finished the whole range.
---@param command string[]
---@return boolean
function EncodeProgressPage:run(command)
	local command_with_status = {}
	for i, arg in ipairs(command) do
		command_with_status[i] = arg
	end
	command_with_status[#command_with_status + 1] = progress.STATUS_FLAG

	self:show()
	local command_line = shell.popen_command(command_with_status, system.is_windows)
	msg.verbose("run_subprocess_popen: running " .. command_line)
	local process = assert(io.popen(command_line))
	for line in process:lines() do
		msg.verbose(string.format("%q", line))
		self.tracker:parse_line(line)
		self:draw()
	end
	process:close()
	self:hide()

	return self.tracker:succeeded()
end

return EncodeProgressPage
