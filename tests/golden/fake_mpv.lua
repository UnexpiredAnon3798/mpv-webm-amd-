-- A scripted stand-in for mpv's Lua API, used by the golden tests.
--
-- It loads a built webm.lua into a sandbox whose mp, mp.msg, mp.utils,
-- mp.options and mp.assdraw modules, along with os and io, are fakes. Every
-- observable side effect the script has (subprocess argv, OSD text, emitted
-- script-messages, properties set, files written or removed) is appended to
-- a transcript. The transcript is what the golden files pin down.
--
-- Only the script's external surface is driven: key presses, script-messages
-- and events. Internal functions are never called directly, so the same
-- goldens apply to any implementation that behaves the same.
--
-- Deliberate simplifications (see README.md): properties are a plain table,
-- observers fire synchronously and only for properties a scenario changes,
-- async commands and timers run only when a scenario asks.

local json = dofile(GOLDEN_DIR .. "json.lua")

local M = {}

-- Fixed clock for os.date/os.time: 2024-03-09 13:45:30 UTC.
local FIXED_TIME = 1709991930

local World = {}
World.__index = World

local function shallow_copy(t)
	local out = {}
	for k, v in pairs(t or {}) do
		out[k] = v
	end
	return out
end

-- Render a property value the way mpv's string conversion would.
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

function M.new(cfg)
	local self = setmetatable({}, World)
	self.cfg = cfg
	self.platform = cfg.platform or "unix"
	self.lines = {}
	self.props = shallow_copy(cfg.props)
	self.osd_props = shallow_copy(cfg.osd_props)
	self.fs = shallow_copy(cfg.files)
	self.env = shallow_copy(cfg.env)
	self.conf = cfg.conf or {}
	self.osd_w = cfg.osd_w or 1280
	self.osd_h = cfg.osd_h or 720
	self.mouse_x, self.mouse_y = 0, 0
	self.script_messages = {}
	self.key_bindings = {}
	self.forced_bindings = {}
	self.events = {}
	self.observers = {}
	self.pending_async = {}
	self.timers = {}
	self.next_tmp = 0
	self.next_handle = 0
	self.quiet = 0
	return self
end

function World:log(line)
	if self.quiet == 0 then
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

function World:is_absolute(p)
	if self.platform == "windows" then
		return p:match("^[A-Za-z]:[/\\]") ~= nil or p:match("^[/\\]") ~= nil
	end
	return p:sub(1, 1) == "/"
end

function World:basename_start(p)
	local pattern = self.platform == "windows" and "^.*()[/\\:]" or "^.*()/"
	local last = p:match(pattern)
	return last and last + 1 or 1
end

-- mp_dirname / mp_basename semantics.
function World:split_path(p)
	local start = self:basename_start(p)
	local dir = p:sub(1, start - 1)
	if dir == "" then
		dir = "."
	end
	return dir, p:sub(start)
end

-- mp_path_join semantics.
function World:join_path(p1, p2)
	if p1 == "" then
		return p2
	end
	if p2 == "" then
		return p1
	end
	if self:is_absolute(p2) then
		return p2
	end
	local last = p1:sub(-1)
	local has_sep = last == "/" or (self.platform == "windows" and (last == "\\" or last == ":"))
	return p1 .. (has_sep and "" or "/") .. p2
end

-- Properties ----------------------------------------------------------------

local NOT_FOUND = "property not found"

function World:get_native(name)
	return self.props[name]
end

function World:set_prop(name, value)
	self.props[name] = value
	for _, obs in ipairs(self.observers) do
		if obs.name == name then
			obs.fn(name, value)
		end
	end
end

-- Subprocess responders ---------------------------------------------------

local function has_arg(args, wanted)
	for _, a in ipairs(args) do
		if a == wanted then
			return true
		end
	end
	return false
end

