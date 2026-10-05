-- Base for the OSD pages. A page owns the OSD and a set of forced key
-- bindings while it is shown, and redraws when the video layout changes.

local mp = require("mp")

local video = require("ui.video")

---@class webm.Page
---@field visible? boolean
---@field keybinds? table<string, function>
---@field size_callback? function
local Page = {}
Page.__index = Page

---Makes a page class that inherits from Page.
---@generic T
---@param class T
---@return T
function Page.extend(class)
	class.__index = class
	return setmetatable(class, { __index = Page })
end

function Page:add_keybinds()
	if not self.keybinds then
		return
	end
	for key, func in pairs(self.keybinds) do
		mp.add_forced_key_binding(key, key, func, { repeatable = true })
	end
end

function Page:remove_keybinds()
	if not self.keybinds then
		return
	end
	for key in pairs(self.keybinds) do
		mp.remove_key_binding(key)
	end
end

function Page:observe_properties()
	-- A fresh closure, so it can be unobserved without touching anyone else's.
	self.size_callback = function()
		self:draw()
	end
	for _, name in ipairs(video.LAYOUT_PROPERTIES) do
		mp.observe_property(name, "native", self.size_callback)
	end
end

function Page:unobserve_properties()
	if self.size_callback then
		mp.unobserve_property(self.size_callback)
		self.size_callback = nil
	end
end

function Page:clear()
	local window_w, window_h = mp.get_osd_size()
	mp.set_osd_ass(window_w, window_h, "")
	mp.osd_message("", 0)
end

-- Called when the page is shown, before the first draw.
function Page:prepare() end

-- Called when the page is hidden.
function Page:dispose() end

function Page:draw() end

function Page:show()
	if self.visible then
		return
	end
	self.visible = true
	self:observe_properties()
	self:add_keybinds()
	self:prepare()
	self:clear()
	self:draw()
end

function Page:hide()
	if not self.visible then
		return
	end
	self.visible = false
	self:unobserve_properties()
	self:remove_keybinds()
	self:clear()
	self:dispose()
end

return Page
