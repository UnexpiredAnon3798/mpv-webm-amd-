-- A scripted stand-in for mpv's Lua API, used by the golden tests.
--
-- It loads a built webm.lua into a sandbox whose mp, mp.msg, mp.utils,
-- mp.options and mp.assdraw modules, along with os and io, are fakes. Every
-- observable side effect the script has (subprocess arguments, OSD text,
-- emitted script-messages, properties set, files written or removed) is
-- appended to a transcript. The transcript is what the golden files pin down.
--
-- Only the script's external surface is driven: key presses, script-messages
-- and events. Internal functions are never called directly, so the same
-- goldens apply to any implementation that behaves the same.
--
-- Deliberate simplifications (see README.md): properties are a plain table,
-- observers fire synchronously and only for properties a scenario changes,
-- asynchronous commands and timers run only when a scenario asks.

local json = dofile(GOLDEN_DIRECTORY .. "json.lua")

local fake_mpv = {}

-- Fixed clock for os.date and os.time: 2024-03-09 13:45:30 UTC.
local FIXED_UNIX_TIME = 1709991930
local DEFAULT_OSD_WIDTH = 1280
local DEFAULT_OSD_HEIGHT = 720
local EXIT_SUCCESS = 0
-- What mpv reports for a subprocess it killed.
local KILLED_STATUS = -2
local NOT_FOUND = "property not found"

local World = {}
World.__index = World

local function shallow_copy(original)
	local copy = {}
	for key, value in pairs(original or {}) do
		copy[key] = value
	end
	return copy
end

-- Renders a property value the way mpv's string conversion would.
local function property_to_string(value)
	local kind = type(value)
	if kind == "boolean" then
		return value and "yes" or "no"
	elseif kind == "number" then
		if value == math.floor(value) then
			return string.format("%d", value)
		end
		return string.format("%f", value)
	elseif kind == "string" then
		return value
	end
	return json.encode(value)
end

-- Joins all arguments with a separator, like mpv's message functions do.
local function join_arguments(separator, ...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(index, ...)))
	end
	return table.concat(parts, separator)
end

function fake_mpv.new(settings)
	local self = setmetatable({}, World)
	self.settings = settings
	self.platform = settings.platform or "unix"
	self.lines = {}
	self.properties = shallow_copy(settings.properties)
	self.osd_properties = shallow_copy(settings.osd_properties)
	self.files = shallow_copy(settings.files)
	self.environment = shallow_copy(settings.environment)
	self.conf_file = settings.conf_file or {}
	self.osd_width = settings.osd_width or DEFAULT_OSD_WIDTH
	self.osd_height = settings.osd_height or DEFAULT_OSD_HEIGHT
	self.mouse_x, self.mouse_y = 0, 0
	self.script_messages = {}
	self.key_bindings = {}
	self.forced_bindings = {}
	self.events = {}
	self.observers = {}
	self.pending_commands = {}
	self.timers = {}
	self.temporary_file_count = 0
	self.command_handle_count = 0
	-- Above zero, transcript lines are dropped. Script errors are always kept.
	self.quiet_depth = 0
	return self
end

