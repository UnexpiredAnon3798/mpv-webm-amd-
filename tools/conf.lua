-- Writes webm.conf from the option definitions in src/core/options.lua.
--
-- Each option is preceded by its comment lines as "# " comments. Booleans are
-- written as yes/no, the way mpv's script-opts files expect them.

local M = {}

local function format_value(value)
	if value == true then
		return "yes"
	elseif value == false then
		return "no"
	end
	return tostring(value)
end

---@param definitions webm.OptionDefinition[]
---@return string
function M.generate(definitions)
	local out = {}
	for _, definition in ipairs(definitions) do
		for _, line in ipairs(definition.comment or {}) do
			out[#out + 1] = line == "" and "#" or ("# " .. line)
		end
		out[#out + 1] = definition.name .. "=" .. format_value(definition.default)
	end
	return table.concat(out, "\n") .. "\n"
end

return M
