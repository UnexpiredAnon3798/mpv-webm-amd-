local device = require("core.device")

-- What `reg query` prints for the display adapter class, in the format of a
-- real Windows machine with a discrete card and an integrated GPU.
local ADAPTER_CLASS =
	[[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}]]
local DISCRETE_MEMORY_HEX = "0x2ff000000" -- 12 GB
local INTEGRATED_MEMORY_HEX = "0x20000000" -- 512 MB

local REGISTRY_NAMES = table.concat({
	"",
	ADAPTER_CLASS .. [[\0000]],
	"    DriverDesc    REG_SZ    AMD Radeon RX 6700 XT",
	"",
	ADAPTER_CLASS .. [[\0001]],
	"    DriverDesc    REG_SZ    AMD Radeon(TM) Graphics",
	"",
	"End of search: 2 match(es) found.",
}, "\r\n")

local REGISTRY_MEMORY = table.concat({
	"",
	ADAPTER_CLASS .. [[\0000]],
	"    HardwareInformation.qwMemorySize    REG_QWORD    " .. DISCRETE_MEMORY_HEX,
	"",
	ADAPTER_CLASS .. [[\0001]],
	"    HardwareInformation.qwMemorySize    REG_QWORD    " .. INTEGRATED_MEMORY_HEX,
}, "\r\n")

local LSPCI = table.concat({
	"00:00.0 Host bridge: Advanced Micro Devices, Inc. [AMD] Root Complex",
	"01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060] (rev a1)",
	"03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] (rev c1)",
	"03:00.1 Audio device: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21/23 HDMI/DP Audio Controller",
	"10:00.0 Display controller: Intel Corporation Arc A310",
}, "\n")

describe("core.device on Windows", function()
	local gpus = device.windows_gpus(REGISTRY_NAMES, REGISTRY_MEMORY)

	it("reads every display adapter with its memory", function()
		assert.are.same({
			{ name = "AMD Radeon RX 6700 XT", vendor = "amd", memory = tonumber(DISCRETE_MEMORY_HEX) },
			{ name = "AMD Radeon(TM) Graphics", vendor = "amd", memory = tonumber(INTEGRATED_MEMORY_HEX) },
		}, gpus)
	end)

	it("reads the CPU name", function()
		local output = "\r\n"
			.. [[HKEY_LOCAL_MACHINE\HARDWARE\DESCRIPTION\System\CentralProcessor\0]]
			.. "\r\n"
			.. "    ProcessorNameString    REG_SZ    AMD Ryzen 5 7600X 6-Core Processor\r\n"
		assert.are.equal("AMD Ryzen 5 7600X 6-Core Processor", device.registry_value(output, "ProcessorNameString"))
	end)

	it("picks the AMD GPU with the most memory, not the integrated one", function()
		local hardware = { platform = "windows", cpu = "AMD Ryzen 5 7600X 6-Core Processor", gpus = gpus }
		assert.are.equal("AMD Radeon RX 6700 XT (GPU)", device.describe("amd", hardware))
		assert.are.equal("AMD Ryzen 5 7600X 6-Core Processor (CPU)", device.describe("cpu", hardware))
		assert.are.equal("no NVIDIA GPU found", device.describe("nvidia", hardware))
		assert.are.equal("VAAPI only works on Linux", device.describe("vaapi", hardware))
	end)
end)

describe("core.device on Linux", function()
	local gpus = device.lspci_gpus(LSPCI)

	it("reads VGA and display controllers and shortens the vendor", function()
		local names = {}
		for _, gpu in ipairs(gpus) do
			names[#names + 1] = gpu.name
		end
		assert.are.same({
			"NVIDIA GA106 [GeForce RTX 3060]",
			"AMD Navi 22 [Radeon RX 6700 XT]",
			"Intel Arc A310",
		}, names)
	end)

	it("reads the CPU from /proc/cpuinfo", function()
		local cpuinfo = "processor\t: 0\nvendor_id\t: AuthenticAMD\nmodel name\t: AMD Ryzen 5 7600X 6-Core Processor\n"
		assert.are.equal("AMD Ryzen 5 7600X 6-Core Processor", device.linux_cpu(cpuinfo))
	end)

	it("finds the VAAPI device by the render node's PCI slot", function()
		local slot = device.uevent_slot("DRIVER=amdgpu\nPCI_CLASS=30000\nPCI_SLOT_NAME=0000:03:00.0\n")
		assert.are.equal("03:00.0", slot)
		local hardware = { platform = "linux", gpus = gpus, vaapi_slot = slot }
		assert.are.equal("AMD Navi 22 [Radeon RX 6700 XT] (GPU)", device.describe("vaapi", hardware))
		assert.are.equal("NVIDIA GA106 [GeForce RTX 3060] (GPU)", device.describe("nvidia", hardware))
	end)

	it("says when there is no VAAPI device", function()
		local hardware = { platform = "linux", gpus = gpus }
		assert.are.equal("no VAAPI device found", device.describe("vaapi", hardware))
	end)
end)

describe("core.device.vendor_of", function()
	it("recognizes the vendors by name", function()
		assert.are.equal("nvidia", device.vendor_of("NVIDIA GeForce RTX 4070"))
		assert.are.equal("amd", device.vendor_of("Radeon RX 580 Series"))
		assert.are.equal("intel", device.vendor_of("Intel(R) UHD Graphics 770"))
		assert.are.equal("other", device.vendor_of("Microsoft Basic Display Adapter"))
	end)
end)
