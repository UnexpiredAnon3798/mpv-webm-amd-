-- The script's live options. Every module that requires this gets the same
-- table, which the options page and the testing messages change at runtime.

local mpopts = require("mp.options")

local options = require("core.options").defaults()
mpopts.read_options(options)

return options
