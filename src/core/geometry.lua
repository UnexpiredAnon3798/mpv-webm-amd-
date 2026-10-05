-- Mapping between OSD (screen) coordinates and source video pixels.
-- Most of this was copied from occivink's mpv-scripts.

local M = {}

---@class webm.VideoDimensions
---@field top_left {x: number, y: number} where the video starts on screen
---@field bottom_right {x: number, y: number} exclusive end of the video on screen
---@field ratios {w: number, h: number} source pixels per screen pixel

---@class webm.ViewState
---@field params {w: number, h: number, dw: number, dh: number} the video-out-params property
---@field keepaspect boolean
---@field rotate number video-rotate
---@field window_w number OSD width
---@field window_h number OSD height
---@field unscaled any video-unscaled
---@field panscan number
---@field zoom number video-zoom
---@field align_x number
---@field pan_x number
---@field align_y number
---@field pan_y number

---Where the video is drawn on screen. Very much ripped from video/out/aspect.c
---in mpv's source.
---@param view webm.ViewState
---@return webm.VideoDimensions
function M.dimensions(view)
	local params = view.params
	local w, h, dw, dh = params["w"], params["h"], params["dw"], params["dh"]
	if view.rotate % 180 == 90 then
		w, h = h, w
		dw, dh = dh, dw
	end

	local d = { top_left = {}, bottom_right = {}, ratios = {} }
	local window_w, window_h = view.window_w, view.window_h

	if view.keepaspect then
		local unscaled = view.unscaled
		local panscan = view.panscan

		local fwidth = window_w
		local fheight = math.floor(window_w / dw * dh)
		if fheight > window_h or fheight < h then
			local tmpw = math.floor(window_h / dh * dw)
			if tmpw <= window_w then
				fheight = window_h
				fwidth = tmpw
			end
		end
		local vo_panscan_area = window_h - fheight
		local f_w = fwidth / fheight
		local f_h = 1
		if vo_panscan_area == 0 then
			vo_panscan_area = window_h - fwidth
			f_w = 1
			f_h = fheight / fwidth
		end

		if unscaled or unscaled == "downscale-big" then
			vo_panscan_area = 0
			if unscaled or (dw <= window_w and dh <= window_h) then
				fwidth = dw
				fheight = dh
			end
		end

		local scaled_width = fwidth + math.floor(vo_panscan_area * panscan * f_w)
		local scaled_height = fheight + math.floor(vo_panscan_area * panscan * f_h)

		local function split_scaling(dst_size, scaled_src_size, zoom, align, pan)
			scaled_src_size = math.floor(scaled_src_size * 2 ^ zoom)
			align = (align + 1) / 2
			local dst_start = math.floor((dst_size - scaled_src_size) * align + pan * scaled_src_size)
			if dst_start < 0 then
				-- account for C int cast truncating as opposed to flooring
				dst_start = dst_start + 1
			end
			local dst_end = dst_start + scaled_src_size
			if dst_start >= dst_end then
				dst_start = 0
				dst_end = 1
			end
			return dst_start, dst_end
		end

		d.top_left.x, d.bottom_right.x = split_scaling(window_w, scaled_width, view.zoom, view.align_x, view.pan_x)
		d.top_left.y, d.bottom_right.y = split_scaling(window_h, scaled_height, view.zoom, view.align_y, view.pan_y)
	else
		d.top_left.x = 0
		d.bottom_right.x = window_w
		d.top_left.y = 0
		d.bottom_right.y = window_h
	end

	d.ratios.w = w / (d.bottom_right.x - d.top_left.x)
	d.ratios.h = h / (d.bottom_right.y - d.top_left.y)
	return d
end

local function clamp(min, val, max)
	if val <= min then
		return min
	end
	if val >= max then
		return max
	end
	return val
end

---A point in the video, in source pixels. -1 means unset.
---@class webm.VideoPoint
---@field x number
---@field y number
local VideoPoint = {}
VideoPoint.__index = VideoPoint

---@return webm.VideoPoint
function M.point()
	return setmetatable({ x = -1, y = -1 }, VideoPoint)
end

---@param d webm.VideoDimensions
---@param sx number screen x
---@param sy number screen y
function VideoPoint:set_from_screen(d, sx, sy)
	local px = clamp(d.top_left.x, sx, d.bottom_right.x)
	local py = clamp(d.top_left.y, sy, d.bottom_right.y)
	self.x = math.floor(d.ratios.w * (px - d.top_left.x) + 0.5)
	self.y = math.floor(d.ratios.h * (py - d.top_left.y) + 0.5)
	-- Mouse coordinates use inclusive pixel indices, while bottom_right is an
	-- exclusive bound the cursor can never reach. Snap the last OSD pixel to
	-- the exclusive video edge so the full frame stays selectable.
	if px >= d.bottom_right.x - 1 and px > d.top_left.x then
		self.x = math.floor(d.ratios.w * (d.bottom_right.x - d.top_left.x) + 0.5)
	end
	if py >= d.bottom_right.y - 1 and py > d.top_left.y then
		self.y = math.floor(d.ratios.h * (d.bottom_right.y - d.top_left.y) + 0.5)
	end
end

---@param d webm.VideoDimensions
---@return {x: number, y: number}
function VideoPoint:to_screen(d)
	return {
		x = math.floor(self.x / d.ratios.w + d.top_left.x + 0.5),
		y = math.floor(self.y / d.ratios.h + d.top_left.y + 0.5),
	}
end

---A rectangle in source pixels. -1 everywhere means "the whole frame".
---@class webm.Region
---@field x number
---@field y number
---@field w number
---@field h number
local Region = {}
Region.__index = Region

---@return webm.Region
function M.region()
	return setmetatable({ x = -1, y = -1, w = -1, h = -1 }, Region)
end

---@return boolean
function Region:is_valid()
	return self.x > -1 and self.y > -1 and self.w > -1 and self.h > -1
end

---@param p1 {x: number, y: number}
---@param p2 {x: number, y: number}
function Region:set_from_points(p1, p2)
	self.x = math.min(p1.x, p2.x)
	self.y = math.min(p1.y, p2.y)
	self.w = math.abs(p1.x - p2.x)
	self.h = math.abs(p1.y - p2.y)
end

return M
