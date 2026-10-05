-- Bitrates for hitting options.target_filesize.

local M = {}

---Returns the video and audio bitrates in kbit/s. Either can be nil.
---@param options webm.Options
---@param format webm.Format
---@param audio_track_count integer selected audio tracks the format can use
---@param length number output duration in seconds
---@return number? video_bitrate
---@return number? audio_bitrate
function M.calculate(options, format, audio_track_count, length)
	if format.video_codec == "" then
		-- Allocate everything to the audio, not a lot we can do here
		return nil, options.target_filesize * 8 / length
	end

	local video_kilobits = options.target_filesize * 8
	local audio_kilobits = nil

	if options.strict_filesize_constraint and audio_track_count > 0 then
		-- We only care about audio bitrate on strict encodes
		audio_kilobits = length * options.strict_audio_bitrate
		video_kilobits = video_kilobits - audio_kilobits
	end

	local video_bitrate = math.floor(video_kilobits / length)
	local audio_bitrate = audio_kilobits and math.floor(audio_kilobits / length) or nil

	return video_bitrate, audio_bitrate
end

return M
