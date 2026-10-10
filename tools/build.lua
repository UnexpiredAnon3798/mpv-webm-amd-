-- Builds build/webm.lua and build/webm.conf from src/.
--
-- Usage, from the repository root: luajit tools/build.lua
-- Runs on Lua 5.1 to 5.4 and LuaJIT.

local tools_dir = arg[0]:match("^(.*[/\\])") or "./"
package.path = tools_dir .. "?.lua;" .. package.path

local bundle = require("bundle")
local conf = require("conf")

-- Every module under src/, stored in package.preload. Listed by hand so the
-- build does not depend on a directory listing library. A module missing here
-- fails at runtime with "module not found", which the golden tests catch.
local MODULES = {
	"core.base64",
	"core.bitrate",
	"core.device",
	"core.filename",
	"core.filters",
	"core.geometry",
	"core.options",
	"core.paths",
	"core.speed",
	"core.time",
	"core.upload",
	"encode.check",
	"encode.command",
	"encode.formats",
	"encode.progress",
	"encode.source",
	"encode.vp8_log",
	"mpv.encoder",
	"mpv.events",
	"mpv.hardware",
	"mpv.host",
	"mpv.options",
	"mpv.system",
	"mpv.testing",
	"ui.crop_page",
	"ui.main_page",
	"ui.options_page",
	"ui.osd",
	"ui.page",
	"ui.preview_page",
	"ui.upload_page",
	"ui.video",
}

local MAIN = "src/main.lua"
local BUILD_DIR = "build"
local is_windows = package.config:sub(1, 1) == "\\"

local function read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	-- Windows checkouts may have CRLF line endings.
	return (text:gsub("\r\n", "\n"))
end

local function write(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

-- os.execute returns a status number on Lua 5.1 and LuaJIT, and true/nil on 5.2+.
local function run(command)
	local result = os.execute(command)
	return result == 0 or result == true
end

local function ensure_build_dir()
	local command = is_windows and ("if not exist " .. BUILD_DIR .. " mkdir " .. BUILD_DIR)
		or ("mkdir -p " .. BUILD_DIR)
	assert(run(command), "could not create " .. BUILD_DIR)
end

local function module_path(name)
	return "src/" .. name:gsub("%.", "/") .. ".lua"
end

local function main()
	ensure_build_dir()

	local modules = {}
	for _, name in ipairs(MODULES) do
		modules[#modules + 1] = { name = name, source = read(module_path(name)) }
	end

	write(
		BUILD_DIR .. "/webm.lua",
		bundle.bundle({
			header = "mpv-webm, built from src/ by tools/build.lua. Edit the sources, not this file.",
			modules = modules,
			chunks = { { name = MAIN, source = read(MAIN) } },
		})
	)
	print("Wrote " .. BUILD_DIR .. "/webm.lua")

	-- loadstring is gone in Lua 5.2+, where load takes a string instead.
	local load_string = loadstring or load
	local options = assert(load_string(read("src/core/options.lua"), "=src/core/options.lua"))()
	write(BUILD_DIR .. "/webm.conf", conf.generate(options.definitions))
	print("Wrote " .. BUILD_DIR .. "/webm.conf")
end

main()
