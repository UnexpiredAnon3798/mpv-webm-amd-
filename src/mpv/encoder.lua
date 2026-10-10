-- Runs an encode: checks the encoder, builds the commands, runs the passes,
-- reports the result and cleans up. The passes run in the background, so the
-- player stays usable and a progress indicator can update.

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")

local check = require("encode.check")
local command = require("encode.command")
local events = require("mpv.events")
local formats = require("encode.formats")
local host = require("mpv.host")
local options = require("mpv.options")
local osd = require("ui.osd")
local progress = require("encode.progress")
local source = require("encode.source")
local system = require("mpv.system")
local vp8_log = require("encode.vp8_log")

local M = {}

-- How often the progress indicator updates, and how long each update stays.
local PROGRESS_INTERVAL_SECONDS = 0.5
local PROGRESS_MESSAGE_SECONDS = 1

local function check_encoder()
	local result = utils.subprocess({ args = check.ENCODER_ARGS, cancellable = false })
	local explanation = check.encoder_problem(result)
	if not explanation then
		return true
	end
	msg.error(explanation)
	msg.error("Encoder startup check: ", result.error or "", result.stderr or "", result.stdout or "")
	osd.message(explanation, 10)
	events.emit("encode-finished", "fail", explanation)
	return false
end

local function resolve_source(start_time, end_time)
	local resolved = source.resolve(host, start_time, end_time)
	if not resolved then
		return nil
	end
	if resolved.warning then
		msg.warn(resolved.warning)
	end
	if resolved.dump_cache then
		mp.command_native(resolved.dump_cache)
	end
	return resolved
end

local function write_file(path, text)
	local file = io.open(path, "w")
	if not file then
		return false
	end
	file:write(text)
	file:close()
	return true
end

---Runs one encoder pass in the background and calls on_finished(succeeded).
---With a progress file, shows "<label> 45%" until the pass ends.
---@param arguments string[]
---@param label string
---@param times webm.EncodeTimes
---@param progress_paths? {script: string, position: string}
---@param on_finished fun(succeeded: boolean)
local function run_pass(arguments, label, times, progress_paths, on_finished)
	local timer = nil
	if progress_paths then
		local with_progress = {}
		for index, argument in ipairs(arguments) do
			with_progress[index] = argument
		end
		for _, argument in ipairs(progress.encoder_arguments(progress_paths.script, progress_paths.position)) do
			with_progress[#with_progress + 1] = argument
		end
		arguments = with_progress
		-- Start from 0%, not from where the previous pass ended.
		os.remove(progress_paths.position)

		local function show_progress()
			local percent =
				progress.percent(system.read_file(progress_paths.position), times.encoderStart, times.encoderEnd)
			mp.osd_message(label .. " " .. percent .. "%", PROGRESS_MESSAGE_SECONDS)
		end
		show_progress()
		timer = mp.add_periodic_timer(PROGRESS_INTERVAL_SECONDS, show_progress)
	end

	msg.verbose(label .. " command line:", table.concat(arguments, " "))
	mp.command_native_async({
		name = "subprocess",
		args = arguments,
		playback_only = false,
		capture_stdout = true,
	}, function(success, result)
		if timer then
			timer:kill()
		end
		local succeeded = success and result ~= nil and result.status == 0
		if not succeeded then
			msg.verbose("Command failed! Reason: ", result and result.error_string or "")
		end
		on_finished(succeeded)
	end)
end

---Encodes the range. on_done(success, out_path) is called when it finishes;
---without it, the encode may run detached.
---@param region webm.Region
---@param start_time number
---@param end_time number
---@param on_done? fun(success: boolean, out_path?: string)
function M.encode(region, start_time, end_time, on_done)
	local format = formats.by_id[options.output_format]
	local function fail()
		if on_done then
			on_done(false)
		end
	end

	if not check_encoder() then
		fail()
		return
	end

	local resolved = resolve_source(start_time, end_time)
	if not resolved then
		osd.message("No file is being played")
		fail()
		return
	end

	local plan = command.build(host, options, {
		format = format,
		region = region,
		path = resolved.path,
		is_stream = resolved.is_stream,
		start_time = resolved.start_time,
		end_time = resolved.end_time,
		original_start_time = start_time,
		original_end_time = end_time,
	})
	for _, entry in ipairs(plan.messages) do
		msg[entry.level](entry.text)
	end
	local out_path = plan.out_path
	local times = plan.times

	-- The encoder reports its position through a file next to the output.
	local progress_paths = nil
	if progress.should_display(options) then
		local paths = { script = out_path .. ".progress.lua", position = out_path .. ".progress" }
		if write_file(paths.script, progress.ENCODER_SCRIPT) then
			progress_paths = paths
		end
	end

	local function remove_progress_files()
		if progress_paths then
			os.remove(progress_paths.script)
			os.remove(progress_paths.position)
		end
	end

	local function clean_up()
		for _, path in ipairs(plan.cleanup_paths) do
			os.remove(path)
		end
		remove_progress_files()
		if resolved.is_temporary then
			os.remove(resolved.path)
		end
	end

	local function finish(succeeded)
		if succeeded then
			osd.message("Encoded successfully! Saved to\\N" .. osd.bold(out_path))
			events.emit("encode-finished", "success")
			if options.completion_command ~= "" then
				mp.command((options.completion_command:gsub("%%{output}", out_path)))
			end
			if on_done then
				on_done(true, out_path)
			end
		else
			osd.message("Encode failed! Check the logs for details.")
			events.emit("encode-finished", "fail")
			fail()
		end
		clean_up()
	end

	local function run_final_pass()
		msg.info("Encoding to", out_path)
		if options.run_detached and not on_done then
			osd.message("Started encode, process was detached.")
			utils.subprocess_detached({ args = plan.command })
			remove_progress_files()
			return
		end
		if not progress_paths then
			osd.message("Started encode...")
		end
		run_pass(plan.command, "Encoding", times, progress_paths, finish)
	end

	events.emit("encode-started")

	if not plan.first_pass then
		run_final_pass()
		return
	end

	-- The first pass ignores run_detached. I don't think two passes work on streams.
	osd.message("Starting first pass...")
	run_pass(plan.first_pass, "First pass", times, progress_paths, function(succeeded)
		if not succeeded then
			osd.message("First pass failed! Check the logs for details.")
			events.emit("encode-finished", "fail")
			fail()
			remove_progress_files()
			return
		end
		if plan.patch_vp8_log then
			-- We need to patch the pass log file before running the second pass.
			msg.verbose("Patching libvpx pass log file...")
			vp8_log.patch_file(plan.pass_log_path, times.outputDuration)
		end
		run_final_pass()
	end)
end

return M
