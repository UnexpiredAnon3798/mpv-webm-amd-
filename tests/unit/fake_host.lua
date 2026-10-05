-- A webm.Host for unit tests: properties come from a plain table, files from
-- a set of paths. Paths use "/" only.

local fake_host = {}

local NOT_FOUND = "property not found"

-- A fixed moment for host.date: 2024-03-09 13:45:30 UTC.
local FIXED_UNIX_TIME = 1709991930

local function to_string(value)
	if type(value) == "boolean" then
		return value and "yes" or "no"
	end
	return tostring(value)
end

---@param properties? table<string, any>
---@param settings? {files?: table<string, boolean>, environment?: table<string, string>}
---@return webm.Host
function fake_host.new(properties, settings)
	properties = properties or {}
	settings = settings or {}
	local files = settings.files or {}
	local environment = settings.environment or { HOME = "/home/me" }

	local host = {}

	function host.get_property(name, default)
		local value = properties[name]
		if value == nil then
			return default, NOT_FOUND
		end
		return to_string(value)
	end

	function host.get_property_osd(name, default)
		local value = properties[name]
		if value == nil then
			return default or "", NOT_FOUND
		end
		return to_string(value)
	end

	function host.get_property_native(name, default)
		local value = properties[name]
		if value == nil then
			return default, NOT_FOUND
		end
		return value
	end

	function host.get_property_number(name, default)
		local value = tonumber(properties[name])
		if value == nil then
			return default, NOT_FOUND
		end
		return value
	end

	function host.get_property_bool(name, default)
		local value = properties[name]
		if type(value) ~= "boolean" then
			return default, NOT_FOUND
		end
		return value
	end

	function host.file_exists(path)
		return files[path] ~= nil
	end

	function host.join_path(first, second)
		if first == "" then
			return second
		end
		if second:sub(1, 1) == "/" then
			return second
		end
		return first:sub(-1) == "/" and first .. second or first .. "/" .. second
	end

	function host.split_path(path)
		local directory, name = path:match("^(.*/)([^/]*)$")
		if not directory then
			return ".", path
		end
		return directory, name
	end

	function host.getenv(name)
		return environment[name]
	end

	function host.date(format)
		return os.date("!" .. format, FIXED_UNIX_TIME) --[[@as string]]
	end

	host.is_windows = false
	return host
end

return fake_host
