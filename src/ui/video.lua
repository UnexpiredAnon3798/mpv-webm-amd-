-- Where the video is on screen, from mpv's current state. The result is
-- cached until one of the properties that affect it changes.

local mp = require("mp")

local geometry = require("core.geometry")

local M = {}

-- These properties affect where the video is drawn.
M.LAYOUT_PROPERTIES = {
	"keepaspect",
	"video-out-params",
	"video-unscaled",
	"panscan",
	"video-zoom",
	"video-align-x",
	"video-pan-x",
	"video-align-y",
	"video-pan-y",
	"osd-width",
	"osd-height",
}

-- These properties always exist while a video is shown.
local function number(name)
	return mp.get_property_number(name) --[[@as number]]
end

local function bool(name)
	return mp.get_property_bool(name) --[[@as boolean]]
end

local changed = true
local cached = {}

---@return webm.VideoDimensions?
function M.dimensions()
	if not changed then
		return cached
	end

	local params = mp.get_property_native("video-out-params")
	if not params then
		return nil
	end

	changed = false
	local window_w, window_h = mp.get_osd_size()
	cached = geometry.dimensions({
		params = params,
		keepaspect = bool("keepaspect"),
		rotate = number("video-rotate"),
		window_w = window_w,
		window_h = window_h,
		unscaled = mp.get_property_native("video-unscaled"),
		panscan = number("panscan"),
		zoom = number("video-zoom"),
		align_x = number("video-align-x"),
		pan_x = number("video-pan-x"),
		align_y = number("video-align-y"),
		pan_y = number("video-pan-y"),
	})
	return cached
end

local function mark_changed()
	changed = true
end

---Starts watching the layout properties. Call once at startup.
function M.monitor()
	for _, name in ipairs(M.LAYOUT_PROPERTIES) do
		mp.observe_property(name, "native", mark_changed)
	end
end

return M
