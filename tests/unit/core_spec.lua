-- These tests pass only the fields the code under test reads.
---@diagnostic disable: missing-fields

local bitrate = require("core.bitrate")
local fake_host = require("fake_host")
local filters = require("core.filters")
local paths = require("core.paths")
local speed = require("core.speed")
local time = require("core.time")

local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 3600
local KILOBITS_PER_KILOBYTE = 8
-- Options use -1 for "not set".
local UNSET = -1

describe("core.time", function()
	local one_minute_two_and_a_half_seconds = SECONDS_PER_MINUTE + 2.5
	local one_hour_two_minutes_three_seconds = SECONDS_PER_HOUR + 2 * SECONDS_PER_MINUTE + 3

	it("formats minutes, seconds and milliseconds", function()
		assert.are.equal("01:02.500", time.to_time_string(one_minute_two_and_a_half_seconds))
		local without_milliseconds = true
		assert.are.equal("01:02", time.to_time_string(one_minute_two_and_a_half_seconds, without_milliseconds))
	end)

	it("adds hours when asked or when over an hour", function()
		local one_second = 1
		local with_milliseconds, with_hours = false, true
		assert.are.equal("0:00:01.000", time.to_time_string(one_second, with_milliseconds, with_hours))
		assert.are.equal("1:02:03.000", time.to_time_string(one_hour_two_minutes_three_seconds))
	end)

	it("truncates milliseconds", function()
		local just_under_two_seconds = 1.9999
		assert.are.equal("00:01.999", time.to_time_string(just_under_two_seconds))
	end)

	it("says unknown for negative times", function()
		assert.are.equal("unknown", time.to_time_string(UNSET))
	end)

	it("uses dots instead of colons for paths", function()
		assert.are.equal("1.02.03.000", time.to_path_element(one_hour_two_minutes_three_seconds))
	end)
end)

describe("core.paths.expand_home", function()
	it("uses HOME first", function()
		local host = fake_host.new({}, { environment = { HOME = "/home/me", USERPROFILE = "C:/Users/me" } })
		assert.are.equal("/home/me/clips", paths.expand_home(host, "~/clips"))
	end)

	it("falls back to USERPROFILE, then HOMEDRIVE and HOMEPATH", function()
		local profile_host = fake_host.new({}, { environment = { USERPROFILE = "C:/Users/me" } })
		assert.are.equal("C:/Users/me/clips", paths.expand_home(profile_host, "~/clips"))
		local drive_host = fake_host.new({}, { environment = { HOMEDRIVE = "D:", HOMEPATH = "me" } })
		assert.are.equal("D:/me/clips", paths.expand_home(drive_host, "~/clips"))
	end)

	it("returns a warning when there is no home directory", function()
		local directory, warning = paths.expand_home(fake_host.new({}, { environment = {} }), "~/clips")
		assert.are.equal("/clips", directory)
		assert.are.equal("Couldn't find home dir.", warning)
	end)

	it("leaves other paths alone", function()
		assert.are.equal("/tmp/~x", paths.expand_home(fake_host.new(), "/tmp/~x"))
	end)
end)

describe("core.speed", function()
	it("keeps the encoder start at the source start", function()
		local start_time, end_time, double_speed = 10, 14, 2
		local times = speed.encode_times(start_time, end_time, double_speed)
		local output_duration = (end_time - start_time) / double_speed
		assert.are.same({
			sourceStart = start_time,
			sourceEnd = end_time,
			speed = double_speed,
			encoderStart = start_time,
			encoderEnd = start_time + output_duration,
			outputDuration = output_duration,
		}, times)
	end)

	it("adds no filters at normal speed", function()
		local normal_speed = 1
		local times = speed.encode_times(1, 2, normal_speed)
		assert.are.same({}, speed.video_flags(times))
		assert.are.same({}, speed.audio_flags(times))
	end)

	it("chains atempo below 0.5", function()
		-- atempo only accepts 0.5 and up, so 0.2 becomes 0.5 * 0.5 * 0.8.
		local fifth_speed = 0.2
		local flags = speed.audio_flags(speed.encode_times(0, 1, fifth_speed))
		local tempo_flag_index = 3
		assert.are.equal("--af-add=atempo=0.5,atempo=0.5,atempo=0.8", flags[tempo_flag_index])
	end)

	it("projects subtitle timing into the encoder timeline", function()
		local start_time, end_time, double_speed = 10, 12, 2
		local times = speed.encode_times(start_time, end_time, double_speed)
		local subtitle_speed, subtitle_delay = 1, 0
		-- The delay moves the source start to where it lands after speeding up.
		local expected_delay = start_time - start_time / double_speed
		assert.are.same(
			{ "--sub-speed=" .. 1 / double_speed, "--sub-delay=" .. expected_delay },
			speed.subtitle_flags(times, subtitle_speed, subtitle_delay)
		)
		local rendered_in_source_time = true
		assert.are.same({}, speed.subtitle_flags(times, subtitle_speed, subtitle_delay, rendered_in_source_time))
	end)
end)

