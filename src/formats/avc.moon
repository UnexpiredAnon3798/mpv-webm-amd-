class AVC extends Format
	new: =>
		@displayName = "AVC (h264/AAC)"
		@supportsTwopass = true
		@videoCodec = "libx264"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	getFlags: =>
		{
			"--ovcopts-add=threads=#{options.threads}"
		}

formats["avc"] = AVC!

class AVCNVENC extends Format
	new: =>
		@displayName = "AVC (h264-NVENC/AAC)"
		@supportsTwopass = true
		@videoCodec = "h264_nvenc"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true
	
	getFlags: =>
		{
			"--ovcopts-add=bf=0"
		}

formats["avc-nvenc"] = AVCNVENC!

class AVCVAAPI extends Format
	new: =>
		@displayName = "AVC (h264-VAAPI/AAC, AMD/Intel GPU Linux)"
		@supportsTwopass = false
		@videoCodec = "h264_vaapi"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	getPostFilters: =>
		{"format=nv12"}

formats["avc-vaapi"] = AVCVAAPI!

class AVCAMF extends Format
	new: =>
		@displayName = "AVC (h264-AMF/AAC, AMD GPU Windows)"
		@supportsTwopass = false
		@videoCodec = "h264_amf"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	-- AMF's H.264 encoder rejects 10-bit input, such as HDR and Dolby Vision
	-- sources, so convert to 8-bit first.
	getPostFilters: =>
		{"format=nv12"}

formats["avc-amf"] = AVCAMF!
