-- The page the keybind opens: pick the range, then crop, preview, change
-- options, encode or upload.

local assdraw = require("mp.assdraw")
local mp = require("mp")

local CropPage = require("ui.crop_page")
local encoder = require("mpv.encoder")
local events = require("mpv.events")
local geometry = require("core.geometry")
local OptionsPage = require("ui.options_page")
local osd = require("ui.osd")
local Page = require("ui.page")
local PreviewPage = require("ui.preview_page")
local system = require("mpv.system")
local time = require("core.time")
local UploadPage = require("ui.upload_page")

---@class webm.MainPage: webm.Page
---@field start_time number -1 when unset
---@field end_time number -1 when unset
---@field region webm.Region
local MainPage = Page.extend({})

---@return webm.MainPage
function MainPage.new()
	local self = setmetatable({}, MainPage)
	local function bind(method)
		return function(...)
			return method(self, ...)
		end
	end
	self.keybinds = {
		["c"] = bind(MainPage.crop),
		["1"] = bind(MainPage.set_start_time),
		["2"] = bind(MainPage.set_end_time),
		["!"] = bind(MainPage.jump_to_start_time),
		["@"] = bind(MainPage.jump_to_end_time),
		["o"] = bind(MainPage.change_options),
		["p"] = bind(MainPage.preview),
		["e"] = bind(MainPage.encode),
		["u"] = bind(MainPage.upload),
		["ESC"] = bind(MainPage.hide),
	}
	self.start_time = -1
	self.end_time = -1
	self.region = geometry.region()
	return self
end

function MainPage:redraw_if_visible()
	if self.visible then
		self:clear()
		self:draw()
	end
end

function MainPage:set_start_time()
	self.start_time = mp.get_property_number("time-pos") --[[@as number]]
	self:redraw_if_visible()
end

function MainPage:set_end_time()
	self.end_time = mp.get_property_number("time-pos") --[[@as number]]
	self:redraw_if_visible()
end

function MainPage:jump_to_start_time()
	mp.set_property("time-pos", self.start_time --[[@as string]])
end

function MainPage:jump_to_end_time()
	mp.set_property("time-pos", self.end_time --[[@as string]])
end

---Resets the range to the whole file. Runs on every file-loaded event.
function MainPage:setup_start_and_end_times()
	if mp.get_property_native("duration") then
		-- Note: there exists an option called rebase-start-time, which, when set to no,
		-- could cause the beginning of the video to not be at 0. Not sure how this
		-- would affect this code.
		self.start_time = 0
		self.end_time = mp.get_property_native("duration")
	else
		self.start_time = -1
		self.end_time = -1
	end
	self:redraw_if_visible()
end

function MainPage:draw()
	local window_w, window_h = mp.get_osd_size()
	local ass = assdraw.ass_new()
	ass:new_event()
	osd.setup_text(ass)
	local b = osd.bold
	ass:append(b("WebM maker") .. "\\N\\N")
	ass:append(b("c:") .. " crop\\N")
	ass:append(b("1:") .. " set start time (current is " .. time.to_time_string(self.start_time) .. ")\\N")
	ass:append(b("2:") .. " set end time (current is " .. time.to_time_string(self.end_time) .. ")\\N")
	ass:append(b("!:") .. " jump to start time\\N")
	ass:append(b("@:") .. " jump to end time\\N")
	ass:append(b("o:") .. " change encode options\\N")
	ass:append(b("p:") .. " preview\\N")
	ass:append(b("e:") .. " encode\\N")
	if system.is_upload_available() then
		ass:append(b("u:") .. " encode & upload\\N")
	end
	ass:append("\\N")
	ass:append(b("ESC:") .. " close\\N")
	mp.set_osd_ass(window_w, window_h, ass.text)
end

function MainPage:show()
	Page.show(self)
	events.emit("show-main-page")
end

function MainPage:crop()
	self:hide()
	CropPage.new(function(updated, region)
		if updated then
			self.region = region
		end
		self:show()
	end, self.region):show()
end

function MainPage:change_options()
	self:hide()
	OptionsPage.new(function()
		self:show()
	end):show()
end

function MainPage:preview()
	self:hide()
	PreviewPage.new(function()
		self:show()
	end, self.region, self.start_time, self.end_time):show()
end

-- Shows a message and returns false when the range can't be encoded.
function MainPage:check_range()
	if self.start_time < 0 then
		osd.message("No start time, aborting")
		return false
	end
	if self.end_time < 0 then
		osd.message("No end time, aborting")
		return false
	end
	if self.start_time >= self.end_time then
		osd.message("Start time is ahead of end time, aborting")
		return false
	end
	return true
end

function MainPage:upload()
	if not system.is_upload_available() then
		osd.message("Uploads need curl on PATH. Set upload_curl_path in webm.conf.")
		return
	end
	if not self:check_range() then
		return
	end
	self:hide()
	encoder.encode(self.region, self.start_time, self.end_time, function(success, out_path)
		if not success or not out_path then
			self:show()
			return
		end
		-- Known bug, kept for now: the failed page offers "o: change upload
		-- options", but the MoonScript version passed the upload page instead of
		-- its state to this callback, so the main page always came back. The
		-- intended behavior is to open the options page for state "options".
		UploadPage.new(function()
			self:show()
		end, out_path):show()
	end)
end

function MainPage:encode()
	self:hide()
	if not self:check_range() then
		return
	end
	encoder.encode(self.region, self.start_time, self.end_time)
end

return MainPage
