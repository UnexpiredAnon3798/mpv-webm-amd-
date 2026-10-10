-- Golden (characterization) tests for the built webm.lua.
--
-- Usage, from the repository root (Lua 5.1 or LuaJIT):
--   lua tests/golden/run.lua                 compare against tests/golden/expected
--   lua tests/golden/run.lua --update        rewrite the expected files
--   lua tests/golden/run.lua encode_gif      only scenarios whose name contains "encode_gif"
--   lua tests/golden/run.lua --script PATH   test another build (default build/webm.lua)
--   lua tests/golden/run.lua --conf PATH     compare another webm.conf (default build/webm.conf)

GOLDEN_DIRECTORY = (arg[0]:match("^(.*[/\\])") or "./")

local fake_mpv = dofile(GOLDEN_DIRECTORY .. "fake_mpv.lua")
local scenarios = dofile(GOLDEN_DIRECTORY .. "scenarios.lua")
local json = fake_mpv.json

-- Lines of context shown above the first difference.
local CONTEXT_LINES = 3
local EXIT_SUCCESS, EXIT_FAILURE = 0, 1

local update = false
local script_path = "build/webm.lua"
local conf_path = "build/webm.conf"
local name_filter

local argument_index = 1
while argument_index <= #arg do
	local argument = arg[argument_index]
	if argument == "--update" then
		update = true
	elseif argument == "--script" then
		argument_index = argument_index + 1
		script_path = arg[argument_index]
	elseif argument == "--conf" then
		argument_index = argument_index + 1
		conf_path = arg[argument_index]
	else
		name_filter = argument
	end
	argument_index = argument_index + 1
end

local function read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return (content:gsub("\r\n", "\n"))
end

local function write_file(path, content)
	local file = assert(io.open(path, "wb"))
	file:write(content)
	file:close()
end

-- Each step is a table whose first entry is the step's name. The other
-- fields are named, for example { "range", start_time = 1, end_time = 2 }.
local steps = {}

function steps.key(world, step)
	world:log("> key " .. step.key)
	world:press(step.key)
end

function steps.options(world, step)
	local payload = json.encode(step.values)
	world:log("> set options " .. payload)
	world:script_message("mpv-webm-set-options", payload)
end

function steps.range(world, step)
	local payload = json.encode({ startTime = step.start_time, endTime = step.end_time, region = step.region })
	world:log("> set range " .. payload)
	world:script_message("mpv-webm-set-range", payload)
end

function steps.encode(world)
	world:log("> encode")
	world:script_message("mpv-webm-encode")
end

function steps.upload(world)
	world:log("> upload")
	world:script_message("mpv-webm-upload")
end

function steps.state(world)
	world:log("> get state")
	world:script_message("mpv-webm-get-state")
end

function steps.set(world, step)
	world:log("> set property " .. step.name .. " = " .. json.encode(step.value))
	world:set_property(step.name, step.value)
end

function steps.mouse(world, step)
	world:log(string.format("> mouse %d,%d", step.x, step.y))
	world.mouse_x, world.mouse_y = step.x, step.y
end

function steps.event(world, step)
	world:log("> event " .. step.name)
	world:fire_event(step.name)
end

function steps.run_pending_commands(world)
	world:log("> run async callbacks")
	world:run_pending_commands()
end

function steps.timers(world)
	world:log("> fire timers")
	world:fire_timers()
end

function steps.file(world, step)
	world:log("> file " .. step.path .. " = " .. json.encode(step.content))
	world.files[step.path] = step.content
end

function steps.bindings(world)
	world:log("> active forced bindings: " .. table.concat(world:active_bindings(), " "))
end

function steps.dump_options(world)
	world:log("> options")
	local options = world.options_table
	if not options then
		world:log("  (read_options was never called)")
		return
	end
	local names = {}
	for name in pairs(options) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		world:log("  " .. name .. " = " .. json.encode(options[name]) .. " (" .. type(options[name]) .. ")")
	end
end

function steps.note(world, step)
	world:log("# " .. step.text)
end

-- Encodes with the given output_template and reports only the output path.
function steps.filename(world, step)
	world.last_output_path = nil
	world.quiet_depth = world.quiet_depth + 1
	world:script_message("mpv-webm-set-options", json.encode({ output_template = step.template }))
	world:script_message("mpv-webm-encode")
	world:finish_encoders()
	world.quiet_depth = world.quiet_depth - 1
	world:log(json.encode(step.template) .. " -> " .. json.encode(world.last_output_path))
end

local function run_scenario(scenario)
	local world = fake_mpv.new(scenario.world or {})
	world:load_script(script_path)
	for _, step in ipairs(scenario.steps or {}) do
		local run_step = steps[step[1]]
		if not run_step then
			error("scenario " .. scenario.name .. ": unknown step " .. tostring(step[1]))
		end
		run_step(world, step)
		-- Encodes run in the background in mpv. Here they finish right away,
		-- unless the scenario holds them to look at the progress indicator.
		world:finish_encoders()
	end
	return table.concat(world.lines, "\n") .. "\n"
end

local function split_lines(text)
	local lines = {}
	for line in text:gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	return lines
end

-- Prints the first difference with a little context.
local function show_difference(expected, actual)
	local expected_lines, actual_lines = split_lines(expected), split_lines(actual)
	for line_number = 1, math.max(#expected_lines, #actual_lines) do
		if expected_lines[line_number] ~= actual_lines[line_number] then
			for context_line = math.max(1, line_number - CONTEXT_LINES), line_number - 1 do
				print("      " .. expected_lines[context_line])
			end
			print("  -   " .. tostring(expected_lines[line_number]))
			print("  +   " .. tostring(actual_lines[line_number]))
			return
		end
	end
end

local failed_count, passed_count, written_count = 0, 0, 0

local function check(name, actual)
	local path = GOLDEN_DIRECTORY .. "expected/" .. name .. ".txt"
	if update then
		if read_file(path) ~= actual then
			write_file(path, actual)
			written_count = written_count + 1
			print("updated " .. name)
		end
		return
	end
	local expected = read_file(path)
	if expected == nil then
		failed_count = failed_count + 1
		print("MISSING " .. name .. " (run with --update to create it)")
	elseif expected ~= actual then
		failed_count = failed_count + 1
		print("FAIL " .. name)
		show_difference(expected, actual)
	else
		passed_count = passed_count + 1
	end
end

assert(read_file(script_path), "cannot read " .. script_path .. " (run make first)")

for _, scenario in ipairs(scenarios) do
	if not name_filter or scenario.name:find(name_filter, 1, true) then
		check(scenario.name, run_scenario(scenario))
	end
end

if not name_filter or ("webm.conf"):find(name_filter, 1, true) then
	local conf_text = read_file(conf_path)
	if conf_text then
		check("webm.conf", conf_text)
	else
		failed_count = failed_count + 1
		print("MISSING " .. conf_path .. " (run make first)")
	end
end

if update then
	print(string.format("%d golden file(s) written", written_count))
else
	print(string.format("%d passed, %d failed", passed_count, failed_count))
end
os.exit(failed_count == 0 and EXIT_SUCCESS or EXIT_FAILURE)
