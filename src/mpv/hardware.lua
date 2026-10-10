-- Reads the CPU and GPU names from the operating system, once. src/core/device.lua
-- turns the output into the device each format encodes on.

local utils = require("mp.utils")

local device = require("core.device")
local system = require("mpv.system")

local M = {}

local DISPLAY_ADAPTER_CLASS = [[HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}]]
local FIRST_PROCESSOR = [[HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0]]
-- The render device VAAPI opens unless told otherwise.
local DEFAULT_RENDER_DEVICE = "/sys/class/drm/renderD128/device/uevent"

-- What the command printed. Kept even when it exits with an error, since reg
-- can print every value and still fail on a key it isn't allowed to read.
local function output_of(arguments)
	local result = utils.subprocess({ args = arguments, playback_only = false, capture_stdout = true })
	return result and result.stdout or ""
end

local function file_text(path)
	local file = io.open(path, "r")
	if not file then
		return ""
	end
	local text = file:read("*a") or ""
	file:close()
	return text
end

local function detect_windows()
	return {
		platform = "windows",
		cpu = device.registry_value(
			output_of({ "reg", "query", FIRST_PROCESSOR, "/v", "ProcessorNameString" }),
			"ProcessorNameString"
		),
		gpus = device.windows_gpus(
			output_of({ "reg", "query", DISPLAY_ADAPTER_CLASS, "/s", "/v", "DriverDesc" }),
			output_of({ "reg", "query", DISPLAY_ADAPTER_CLASS, "/s", "/v", "HardwareInformation.qwMemorySize" })
		),
	}
end

local function detect_macos()
	local cpu = output_of({ "sysctl", "-n", "machdep.cpu.brand_string" }):match("^%s*(.-)%s*$")
	return { platform = "macos", cpu = cpu ~= "" and cpu or nil, gpus = {} }
end

local function detect_linux()
	return {
		platform = "linux",
		cpu = device.linux_cpu(file_text("/proc/cpuinfo")),
		gpus = device.lspci_gpus(output_of({ "lspci" })),
		vaapi_slot = device.uevent_slot(file_text(DEFAULT_RENDER_DEVICE)),
	}
end

local detected = nil

---@return webm.Hardware
function M.detect()
	if detected == nil then
		if system.is_windows then
			detected = detect_windows()
		elseif system.is_macos then
			detected = detect_macos()
		else
			detected = detect_linux()
		end
	end
	return detected
end

---What the options page shows for a format.
---@param format webm.Format
---@return string
function M.describe(format)
	return device.describe(format.device, M.detect())
end

return M
