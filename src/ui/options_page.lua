-- The encode options page.

local assdraw = require("mp.assdraw")
local mp = require("mp")
local msg = require("mp.msg")

local formats = require("encode.formats")
local hardware = require("mpv.hardware")
local options = require("mpv.options")
local osd = require("ui.osd")
local Page = require("ui.page")
local system = require("mpv.system")
local upload = require("core.upload")

-- One row on the page.
--
-- If kind is "bool" or "int", value is the boolean/integer value of the option.
-- Additionally, when kind is "int":
--     - opts.step specifies the step on which the values are changed.
--     - opts.min specifies a minimum value for the option.
--     - opts.max specifies a maximum value for the option.
--     - opts.altDisplayNames is a int->string dict, which contains alternative display names
--       for certain values.
-- If kind is "list", value is the index of the current option, inside opts.possibleValues.
-- opts.possibleValues is a array in the format
-- {
--		{value, displayValue}, -- Display value can be omitted.
-- 		{value}
-- }
-- If kind is "info", the row only shows text: opts.text() gives it. It can't be
-- selected and isn't saved.
-- visible_check is a function to check for visibility, it can be used to hide options based on rules
---@class webm.OptionRow
---@field kind "bool"|"int"|"list"|"info"
---@field display_text string
---@field opts table
---@field value any
---@field visible_check? fun(): boolean
local Option = {}
Option.__index = Option

---@return webm.OptionRow
local function new_option(kind, display_text, value, opts, visible_check)
	local self = setmetatable({
		kind = kind,
		display_text = display_text,
		opts = opts,
		value = 1,
		visible_check = visible_check,
	}, Option)
	self:set_value(value)
	return self
end

-- Whether we have a "previous" option (for left key)
function Option:has_previous()
	if self.kind == "bool" then
		return true
	elseif self.kind == "int" then
		if self.opts.min then
			return self.value > self.opts.min
		end
		return true
	elseif self.kind == "list" then
		return self.value > 1
	end
end

-- Analogous of has_previous.
function Option:has_next()
	if self.kind == "bool" then
		return true
	elseif self.kind == "int" then
		if self.opts.max then
			return self.value < self.opts.max
		end
		return true
	elseif self.kind == "list" then
		return self.value < #self.opts.possibleValues
	end
end

function Option:left_key()
	if self.kind == "bool" then
		self.value = not self.value
	elseif self.kind == "int" then
		self.value = self.value - self.opts.step
		if self.opts.min and self.opts.min > self.value then
			self.value = self.opts.min
		end
	elseif self.kind == "list" then
		if self.value > 1 then
			self.value = self.value - 1
		end
	end
end

function Option:right_key()
	if self.kind == "bool" then
		self.value = not self.value
	elseif self.kind == "int" then
		self.value = self.value + self.opts.step
		if self.opts.max and self.opts.max < self.value then
			self.value = self.opts.max
		end
	elseif self.kind == "list" then
		if self.value < #self.opts.possibleValues then
			self.value = self.value + 1
		end
	end
end

function Option:get_value()
	if self.kind == "list" then
		return self.opts.possibleValues[self.value][1]
	end
	return self.value
end

function Option:set_value(value)
	if self.kind == "list" then
		for i, pair in ipairs(self.opts.possibleValues) do
			if pair[1] == value then
				self.value = i
				return
			end
		end
		msg.warn(
			"Tried to set invalid value " .. tostring(value) .. " to " .. tostring(self.display_text) .. " option."
		)
	else
		-- The int min and max are not enforced here; the script's own values are trusted.
		self.value = value
	end
end

function Option:get_display_value()
	if self.kind == "bool" then
		return self.value and "yes" or "no"
	elseif self.kind == "int" then
		if self.opts.altDisplayNames and self.opts.altDisplayNames[self.value] then
			return self.opts.altDisplayNames[self.value]
		end
		return tostring(self.value)
	elseif self.kind == "list" then
		local pair = self.opts.possibleValues[self.value]
		return pair[2] or pair[1]
	elseif self.kind == "info" then
		return self.opts.text()
	end
end

function Option:draw(ass, selected)
	if selected then
		ass:append(osd.bold(self.display_text) .. ": ")
	else
		ass:append(self.display_text .. ": ")
	end
	if self:has_previous() then
		ass:append("◀ ")
	end
	ass:append(self:get_display_value())
	if self:has_next() then
		ass:append(" ▶")
	end
	ass:append("\\N")
end

function Option:is_visible()
	if self.visible_check == nil then
		return true
	end
	return self.visible_check()
end

function Option:is_selectable()
	return self.kind ~= "info" and self:is_visible()
end

---@class webm.OptionsPage: webm.Page
---@field callback fun(updated: boolean)
---@field current integer
---@field rows {[1]: string, [2]: webm.OptionRow}[]
local OptionsPage = Page.extend({})

