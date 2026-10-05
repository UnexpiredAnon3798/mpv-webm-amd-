---@meta mp.options

---@class mp.options
local options = {}

---Fill `tbl` from script-opts/<identifier>.conf and --script-opts. Values are
---converted to the type of each default in `tbl`.
---@param tbl table
---@param identifier? string defaults to the script name
---@param on_update? fun(changed: table<string, boolean>)
function options.read_options(tbl, identifier, on_update) end

return options
