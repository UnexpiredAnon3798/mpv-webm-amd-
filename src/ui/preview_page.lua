-- Plays the selected range on a loop, with the crop applied.

local assdraw = require("mp.assdraw")
local mp = require("mp")

local osd = require("ui.osd")
local Page = require("ui.page")

-- Properties the preview changes, restored in this order afterwards.
local SAVED_PROPERTIES = { "vf", "time-pos", "pause" }

---@class webm.PreviewPage: webm.Page
---@field callback fun()
---@field saved table<string, any>
---@field region webm.Region
---@field start_time number
---@field end_time number
local PreviewPage = Page.extend({})

---@param callback fun()
---@param region webm.Region
---@param start_time number
---@param end_time number
---@return webm.PreviewPage
function PreviewPage.new(callback, region, start_time, end_time)
	local self = setmetatable({}, PreviewPage) --[[@as webm.PreviewPage]]
	self.callback = callback
	self.saved = {}
	for _, name in ipairs(SAVED_PROPERTIES) do
		self.saved[name] = mp.get_property_native(name)
	end
	self.keybinds = {
		["ESC"] = function()
			self:cancel()
		end,
	}
	self.region = region
	self.start_time = start_time
	self.end_time = end_time
	return self
end

function PreviewPage:prepare()
	local vf = mp.get_property_native("vf")
	-- Apply crop before subtitle rendering, matching mpv playback.
	if self.region:is_valid() then
		vf[#vf + 1] = {
			name = "crop",
			params = {
				w = tostring(self.region.w),
				h = tostring(self.region.h),
				x = tostring(self.region.x),
				y = tostring(self.region.y),
			},
		}
	end
	vf[#vf + 1] = { name = "sub" }

	mp.set_property_native("vf", vf)
	if self.start_time > -1 and self.end_time > -1 then
		mp.set_property_native("ab-loop-a", self.start_time)
		mp.set_property_native("ab-loop-b", self.end_time)
		mp.set_property_native("time-pos", self.start_time)
	end
	mp.set_property_native("pause", false)
end

function PreviewPage:dispose()
	mp.set_property("ab-loop-a", "no")
	mp.set_property("ab-loop-b", "no")
	for _, name in ipairs(SAVED_PROPERTIES) do
		mp.set_property_native(name, self.saved[name])
	end
end

function PreviewPage:draw()
	local window_w, window_h = mp.get_osd_size()
	local ass = assdraw.ass_new()
	ass:new_event()
	osd.setup_text(ass)
	ass:append("Press " .. osd.bold("ESC") .. " to exit preview.\\N")
	mp.set_osd_ass(window_w, window_h, ass.text)
end

function PreviewPage:cancel()
	self:hide()
	self.callback()
end

return PreviewPage
