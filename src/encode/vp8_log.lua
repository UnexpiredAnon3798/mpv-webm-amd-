-- Fixes the frame durations in libvpx's (VP8) first-pass log before the
-- second pass.
--
-- The log is base64 text holding FIRSTPASS_STATS records: 18 little-endian
-- doubles each, where the 17th is the duration in units of 1e-7 seconds. The
-- last record is the aggregate of all the others. Every frame record gets the
-- average duration and the aggregate gets the total, so the second pass
-- budgets bits for the length of the encoded clip.

local base64 = require("core.base64")

local M = {}

local FIELDS_BEFORE_DURATION = 16
local FIELDS_AFTER_DURATION = 1
local RECORD_SIZE = (FIELDS_BEFORE_DURATION + 1 + FIELDS_AFTER_DURATION) * 8
local DURATION_OFFSET = FIELDS_BEFORE_DURATION * 8
local DURATION_MULTIPLIER = 10000000.0

-- From https://gist.github.com/Kubuxu/e5e04c028d8aaeab4be8, big-endian order.
local function write_double(num)
	local bytes = { 0, 0, 0, 0, 0, 0, 0, 0 }
	if num == 0 then
		return bytes
	end

	local anum = math.abs(num)

	local mantissa, exponent = math.frexp(anum)
	exponent = exponent - 1
	mantissa = mantissa * 2 - 1
	local sign = num ~= anum and 128 or 0
	exponent = exponent + 1023

	bytes[1] = sign + math.floor(exponent / 2 ^ 4)
	mantissa = mantissa * 2 ^ 4
	local current_mantissa = math.floor(mantissa)
	mantissa = mantissa - current_mantissa
	bytes[2] = (exponent % 2 ^ 4) * 2 ^ 4 + current_mantissa
	for i = 3, 8 do
		mantissa = mantissa * 2 ^ 8
		current_mantissa = math.floor(mantissa)
		mantissa = mantissa - current_mantissa
		bytes[i] = current_mantissa
	end
	return bytes
end

local function duration_bytes(seconds)
	local big_endian = write_double(seconds * DURATION_MULTIPLIER)
	local out = {}
	for i = 8, 1, -1 do
		out[#out + 1] = string.char(big_endian[i])
	end
	return table.concat(out)
end

---Rewrites the durations in decoded log data.
---@param data string the decoded log
---@param total_duration number seconds
---@return string
function M.patch(data, total_duration)
	assert(#data % RECORD_SIZE == 0, "first-pass log has a partial record")
	local count = #data / RECORD_SIZE
	assert(count > 0, "first-pass log is empty")

	local average_duration = total_duration / (count - 1)
	local out = {}
	for i = 0, count - 1 do
		local record = data:sub(i * RECORD_SIZE + 1, (i + 1) * RECORD_SIZE)
		local duration = i == count - 1 and total_duration or average_duration
		out[#out + 1] = record:sub(1, DURATION_OFFSET) .. duration_bytes(duration) .. record:sub(DURATION_OFFSET + 9)
	end
	return table.concat(out)
end

---Patches the log file in place.
---@param path string
---@param total_duration number seconds
function M.patch_file(path, total_duration)
	local file = assert(io.open(path, "rb"))
	local data = base64.decode(file:read())
	file:close()

	local patched = M.patch(data, total_duration)

	file = assert(io.open(path, "wb"))
	file:write(base64.encode(patched))
	file:close()
end

return M