local function find_arg_value(args, prefix)
	for _, a in ipairs(args) do
		if a:sub(1, #prefix) == prefix then
			return a:sub(#prefix + 1)
		end
	end
end

-- A fake libvpx first-pass log: two frame records plus the aggregate record,
-- 18 doubles each. The bytes are a fixed pattern; only the duration field is
-- interpreted, and the patcher rewrites it.
local function fake_vp8_stats_bytes()
	local bytes = {}
	for i = 1, 3 * 18 * 8 do
		bytes[i] = string.char((i * 37) % 256)
	end
	return table.concat(bytes)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local chars = {}
		for j = 3, 0, -1 do
			local idx = math.floor(n / 64 ^ j) % 64
			chars[#chars + 1] = B64:sub(idx + 1, idx + 1)
		end
		if not b then
			chars[3], chars[4] = "=", "="
		elseif not c then
			chars[4] = "="
		end
		out[#out + 1] = table.concat(chars)
	end
	return table.concat(out)
end

function World:run_subprocess(args)
	local cfg = self.cfg
	if args[1] == "mpv" and args[2] == "--no-config" and args[3] == "--version" then
		return shallow_copy(cfg.encoder_check or { status = 0, stdout = "mpv 0.40.0\n", error_string = "" })
	end
	if args[2] == "--version" then
		-- The curl availability probe.
		return shallow_copy(cfg.curl or { status = 0, stdout = "curl 8.0.0\n", error_string = "" })
	end
	if args[1] == "mpv" then
		local out = find_arg_value(args, "--o=")
		self.last_out = out
		if has_arg(args, "--ovcopts-add=flags=+pass1") then
			if cfg.first_pass_status and cfg.first_pass_status ~= 0 then
				return { status = cfg.first_pass_status, stdout = "", error_string = "" }
			end
			if out and find_arg_value(args, "--ovc=") == "libvpx" then
				self.fs[out .. "-video-pass1.log"] = base64(fake_vp8_stats_bytes())
			end
			return { status = 0, stdout = "", error_string = "" }
		end
		local status = cfg.encode_status or 0
		if status == 0 and out then
			self.fs[out] = "encoded"
		end
		return { status = status, stdout = "", error_string = "" }
	end
	return { status = 0, stdout = "", error_string = "" }
end

-- Popen'd encodes (progress display). Lines mimic mpv's terminal output.
function World:popen_output(command_line)
	if self.cfg.popen_lines then
		return self.cfg.popen_lines
	end
	return {
		"[encode] Opening output file",
		"Encode time-pos: 2.000000",
		"Encode time-pos: 1.000000",
		"Encode time-pos: 3.500000",
		"Exiting... (End of file)",
	}
end

-- Async subprocess (uploads, clipboard tools).
function World:async_result(t)
	local args = t.args or {}
	if args[1] == (self.cfg.curl_path or "curl") then
		local response_path = args[(function()
			for i, a in ipairs(args) do
				if a == "-o" then
					return i + 1
				end
			end
		end)()]
		local upload = self.cfg.upload or { status = 0, http = "200", body = "https://files.catbox.moe/abc123.mp4\n" }
		if response_path then
			self.fs[response_path] = upload.body
		end
		return upload.status == 0,
			{
				status = upload.status,
				stdout = upload.http,
				error_string = upload.error_string or "",
				killed_by_us = false,
			},
			nil
	end
	return true, { status = 0, stdout = "", error_string = "" }, nil
end

-- Module construction -----------------------------------------------------

function World:make_mp()
	local world = self
	local mp = {}

	function mp.get_property(name, def)
		local v = world.props[name]
		if v == nil then
			return def, NOT_FOUND
		end
		return property_to_string(v)
	end

	function mp.get_property_osd(name, def)
		local v = world.osd_props[name]
		if v == nil and world.props[name] ~= nil then
			v = property_to_string(world.props[name])
		end
		if v == nil then
			if def == nil then
				return "", NOT_FOUND
			end
			return def, NOT_FOUND
		end
		return v
	end

	function mp.get_property_native(name, def)
		local v = world.props[name]
		if v == nil then
			return def, NOT_FOUND
		end
		if type(v) == "table" then
			-- mpv hands out a fresh table on every call.
			return json.decode(json.encode(v))
		end
		return v
	end

	function mp.get_property_number(name, def)
		local v = world.props[name]
		if type(v) == "string" then
			v = tonumber(v)
		end
		if type(v) ~= "number" then
			return def, NOT_FOUND
		end
		return v
	end

	function mp.get_property_bool(name, def)
		local v = world.props[name]
		if v == "yes" then
			return true
		elseif v == "no" then
			return false
		elseif type(v) == "boolean" then
			return v
		end
		return def, NOT_FOUND
	end

	local function set(kind, name, value)
		if name == "clipboard/text" and world.cfg.clipboard_property == false then
			world:log(kind .. ": " .. name .. " (rejected)")
			return nil, NOT_FOUND
		end
		world:log(kind .. ": " .. name .. " = " .. json.encode(value))
		world.props[name] = value
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

	function mp.observe_property(name, kind, fn)
		world.observers[#world.observers + 1] = { name = name, fn = fn }
	end
	function mp.unobserve_property(fn)
		local kept = {}
		for _, obs in ipairs(world.observers) do
			if obs.fn ~= fn then
				kept[#kept + 1] = obs
			end
		end
		world.observers = kept
	end

	function mp.osd_message(text, duration)
		world:log("osd_message(" .. tostring(duration) .. "): " .. tostring(text))
	end

	function mp.set_osd_ass(w, h, text)
		if text == "" then
			world:log(string.format("osd_ass %dx%d: <clear>", w, h))
			return
		end
		local lines = {}
		for line in (text .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = line
		end
		world:log_block(string.format("osd_ass %dx%d:", w, h), lines)
	end

	function mp.get_osd_size()
		return world.osd_w, world.osd_h
	end

	function mp.get_mouse_pos()
		return world.mouse_x, world.mouse_y
	end

	function mp.commandv(...)
		local args = { ... }
		if args[1] == "script-message" then
			world:log("event: " .. table.concat(args, " ", 2))
			return true
		end
		world:log("commandv: " .. json.encode(args))
		return true
	end

	function mp.command(cmd)
		world:log("command: " .. cmd)
		return true
	end

	function mp.command_native(t)
		world:log("command_native: " .. json.encode(t))
		if t[1] == "dump_cache" then
			world.fs[t[4]] = "cache"
		end
		return {}
	end

	function mp.command_native_async(t, cb)
		world.next_handle = world.next_handle + 1
		local handle = { id = world.next_handle }
		local copy = shallow_copy(t)
		local args = copy.args
		copy.args = nil
		world:log_block("command_native_async #" .. handle.id .. " " .. json.encode(copy) .. ":", args or {})
		world.pending_async[#world.pending_async + 1] = { handle = handle, t = t, cb = cb }
		return handle
	end

	function mp.abort_async_command(handle)
		world:log("abort_async_command #" .. handle.id)
		for _, p in ipairs(world.pending_async) do
			if p.handle == handle then
				p.aborted = true
			end
		end
	end

	local function make_timer(seconds, fn, periodic)
		local timer = { seconds = seconds, fn = fn, periodic = periodic, active = true }
		function timer.kill(t)
			t.active = false
		end
		timer.stop = timer.kill
		function timer.resume(t)
			t.active = true
		end
		function timer.is_enabled(t)
			return t.active
		end
		world.timers[#world.timers + 1] = timer
		return timer
	end
	function mp.add_periodic_timer(seconds, fn)
		return make_timer(seconds, fn, true)
	end
	function mp.add_timeout(seconds, fn)
		return make_timer(seconds, fn, false)
	end

	function mp.add_key_binding(key, name, fn, flags)
		world:log("add_key_binding: " .. tostring(key) .. " " .. tostring(name) .. " " .. json.encode(flags or {}))
		world.key_bindings[key] = fn
	end
	function mp.add_forced_key_binding(key, name, fn, flags)
		world.forced_bindings[name or key] = { key = key, fn = fn, flags = flags }
	end
	function mp.remove_key_binding(name)
		world.forced_bindings[name] = nil
	end

	function mp.register_event(name, fn)
		world:log("register_event: " .. name)
		world.events[name] = world.events[name] or {}
		table.insert(world.events[name], fn)
	end

	function mp.register_script_message(name, fn)
		world.script_messages[name] = fn
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
	local msg = {}
	local function logger(level, record)
		return function(...)
			if not record then
				return
			end
			local parts = {}
			for i = 1, select("#", ...) do
				parts[#parts + 1] = tostring((select(i, ...)))
			end
			world:log("msg." .. level .. ": " .. table.concat(parts, " "))
		end
	end
	msg.fatal = logger("fatal", true)
	msg.error = logger("error", true)
	msg.warn = logger("warn", true)
	msg.info = logger("info", true)
	-- Verbose/debug output is diagnostics, not behavior; the command lines it
	-- prints are already captured from the subprocess calls themselves.
	msg.verbose = logger("verbose", false)
	msg.debug = logger("debug", false)
	msg.trace = logger("trace", false)
	return msg
end

function World:make_utils()
	local world = self
	local utils = {}

	function utils.file_info(path)
		if world.fs[path] ~= nil then
			if world.fs[path] == true then
				return { is_dir = true, is_file = false, size = 0 }
			end
			return { is_file = true, is_dir = false, size = world.cfg.file_size or #world.fs[path] }
		end
		return nil, "No such file or directory"
	end

	function utils.split_path(p)
		return world:split_path(p)
	end

	function utils.join_path(a, b)
		return world:join_path(a, b)
	end

	function utils.subprocess(t)
		local flags = {}
		for k, v in pairs(t) do
			if k ~= "args" then
				flags[k] = v
			end
		end
		world:log_block("subprocess " .. json.encode(flags) .. ":", t.args)
		local res = world:run_subprocess(t.args)
		if res.error_string and res.error_string ~= "" then
			res.error = res.error_string
		end
		return res
	end

	function utils.subprocess_detached(t)
		world:log_block("subprocess_detached:", t.args)
	end

	function utils.parse_json(s)
		return json.decode(s)
	end

	function utils.format_json(v)
		return json.encode(v)
	end

	function utils.getcwd()
		return world.cfg.cwd or "/home/tester"
	end

	return utils
end

-- read_options: apply "key=value" overrides the way mp.options converts them
-- to the type of each default.
function World:make_options()
	local world = self
	local options = {}
	function options.read_options(tbl, identifier, on_update)
		-- Keep a reference so scenarios can dump the effective options. The
		-- script reads and writes this same table at runtime.
		world.options_table = tbl
		world:log("read_options: identifier=" .. tostring(identifier))
		local keys = {}
		for k in pairs(world.conf) do
			keys[#keys + 1] = k
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local raw = world.conf[key]
			local default = tbl[key]
			local kind = type(default)
			if default == nil then
				world:log("options: unknown key " .. key .. ", ignoring")
			elseif kind == "boolean" then
				if raw == "yes" then
					tbl[key] = true
				elseif raw == "no" then
					tbl[key] = false
				else
					world:log("options: bad boolean for " .. key .. ": " .. raw)
				end
			elseif kind == "number" then
				if tonumber(raw) then
					tbl[key] = tonumber(raw)
				else
					world:log("options: bad number for " .. key .. ": " .. raw)
				end
			else
				tbl[key] = raw
			end
		end
	end
	return options
end

-- Same behavior as mpv's player/lua/assdraw.lua for the calls the script uses.
local function make_assdraw()
	local ass_mt = {}
	ass_mt.__index = ass_mt

	local function ass_new()
		return setmetatable({ scale = 4, text = "" }, ass_mt)
	end

	function ass_mt.new_event(ass)
		if #ass.text > 0 then
			ass.text = ass.text .. "\n"
		end
	end
	function ass_mt.draw_start(ass)
		ass.text = string.format("%s{\\p%d}", ass.text, ass.scale)
	end
	function ass_mt.draw_stop(ass)
		ass.text = ass.text .. "{\\p0}"
	end
	function ass_mt.coord(ass, x, y)
		local scale = 2 ^ (ass.scale - 1)
		ass.text = string.format("%s %d %d", ass.text, math.ceil(x * scale), math.ceil(y * scale))
	end
	function ass_mt.append(ass, s)
		ass.text = ass.text .. s
	end
	function ass_mt.merge(ass1, ass2)
		ass1.text = ass1.text .. ass2.text
	end
	function ass_mt.pos(ass, x, y)
		ass:append(string.format("{\\pos(%f,%f)}", x, y))
	end
	function ass_mt.an(ass, an)
		ass:append(string.format("{\\an%d}", an))
	end
	function ass_mt.move_to(ass, x, y)
		ass:append(" m")
		ass:coord(x, y)
	end
	function ass_mt.line_to(ass, x, y)
		ass:append(" l")
		ass:coord(x, y)
	end
	function ass_mt.rect_cw(ass, x0, y0, x1, y1)
		ass:move_to(x0, y0)
		ass:line_to(x1, y0)
		ass:line_to(x1, y1)
		ass:line_to(x0, y1)
	end

	return { ass_new = ass_new }
end

function World:make_os()
	local world = self
	local fake = {}
	function fake.getenv(name)
		return world.env[name]
	end
	function fake.date(fmt, t)
		fmt = fmt or "%c"
		if fmt:sub(1, 1) ~= "!" then
			fmt = "!" .. fmt
		end
		return os.date(fmt, t or FIXED_TIME)
	end
	function fake.time()
		return FIXED_TIME
	end
	fake.clock = os.clock
	function fake.remove(path)
		local existed = world.fs[path] ~= nil
		world.fs[path] = nil
		world:log("os.remove: " .. path .. (existed and "" or " (missing)"))
		if existed then
			return true
		end
		return nil, path .. ": No such file or directory"
	end
	function fake.tmpname()
		world.next_tmp = world.next_tmp + 1
		return "/tmp/lua_tmp" .. world.next_tmp
	end
	function fake.exit()
		error("os.exit called")
	end
	function fake.execute(cmd)
		world:log("os.execute: " .. tostring(cmd))
		return 0
	end
	return fake
end

function World:make_io()
	local world = self
	local fake = {}

	local function reader(content, on_close)
		local f = { pos = 1, content = content }
		function f.read(file, fmt)
			fmt = fmt or "*l"
			if file.pos > #file.content then
				return nil
			end
			if fmt == "*a" or fmt == "a" then
				local rest = file.content:sub(file.pos)
				file.pos = #file.content + 1
				return rest
			end
			local nl = file.content:find("\n", file.pos, true)
			local line = file.content:sub(file.pos, (nl or #file.content + 1) - 1)
			file.pos = (nl or #file.content) + 1
			return line
		end
		function f.lines(file)
			return function()
				return file:read("*l")
			end
		end
		function f.close()
			if on_close then
				return on_close()
			end
			return true
		end
		return f
	end

	function fake.open(path, mode)
		mode = mode or "r"
		if mode:sub(1, 1) == "r" then
			local content = world.fs[path]
			if type(content) ~= "string" then
				return nil, path .. ": No such file or directory"
			end
			return reader(content)
		end
		local buffer = {}
		if mode:sub(1, 1) == "a" and type(world.fs[path]) == "string" then
			buffer[1] = world.fs[path]
		end
		local f = {}
		function f.write(file, ...)
			for i = 1, select("#", ...) do
				buffer[#buffer + 1] = tostring((select(i, ...)))
			end
			return file
		end
		function f.close()
			local content = table.concat(buffer)
			world.fs[path] = content
			world:log("io.write: " .. path .. " <- " .. json.encode(content))
			return true
		end
		return f
	end

	function fake.popen(cmd, mode)
		world:log("io.popen: " .. cmd)
		local content = table.concat(world:popen_output(cmd), "\n")
		return reader(content)
	end

	fake.lines = function(path)
		return reader(world.fs[path] or ""):lines()
	end

	return fake
end

-- pairs() in sorted key order. Real hash order differs between PUC Lua and
-- LuaJIT (and between LuaJIT builds), and a few script outputs depend on it.
-- Giving the sandbox a canonical order keeps the goldens runtime-independent.
local KEY_TYPE_RANK = { number = 1, string = 2, boolean = 3 }

local function key_less(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return (KEY_TYPE_RANK[ta] or 9) < (KEY_TYPE_RANK[tb] or 9)
	end
	if ta == "number" or ta == "string" then
		return a < b
	end
	return tostring(a) < tostring(b)
end

local function sorted_pairs(t)
	local keys = {}
	for k in next, t do
		keys[#keys + 1] = k
	end
	table.sort(keys, key_less)
	local i = 0
	return function()
		while true do
			i = i + 1
			local k = keys[i]
			if k == nil then
				return nil
			end
			-- Skip keys removed during traversal, as next() would.
			local v = rawget(t, k)
			if v ~= nil then
				return k, v
			end
		end
	end,
		t,
		nil
end

-- Loading -----------------------------------------------------------------

function World:load_script(script_path)
	local file = assert(io.open(script_path, "rb"))
	local source = file:read("*a")
	file:close()

	local chunk, err = loadstring(source, "=webm.lua")
	if not chunk then
		error("cannot compile " .. script_path .. ": " .. err)
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

	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.pairs = sorted_pairs
	-- Like the real require: already loaded modules first (the mp modules
	-- start there), then the loaders the bundle put in package.preload.
	env.require = function(name)
		if modules[name] == nil then
			local loader = env.package.preload[name]
			if not loader then
				error("module '" .. name .. "' not found")
			end
			local result = loader(name)
			modules[name] = result == nil and true or result
		end
		return modules[name]
	end
	env.package = {
		config = (self.platform == "windows" and "\\" or "/") .. "\n;\n?\n!\n-\n",
		path = "",
		cpath = "",
		loaded = modules,
		preload = {},
	}
	env.os = self:make_os()
	env.io = self:make_io()
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(i, ...)))
		end
		self:log("print: " .. table.concat(parts, "\t"))
	end
	setfenv(chunk, env)
	self.env_table = env
	self:protected(chunk)
end

-- Run fn, turning script errors into a transcript line. Line numbers are
-- dropped so the goldens do not depend on the layout of the built file.
function World:protected(fn, ...)
	local args = { ... }
	local n = select("#", ...)
	local ok, err = xpcall(function()
		return fn(unpack(args, 1, n))
	end, function(e)
		return tostring(e)
	end)
	if not ok then
		err = err:gsub("webm%.lua:%d+: ", "webm.lua: ")
		-- Errors are always recorded, even inside quiet steps.
		self.lines[#self.lines + 1] = "SCRIPT ERROR: " .. err
	end
	return ok
end

-- Scenario actions ----------------------------------------------------------

function World:press(key)
	for _, b in pairs(self.forced_bindings) do
		if b.key == key then
			return self:protected(b.fn)
		end
	end
	if self.key_bindings[key] then
		return self:protected(self.key_bindings[key])
	end
	self:log("key " .. key .. ": not bound")
end

function World:script_message(name, ...)
	local fn = self.script_messages[name]
	if not fn then
		self:log("script-message " .. name .. ": no handler")
		return
	end
	return self:protected(fn, ...)
end

function World:fire_event(name)
	for _, fn in ipairs(self.events[name] or {}) do
		self:protected(fn, { event = name })
	end
end

function World:run_async()
	local pending = self.pending_async
	self.pending_async = {}
	for _, p in ipairs(pending) do
		if p.aborted then
			self:protected(p.cb, false, { status = -2, killed_by_us = true, error_string = "killed" }, "killed")
		else
			local success, result, err = self:async_result(p.t)
			self:protected(p.cb, success, result, err)
		end
	end
end

function World:fire_timers()
	local timers = self.timers
	for _, t in ipairs(timers) do
		if t.active then
			if not t.periodic then
				t.active = false
			end
			self:protected(t.fn)
		end
	end
end

function World:active_bindings()
	local keys = {}
	for _, b in pairs(self.forced_bindings) do
		keys[#keys + 1] = b.key
	end
	table.sort(keys)
	return keys
end

M.json = json
M.property_to_string = property_to_string
return M
