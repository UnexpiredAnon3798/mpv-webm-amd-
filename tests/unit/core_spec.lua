local bitrate = require("core.bitrate")
local fake_host = require("fake_host")
local filters = require("core.filters")
local paths = require("core.paths")
local speed = require("core.speed")
local time = require("core.time")

describe("core.time", function()
	it("formats minutes, seconds and milliseconds", function()
		assert.are.equal("01:02.500", time.to_time_string(62.5))
		assert.are.equal("01:02", time.to_time_string(62.5, true))
	end)

	it("adds hours when asked or when over an hour", function()
		assert.are.equal("0:00:01.000", time.to_time_string(1, false, true))
		assert.are.equal("1:02:03.000", time.to_time_string(3723))
	end)

	it("truncates milliseconds", function()
		assert.are.equal("00:01.999", time.to_time_string(1.9999))
	end)

	it("says unknown for negative times", function()
		assert.are.equal("unknown", time.to_time_string(-1))
	end)

	it("uses dots instead of colons for paths", function()
		assert.are.equal("1.02.03.000", time.to_path_element(3723))
	end)
end)

describe("core.paths.expand_home", function()
	it("uses HOME first", function()
		local host = fake_host.new({}, { env = { HOME = "/home/me", USERPROFILE = "C:/Users/me" } })
		assert.are.equal("/home/me/clips", paths.expand_home(host, "~/clips"))
	end)

	it("falls back to USERPROFILE, then HOMEDRIVE and HOMEPATH", function()
		local profile = fake_host.new({}, { env = { USERPROFILE = "C:/Users/me" } })
		assert.are.equal("C:/Users/me/clips", paths.expand_home(profile, "~/clips"))
		local drive = fake_host.new({}, { env = { HOMEDRIVE = "D:", HOMEPATH = "me" } })
		assert.are.equal("D:/me/clips", paths.expand_home(drive, "~/clips"))
	end)

	it("returns a warning when there is no home directory", function()
		local dir, warning = paths.expand_home(fake_host.new({}, { env = {} }), "~/clips")
		assert.are.equal("/clips", dir)
		assert.are.equal("Couldn't find home dir.", warning)
	end)

	it("leaves other paths alone", function()
		assert.are.equal("/tmp/~x", paths.expand_home(fake_host.new(), "/tmp/~x"))
	end)
end)

describe("core.speed", function()
	it("keeps the encoder start at the source start", function()
		local times = speed.encode_times(10, 14, 2)
		assert.are.same({
			sourceStart = 10,
			sourceEnd = 14,
			speed = 2,
			encoderStart = 10,
			encoderEnd = 12,
			outputDuration = 2,
		}, times)
	end)

	it("adds no filters at normal speed", function()
		local times = speed.encode_times(1, 2, 1)
		assert.are.same({}, speed.video_flags(times))
		assert.are.same({}, speed.audio_flags(times))
	end)

	it("chains atempo below 0.5", function()
		local flags = speed.audio_flags(speed.encode_times(0, 1, 0.2))
		assert.are.equal("--af-add=atempo=0.5,atempo=0.5,atempo=0.8", flags[3])
	end)

	it("projects subtitle timing into the encoder timeline", function()
		local times = speed.encode_times(10, 12, 2)
		assert.are.same({ "--sub-speed=0.5", "--sub-delay=5" }, speed.subtitle_flags(times, 1, 0))
		assert.are.same({}, speed.subtitle_flags(times, 1, 0, true))
	end)
end)

describe("core.filters", function()
	it("scales to the chosen height, and to square pixels first", function()
		assert.are.same(
			{ "lavfi-scale=iw*sar:ih", "lavfi-scale=-2:720" },
			filters.scale({ force_square_pixels = true, scale_height = 720 })
		)
		assert.are.same({}, filters.scale({ force_square_pixels = false, scale_height = -1 }))
	end)

	it("only changes fps when set", function()
		assert.are.same({ "fps=30" }, filters.fps({ fps = 30 }))
		assert.are.same({}, filters.fps({ fps = -1 }))
	end)

	it("maps mpv color adjustments to eq", function()
		assert.are.same({}, filters.color_adjustments(0, 0, 0))
		assert.are.same(
			{ "lavfi-eq=contrast=1.5:saturation=0:brightness=0.75" },
			filters.color_adjustments(50, 50, -100)
		)
	end)

	it("serializes lavfi filters with positional, named and graph params", function()
		assert.are.equal(
			"lavfi-crop=320:100:0:40",
			filters.serialize_lavfi({
				name = "lavfi-crop",
				params = { ["@0"] = "320", ["@1"] = "100", ["@2"] = "0", ["@3"] = "40" },
			})
		)
		assert.are.equal(
			"lavfi-eq=contrast=1.5:saturation=1.2",
			filters.serialize_lavfi({ name = "lavfi-eq", params = { saturation = "1.2", contrast = "1.5" } })
		)
		assert.are.equal("lavfi=[hflip]", filters.serialize_lavfi({ name = "lavfi", params = { graph = "hflip" } }))
		assert.are.equal("lavfi-null", filters.serialize_lavfi({ name = "lavfi-null" }))
	end)

	it("skips disabled filters and quotes plain filter params", function()
		assert.are.same(
			{ "scale:w=%3%640", "vflip" },
			filters.current({
				{ name = "scale", params = { w = "640" } },
				{ name = "hflip", enabled = false },
				{ name = "vflip" },
			})
		)
	end)
end)

describe("core.bitrate", function()
	local video = { video_codec = "libx264" }
	local audio_only = { video_codec = "" }

	it("gives all of the size to video by default", function()
		local options = { target_filesize = 2500, strict_filesize_constraint = false, strict_audio_bitrate = 64 }
		assert.are.same({ 2000 }, { bitrate.calculate(options, video, 1, 10) })
	end)

	it("reserves audio bitrate when strict and there is audio", function()
		local options = { target_filesize = 2500, strict_filesize_constraint = true, strict_audio_bitrate = 64 }
		assert.are.same({ 1936, 64 }, { bitrate.calculate(options, video, 1, 10) })
		assert.are.same({ 2000 }, { bitrate.calculate(options, video, 0, 10) })
	end)

	it("gives everything to audio for audio-only formats, without rounding", function()
		local options = { target_filesize = 1000, strict_filesize_constraint = false, strict_audio_bitrate = 64 }
		local video_bitrate, audio_bitrate = bitrate.calculate(options, audio_only, 1, 3)
		assert.is_nil(video_bitrate)
		assert.are.equal(8000 / 3, audio_bitrate)
	end)
end)
