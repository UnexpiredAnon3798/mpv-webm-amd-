local base64 = require("core.base64")
local check = require("encode.check")
local fake_host = require("fake_host")
local progress = require("encode.progress")
local shell = require("encode.shell")
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
		local bytes = {}
		for i = 0, 255 do
			bytes[#bytes + 1] = string.char(i)
		end
		local data = table.concat(bytes)
		assert.are.equal(data, base64.decode(base64.encode(data)))
	end)
end)

-- Little-endian double, for checking what the patcher wrote.
local function read_double(s)
	local b = { s:byte(1, 8) }
	local sign = b[8] > 127 and -1 or 1
	local exponent = (b[8] % 128) * 16 + math.floor(b[7] / 16)
	local mantissa = b[7] % 16
	for i = 6, 1, -1 do
		mantissa = mantissa * 256 + b[i]
	end
	if exponent == 0 then
		return 0
	end
	return sign * math.ldexp(math.ldexp(mantissa, -52) + 1, exponent - 1023)
end

describe("encode.vp8_log", function()
	local RECORD = 144
	local function records(n)
		local out = {}
		for i = 1, n * RECORD do
			out[#out + 1] = string.char((i * 7) % 256)
		end
		return table.concat(out)
	end

	it("gives frames the average duration and the aggregate the total", function()
		local data = records(3)
		local patched = vp8_log.patch(data, 4)
		assert.are.equal(#data, #patched)
		local function duration(i)
			return read_double(patched:sub(i * RECORD + 129, i * RECORD + 136)) / 1e7
		end
		assert.are.equal(2, duration(0))
		assert.are.equal(2, duration(1))
		assert.are.equal(4, duration(2))
	end)

	it("leaves every other byte alone", function()
		local data = records(2)
		local patched = vp8_log.patch(data, 1.5)
		for i = 0, 1 do
			local from, to = i * RECORD, (i + 1) * RECORD
			assert.are.equal(data:sub(from + 1, from + 128), patched:sub(from + 1, from + 128))
			assert.are.equal(data:sub(from + 137, to), patched:sub(from + 137, to))
		end
	end)

	it("rejects a log with a partial record or no records", function()
		assert.has_error(function()
			vp8_log.patch(records(1) .. "x", 1)
		end)
		assert.has_error(function()
			vp8_log.patch("", 1)
		end)
	end)
end)

describe("encode.progress", function()
	it("tracks the furthest position and the exit reason", function()
		local tracker = progress.new(10, 20)
		assert.are.equal("0%", tracker:percent_text())
		tracker:parse_line("Encode time-pos: 15.000000")
		tracker:parse_line("Encode time-pos: 12.000000")
		assert.are.equal("50%", tracker:percent_text())
		assert.is_false(tracker.finished)
		tracker:parse_line("Exiting... (End of file)")
		assert.is_true(tracker:succeeded())
	end)

	it("fails on any other exit reason", function()
		local tracker = progress.new(0, 1)
		tracker:parse_line("Exiting... (Errors when loading file)")
		assert.is_true(tracker.finished)
		assert.is_false(tracker:succeeded())
	end)

	it("shows progress automatically except on Windows", function()
		assert.is_true(progress.should_display({ display_progress = "auto" }, false))
		assert.is_false(progress.should_display({ display_progress = "auto" }, true))
		assert.is_false(progress.should_display({ display_progress = false }, false))
	end)
end)

describe("encode.shell", function()
	it("quotes arguments with special characters for sh", function()
		assert.are.equal(
			"mpv '/a b.mkv' 'it'\\''s' --no-pause 2>&1",
			shell.popen_command({ "mpv", "/a b.mkv", "it's", "--no-pause" }, false)
		)
	end)

	it("quotes for cmd and wraps the whole line", function()
		assert.are.equal(
			'""C:\\a b.mkv" "say "\\""hi"\\"""" 2>&1',
			shell.popen_command({ "C:\\a b.mkv", 'say "hi"' }, true)
		)
	end)
end)

describe("encode.check.encoder_problem", function()
	it("is fine when mpv runs", function()
		assert.is_nil(check.encoder_problem({ status = 0 }))
	end)

	it("tells a missing mpv apart from a failing one", function()
		assert.matches("^Cannot start the mpv encoder", check.encoder_problem({ status = -3 }))
		assert.matches("^The mpv encoder failed", check.encoder_problem({ status = 2 }))
	end)
end)

describe("encode.source.resolve", function()
	it("returns nil when nothing is playing", function()
		assert.is_nil(source.resolve(fake_host.new({}), 1, 2))
	end)

	it("uses a local file as it is", function()
		local host = fake_host.new({ path = "/videos/a.mkv" }, { files = { ["/videos/a.mkv"] = true } })
		local s = source.resolve(host, 1, 2)
		assert.are.same(
			{ path = "/videos/a.mkv", is_stream = false, is_temporary = false, start_time = 1, end_time = 2 },
			s
		)
	end)

	it("dumps the cache of an HLS stream and rebases the times", function()
		local host = fake_host.new({ path = "https://x/live.m3u8", ["file-format"] = "hls" })
		local s = source.resolve(host, 30, 35)
		assert.are.same({
			path = "/home/me/cache_dump.ts",
			is_stream = true,
			is_temporary = true,
			start_time = 0,
			end_time = 5,
			dump_cache = { "dump_cache", "0:00:30.000", "0:00:40.000", "/home/me/cache_dump.ts" },
		}, s)
	end)

	it("reads other streams directly", function()
		local s = source.resolve(fake_host.new({ path = "https://x/v.mp4", ["file-format"] = "mp4" }), 3, 5)
		assert.is_true(s.is_stream)
		assert.is_nil(s.dump_cache)
		assert.are.equal("https://x/v.mp4", s.path)
	end)
end)
