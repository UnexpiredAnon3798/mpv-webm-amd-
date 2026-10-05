-- Golden (characterization) tests for the built webm.lua.
--
-- Usage, from the repository root (Lua 5.1 or LuaJIT):
--   lua tests/golden/run.lua                 compare against tests/golden/expected
--   lua tests/golden/run.lua --update        rewrite the expected files
--   lua tests/golden/run.lua encode_gif      only scenarios whose name contains "encode_gif"
--   lua tests/golden/run.lua --script PATH   test another build (default build/webm.lua)
--   lua tests/golden/run.lua --conf PATH     compare another webm.conf (default build/webm.conf)

GOLDEN_DIR = (arg[0]:match("^(.*[/\\])") or "./")

local fake_mpv = dofile(GOLDEN_DIR .. "fake_mpv.lua")
local scenarios = dofile(GOLDEN_DIR .. "scenarios.lua")
local json = fake_mpv.json

local update = false
local script_path = "build/webm.lua"
local conf_path = "build/webm.conf"
local filter

local i = 1
while i <= #arg do
	local a = arg[i]
	if a == "--update" then
		update = true
	elseif a == "--script" then
		i = i + 1
		script_path = arg[i]
	elseif a == "--conf" then
		i = i + 1
		conf_path = arg[i]
	else
		filter = a
	end
	i = i + 1
end

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return (content:gsub("\r\n", "\n"))
end

local function write_file(path, content)
	local f = assert(io.open(path, "wb"))
	f:write(content)
	f:close()
end

local steps = {}

function steps.key(w, key)
	w:log("> key " .. key)
	w:press(key)
end

function steps.options(w, tbl)
	local payload = json.encode(tbl)
	w:log("> set options " .. payload)
	w:script_message("mpv-webm-set-options", payload)
end

function steps.range(w, start_time, end_time, region)
	local payload = json.encode({ startTime = start_time, endTime = end_time, region = region })
	w:log("> set range " .. payload)
	w:script_message("mpv-webm-set-range", payload)
end

function steps.encode(w)
	w:log("> encode")
	w:script_message("mpv-webm-encode")
end

function steps.upload(w)
	w:log("> upload")
	w:script_message("mpv-webm-upload")
end

function steps.state(w)
	w:log("> get state")
	w:script_message("mpv-webm-get-state")
end

function steps.set(w, name, value)
	w:log("> set property " .. name .. " = " .. json.encode(value))
	w:set_prop(name, value)
end

function steps.mouse(w, x, y)
	w:log(string.format("> mouse %d,%d", x, y))
	w.mouse_x, w.mouse_y = x, y
end

function steps.event(w, name)
	w:log("> event " .. name)
	w:fire_event(name)
end

function steps.async(w)
	w:log("> run async callbacks")
	w:run_async()
end

function steps.timers(w)
	w:log("> fire timers")
	w:fire_timers()
end

function steps.file(w, path, content)
	w:log("> file " .. path .. " = " .. json.encode(content))
	w.fs[path] = content
end

function steps.bindings(w)
	w:log("> active forced bindings: " .. table.concat(w:active_bindings(), " "))
end

function steps.dump_options(w)
	w:log("> options")
	local opts = w.options_table
	if not opts then
		w:log("  (read_options was never called)")
		return
	end
	local keys = {}
	for k in pairs(opts) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		w:log("  " .. k .. " = " .. json.encode(opts[k]) .. " (" .. type(opts[k]) .. ")")
	end
end

function steps.note(w, text)
	w:log("# " .. text)
end

-- Encode with the given output_template and report only the output path.
function steps.filename(w, template)
	w.last_out = nil
	w.quiet = w.quiet + 1
	w:script_message("mpv-webm-set-options", json.encode({ output_template = template }))
	w:script_message("mpv-webm-encode")
	w.quiet = w.quiet - 1
	w:log(json.encode(template) .. " -> " .. json.encode(w.last_out))
end

local function run_scenario(s)
	local w = fake_mpv.new(s.world or {})
	w:load_script(script_path)
	for _, step in ipairs(s.steps or {}) do
		local fn = steps[step[1]]
		if not fn then
			error("scenario " .. s.name .. ": unknown step " .. tostring(step[1]))
		end
		fn(w, unpack(step, 2, table.maxn(step)))
	end
	return table.concat(w.lines, "\n") .. "\n"
end

-- Print the first difference with a little context.
local function show_diff(expected, actual)
	local e, a = {}, {}
	for line in expected:gmatch("(.-)\n") do
		e[#e + 1] = line
	end
	for line in actual:gmatch("(.-)\n") do
		a[#a + 1] = line
	end
	local n = math.max(#e, #a)
	for idx = 1, n do
		if e[idx] ~= a[idx] then
			for c = math.max(1, idx - 3), idx - 1 do
				print("      " .. e[c])
			end
			print("  -   " .. tostring(e[idx]))
			print("  +   " .. tostring(a[idx]))
			return
		end
	end
end

local failures, passed, written = 0, 0, 0

local function check(name, actual)
	local path = GOLDEN_DIR .. "expected/" .. name .. ".txt"
	if update then
		if read_file(path) ~= actual then
			write_file(path, actual)
			written = written + 1
			print("updated " .. name)
		end
		return
	end
	local expected = read_file(path)
	if expected == nil then
		failures = failures + 1
		print("MISSING " .. name .. " (run with --update to create it)")
	elseif expected ~= actual then
		failures = failures + 1
		print("FAIL " .. name)
		show_diff(expected, actual)
	else
		passed = passed + 1
	end
end

assert(read_file(script_path), "cannot read " .. script_path .. " (run make first)")

for _, s in ipairs(scenarios) do
	if not filter or s.name:find(filter, 1, true) then
		check(s.name, run_scenario(s))
	end
end

if not filter or ("webm.conf"):find(filter, 1, true) then
	local conf = read_file(conf_path)
	if conf then
		check("webm.conf", conf)
	else
		failures = failures + 1
		print("MISSING " .. conf_path .. " (run make first)")
	end
end

if update then
	print(string.format("%d golden file(s) written", written))
else
	print(string.format("%d passed, %d failed", passed, failures))
end
os.exit(failures == 0 and 0 or 1)
