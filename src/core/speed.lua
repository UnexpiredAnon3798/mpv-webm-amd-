-- Handling of playback speed changes.
--
-- Two time domains are involved:
--   source  - the user's selection inside the file (sourceStart/sourceEnd)
--   encoder - the timeline mpv's encoder uses, after the filter chain (with
--             possible speed changes) is applied
--
-- mpv's --start and --end options are a little counter-intuitive:
-- 1. --start takes a source time as input and seeks to that point.
-- 2. The filters are applied
-- 3. then the same --start time is used to encode.
-- But if the timeline has changed due to speed filters, the start time is now
-- offset and will be wrong, leading to the wrong part of the video being encoded.
-- Same applies for the end time, due to timeline changes the end time can be offset.
--
-- To fix this, we need to offset the filtered timeline back to the old sourceStart,
-- so the sourceStart time and the encoderStart time are identical.

local M = {}

---@class webm.EncodeTimes
---@field sourceStart number
---@field sourceEnd number
---@field speed number
---@field encoderStart number
---@field encoderEnd number
---@field outputDuration number

---@param start_time number
---@param end_time number
---@param speed number
---@return webm.EncodeTimes
function M.encode_times(start_time, end_time, speed)
	local output_duration = (end_time - start_time) / speed
	return {
		sourceStart = start_time,
		sourceEnd = end_time,
		speed = speed,
		encoderStart = start_time, -- not scaled, see the comment at the top
		encoderEnd = start_time + output_duration,
		outputDuration = output_duration,
	}
end

---@param times webm.EncodeTimes
---@return string[]
function M.video_flags(times)
	if times.speed == 1 then
		return {}
	end
	-- Rebase both streams to the selection origin, not their first frame/sample,
	-- so an initial A/V offset survives the speed change.
	return {
		"--vf-add=trim=start=" .. tostring(times.sourceStart) .. ":end=" .. tostring(times.sourceEnd),
		"--vf-add=setpts=(PTS-" .. tostring(times.sourceStart) .. "/TB)/" .. tostring(times.speed),
		"--vf-add=setpts=PTS+" .. tostring(times.sourceStart) .. "/TB",
	}
end

---@param times webm.EncodeTimes
---@return string[]
function M.audio_flags(times)
	if times.speed == 1 then
		return {}
	end
	-- libavfilter's atempo only accepts [0.5, 100]; below that it has to be
	-- chained, so that any of mpv's speeds (down to 0.01) works.
	local atempo = {}
	local tempo = times.speed
	while tempo < 0.5 do
		atempo[#atempo + 1] = "atempo=0.5"
		tempo = tempo * 2
	end
	atempo[#atempo + 1] = "atempo=" .. tostring(tempo)
	-- Scale the initial offset from the shared selection origin before atempo.
	-- atempo changes sample duration but preserves the first input timestamp.
	return {
		"--af-add=atrim=start=" .. tostring(times.sourceStart) .. ":end=" .. tostring(times.sourceEnd),
		"--af-add=asetpts=(PTS-" .. tostring(times.sourceStart) .. "/TB)/" .. tostring(times.speed),
		"--af-add=" .. table.concat(atempo, ","),
		"--af-add=asetpts=PTS+" .. tostring(times.sourceStart) .. "/TB",
	}
end

---Subtitle speed and delay flags. A filter that renders subtitles before the
---video is retimed (GIF) passes source_time and gets the user's own values.
---@param times webm.EncodeTimes
---@param sub_speed number the sub-speed property
---@param sub_delay number the sub-delay property
---@param source_time? boolean
---@return string[]
function M.subtitle_flags(times, sub_speed, sub_delay, source_time)
	if times.speed ~= 1 and not source_time then
		-- Project both user adjustments into the encoder timeline.
		sub_speed = sub_speed * (1 / times.speed)
		sub_delay = sub_delay / times.speed + times.sourceStart - times.sourceStart / times.speed
	end
	local ret = {}
	if sub_speed ~= 1 then
		ret[#ret + 1] = "--sub-speed=" .. tostring(sub_speed)
	end
	if sub_delay ~= 0 then
		ret[#ret + 1] = "--sub-delay=" .. tostring(sub_delay)
	end
	return ret
end

return M