function World:log(line)
	if self.quiet_depth == 0 then
		self.lines[#self.lines + 1] = line
	end
end

function World:log_block(header, items)
	self:log(header)
	for _, item in ipairs(items) do
		self:log("  | " .. tostring(item))
	end
end

-- Paths -------------------------------------------------------------------

function World:is_absolute(path)
	if self.platform == "windows" then
		return path:match("^[A-Za-z]:[/\\]") ~= nil or path:match("^[/\\]") ~= nil
	end
	return path:sub(1, 1) == "/"
end

-- Where the last path component starts.
function World:basename_start(path)
	local pattern = self.platform == "windows" and "^.*()[/\\:]" or "^.*()/"
	local last_separator = path:match(pattern)
	return last_separator and last_separator + 1 or 1
end

-- Same results as mpv's mp_dirname and mp_basename.
function World:split_path(path)
	local start = self:basename_start(path)
	local directory = path:sub(1, start - 1)
	if directory == "" then
		directory = "."
	end
	return directory, path:sub(start)
end

-- Same results as mpv's mp_path_join.
function World:join_path(first, second)
	if first == "" then
		return second
	end
	if second == "" then
		return first
	end
	if self:is_absolute(second) then
		return second
	end
	local last_character = first:sub(-1)
	local ends_with_separator = last_character == "/"
		or (self.platform == "windows" and (last_character == "\\" or last_character == ":"))
	return first .. (ends_with_separator and "" or "/") .. second
end

-- Properties ----------------------------------------------------------------

function World:set_property(name, value)
	self.properties[name] = value
	for _, observer in ipairs(self.observers) do
		if observer.name == name then
			observer.callback(name, value)
		end
	end
end

-- Subprocess responders ---------------------------------------------------

local function has_argument(arguments, wanted)
	for _, argument in ipairs(arguments) do
		if argument == wanted then
			return true
		end
	end
	return false
end

local function argument_value(arguments, prefix)
	for _, argument in ipairs(arguments) do
		if argument:sub(1, #prefix) == prefix then
			return argument:sub(#prefix + 1)
		end
	end
end

-- A fake libvpx first-pass log: two frame records plus the aggregate record,
-- 18 doubles of 8 bytes each. The bytes are a fixed pattern. Only the
-- duration field is interpreted, and the patcher rewrites it.
local VP8_RECORD_COUNT = 3
local VP8_RECORD_SIZE = 18 * 8
local BYTE_VALUES = 256

local function fake_vp8_log_bytes()
	local bytes = {}
	for position = 1, VP8_RECORD_COUNT * VP8_RECORD_SIZE do
		bytes[position] = string.char((position * 37) % BYTE_VALUES)
	end
	return table.concat(bytes)
end

-- Base64 encoding, written separately from the script's own so the test
-- does not trust the code it checks. Every 3 bytes become 4 characters of 6
-- bits each.
local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_VALUES = 64

local function base64(data)
	local groups = {}
	for start = 1, #data, 3 do
		local first, second, third = data:byte(start, start + 2)
		local combined = first * BYTE_VALUES * BYTE_VALUES + (second or 0) * BYTE_VALUES + (third or 0)
		local characters = {}
		for shift = 3, 0, -1 do
			local value = math.floor(combined / BASE64_VALUES ^ shift) % BASE64_VALUES
			characters[#characters + 1] = BASE64_ALPHABET:sub(value + 1, value + 1)
		end
		if not second then
			characters[3], characters[4] = "=", "="
		elseif not third then
			characters[4] = "="
		end
		groups[#groups + 1] = table.concat(characters)
	end
	return table.concat(groups)
end

local function result(status, output)
	return { status = status, stdout = output or "", error_string = "" }
end

function World:run_subprocess(arguments)
	local settings = self.settings
	if arguments[1] == "mpv" and arguments[2] == "--no-config" and arguments[3] == "--version" then
		return shallow_copy(settings.encoder_check or result(EXIT_SUCCESS, "mpv 0.40.0\n"))
	end
	if arguments[2] == "--version" then
		-- The curl availability probe.
		return shallow_copy(settings.curl_check or result(EXIT_SUCCESS, "curl 8.0.0\n"))
	end
	if arguments[1] == "mpv" then
		local output_path = argument_value(arguments, "--o=")
		self.last_output_path = output_path
		if has_argument(arguments, "--ovcopts-add=flags=+pass1") then
			if settings.first_pass_status and settings.first_pass_status ~= EXIT_SUCCESS then
				return result(settings.first_pass_status)
			end
			if output_path and argument_value(arguments, "--ovc=") == "libvpx" then
				self.files[output_path .. "-video-pass1.log"] = base64(fake_vp8_log_bytes())
			end
			return result(EXIT_SUCCESS)
		end
		local status = settings.encode_status or EXIT_SUCCESS
		if status == EXIT_SUCCESS and output_path then
			self.files[output_path] = "encoded"
		end
		return result(status)
	end
	return result(EXIT_SUCCESS)
end

-- Results of asynchronous subprocesses: encodes, uploads and clipboard tools.
function World:asynchronous_result(command)
	local arguments = command.args or {}
	if arguments[1] == "mpv" then
		return true, self:run_subprocess(arguments), nil
	end
	if arguments[1] == (self.settings.curl_path or "curl") then
		local output_flag_index = nil
		for index, argument in ipairs(arguments) do
			if argument == "-o" then
				output_flag_index = index
			end
		end
		local response_path = output_flag_index and arguments[output_flag_index + 1]
		local upload = self.settings.upload
			or { status = EXIT_SUCCESS, http = "200", body = "https://files.catbox.moe/abc123.mp4\n" }
		if response_path then
			self.files[response_path] = upload.body
		end
		return upload.status == EXIT_SUCCESS,
			{
				status = upload.status,
				stdout = upload.http,
				error_string = upload.error_string or "",
				killed_by_us = false,
			},
			nil
	end
	return true, result(EXIT_SUCCESS), nil
end

-- Module construction -----------------------------------------------------

function World:make_mp()
	local world = self
	local mp = {}

	function mp.get_property(name, default)
		local value = world.properties[name]
		if value == nil then
			return default, NOT_FOUND
		end
		return property_to_string(value)
	end

	function mp.get_property_osd(name, default)
		local value = world.osd_properties[name]
		if value == nil and world.properties[name] ~= nil then
			value = property_to_string(world.properties[name])
		end
		if value == nil then
			if default == nil then
				return "", NOT_FOUND
			end
			return default, NOT_FOUND
		end
		return value
	end

	function mp.get_property_native(name, default)
		local value = world.properties[name]
		if value == nil then
			return default, NOT_FOUND
		end
		if type(value) == "table" then
			-- mpv hands out a fresh table on every call.
			return json.decode(json.encode(value))
		end
		return value
	end

	function mp.get_property_number(name, default)
		local value = world.properties[name]
		if type(value) == "string" then
			value = tonumber(value)
		end
		if type(value) ~= "number" then
			return default, NOT_FOUND
		end
		return value
	end

	function mp.get_property_bool(name, default)
		local value = world.properties[name]
		if value == "yes" then
			return true
		elseif value == "no" then
			return false
		elseif type(value) == "boolean" then
			return value
		end
		return default, NOT_FOUND
	end

	local function set(kind, name, value)
		if name == "clipboard/text" and world.settings.clipboard_property == false then
			world:log(kind .. ": " .. name .. " (rejected)")
			return nil, NOT_FOUND
		end
		world:log(kind .. ": " .. name .. " = " .. json.encode(value))
		world.properties[name] = value
		return true
	end
	function mp.set_property(name, value)
		return set("set_property", name, value)
	end
	function mp.set_property_native(name, value)
		return set("set_property_native", name, value)
	end
	function mp.set_property_number(name, value)
		return set("set_property_number", name, value)
	end
	function mp.set_property_bool(name, value)
		return set("set_property_bool", name, value)
	end

	function mp.observe_property(name, kind, callback)
		world.observers[#world.observers + 1] = { name = name, callback = callback }
	end
	function mp.unobserve_property(callback)
		local kept = {}
		for _, observer in ipairs(world.observers) do
			if observer.callback ~= callback then
				kept[#kept + 1] = observer
			end
		end
		world.observers = kept
	end

	function mp.osd_message(text, duration)
		world:log("osd_message(" .. tostring(duration) .. "): " .. tostring(text))
	end

	function mp.set_osd_ass(width, height, text)
		if text == "" then
			world:log(string.format("osd_ass %dx%d: <clear>", width, height))
			return
		end
		local lines = {}
		for line in (text .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = line
		end
		world:log_block(string.format("osd_ass %dx%d:", width, height), lines)
	end

	function mp.get_osd_size()
		return world.osd_width, world.osd_height
	end

	function mp.get_mouse_pos()
		return world.mouse_x, world.mouse_y
	end

	function mp.commandv(...)
		local arguments = { ... }
		if arguments[1] == "script-message" then
			world:log("event: " .. table.concat(arguments, " ", 2))
			return true
		end
		world:log("commandv: " .. json.encode(arguments))
		return true
	end

	function mp.command(command)
		world:log("command: " .. command)
		return true
	end

	function mp.command_native(command)
		world:log("command_native: " .. json.encode(command))
		if command[1] == "dump_cache" then
			local dump_path = command[4]
			world.files[dump_path] = "cache"
		end
		return {}
	end

	function mp.command_native_async(command, callback)
		world.command_handle_count = world.command_handle_count + 1
		local handle = { id = world.command_handle_count }
		local options = shallow_copy(command)
		local arguments = options.args
		options.args = nil
		world:log_block("command_native_async #" .. handle.id .. " " .. json.encode(options) .. ":", arguments or {})
		world.pending_commands[#world.pending_commands + 1] =
			{ handle = handle, command = command, callback = callback }
		return handle
	end

	function mp.abort_async_command(handle)
		world:log("abort_async_command #" .. handle.id)
		for _, pending in ipairs(world.pending_commands) do
			if pending.handle == handle then
				pending.aborted = true
			end
		end
	end

	local function make_timer(seconds, callback, periodic)
		local timer = { seconds = seconds, callback = callback, periodic = periodic, active = true }
		function timer.kill(this_timer)
			this_timer.active = false
		end
		timer.stop = timer.kill
		function timer.resume(this_timer)
			this_timer.active = true
		end
		function timer.is_enabled(this_timer)
			return this_timer.active
		end
		world.timers[#world.timers + 1] = timer
		return timer
	end
	function mp.add_periodic_timer(seconds, callback)
		return make_timer(seconds, callback, true)
	end
	function mp.add_timeout(seconds, callback)
		return make_timer(seconds, callback, false)
	end

	function mp.add_key_binding(key, name, callback, flags)
		world:log("add_key_binding: " .. tostring(key) .. " " .. tostring(name) .. " " .. json.encode(flags or {}))
		world.key_bindings[key] = callback
	end
	function mp.add_forced_key_binding(key, name, callback, flags)
		world.forced_bindings[name or key] = { key = key, callback = callback, flags = flags }
	end
	function mp.remove_key_binding(name)
		world.forced_bindings[name] = nil
	end

	function mp.register_event(name, callback)
		world:log("register_event: " .. name)
		world.events[name] = world.events[name] or {}
		table.insert(world.events[name], callback)
	end

	function mp.register_script_message(name, callback)
		world.script_messages[name] = callback
	end

	function mp.get_time()
		return 0
	end

	function mp.get_script_name()
		return "webm"
	end

	return mp
end

function World:make_msg()
	local world = self
	local messages = {}
	local function logger(level, recorded)
		return function(...)
			if recorded then
				world:log("msg." .. level .. ": " .. join_arguments(" ", ...))
			end
		end
	end
	messages.fatal = logger("fatal", true)
	messages.error = logger("error", true)
	messages.warn = logger("warn", true)
	messages.info = logger("info", true)
	-- Verbose and debug output is diagnostics, not behavior. The command lines
	-- it prints are already captured from the subprocess calls themselves.
	messages.verbose = logger("verbose", false)
	messages.debug = logger("debug", false)
	messages.trace = logger("trace", false)
	return messages
end

function World:make_utils()
	local world = self
	local utils = {}

	function utils.file_info(path)
		local content = world.files[path]
		if content == nil then
			return nil, "No such file or directory"
		end
		-- Directories are stored as true.
		if content == true then
			return { is_dir = true, is_file = false, size = 0 }
		end
		return { is_file = true, is_dir = false, size = world.settings.file_size or #content }
	end

	function utils.split_path(path)
		return world:split_path(path)
	end

	function utils.join_path(first, second)
		return world:join_path(first, second)
	end

	function utils.subprocess(command)
		local flags = {}
		for name, value in pairs(command) do
			if name ~= "args" then
				flags[name] = value
			end
		end
		world:log_block("subprocess " .. json.encode(flags) .. ":", command.args)
		local outcome = world:run_subprocess(command.args)
		if outcome.error_string and outcome.error_string ~= "" then
			outcome.error = outcome.error_string
		end
		return outcome
	end

	function utils.subprocess_detached(command)
		world:log_block("subprocess_detached:", command.args)
	end

	function utils.parse_json(text)
		return json.decode(text)
	end

	function utils.format_json(value)
		return json.encode(value)
	end

	function utils.getcwd()
		return world.settings.working_directory or "/home/tester"
	end

	return utils
end

-- read_options: applies webm.conf entries the way mp.options converts them to
-- the type of each default.
function World:make_options()
	local world = self
	local options = {}
	function options.read_options(script_options, identifier, on_update)
		-- Keep a reference so scenarios can dump the effective options. The
		-- script reads and writes this same table at runtime.
		world.options_table = script_options
		world:log("read_options: identifier=" .. tostring(identifier))
		local names = {}
		for name in pairs(world.conf_file) do
			names[#names + 1] = name
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local text = world.conf_file[name]
			local default = script_options[name]
			local kind = type(default)
			if default == nil then
				world:log("options: unknown key " .. name .. ", ignoring")
			elseif kind == "boolean" then
				if text == "yes" then
					script_options[name] = true
				elseif text == "no" then
					script_options[name] = false
				else
					world:log("options: bad boolean for " .. name .. ": " .. text)
				end
			elseif kind == "number" then
				if tonumber(text) then
					script_options[name] = tonumber(text)
				else
					world:log("options: bad number for " .. name .. ": " .. text)
				end
			else
				script_options[name] = text
			end
		end
	end
	return options
end

-- Same behavior as mpv's player/lua/assdraw.lua for the calls the script uses.
-- Drawing commands are written at 2^(scale - 1) times the given coordinates.
local ASSDRAW_DEFAULT_SCALE = 4

local function make_assdraw()
	local Drawing = {}
	Drawing.__index = Drawing

	local function ass_new()
		return setmetatable({ scale = ASSDRAW_DEFAULT_SCALE, text = "" }, Drawing)
	end

	function Drawing.new_event(drawing)
		if #drawing.text > 0 then
			drawing.text = drawing.text .. "\n"
		end
	end
	function Drawing.draw_start(drawing)
		drawing.text = string.format("%s{\\p%d}", drawing.text, drawing.scale)
	end
	function Drawing.draw_stop(drawing)
		drawing.text = drawing.text .. "{\\p0}"
	end
	function Drawing.coord(drawing, x, y)
		local multiplier = 2 ^ (drawing.scale - 1)
		drawing.text = string.format("%s %d %d", drawing.text, math.ceil(x * multiplier), math.ceil(y * multiplier))
	end
	function Drawing.append(drawing, text)
		drawing.text = drawing.text .. text
	end
	function Drawing.merge(drawing, other)
		drawing.text = drawing.text .. other.text
	end
	function Drawing.pos(drawing, x, y)
		drawing:append(string.format("{\\pos(%f,%f)}", x, y))
	end
	function Drawing.an(drawing, alignment)
		drawing:append(string.format("{\\an%d}", alignment))
	end
	function Drawing.move_to(drawing, x, y)
		drawing:append(" m")
		drawing:coord(x, y)
	end
	function Drawing.line_to(drawing, x, y)
		drawing:append(" l")
		drawing:coord(x, y)
	end
	function Drawing.rect_cw(drawing, left, top, right, bottom)
		drawing:move_to(left, top)
		drawing:line_to(right, top)
		drawing:line_to(right, bottom)
		drawing:line_to(left, bottom)
	end

	return { ass_new = ass_new }
end

function World:make_os()
	local world = self
	local fake = {}
	function fake.getenv(name)
		return world.environment[name]
	end
	function fake.date(format, unix_time)
		format = format or "%c"
		-- A leading "!" means UTC, so the result doesn't depend on the time zone.
		if format:sub(1, 1) ~= "!" then
			format = "!" .. format
		end
		return os.date(format, unix_time or FIXED_UNIX_TIME)
	end
	function fake.time()
		return FIXED_UNIX_TIME
	end
	fake.clock = os.clock
	function fake.remove(path)
		local existed = world.files[path] ~= nil
		world.files[path] = nil
		world:log("os.remove: " .. path .. (existed and "" or " (missing)"))
		if existed then
			return true
		end
		return nil, path .. ": No such file or directory"
	end
	function fake.tmpname()
		world.temporary_file_count = world.temporary_file_count + 1
		return "/tmp/lua_tmp" .. world.temporary_file_count
	end
	function fake.exit()
		error("os.exit called")
	end
	function fake.execute(command)
		world:log("os.execute: " .. tostring(command))
		return EXIT_SUCCESS
	end
	return fake
end

function World:make_io()
	local world = self
	local fake = {}

	local function reader(content)
		local file = { position = 1, content = content }
		function file.read(this_file, format)
			format = format or "*l"
			if this_file.position > #this_file.content then
				return nil
			end
			if format == "*a" or format == "a" then
				local rest = this_file.content:sub(this_file.position)
				this_file.position = #this_file.content + 1
				return rest
			end
			local newline = this_file.content:find("\n", this_file.position, true)
			local line_end = newline or #this_file.content + 1
			local line = this_file.content:sub(this_file.position, line_end - 1)
			this_file.position = line_end + 1
			return line
		end
		function file.lines(this_file)
			return function()
				return this_file:read("*l")
			end
		end
		function file.close()
			return true
		end
		return file
	end

	function fake.open(path, mode)
		mode = mode or "r"
		local access = mode:sub(1, 1)
		if access == "r" then
			local content = world.files[path]
			if type(content) ~= "string" then
				return nil, path .. ": No such file or directory"
			end
			return reader(content)
		end
		local buffer = {}
		if access == "a" and type(world.files[path]) == "string" then
			buffer[1] = world.files[path]
		end
		local file = {}
		function file.write(this_file, ...)
			buffer[#buffer + 1] = join_arguments("", ...)
			return this_file
		end
		function file.close()
			local content = table.concat(buffer)
			world.files[path] = content
			world:log("io.write: " .. path .. " <- " .. json.encode(content))
			return true
		end
		return file
	end

	function fake.popen(command)
		world:log("io.popen: " .. command)
		return reader("")
	end

	function fake.lines(path)
		return reader(world.files[path] or ""):lines()
	end

	return fake
end

-- pairs() in sorted key order. Real hash order differs between PUC Lua and
-- LuaJIT (and between LuaJIT builds), and a few script outputs depend on it.
-- Giving the sandbox a canonical order keeps the goldens runtime-independent.
-- Numbers sort first, then strings, then booleans, then anything else.
local KEY_TYPE_RANK = { number = 1, string = 2, boolean = 3 }
local OTHER_KEY_RANK = 4

local function key_comes_first(first, second)
	local first_type, second_type = type(first), type(second)
	if first_type ~= second_type then
		return (KEY_TYPE_RANK[first_type] or OTHER_KEY_RANK) < (KEY_TYPE_RANK[second_type] or OTHER_KEY_RANK)
	end
	if first_type == "number" or first_type == "string" then
		return first < second
	end
	return tostring(first) < tostring(second)
end

local function sorted_pairs(target)
	local keys = {}
	for key in next, target do
		keys[#keys + 1] = key
	end
	table.sort(keys, key_comes_first)
	local index = 0
	return function()
		while true do
			index = index + 1
			local key = keys[index]
			if key == nil then
				return nil
			end
			-- Skip keys removed during traversal, as next() would.
			local value = rawget(target, key)
			if value ~= nil then
				return key, value
			end
		end
	end,
		target,
		nil
end

-- Loading -----------------------------------------------------------------

function World:load_script(script_path)
	local file = assert(io.open(script_path, "rb"))
	local source = file:read("*a")
	file:close()

	local chunk, compile_error = loadstring(source, "=webm.lua")
	if not chunk then
		error("cannot compile " .. script_path .. ": " .. compile_error)
	end

	---@type table<string, any>
	local modules = {
		mp = self:make_mp(),
		["mp.msg"] = self:make_msg(),
		["mp.utils"] = self:make_utils(),
		["mp.options"] = self:make_options(),
		["mp.assdraw"] = make_assdraw(),
	}
	self.mp = modules.mp

	local environment = setmetatable({}, { __index = _G })
	environment._G = environment
	environment.pairs = sorted_pairs
	-- Like the real require: already loaded modules first (the mp modules
	-- start there), then the loaders the bundle put in package.preload.
	environment.require = function(name)
		if modules[name] == nil then
			local loader = environment.package.preload[name]
			if not loader then
				error("module '" .. name .. "' not found")
			end
			local loaded = loader(name)
			modules[name] = loaded == nil and true or loaded
		end
		return modules[name]
	end
	-- package.config starts with the platform's directory separator.
	environment.package = {
		config = (self.platform == "windows" and "\\" or "/") .. "\n;\n?\n!\n-\n",
		path = "",
		cpath = "",
		loaded = modules,
		preload = {},
	}
	environment.os = self:make_os()
	environment.io = self:make_io()
	environment.print = function(...)
		self:log("print: " .. join_arguments("\t", ...))
	end
	setfenv(chunk, environment)
	self:protected(chunk)
end

-- Runs the function, turning script errors into a transcript line. Line
-- numbers are dropped so the goldens do not depend on the layout of the
-- built file.
function World:protected(callback, ...)
	local arguments = { ... }
	local argument_count = select("#", ...)
	local succeeded, message = xpcall(function()
		return callback(unpack(arguments, 1, argument_count))
	end, function(error_value)
		return tostring(error_value)
	end)
	if not succeeded then
		message = message:gsub("webm%.lua:%d+: ", "webm.lua: ")
		-- Errors are always recorded, even inside quiet steps.
		self.lines[#self.lines + 1] = "SCRIPT ERROR: " .. message
	end
	return succeeded
end

-- Scenario actions ----------------------------------------------------------

function World:press(key)
	for _, binding in pairs(self.forced_bindings) do
		if binding.key == key then
			return self:protected(binding.callback)
		end
	end
	if self.key_bindings[key] then
		return self:protected(self.key_bindings[key])
	end
	self:log("key " .. key .. ": not bound")
end

function World:script_message(name, ...)
	local handler = self.script_messages[name]
	if not handler then
		self:log("script-message " .. name .. ": no handler")
		return
	end
	return self:protected(handler, ...)
end

function World:fire_event(name)
	for _, handler in ipairs(self.events[name] or {}) do
		self:protected(handler, { event = name })
	end
end

function World:run_pending_commands()
	local pending_commands = self.pending_commands
	self.pending_commands = {}
	for _, pending in ipairs(pending_commands) do
		if pending.aborted then
			local killed = { status = KILLED_STATUS, killed_by_us = true, error_string = "killed" }
			self:protected(pending.callback, false, killed, "killed")
		else
			local success, outcome, message = self:asynchronous_result(pending.command)
			self:protected(pending.callback, success, outcome, message)
		end
	end
end

-- Lets every pending encoder command finish, including passes they start.
-- Scenarios with hold_encoders keep them pending until run_pending_commands.
function World:finish_encoders()
	if self.settings.hold_encoders then
		return
	end
	while true do
		local encoder = nil
		for index, pending in ipairs(self.pending_commands) do
			if (pending.command.args or {})[1] == "mpv" then
				encoder = table.remove(self.pending_commands, index)
				break
			end
		end
		if not encoder then
			return
		end
		local success, outcome, message = self:asynchronous_result(encoder.command)
		self:protected(encoder.callback, success, outcome, message)
	end
end

function World:fire_timers()
	for _, timer in ipairs(self.timers) do
		if timer.active then
			if not timer.periodic then
				timer.active = false
			end
			self:protected(timer.callback)
		end
	end
end

function World:active_bindings()
	local keys = {}
	for _, binding in pairs(self.forced_bindings) do
		keys[#keys + 1] = binding.key
	end
	table.sort(keys)
	return keys
end

fake_mpv.json = json
fake_mpv.property_to_string = property_to_string
return fake_mpv
