-- A webm.Host for unit tests: properties come from a plain table, files from
-- a set of paths. Paths use "/" only.

local M = {}

local NOT_FOUND = "property not found"

local function to_string(value)
	if type(value) == "boolean" then
		return value and "yes" or "no"
	end
	return tostring(value)
end

---@param props? table<string, any>
---@param opts? {files?: table<string, boolean>, env?: table<string, string>}
---@return webm.Host
function M.new(props, opts)
	props = props or {}
	opts = opts or {}
	local files = opts.files or {}
	local env = opts.env or { HOME = "/home/me" }

	local host = {}

	function host.get_property(name, def)
		local value = props[name]
		if value == nil then
			return def, NOT_FOUND
		end
		return to_string(value)
	end

	function host.get_property_osd(name, def)
		local value = props[name]
		if value == nil then
			return def or "", NOT_FOUND
		end
		return to_string(value)
	end

	function host.get_property_native(name, def)
		local value = props[name]
		if value == nil then
			return def, NOT_FOUND
		end
		return value
	end

	function host.get_property_number(name, def)
		local value = tonumber(props[name])
		if value == nil then
			return def, NOT_FOUND
		end
		return value
	end

	function host.get_property_bool(name, def)
		local value = props[name]
		if type(value) ~= "boolean" then
			return def, NOT_FOUND
		end
		return value
	end

	function host.file_exists(path)
		return files[path] ~= nil
	end

	function host.join_path(a, b)
		if a == "" then
			return b
		end
		if b:sub(1, 1) == "/" then
			return b
		end
		return a:sub(-1) == "/" and a .. b or a .. "/" .. b
	end

	function host.split_path(path)
		local dir, name = path:match("^(.*/)([^/]*)$")
		if not dir then
			return ".", path
		end
		return dir, name
	end

	function host.getenv(name)
		return env[name]
	end

	-- A fixed moment: 2024-03-09 13:45:30 UTC.
	function host.date(format)
		return os.date("!" .. format, 1709991930) --[[@as string]]
	end

	host.is_windows = false
	return host
end

return M