describe("core.filters", function()
	it("scales to the chosen height, and to square pixels first", function()
		local height = 720
		assert.are.same(
			{ "lavfi-scale=iw*sar:ih", "lavfi-scale=-2:" .. height },
			filters.scale({ force_square_pixels = true, scale_height = height })
		)
		assert.are.same({}, filters.scale({ force_square_pixels = false, scale_height = UNSET }))
	end)

	it("only changes fps when set", function()
		local frames_per_second = 30
		assert.are.same({ "fps=" .. frames_per_second }, filters.fps({ fps = frames_per_second }))
		assert.are.same({}, filters.fps({ fps = UNSET }))
	end)

	it("maps mpv color adjustments to eq", function()
		local neutral = 0
		assert.are.same({}, filters.color_adjustments(neutral, neutral, neutral))
		-- mpv's adjustments run from -100 to 100. eq wants multipliers instead.
		local brightness, contrast, saturation = 50, 50, -100
		assert.are.same(
			{ "lavfi-eq=contrast=1.5:saturation=0:brightness=0.75" },
			filters.color_adjustments(brightness, contrast, saturation)
		)
	end)

	it("serializes lavfi filters with positional, named and graph params", function()
		assert.are.equal(
			"lavfi-crop=320:100:0:40",
			filters.serialize_lavfi({
				name = "lavfi-crop",
				-- width, height, x, y
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
		-- %3% says the value that follows is 3 characters long.
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
	local video_format = { video_codec = "libx264" }
	local audio_only_format = { video_codec = "" }
	local target_kilobytes = 2500
	local length_seconds = 10
	local strict_audio_kilobits_per_second = 64
	local one_audio_track, no_audio_tracks = 1, 0

	it("gives all of the size to video by default", function()
		local options = {
			target_filesize = target_kilobytes,
			strict_filesize_constraint = false,
			strict_audio_bitrate = strict_audio_kilobits_per_second,
		}
		local expected_video = target_kilobytes * KILOBITS_PER_KILOBYTE / length_seconds
		assert.are.same(
			{ expected_video },
			{ bitrate.calculate(options, video_format, one_audio_track, length_seconds) }
		)
	end)

	it("reserves audio bitrate when strict and there is audio", function()
		local options = {
			target_filesize = target_kilobytes,
			strict_filesize_constraint = true,
			strict_audio_bitrate = strict_audio_kilobits_per_second,
		}
		local total = target_kilobytes * KILOBITS_PER_KILOBYTE / length_seconds
		assert.are.same(
			{ total - strict_audio_kilobits_per_second, strict_audio_kilobits_per_second },
			{ bitrate.calculate(options, video_format, one_audio_track, length_seconds) }
		)
		assert.are.same({ total }, { bitrate.calculate(options, video_format, no_audio_tracks, length_seconds) })
	end)

	it("gives everything to audio for audio-only formats, without rounding", function()
		local small_target_kilobytes = 1000
		local short_length_seconds = 3
		local options = {
			target_filesize = small_target_kilobytes,
			strict_filesize_constraint = false,
			strict_audio_bitrate = strict_audio_kilobits_per_second,
		}
		local video_bitrate, audio_bitrate =
			bitrate.calculate(options, audio_only_format, one_audio_track, short_length_seconds)
		assert.is_nil(video_bitrate)
		assert.are.equal(small_target_kilobytes * KILOBITS_PER_KILOBYTE / short_length_seconds, audio_bitrate)
	end)
end)
