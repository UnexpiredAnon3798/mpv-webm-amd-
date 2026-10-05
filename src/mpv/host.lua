-- The real host: mpv's property API plus the file and environment helpers
-- that src/core and src/encode use. Those modules never call mp.* directly,
-- so tests can hand them a fake host instead.

---@class webm.Host
---@field get_property fun(name: string, def?: string): string?, string?
---@field get_property_osd fun(name: string, def?: string): string, string?
---@field get_property_native fun(name: string, def?: any): any, string?
---@field get_property_number fun(name: string, def?: number): number?, string?
---@field get_property_bool fun(name: string, def?: boolean): boolean?, string?
---@field file_exists fun(path: string): boolean
---@field join_path fun(p1: string, p2: string): string
---@field split_path fun(path: string): string, string
---@field getenv fun(name: string): string?
---@field date fun(format: string): string
---@field is_windows boolean

local mp = require("mp")
local utils = require("mp.utils")

---@type webm.Host
local host = {
	get_property = mp.get_property,
	get_property_osd = mp.get_property_osd,
	get_property_native = mp.get_property_native,
	get_property_number = mp.get_property_number,
	get_property_bool = mp.get_property_bool,
	file_exists = function(path)
		return utils.file_info(path) ~= nil
	end,
	join_path = utils.join_path,
	split_path = utils.split_path,
	getenv = os.getenv,
	date = function(format)
		return os.date(format) --[[@as string]]
	end,
	is_windows = package.config:sub(1, 1) == "\\",
}

return host
