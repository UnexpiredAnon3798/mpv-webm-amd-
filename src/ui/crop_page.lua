-- Picks a crop region with two corner points under the mouse.

local assdraw = require("mp.assdraw")
local mp = require("mp")

local events = require("mpv.events")
local geometry = require("core.geometry")
local osd = require("ui.osd")
local Page = require("ui.page")
local video = require("ui.video")

---@class webm.CropPage: webm.Page
---@field point_a webm.VideoPoint
---@field point_b webm.VideoPoint
---@field callback fun(updated: boolean, region?: webm.Region)
local CropPage = Page.extend({})

---@param callback fun(updated: boolean, region?: webm.Region)
---@param region? webm.Region the current crop, to start from
---@return webm.CropPage
function CropPage.new(callback, region)
	local self = setmetatable({}, CropPage)
	self.point_a = geometry.point()
	self.point_b = geometry.point()
	self.keybinds = {
		["1"] = function()
			self:set_point_a()
		end,
		["2"] = function()
			self:set_point_b()
		end,
		["r"] = function()
			self:reset()
		end,
		["ESC"] = function()
			self:cancel()
		end,
		["ENTER"] = function()
			self:finish()
		end,
	}
	self:reset()
	self.callback = callback
	-- If we have a region, set point A and B from it
	if region and region:is_valid() then
		self.point_a.x = region.x
		self.point_a.y = region.y
		self.point_b.x = region.x + region.w
		self.point_b.y = region.y + region.h
	end
	return self
end

function CropPage:show()
	Page.show(self)
	events.emit("show-crop-page")
end

function CropPage:reset()
	local d = video.dimensions() --[[@as webm.VideoDimensions]]
	self.point_a:set_from_screen(d, d.top_left.x, d.top_left.y)
	self.point_b:set_from_screen(d, d.bottom_right.x, d.bottom_right.y)
	if self.visible then
		self:draw()
	end
end

function CropPage:set_point_a()
	local x, y = mp.get_mouse_pos()
	self.point_a:set_from_screen(video.dimensions(), x, y)
	events.emit("crop-point-a", tostring(self.point_a.x), tostring(self.point_a.y))
	if self.visible then
		-- No need to clear, as we draw the entire OSD (also it causes flickering)
		self:draw()
	end
end

function CropPage:set_point_b()
	local x, y = mp.get_mouse_pos()
	self.point_b:set_from_screen(video.dimensions(), x, y)
	events.emit("crop-point-b", tostring(self.point_b.x), tostring(self.point_b.y))
	if self.visible then
		self:draw()
	end
end

function CropPage:cancel()
	self:hide()
	self.callback(false, nil)
end

function CropPage:finish()
	local region = geometry.region()
	region:set_from_points(self.point_a, self.point_b)
	self:hide()
	self.callback(true, region)
end

---@param ass mp.assdraw.Ass
function CropPage:draw_box(ass)
	local d = video.dimensions() --[[@as webm.VideoDimensions]]
	local region = geometry.region()
	region:set_from_points(self.point_a:to_screen(d), self.point_b:to_screen(d))

	ass:new_event()
	ass:append("{\\an7}")
	ass:pos(0, 0)
	ass:append("{\\bord0}")
	ass:append("{\\shad0}")
	ass:append("{\\c&H000000&}")
	ass:append("{\\alpha&H77}")
	-- Draw a black layer over the uncropped area
	ass:draw_start()
	ass:rect_cw(d.top_left.x, d.top_left.y, region.x, region.y + region.h) -- Top left uncropped area
	ass:rect_cw(region.x, d.top_left.y, d.bottom_right.x, region.y) -- Top right uncropped area
	ass:rect_cw(d.top_left.x, region.y + region.h, region.x + region.w, d.bottom_right.y) -- Bottom left uncropped area
	ass:rect_cw(region.x + region.w, region.y, d.bottom_right.x, d.bottom_right.y) -- Bottom right uncropped area
	ass:draw_stop()
end

function CropPage:draw()
	local window_w, window_h = mp.get_osd_size()
	local ass = assdraw.ass_new()
	self:draw_box(ass)
	ass:new_event()
	osd.setup_text(ass)
	local a, b = self.point_a, self.point_b
	ass:append(osd.bold("Crop:") .. "\\N")
	ass:append(osd.bold("1:") .. " change point A (" .. tostring(a.x) .. ", " .. tostring(a.y) .. ")\\N")
	ass:append(osd.bold("2:") .. " change point B (" .. tostring(b.x) .. ", " .. tostring(b.y) .. ")\\N")
	ass:append(osd.bold("r:") .. " reset to whole screen\\N")
	ass:append(osd.bold("ESC:") .. " cancel crop\\N")
	local width, height = math.abs(a.x - b.x), math.abs(a.y - b.y)
	ass:append(osd.bold("ENTER:") .. " confirm crop (" .. tostring(width) .. "x" .. tostring(height) .. ")\\N")
	mp.set_osd_ass(window_w, window_h, ass.text)
end

return CropPage
