-- Runs an encode: checks the encoder, builds the commands, runs the passes,
-- reports the result and cleans up.

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")

local check = require("encode.check")
local command = require("encode.command")
local EncodeProgressPage = require("ui.encode_progress_page")
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

	events.emit("encode-started")

	-- Do the first pass now, as it won't require the output path. I don't think this works on streams.
	-- Also this will ignore run_detached, at least for the first pass.
	if plan.first_pass then
		osd.message("Starting first pass...")
		msg.verbose("First-pass command line: ", table.concat(plan.first_pass, " "))
		if not system.run({ args = plan.first_pass, cancellable = false }) then
			osd.message("First pass failed! Check the logs for details.")
			events.emit("encode-finished", "fail")
			fail()
			return
		end
		if plan.patch_vp8_log then
			-- We need to patch the pass log file before running the second pass.
			msg.verbose("Patching libvpx pass log file...")
			vp8_log.patch_file(plan.pass_log_path, times.outputDuration)
		end
	end

	msg.info("Encoding to", out_path)
	msg.verbose("Command line:", table.concat(plan.command, " "))

	if options.run_detached and not on_done then
		osd.message("Started encode, process was detached.")
		utils.subprocess_detached({ args = plan.command })
		return
	end

	local succeeded
	if not progress.should_display(options, system.is_windows) then
		osd.message("Started encode...")
		succeeded = system.run({ args = plan.command, cancellable = false })
	else
		succeeded = EncodeProgressPage.new(times.encoderStart, times.encoderEnd):run(plan.command)
	end

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

	for _, path in ipairs(plan.cleanup_paths) do
		os.remove(path)
	end
	if resolved.is_temporary then
		os.remove(resolved.path)
	end
end

return M
