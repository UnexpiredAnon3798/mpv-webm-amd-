-- Small helpers for OSD text.

local mp = require("mp")

local options = require("mpv.options")

local M = {}

---@param text string
---@return string
function M.bold(text)
	return "{\\b1}" .. tostring(text) .. "{\\b0}"
end

---Shows an OSD message. The text may contain ASS tags.
---@param text string
---@param duration? number seconds, defaults to options.message_duration
function M.message(text, duration)
	-- The font size can't be set here, it has nothing to do with the font
	-- size of the pages drawn with set_osd_ass.
	local ass = mp.get_property_osd("osd-ass-cc/0")
	mp.osd_message(ass .. text, duration or options.message_duration)
end

---Pages are laid out for a 720 pixel high OSD and scaled from there.
---@return number
function M.scale_factor()
	local _, osd_h = mp.get_osd_size()
	return osd_h / 720
end

---Starts a page's text block: top left, with the margin and font size.
---@param ass mp.assdraw.Ass
function M.setup_text(ass)
	local scale = M.scale_factor()
	local margin = options.margin * scale
	ass:append("{\\an7}")
	ass:pos(margin, margin)
	ass:append("{\\fs" .. tostring(options.font_size * scale) .. "}")
end

return M
