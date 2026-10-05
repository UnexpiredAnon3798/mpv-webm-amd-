local geometry = require("core.geometry")
local options_module = require("core.options")
local upload = require("core.upload")

local function index_of(list, wanted)
	for index, value in ipairs(list) do
		if value == wanted then
			return index
		end
	end
end

describe("core.upload", function()
	local EXIT_SUCCESS = 0
	-- What mpv reports for a process it killed, such as an aborted upload.
	local KILLED = -2
	local HTTP_OK = "200"
	local HTTP_PRECONDITION_FAILED = "412"
	local HTTP_SERVER_ERROR = "500"
	-- Error messages from the server are cut to this many characters.
	local MAX_ERROR_LENGTH = 300

	local FILE = "/videos/clip.mp4"
	local RESPONSE_PATH = "/tmp/response"
	local PROGRESS_PATH = "/tmp/progress"

	local function options_with(overrides)
		local options = options_module.defaults()
		for name, value in pairs(overrides or {}) do
			options[name] = value
		end
		return options
	end

	it("builds the catbox command with an optional userhash", function()
		local arguments =
			upload.curl_args(options_with({ catbox_userhash = "abc" }), FILE, RESPONSE_PATH, PROGRESS_PATH)
		assert.are.same({
			"curl",
			"-#",
			"-S",
			"-o",
			RESPONSE_PATH,
			"--stderr",
			PROGRESS_PATH,
			"-w",
			"%{http_code}",
			"-F",
			"reqtype=fileupload",
			"-F",
			"userhash=abc",
			"-F",
			"fileToUpload=@" .. FILE,
			"https://catbox.moe/user/api.php",
		}, arguments)
	end)

	it("sends the expiry to litterbox and never the userhash", function()
		local arguments = upload.curl_args(
			options_with({ upload_host = "litterbox", litterbox_time = "72h", catbox_userhash = "abc" }),
			FILE,
			RESPONSE_PATH,
			PROGRESS_PATH
		)
		assert.is_truthy(index_of(arguments, "time=72h"))
		assert.is_nil(index_of(arguments, "userhash=abc"))
		assert.are.equal("https://litterbox.catbox.moe/resources/internals/api.php", arguments[#arguments])
	end)

	it("escapes commas and semicolons in the file path", function()
		local arguments = upload.curl_args(options_with(), "/videos/a,b;c.mp4", RESPONSE_PATH, PROGRESS_PATH)
		assert.is_truthy(index_of(arguments, "fileToUpload=@/videos/a\\,b\\;c.mp4"))
	end)

	it("falls back to catbox for an unknown host", function()
		assert.are.equal("catbox", upload.host("nope").id)
	end)

	it("reads the last percentage from curl's progress meter", function()
		local last_percentage = 45.5
		local meter = "##   12.0%\r#####   " .. last_percentage .. "%"
		assert.are.equal(last_percentage, upload.progress_percent(meter))
		assert.is_nil(upload.progress_percent("starting"))
	end)

	it("accepts a 2xx response with a URL", function()
		local link = "https://files.catbox.moe/x.mp4"
		local url = upload.parse_result(true, { status = EXIT_SUCCESS, stdout = HTTP_OK }, nil, link)
		assert.are.equal(link, url)
	end)

	it("reports the response text on failure, on one line and shortened", function()
		local result = { status = EXIT_SUCCESS, stdout = HTTP_PRECONDITION_FAILED }
		local url, message = upload.parse_result(true, result, nil, "No file\n\n  given")
		assert.is_nil(url)
		assert.are.equal("No file given", message)

		local too_long = string.rep("x", MAX_ERROR_LENGTH + 100)
		local _, shortened =
			upload.parse_result(true, { status = EXIT_SUCCESS, stdout = HTTP_SERVER_ERROR }, nil, too_long)
		assert.are.equal(MAX_ERROR_LENGTH, #shortened)
	end)

	it("falls back to curl's error when there is no response", function()
		local _, message = upload.parse_result(false, { status = KILLED, error_string = "killed" }, nil, "")
		assert.are.equal("killed", message)
	end)
end)

describe("core.geometry", function()
	-- A 1920x1080 video in a 1280x720 window: same aspect ratio, scaled by 2/3.
	local VIDEO_WIDTH, VIDEO_HEIGHT = 1920, 1080
	local WINDOW_WIDTH, WINDOW_HEIGHT = 1280, 720
	local SOURCE_PIXELS_PER_SCREEN_PIXEL = VIDEO_WIDTH / WINDOW_WIDTH

	-- Field names follow mpv's video-out-params property and geometry.ViewState.
	local function view_with(overrides)
		local view = {
			params = { w = VIDEO_WIDTH, h = VIDEO_HEIGHT, dw = VIDEO_WIDTH, dh = VIDEO_HEIGHT },
			keepaspect = true,
			rotate = 0,
			window_w = WINDOW_WIDTH,
			window_h = WINDOW_HEIGHT,
			unscaled = false,
			panscan = 0,
			zoom = 0,
			align_x = 0,
			pan_x = 0,
			align_y = 0,
			pan_y = 0,
		}
		for name, value in pairs(overrides or {}) do
			view[name] = value
		end
		return view
	end

	it("fills the window when the aspect ratios match", function()
		local dimensions = geometry.dimensions(view_with())
		assert.are.same({ x = 0, y = 0 }, dimensions.top_left)
		assert.are.same({ x = WINDOW_WIDTH, y = WINDOW_HEIGHT }, dimensions.bottom_right)
		assert.are.equal(SOURCE_PIXELS_PER_SCREEN_PIXEL, dimensions.ratios.w)
	end)

	it("letterboxes a wider video", function()
		local tall_window_height = 1024
		local wide_video_height = 800
		local dimensions = geometry.dimensions(view_with({
			window_h = tall_window_height,
			params = { w = VIDEO_WIDTH, h = wide_video_height, dw = VIDEO_WIDTH, dh = wide_video_height },
		}))
		-- The video is drawn WINDOW_WIDTH wide, so its height is
		-- 1280 / 1920 * 800 = 533.3 rows, floored to 533, and centered.
		local drawn_height = math.floor(WINDOW_WIDTH / VIDEO_WIDTH * wide_video_height)
		local top = math.floor((tall_window_height - drawn_height) / 2)
		assert.are.same({ x = 0, y = top }, dimensions.top_left)
		assert.are.same({ x = WINDOW_WIDTH, y = top + drawn_height }, dimensions.bottom_right)
	end)

	it("swaps width and height for 90 degree rotation", function()
		local quarter_turn = 90
		local dimensions = geometry.dimensions(view_with({ rotate = quarter_turn }))
		local drawn_width = dimensions.bottom_right.x - dimensions.top_left.x
		assert.is_true(drawn_width < WINDOW_WIDTH)
	end)

	it("maps screen points to source pixels and back", function()
		local dimensions = geometry.dimensions(view_with())
		local point = geometry.point()
		local screen_x, screen_y = 100, 50
		point:set_from_screen(dimensions, screen_x, screen_y)
		assert.are.same(
			{ screen_x * SOURCE_PIXELS_PER_SCREEN_PIXEL, screen_y * SOURCE_PIXELS_PER_SCREEN_PIXEL },
			{ point.x, point.y }
		)
		assert.are.same({ x = screen_x, y = screen_y }, point:to_screen(dimensions))
	end)

	it("snaps the last pixel to the frame edge and clamps outside points", function()
		local dimensions = geometry.dimensions(view_with())
		local point = geometry.point()
		local last_screen_x, last_screen_y = WINDOW_WIDTH - 1, WINDOW_HEIGHT - 1
		point:set_from_screen(dimensions, last_screen_x, last_screen_y)
		assert.are.same({ VIDEO_WIDTH, VIDEO_HEIGHT }, { point.x, point.y })

		local right_of_window, above_window = WINDOW_WIDTH + 720, -5
		point:set_from_screen(dimensions, right_of_window, above_window)
		assert.are.same({ VIDEO_WIDTH, 0 }, { point.x, point.y })
	end)

	it("builds a region from two corners in any order", function()
		local region = geometry.region()
		assert.is_false(region:is_valid())
		local bottom_right, top_left = { x = 300, y = 200 }, { x = 100, y = 50 }
		region:set_from_points(bottom_right, top_left)
		assert.are.same({
			top_left.x,
			top_left.y,
			bottom_right.x - top_left.x,
			bottom_right.y - top_left.y,
		}, { region.x, region.y, region.w, region.h })
		assert.is_true(region:is_valid())
	end)
end)
