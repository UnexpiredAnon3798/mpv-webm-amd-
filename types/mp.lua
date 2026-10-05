---@meta mp

-- Type declarations for the parts of mpv's Lua API this script uses, for the
-- Lua Language Server. Written against the mpv manual (DOCS/man/lua.rst) and
-- player/lua/defaults.lua on mpv master. Nothing here runs.

---@class mp
---@field msg mp.msg
---@field utils mp.utils
---@field options mp.options
mp = {}

-- Commands ---------------------------------------------------------------

---Run an input.conf style command. Shows OSD feedback like input.conf would.
---@param command string
---@return true|nil ok
---@return string? err
function mp.command(command) end

---Run a command with each argument passed separately. Properties are not expanded.
---@param ... string|number|boolean
---@return true|nil ok
---@return string? err
function mp.commandv(...) end

---Run a command given as an array of arguments, or as a table of named arguments
---with a `name` or `_name` entry.
---@param command table
---@param def? any returned instead of the result on error
---@return any result
---@return string? err
function mp.command_native(command, def) end

---@alias mp.AsyncCallback fun(success: boolean, result: any, err: string?)

---Run a command asynchronously. `fn` is always called asynchronously.
---@param command table
---@param fn? mp.AsyncCallback
---@return table|nil handle pass to `mp.abort_async_command`
---@return string? err
function mp.command_native_async(command, fn) end

---Abort a command started with `mp.command_native_async`. The abort is asynchronous.
---@param handle table
function mp.abort_async_command(handle) end

-- Properties ---------------------------------------------------------------

---Property value as a string, formatted like `${=name}`.
---@param name string
---@param def? string
---@return string|nil value
---@return string? err
function mp.get_property(name, def) end

---Property value formatted for the OSD, like `${name}`. Always returns a string.
---@param name string
---@param def? string defaults to ""
---@return string value
---@return string? err
function mp.get_property_osd(name, def) end

---@param name string
---@param def? boolean
---@return boolean|nil value
---@return string? err
function mp.get_property_bool(name, def) end

---@param name string
---@param def? number
---@return number|nil value
---@return string? err
function mp.get_property_number(name, def) end

---Property value using the closest Lua type. Some properties return tables.
---@param name string
---@param def? any
---@return any value
---@return string? err
function mp.get_property_native(name, def) end

---@param name string
---@param value string
---@return true|nil ok
---@return string? err
function mp.set_property(name, value) end

---@param name string
---@param value boolean
---@return true|nil ok
---@return string? err
function mp.set_property_bool(name, value) end

---@param name string
---@param value number
---@return true|nil ok
---@return string? err
function mp.set_property_number(name, value) end

---@param name string
---@param value any
---@return true|nil ok
---@return string? err
function mp.set_property_native(name, value) end

---@alias mp.PropertyType "none"|"native"|"bool"|"string"|"number"

---Call `fn(name, value)` when the property changes, and once initially.
---@param name string
---@param type mp.PropertyType|nil
---@param fn fun(name: string, value: any)
function mp.observe_property(name, type, fn) end

---Remove every observer registered with this exact function.
---@param fn function
function mp.unobserve_property(fn) end

-- Key bindings, events and messages ----------------------------------------

---@class mp.KeyBindingFlags
---@field repeatable? boolean
---@field scalable? boolean
---@field complex? boolean

---@param key string|nil
---@param name string|function
---@param fn? function|mp.KeyBindingFlags
---@param flags? mp.KeyBindingFlags
function mp.add_key_binding(key, name, fn, flags) end

---Like `mp.add_key_binding`, but overrides the user's input.conf bindings.
---@param key string|nil
---@param name string|function
---@param fn? function|mp.KeyBindingFlags
---@param flags? mp.KeyBindingFlags
function mp.add_forced_key_binding(key, name, fn, flags) end

---@param name string
function mp.remove_key_binding(name) end

---@param name string
---@param fn fun(event: table)
---@return boolean exists
function mp.register_event(name, fn) end

---@param fn function
function mp.unregister_event(fn) end

---Handle `script-message` and `script-message-to` with this name.
---@param name string
---@param fn fun(...: string)
function mp.register_script_message(name, fn) end

---@param name string
function mp.unregister_script_message(name) end

-- Timers -------------------------------------------------------------------

---@class mp.Timer
local Timer = {}

---Disable the timer, keeping the elapsed time.
function Timer:stop() end

---Disable the timer and reset the elapsed time.
function Timer:kill() end

---Restart the timer.
function Timer:resume() end

---@return boolean
function Timer:is_enabled() end

---One-shot timer.
---@param seconds number
---@param fn function
---@param disabled? boolean
---@return mp.Timer
function mp.add_timeout(seconds, fn, disabled) end

---@param seconds number
---@param fn function
---@param disabled? boolean
---@return mp.Timer
function mp.add_periodic_timer(seconds, fn, disabled) end

-- OSD ------------------------------------------------------------------

---@param text string
---@param duration? number seconds, defaults to --osd-duration
function mp.osd_message(text, duration) end

---@return integer width
---@return integer height
---@return number par
function mp.get_osd_size() end

---Show ASS events on the OSD. Kept by mpv as a legacy wrapper around
---`mp.create_osd_overlay`.
---@param res_x integer
---@param res_y integer
---@param data string
function mp.set_osd_ass(res_x, res_y, data) end

---@class mp.OsdOverlay
---@field data string
---@field res_x integer
---@field res_y integer
---@field z integer
---@field hidden boolean
local OsdOverlay = {}

function OsdOverlay:update() end

function OsdOverlay:remove() end

---@param format "ass-events"|"none"
---@return mp.OsdOverlay
function mp.create_osd_overlay(format) end

---Mouse position in OSD coordinates. Reads the `mouse-pos` property.
---@return integer x
---@return integer y
function mp.get_mouse_pos() end

-- Misc ---------------------------------------------------------------------

---@return number seconds
function mp.get_time() end

---@return string
function mp.get_script_name() end

---Directory of a directory-style script, or nothing for a single-file script.
---@return string?
function mp.get_script_directory() end

return mp