---@param callback fun(updated: boolean)
---@return webm.OptionsPage
function OptionsPage.new(callback)
	local self = setmetatable({}, OptionsPage) --[[@as webm.OptionsPage]]
	self.callback = callback
	self.current = 1

	local scale_height_opts = {
		possibleValues = {
			{ -1, "no" },
			{ 144 },
			{ 240 },
			{ 360 },
			{ 480 },
			{ 540 },
			{ 720 },
			{ 1080 },
			{ 1440 },
			{ 2160 },
		},
	}
	local filesize_opts = {
		step = 250,
		min = 0,
		altDisplayNames = { [0] = "0 (constant quality)" },
	}
	local crf_opts = {
		step = 1,
		min = -1,
		altDisplayNames = { [-1] = "disabled" },
	}
	local fps_opts = {
		possibleValues = {
			{ -1, "source" },
			{ 4 },
			{ 8 },
			{ 10 },
			{ 12 },
			{ 15 },
			{ 16 },
			{ 20 },
			{ 24 },
			{ 30 },
			{ 48 },
			{ 50 },
			{ 60 },
			{ 90 },
			{ 120 },
			{ 240 },
		},
	}
	local format_values = {}
	for _, id in ipairs(formats.ids) do
		format_values[#format_values + 1] = { id, formats.by_id[id].display_name }
	end
	local gif_dither_opts = {
		possibleValues = {
			{ 0, "bayer_scale 0" },
			{ 1, "bayer_scale 1" },
			{ 2, "bayer_scale 2" },
			{ 3, "bayer_scale 3" },
			{ 4, "bayer_scale 4" },
			{ 5, "bayer_scale 5" },
			{ 6, "sierra2_4a" },
		},
	}

	-- An array of pairs rather than a dict, to keep the order.
	self.rows = {
		{
			"output_format",
			new_option("list", "Output Format", options.output_format, { possibleValues = format_values }),
		},
		{
			"device",
			new_option("info", "Device", nil, {
				text = function()
					return hardware.describe(formats.by_id[self.rows[1][2]:get_value()])
				end,
			}),
		},
		{
			"upload_host",
			new_option(
				"list",
				"Upload Destination",
				options.upload_host,
				{ possibleValues = upload.host_choices() },
				system.is_upload_available
			),
		},
		{ "twopass", new_option("bool", "Two Pass", options.twopass) },
		{ "apply_current_filters", new_option("bool", "Apply Current Video Filters", options.apply_current_filters) },
		{ "scale_height", new_option("list", "Scale Height", options.scale_height, scale_height_opts) },
		{
			"strict_filesize_constraint",
			new_option("bool", "Strict Filesize Constraint", options.strict_filesize_constraint),
		},
		{
			"write_filename_on_metadata",
			new_option("bool", "Write Filename on Metadata", options.write_filename_on_metadata),
		},
		{ "target_filesize", new_option("int", "Target Filesize", options.target_filesize, filesize_opts) },
		{ "crf", new_option("int", "CRF", options.crf, crf_opts) },
		{ "fps", new_option("list", "FPS", options.fps, fps_opts) },
		{
			"gif_dither",
			new_option("list", "GIF Dither Type", options.gif_dither, gif_dither_opts, function()
				return self.rows[1][2]:get_value() == "gif"
			end),
		},
		{ "force_square_pixels", new_option("bool", "Force Square Pixels", options.force_square_pixels) },
	}

	self.keybinds = {
		["LEFT"] = function()
			self:left_key()
		end,
		["RIGHT"] = function()
			self:right_key()
		end,
		["UP"] = function()
			self:prev_option()
		end,
		["DOWN"] = function()
			self:next_option()
		end,
		["ENTER"] = function()
			self:confirm()
		end,
		["ESC"] = function()
			self:cancel()
		end,
	}
	return self
end

function OptionsPage:current_option()
	return self.rows[self.current][2]
end

function OptionsPage:left_key()
	self:current_option():left_key()
	self:draw()
end

function OptionsPage:right_key()
	self:current_option():right_key()
	self:draw()
end

function OptionsPage:prev_option()
	for i = self.current - 1, 1, -1 do
		if self.rows[i][2]:is_selectable() then
			self.current = i
			break
		end
	end
	self:draw()
end

function OptionsPage:next_option()
	for i = self.current + 1, #self.rows do
		if self.rows[i][2]:is_selectable() then
			self.current = i
			break
		end
	end
	self:draw()
end

function OptionsPage:confirm()
	for _, row in ipairs(self.rows) do
		if row[2].kind ~= "info" then
			options[row[1]] = row[2]:get_value()
		end
	end
	self:hide()
	self.callback(true)
end

function OptionsPage:cancel()
	self:hide()
	self.callback(false)
end

function OptionsPage:draw()
	local window_w, window_h = mp.get_osd_size()
	local ass = assdraw.ass_new()
	ass:new_event()
	osd.setup_text(ass)
	ass:append(osd.bold("Options:") .. "\\N\\N")
	for i, row in ipairs(self.rows) do
		local option = row[2]
		if option:is_visible() then
			option:draw(ass, self.current == i)
		end
	end
	ass:append("\\N▲ / ▼: navigate\\N")
	ass:append(osd.bold("ENTER:") .. " confirm options\\N")
	ass:append(osd.bold("ESC:") .. " cancel\\N")
	mp.set_osd_ass(window_w, window_h, ass.text)
end

return OptionsPage
