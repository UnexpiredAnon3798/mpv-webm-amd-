-- Joins Lua sources into the single webm.lua that users install.
--
-- mpv does not put a single-file script's directory on package.path, so
-- modules can't be loaded from disk. Each module is stored in
-- package.preload instead, where require() finds it. Every mpv script runs
-- in its own Lua state, so these names can't clash with other scripts.
--
-- After the modules come the main chunks, in order. The build has one,
-- src/main.lua.

local M = {}

-- parts.header: comment text put at the top (optional)
-- parts.modules: list of { name = "core.options", source = "..." }
-- parts.chunks: list of { name = "src/main.lua", source = "..." }
function M.bundle(parts)
	local out = {}

	if parts.header then
		for line in (parts.header .. "\n"):gmatch("(.-)\n") do
			out[#out + 1] = "-- " .. line
		end
		out[#out + 1] = ""
	end

	local seen = {}
	for _, module in ipairs(parts.modules or {}) do
		assert(not seen[module.name], "module listed twice: " .. module.name)
		seen[module.name] = true
		out[#out + 1] = string.format("package.preload[%q] = function(...)", module.name)
		out[#out + 1] = module.source
		out[#out + 1] = "end"
		out[#out + 1] = ""
	end

	for _, chunk in ipairs(parts.chunks or {}) do
		out[#out + 1] = chunk.source
	end

	local text = table.concat(out, "\n")
	if text:sub(-1) ~= "\n" then
		text = text .. "\n"
	end
	return text
end

return M
