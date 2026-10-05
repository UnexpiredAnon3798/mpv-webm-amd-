-- Uploading the encoded clip. Only Catbox's two services are supported: both
-- expose the same anonymous multipart API, differing only by endpoint and the
-- required litterbox expiry. streamable.com is intentionally absent: its upload
-- API requires an account (HTTP 401) and its web upload routes 404.
--
-- The POST itself is a single curl call.

local M = {}

---@class webm.UploadHost
---@field id string
---@field label string
---@field url string
---@field uses_expiry boolean sends options.litterbox_time

---@type table<string, webm.UploadHost>
local HOSTS = {
	catbox = {
		id = "catbox",
		label = "catbox.moe",
		url = "https://catbox.moe/user/api.php",
		uses_expiry = false,
	},
	litterbox = {
		id = "litterbox",
		label = "litterbox.catbox.moe",
		url = "https://litterbox.catbox.moe/resources/internals/api.php",
		uses_expiry = true,
	},
}

---Unknown ids fall back to catbox.
---@param id string
---@return webm.UploadHost
function M.host(id)
	return HOSTS[id] or HOSTS.catbox
end

---Values for the options page, in order.
---@return string[][]
function M.host_choices()
	return { { "catbox", "catbox.moe" }, { "litterbox", "litterbox.catbox.moe" } }
end

-- curl treats comma and semicolon specially inside -F values; escape them so a
-- filename containing either still resolves to a single file.
local function escape_form_path(path)
	return (path:gsub("([,;])", "\\%1"))
end

---The curl command. The response body (the URL) goes to response_path; curl's
---progress meter and errors go to progress_path; the HTTP status is printed to
---stdout.
---@param options webm.Options
---@param path string file to upload
---@param response_path string
---@param progress_path string
---@return string[]
function M.curl_args(options, path, response_path, progress_path)
	local host = M.host(options.upload_host)
	local args = {
		options.upload_curl_path,
		"-#",
		"-S",
		"-o",
		response_path,
		"--stderr",
		progress_path,
		"-w",
		"%{http_code}",
		"-F",
		"reqtype=fileupload",
	}

	local expiry = host.uses_expiry and options.litterbox_time or nil
	if expiry and expiry ~= "" then
		args[#args + 1] = "-F"
		args[#args + 1] = "time=" .. tostring(expiry)
	end

	if host.id == "catbox" and options.catbox_userhash ~= "" then
		args[#args + 1] = "-F"
		args[#args + 1] = "userhash=" .. tostring(options.catbox_userhash)
	end

	args[#args + 1] = "-F"
	args[#args + 1] = "fileToUpload=@" .. escape_form_path(path)
	args[#args + 1] = host.url
	return args
end

---The last percentage in curl's progress meter output, if any.
---@param content string
---@return number?
function M.progress_percent(content)
	local percent = nil
	for match in content:gmatch("(%d+%.?%d*)%%") do
		percent = tonumber(match)
	end
	return percent
end

---Checks curl's result. Returns the uploaded URL, or nil and an error message.
---@param success boolean the subprocess command ran
---@param result? table the subprocess result
---@param err? string
---@param response string what curl wrote to response_path, trimmed
---@return string? url
---@return string? error_message
function M.parse_result(success, result, err, response)
	local http_code = result and tonumber(result.stdout)
	local ok = success
		and result
		and result.status == 0
		and http_code
		and http_code >= 200
		and http_code < 300
		and response:match("^https?://")
	if ok then
		return response
	end
	local message = response
	if message == "" then
		message = (result and result.error_string) or tostring(err) or "upload failed"
	end
	return nil, (message:gsub("%s+", " "):sub(1, 300))
end

return M
