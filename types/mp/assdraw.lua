---@meta mp.assdraw

---@class mp.assdraw
local assdraw = {}

---@class mp.assdraw.Ass
---@field text string
---@field scale integer
local Ass = {}

---Start a new ASS event (adds a newline unless the text is empty).
function Ass:new_event() end

---@param s string
function Ass:append(s) end

---@param other mp.assdraw.Ass
function Ass:merge(other) end

---@param x number
---@param y number
function Ass:pos(x, y) end

---@param an integer
function Ass:an(an) end

function Ass:draw_start() end

function Ass:draw_stop() end

---@param x number
---@param y number
function Ass:move_to(x, y) end

---@param x number
---@param y number
function Ass:line_to(x, y) end

---Clockwise rectangle path.
---@param x0 number
---@param y0 number
---@param x1 number
---@param y1 number
function Ass:rect_cw(x0, y0, x1, y1) end

---@return mp.assdraw.Ass
function assdraw.ass_new() end

return assdraw
