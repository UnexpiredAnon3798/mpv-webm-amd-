-- mpv-webm: makes WebM/MP4/GIF clips from the video that is playing.
--
-- This file only wires the script into mpv. The logic lives in the modules
-- under src/core, src/encode, src/ui and src/mpv.

local mp = require("mp")
local msg = require("mp.msg")

-- Reads webm.conf and --script-opts. Required first so every module after
-- this sees the user's options.
local options = require("mpv.options")

local events = require("mpv.events")
local MainPage = require("ui.main_page")
local testing = require("mpv.testing")
local video = require("ui.video")

testing.register_options_handler()

video.monitor()
local main_page = MainPage.new()
testing.register_main_page_handlers(main_page)

mp.add_key_binding(options.keybind, "display-webm-encoder", function()
	main_page:show()
end, { repeatable = false })
mp.register_event("file-loaded", function()
	main_page:setup_start_and_end_times()
end)

msg.verbose("Loaded mpv-webm script!")
events.emit("script-loaded")
