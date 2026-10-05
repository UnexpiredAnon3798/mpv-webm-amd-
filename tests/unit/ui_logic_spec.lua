local geometry = require("core.geometry")
local options_module = require("core.options")
local upload = require("core.upload")

describe("core.upload", function()
	local function options(extra)
		local o = options_module.defaults()
		for k, v in pairs(extra or {}) do
			o[k] = v
		end
		return o
	end

	it("builds the catbox command with an optional userhash", function()
		local args = upload.curl_args(options({ catbox_userhash = "abc" }), "/v/a.mp4", "/tmp/r", "/tmp/p")
		assert.are.same({
			"curl",
			"-#",
			"-S",
			"-o",
			"/tmp/r",
			"--stderr",
			"/tmp/p",
			"-w",
			"%{http_code}",
			"-F",
			"reqtype=fileupload",
			"-F",
			"userhash=abc",
			"-F",
			"fileToUpload=@/v/a.mp4",
			"https://catbox.moe/user/api.php",
		}, args)
	end)

	it("sends the expiry to litterbox and never the userhash", function()
		local args = upload.curl_args(
			options({ upload_host = "litterbox", litterbox_time = "72h", catbox_userhash = "abc" }),
			"/v/a.mp4",
			"/tmp/r",
			"/tmp/p"
		)
		assert.are.equal("time=72h", args[13])
		assert.are.equal("fileToUpload=@/v/a.mp4", args[15])
		assert.are.equal("https://litterbox.catbox.moe/resources/internals/api.php", args[16])
	end)

	it("escapes commas and semicolons in the file path", function()
		local args = upload.curl_args(options(), "/v/a,b;c.mp4", "/tmp/r", "/tmp/p")
		assert.are.equal("fileToUpload=@/v/a\\,b\\;c.mp4", args[13])
	end)

	it("falls back to catbox for an unknown host", function()
		assert.are.equal("catbox", upload.host("nope").id)
	end)

	it("reads the last percentage from curl's progress meter", function()
		assert.are.equal(45.5, upload.progress_percent("##   12.0%\r#####   45.5%"))
		assert.is_nil(upload.progress_percent("starting"))
	end)

	it("accepts a 2xx response with a URL", function()
		local url = upload.parse_result(true, { status = 0, stdout = "200" }, nil, "https://files.catbox.moe/x.mp4")
		assert.are.equal("https://files.catbox.moe/x.mp4", url)
	end)

	it("reports the response text on failure, on one line and shortened", function()
		local url, err = upload.parse_result(true, { status = 0, stdout = "412" }, nil, "No file\n\n  given")
		assert.is_nil(url)
		assert.are.equal("No file given", err)
		local _, long = upload.parse_result(true, { status = 0, stdout = "500" }, nil, string.rep("x", 400))
		assert.are.equal(300, #long)
	end)

	it("falls back to curl's error when there is no response", function()
		local _, err = upload.parse_result(false, { status = -2, error_string = "killed" }, nil, "")
		assert.are.equal("killed", err)
	end)
end)

describe("core.geometry", function()
	local function view(extra)
		local v = {
			params = { w = 1920, h = 1080, dw = 1920, dh = 1080 },
			keepaspect = true,
			rotate = 0,
			window_w = 1280,
			window_h = 720,
			unscaled = false,
			panscan = 0,
			zoom = 0,
			align_x = 0,
			pan_x = 0,
			align_y = 0,
			pan_y = 0,
		}
		for k, val in pairs(extra or {}) do
			v[k] = val
		end
		return v
	end

	it("fills the window when the aspect ratios match", function()
		local d = geometry.dimensions(view())
		assert.are.same({ x = 0, y = 0 }, d.top_left)
		assert.are.same({ x = 1280, y = 720 }, d.bottom_right)
		assert.are.equal(1.5, d.ratios.w)
	end)

	it("letterboxes a wider video", function()
		local d = geometry.dimensions(view({ window_h = 1024, params = { w = 1920, h = 800, dw = 1920, dh = 800 } }))
		-- 1280 / 1920 * 800 = 533.3, floored to 533 rows, centered.
		assert.are.same({ x = 0, y = 245 }, d.top_left)
		assert.are.same({ x = 1280, y = 778 }, d.bottom_right)
	end)

	it("swaps width and height for 90 degree rotation", function()
		local d = geometry.dimensions(view({ rotate = 90 }))
		assert.is_true(d.bottom_right.x - d.top_left.x < 1280)
	end)

	it("maps screen points to source pixels and back", function()
		local d = geometry.dimensions(view())
		local p = geometry.point()
		p:set_from_screen(d, 100, 50)
		assert.are.same({ 150, 75 }, { p.x, p.y })
		assert.are.same({ x = 100, y = 50 }, p:to_screen(d))
	end)

	it("snaps the last pixel to the frame edge and clamps outside points", function()
		local d = geometry.dimensions(view())
		local p = geometry.point()
		p:set_from_screen(d, 1279, 719)
		assert.are.same({ 1920, 1080 }, { p.x, p.y })
		p:set_from_screen(d, 2000, -5)
		assert.are.same({ 1920, 0 }, { p.x, p.y })
	end)

	it("builds a region from two corners in any order", function()
		local r = geometry.region()
		assert.is_false(r:is_valid())
		r:set_from_points({ x = 300, y = 200 }, { x = 100, y = 50 })
		assert.are.same({ 100, 50, 200, 150 }, { r.x, r.y, r.w, r.h })
		assert.is_true(r:is_valid())
	end)
end)
