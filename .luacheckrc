-- mpv runs scripts on LuaJIT (or Lua 5.1 on some builds).
std = "luajit"

-- StyLua formats the code. Long comments and strings are fine.
max_line_length = false

-- Methods often don't need self, such as the empty hooks on ui.page.
self = false

exclude_files = {
	"build/**",
	"types/**",
	"tests/integration/**",
}

-- Format methods share one signature, and most don't use every argument.
files["src/encode/formats.lua"] = {
	unused_args = false,
}

files["tests/unit/**"] = {
	std = "+busted",
}

files["tests/golden/**"] = {
	globals = { "GOLDEN_DIR" },
	-- The fake mpv API mirrors real signatures, so many arguments go unused.
	unused_args = false,
}
