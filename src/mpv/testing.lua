-- Script-messages used by the integration tests to drive the script through
-- the same code paths as the UI. They also work from input.conf or other
-- scripts.

local mp = require("mp")
local utils = require("mp.utils")

local events = require("mpv.events")
local options = require("mpv.options")

local M = {}

---mpv-webm-set-options <json>: overwrite options for this session.
function M.register_options_handler()
	mp.register_script_message("mpv-webm-set-options", function(new_options_json)
		local new_options = utils.parse_json(new_options_json)
		for k, v in pairs(new_options) do
			options[k] = v
		end
		events.emit("options-set")
	end)
end

---The handlers that need the main page. Registered after it is created so
---tests use the same controller as the interactive UI.
---@param main_page webm.MainPage
function M.register_main_page_handlers(main_page)
	mp.register_script_message("mpv-webm-set-range", function(range_json)
		local range = utils.parse_json(range_json)
		main_page.start_time = range.startTime
		main_page.end_time = range.endTime
		if range.region then
			for _, key in ipairs({ "x", "y", "w", "h" }) do
				main_page.region[key] = range.region[key]
			end
		end
		events.emit("range-set")
	end)
	mp.register_script_message("mpv-webm-encode", function()
		main_page:encode()
	end)
	mp.register_script_message("mpv-webm-upload", function()
		main_page:upload()
	end)
	mp.register_script_message("mpv-webm-get-state", function()
		local mouse_x, mouse_y = mp.get_mouse_pos()
		local osd_w, osd_h = mp.get_osd_size()
		local region = main_page.region
		local state_json = utils.format_json({
			startTime = main_page.start_time,
			endTime = main_page.end_time,
			region = { x = region.x, y = region.y, w = region.w, h = region.h },
			mainVisible = main_page.visible or false,
			mouse = { x = mouse_x, y = mouse_y },
			osd = { w = osd_w, h = osd_h },
		})
		events.emit("state", state_json --[[@as string]])
	end)
end

return M
