class HEVC extends Format
	new: =>
		@displayName = "HEVC"
		@supportsTwopass = true
		@videoCodec = "libx265"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	getFlags: =>
		{
			"--ovcopts-add=threads=#{options.threads}"
		}

formats["hevc"] = HEVC!

class HEVCVAAPI extends Format
	new: =>
		@displayName = "HEVC (VAAPI/AAC, AMD/Intel GPU Linux)"
		@supportsTwopass = false
		@videoCodec = "hevc_vaapi"
		@audioCodec = "aac"
		@outputExtension = "mp4"
		@acceptsBitrate = true

	getPostFilters: =>
		{"format=nv12"}

formats["hevc-vaapi"] = HEVCVAAPI!
