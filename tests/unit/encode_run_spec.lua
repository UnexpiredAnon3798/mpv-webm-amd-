-- These tests pass only the fields the code under test reads.
---@diagnostic disable: missing-fields

local base64 = require("core.base64")
local check = require("encode.check")
local fake_host = require("fake_host")
local progress = require("encode.progress")
local source = require("encode.source")
local vp8_log = require("encode.vp8_log")

describe("core.base64", function()
	it("encodes with padding", function()
		assert.are.equal("", base64.encode(""))
		assert.are.equal("Zg==", base64.encode("f"))
		assert.are.equal("Zm8=", base64.encode("fo"))
		assert.are.equal("Zm9v", base64.encode("foo"))
	end)

	it("decodes and ignores characters outside the alphabet", function()
		assert.are.equal("foobar", base64.decode("Zm9v\nYmFy"))
	end)

	it("round-trips every byte value", function()
		local LAST_BYTE_VALUE = 255
		local bytes = {}
		for byte_value = 0, LAST_BYTE_VALUE do
			bytes[#bytes + 1] = string.char(byte_value)
		end
		local data = table.concat(bytes)
		assert.are.equal(data, base64.decode(base64.encode(data)))
	end)
end)

-- An IEEE 754 double is 8 bytes: 1 sign bit, 11 exponent bits and 52
-- mantissa bits, stored here with the least significant byte first.
local DOUBLE_SIZE = 8
local EXPONENT_BIAS = 1023
local MANTISSA_BITS = 52

-- Reads a little-endian double, for checking what the patcher wrote.
local function read_double(text)
	local bytes = { text:byte(1, DOUBLE_SIZE) }
	local highest, second_highest = bytes[8], bytes[7]
	local sign = highest >= 128 and -1 or 1
	-- The exponent is the low 7 bits of the highest byte and the high 4 bits of the next one.
	local exponent = (highest % 128) * 16 + math.floor(second_highest / 16)
	local mantissa = second_highest % 16
	for byte_index = 6, 1, -1 do
		mantissa = mantissa * 256 + bytes[byte_index]
	end
	if exponent == 0 then
		return 0
	end
	return sign * math.ldexp(math.ldexp(mantissa, -MANTISSA_BITS) + 1, exponent - EXPONENT_BIAS)
end

describe("encode.vp8_log", function()
	-- Each libvpx first-pass record is 18 doubles. The 17th is the duration.
	local RECORD_SIZE = 18 * DOUBLE_SIZE
	local DURATION_START = 16 * DOUBLE_SIZE + 1
	local DURATION_END = DURATION_START + DOUBLE_SIZE - 1
	-- Durations are stored in units of 1/10,000,000 of a second.
	local DURATION_UNITS_PER_SECOND = 10000000

	-- Makes the given number of records filled with a recognizable byte pattern.
	local function make_records(count)
		local bytes = {}
		for position = 1, count * RECORD_SIZE do
			bytes[#bytes + 1] = string.char((position * 7) % 256)
		end
		return table.concat(bytes)
	end

	-- record_index counts from 0.
	local function record_offset(record_index)
		return record_index * RECORD_SIZE
	end

	it("gives frames the average duration and the aggregate the total", function()
		local frame_count = 2
		local total_seconds = 4
		-- The last record is the aggregate of all the frames.
		local data = make_records(frame_count + 1)
		local patched = vp8_log.patch(data, total_seconds)
		assert.are.equal(#data, #patched)

		local function duration_of(record_index)
			local offset = record_offset(record_index)
			local stored = patched:sub(offset + DURATION_START, offset + DURATION_END)
			return read_double(stored) / DURATION_UNITS_PER_SECOND
		end
		local average_seconds = total_seconds / frame_count
		assert.are.equal(average_seconds, duration_of(0))
		assert.are.equal(average_seconds, duration_of(1))
		assert.are.equal(total_seconds, duration_of(frame_count))
	end)

	it("leaves every other byte alone", function()
		local record_count = 2
		local total_seconds = 1.5
		local data = make_records(record_count)
		local patched = vp8_log.patch(data, total_seconds)
		for record_index = 0, record_count - 1 do
			local offset = record_offset(record_index)
			local before_duration = { offset + 1, offset + DURATION_START - 1 }
			local after_duration = { offset + DURATION_END + 1, offset + RECORD_SIZE }
			assert.are.equal(data:sub(unpack(before_duration)), patched:sub(unpack(before_duration)))
			assert.are.equal(data:sub(unpack(after_duration)), patched:sub(unpack(after_duration)))
		end
	end)

	it("rejects a log with a partial record or no records", function()
		local any_duration = 1
		assert.has_error(function()
			vp8_log.patch(make_records(1) .. "x", any_duration)
		end)
		assert.has_error(function()
			vp8_log.patch("", any_duration)
		end)
	end)
end)

describe("encode.progress", function()
	local START_TIME, END_TIME = 10, 20

	it("turns the position the encoder wrote into a percentage", function()
		local halfway = START_TIME + (END_TIME - START_TIME) / 2
		assert.are.equal(50, progress.percent(tostring(halfway), START_TIME, END_TIME))
		assert.are.equal(0, progress.percent(tostring(START_TIME), START_TIME, END_TIME))
		assert.are.equal(100, progress.percent(tostring(END_TIME), START_TIME, END_TIME))
	end)

	it("stays between 0 and 100", function()
		local before_start, after_end = START_TIME - 5, END_TIME + 5
		assert.are.equal(0, progress.percent(tostring(before_start), START_TIME, END_TIME))
		assert.are.equal(100, progress.percent(tostring(after_end), START_TIME, END_TIME))
	end)

	it("shows 0% before the encoder writes anything", function()
		assert.are.equal(0, progress.percent(nil, START_TIME, END_TIME))
		assert.are.equal(0, progress.percent("", START_TIME, END_TIME))
	end)

	it("passes the script and the position file to the encoder", function()
		assert.are.same(
			{ "--script=/out.mp4.progress.lua", "--script-opts-append=webm-progress-file=/out.mp4.progress" },
			progress.encoder_arguments("/out.mp4.progress.lua", "/out.mp4.progress")
		)
	end)

	it("gives the encoder a script that compiles", function()
		assert.is_function(loadstring(progress.ENCODER_SCRIPT))
	end)

	it("shows progress automatically on every platform", function()
		assert.is_true(progress.should_display({ display_progress = "auto" }))
		assert.is_false(progress.should_display({ display_progress = false }))
	end)
end)

describe("encode.check.encoder_problem", function()
	local EXIT_SUCCESS = 0
	-- mpv reports negative statuses when the process could not start at all.
	local COULD_NOT_START = -3
	local EXITED_WITH_ERROR = 2

	it("is fine when mpv runs", function()
		assert.is_nil(check.encoder_problem({ status = EXIT_SUCCESS }))
	end)

	it("tells a missing mpv apart from a failing one", function()
		-- "or ''" turns a nil result into a failed match.
		assert.matches("^Cannot start the mpv encoder", check.encoder_problem({ status = COULD_NOT_START }) or "")
		assert.matches("^The mpv encoder failed", check.encoder_problem({ status = EXITED_WITH_ERROR }) or "")
	end)
end)

describe("encode.source.resolve", function()
	it("returns nil when nothing is playing", function()
		assert.is_nil(source.resolve(fake_host.new({}), 1, 2))
	end)

	it("uses a local file as it is", function()
		local start_time, end_time = 1, 2
		local host = fake_host.new({ path = "/videos/a.mkv" }, { files = { ["/videos/a.mkv"] = true } })
		local resolved = source.resolve(host, start_time, end_time)
		assert.are.same({
			path = "/videos/a.mkv",
			is_stream = false,
			is_temporary = false,
			start_time = start_time,
			end_time = end_time,
		}, resolved)
	end)

	it("dumps the cache of an HLS stream and rebases the times", function()
		local start_time, end_time = 30, 35
		-- The dump keeps 5 extra seconds past the end of the selection.
		local extra_seconds = 5
		local host = fake_host.new({ path = "https://x/live.m3u8", ["file-format"] = "hls" })
		local resolved = source.resolve(host, start_time, end_time)
		assert.are.same({
			path = "/home/me/cache_dump.ts",
			is_stream = true,
			is_temporary = true,
			start_time = 0,
			end_time = end_time - start_time,
			dump_cache = {
				"dump_cache",
				"0:00:" .. start_time .. ".000",
				"0:00:" .. (end_time + extra_seconds) .. ".000",
				"/home/me/cache_dump.ts",
			},
		}, resolved)
	end)

	it("reads other streams directly", function()
		local host = fake_host.new({ path = "https://x/v.mp4", ["file-format"] = "mp4" })
		local resolved = assert(source.resolve(host, 3, 5))
		assert.is_true(resolved.is_stream)
		assert.is_nil(resolved.dump_cache)
		assert.are.equal("https://x/v.mp4", resolved.path)
	end)
end)
