-- Works out which CPU or GPU an output format encodes on, from what the
-- operating system reports. The reading itself is in src/mpv/hardware.lua.

local M = {}

---@alias webm.DeviceKind "cpu"|"nvidia"|"amd"|"vaapi"

---@class webm.Gpu
---@field name string
---@field vendor "nvidia"|"amd"|"intel"|"other"
---@field memory number bytes, 0 when unknown
---@field slot? string PCI slot on Linux, such as "03:00.0"

---@class webm.Hardware
---@field platform "windows"|"linux"|"macos"
---@field cpu? string
---@field gpus webm.Gpu[]
---@field vaapi_slot? string PCI slot of Linux's default render device

local VENDOR_NAMES = { nvidia = "NVIDIA", amd = "AMD" }

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param name string
---@return "nvidia"|"amd"|"intel"|"other"
function M.vendor_of(name)
	local lower = name:lower()
	if lower:find("nvidia", 1, true) then
		return "nvidia"
	elseif lower:find("amd", 1, true) or lower:find("radeon", 1, true) then
		return "amd"
	elseif lower:find("intel", 1, true) then
		return "intel"
	end
	return "other"
end

---The value of the first registry entry with this name in `reg query` output.
---@param output string
---@param value_name string
---@return string?
function M.registry_value(output, value_name)
	for line in output:gmatch("[^\r\n]+") do
		local name, value = line:match("^%s+(%S+)%s+REG_%S+%s+(.-)%s*$")
		if name == value_name then
			return value
		end
	end
end

-- Reads a REG_QWORD value such as "0x2ff000000". Done by hand because
-- tonumber overflows on values over 4 GB with Lua 5.1 on Windows.
local function parse_hex(text)
	local digits = text and text:match("^0[xX](%x+)$")
	if not digits then
		return 0
	end
	local value = 0
	for digit in digits:gmatch("%x") do
		value = value * 16 + tonumber(digit, 16)
	end
	return value
end

-- Values of one registry entry for every key in `reg query /s` output, by key.
local function registry_values_by_key(output, value_name)
	local values = {}
	local key
	for line in output:gmatch("[^\r\n]+") do
		if line:match("^HKEY_") then
			key = line
		else
			local name, value = line:match("^%s+(%S+)%s+REG_%S+%s+(.-)%s*$")
			if key and name == value_name then
				values[key] = value
			end
		end
	end
	return values
end

---GPUs from `reg query` of the display adapter class, run once for DriverDesc
---and once for HardwareInformation.qwMemorySize. Listed in registry order.
---@param names_output string
---@param memory_output string
---@return webm.Gpu[]
function M.windows_gpus(names_output, memory_output)
	local names = registry_values_by_key(names_output, "DriverDesc")
	local memory = registry_values_by_key(memory_output, "HardwareInformation.qwMemorySize")
	local keys = {}
	for key in pairs(names) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local gpus = {}
	for _, key in ipairs(keys) do
		gpus[#gpus + 1] = {
			name = names[key],
			vendor = M.vendor_of(names[key]),
			memory = parse_hex(memory[key]),
		}
	end
	return gpus
end

---The "model name" line of /proc/cpuinfo.
---@param cpuinfo string
---@return string?
function M.linux_cpu(cpuinfo)
	local name = cpuinfo:match("model name%s*:%s*([^\n]+)")
	return name and trim(name)
end

-- lspci writes the full company name before the model.
local LSPCI_VENDOR_PREFIXES = {
	{ "^Advanced Micro Devices, Inc%. %[AMD/ATI%] ", "AMD " },
	{ "^NVIDIA Corporation ", "NVIDIA " },
	{ "^Intel Corporation ", "Intel " },
}

---GPUs from `lspci` output: VGA, 3D and display controllers.
---@param output string
---@return webm.Gpu[]
function M.lspci_gpus(output)
	local gpus = {}
	for line in output:gmatch("[^\r\n]+") do
		local slot, class, name = line:match("^(%S+) ([^:]+): (.+)$")
		if class and (class:find("VGA", 1, true) or class:find("3D", 1, true) or class:find("Display", 1, true)) then
			name = trim((name:gsub("%s*%(rev %x+%)$", "")))
			local vendor = M.vendor_of(name)
			for _, prefix in ipairs(LSPCI_VENDOR_PREFIXES) do
				name = name:gsub(prefix[1], prefix[2])
			end
			gpus[#gpus + 1] = { name = name, vendor = vendor, memory = 0, slot = slot }
		end
	end
	return gpus
end

---The PCI slot in a /sys/class/drm/renderD128/device/uevent file, without the
---leading "0000:" domain that lspci leaves out.
---@param uevent string
---@return string?
function M.uevent_slot(uevent)
	local slot = uevent:match("PCI_SLOT_NAME=([%x:.]+)")
	return slot and (slot:gsub("^0000:", ""))
end

---The GPU of a vendor that the encoder uses: the one with the most memory,
---or the first one listed when the memory is unknown.
---@param gpus webm.Gpu[]
---@param vendor string
---@return webm.Gpu?
function M.pick_gpu(gpus, vendor)
	local best
	for _, gpu in ipairs(gpus) do
		if gpu.vendor == vendor and (best == nil or gpu.memory > best.memory) then
			best = gpu
		end
	end
	return best
end

---What the options page shows for a device kind.
---@param kind webm.DeviceKind
---@param hardware webm.Hardware
---@return string
function M.describe(kind, hardware)
	if kind == "cpu" then
		return (hardware.cpu or "unknown") .. " (CPU)"
	end
	if kind == "vaapi" then
		if hardware.platform ~= "linux" then
			return "VAAPI only works on Linux"
		end
		for _, gpu in ipairs(hardware.gpus) do
			if hardware.vaapi_slot and gpu.slot == hardware.vaapi_slot then
				return gpu.name .. " (GPU)"
			end
		end
		return "no VAAPI device found"
	end
	local gpu = M.pick_gpu(hardware.gpus, kind)
	if gpu then
		return gpu.name .. " (GPU)"
	end
	return "no " .. VENDOR_NAMES[kind] .. " GPU found"
end

return M
