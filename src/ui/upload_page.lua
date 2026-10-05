-- Progress, done and failed states for a single upload. The curl process runs
-- asynchronously so ESC can abort it and the progress percentage keeps
-- redrawing.

local assdraw = require("mp.assdraw")
local mp = require("mp")
local utils = require("mp.utils")

local events = require("mpv.events")
local options = require("mpv.options")
local osd = require("ui.osd")
local Page = require("ui.page")
local system = require("mpv.system")
local upload = require("core.upload")

---@alias webm.UploadState "uploading"|"done"|"failed"|"cancelled"|"options"

---@class webm.UploadPage: webm.Page
---@field callback fun(state: webm.UploadState)
---@field path string
---@field filename string
---@field size_text string
---@field response_path string
---@field progress_path string
---@field state webm.UploadState
---@field percent number
---@field finished boolean
---@field cancelled boolean
---@field closing? boolean
---@field host? webm.UploadHost
---@field timer? mp.Timer
---@field handle? table
---@field url? string
---@field error_message? string
local UploadPage = Page.extend({})

---@param callback fun(state: webm.UploadState) called with "done", "failed", "cancelled" or "options"
---@param path string the encoded file
---@return webm.UploadPage
function UploadPage.new(callback, path)
	local self = setmetatable({}, UploadPage)
	self.callback = callback
	self.path = path
	local _, filename = utils.split_path(path)
	self.filename = filename
	local info = utils.file_info(path)
	self.size_text = info and string.format("%.1f MB", info.size / 1000000) or "unknown size"
	self.response_path = os.tmpname()
	self.progress_path = os.tmpname()
	self.state = "uploading"
	self.percent = 0
	self.finished = false
	self.cancelled = false
	self.keybinds = {
		["ESC"] = function()
			self:on_escape()
		end,
		["c"] = function()
			self:copy_again()
		end,
		["o"] = function()
			self:open_something()
		end,
		["r"] = function()
			self:retry()
		end,
	}
	return self
end

function UploadPage:prepare()
	self:start_upload()
end

function UploadPage:dispose()
	self:stop_timer()
	if self.response_path then
		os.remove(self.response_path)
	end
	if self.progress_path then
		os.remove(self.progress_path)
	end
end

function UploadPage:stop_timer()
	if self.timer then
		self.timer:kill()
		self.timer = nil
	end
end

function UploadPage:start_upload()
	self.state = "uploading"
	self.percent = 0
	self.finished = false
	self.cancelled = false
	self.host = upload.host(options.upload_host)

	-- Clear a stale progress meter from a previous attempt.
	local file = io.open(self.progress_path, "w")
	if file then
		file:close()
	end

	local args = upload.curl_args(options, self.path, self.response_path, self.progress_path)
	self.timer = mp.add_periodic_timer(0.2, function()
		self:poll_progress()
	end)
	self.handle = mp.command_native_async({
		name = "subprocess",
		args = args,
		playback_only = false,
		capture_stdout = true,
		capture_stderr = false,
		capture_size = 128,
	}, function(success, result, err)
		self:on_finished(success, result, err)
	end)
end

function UploadPage:poll_progress()
	if self.state ~= "uploading" then
		return
	end
	local content = system.read_file(self.progress_path)
	if not content or content == "" then
		return
	end
	local percent = upload.progress_percent(content)
	if percent and math.floor(percent) ~= self.percent then
		self.percent = math.floor(percent)
		self:draw()
	end
end

function UploadPage:on_finished(success, result, err)
	if self.finished then
		return
	end
	self.finished = true
	self:stop_timer()

	if self.cancelled then
		events.emit("upload-finished", "cancelled")
		self:finish("cancelled")
		return
	end

	local response = (system.read_file(self.response_path) or ""):match("^%s*(.-)%s*$")
	local url, error_message = upload.parse_result(success, result, err, response)
	if url then
		self.url = url
		self.state = "done"
		pcall(function()
			system.copy_to_clipboard(url)
		end)
		if options.open_after_upload then
			pcall(function()
				system.open_url(url)
			end)
		end
	else
		self.state = "failed"
		self.error_message = error_message
	end
	events.emit("upload-finished", self.state)
	self:draw()
end

function UploadPage:on_escape()
	if self.state == "uploading" then
		self.cancelled = true
		self:stop_timer()
		if self.handle then
			mp.abort_async_command(self.handle)
		end
		-- If the abort never reports back, close anyway.
		mp.add_timeout(0.5, function()
			if not self.closing then
				self:finish("cancelled")
			end
		end)
	else
		self:finish(self.state)
	end
end

-- Only meaningful on the done page.
function UploadPage:copy_again()
	if self.state == "done" and self.url then
		system.copy_to_clipboard(self.url)
		osd.message("Link copied to clipboard.")
	end
end

-- Open the result on the done page; jump to the options on the failed page.
function UploadPage:open_something()
	if self.state == "done" and self.url then
		system.open_url(self.url)
	elseif self.state == "failed" then
		self:finish("options")
	end
end

function UploadPage:retry()
	if self.state == "failed" then
		self:start_upload()
	end
end

---@param state webm.UploadState
function UploadPage:finish(state)
	if self.closing then
		return
	end
	self.closing = true
	self:hide()
	self.callback(state)
end

function UploadPage:draw()
	local window_w, window_h = mp.get_osd_size()
	local ass = assdraw.ass_new()
	ass:new_event()
	osd.setup_text(ass)
	if self.state == "uploading" then
		ass:append("Uploading (" .. osd.bold(tostring(self.percent) .. "%") .. ")\\N")
		ass:append(self.filename .. "\\N")
		ass:append(self.size_text .. " to " .. self.host.label .. "\\N\\N")
		ass:append(osd.bold("ESC:") .. " cancel upload\\N")
	elseif self.state == "done" then
		ass:append(osd.bold("Upload complete") .. "\\N\\N")
		ass:append(tostring(self.url) .. "\\N")
		ass:append("Link copied to clipboard.\\N\\N")
		ass:append(osd.bold("c:") .. " copy link again\\N")
		ass:append(osd.bold("o:") .. " open in browser\\N")
		ass:append(osd.bold("ESC:") .. " close\\N")
	elseif self.state == "failed" then
		ass:append(osd.bold("Upload failed") .. "\\N\\N")
		ass:append(tostring(self.error_message) .. "\\N")
		ass:append("The clip is still saved locally.\\N\\N")
		ass:append(osd.bold("r:") .. " retry upload\\N")
		ass:append(osd.bold("o:") .. " change upload options\\N")
		ass:append(osd.bold("ESC:") .. " close\\N")
	end
	mp.set_osd_ass(window_w, window_h, ass.text)
end

return UploadPage
