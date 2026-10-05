-- Minimal JSON encode/decode for the golden harness. Stands in for
-- mp.utils.parse_json/format_json and lets scenarios build script-message
-- payloads. Object keys are emitted sorted so transcripts are deterministic.

local json = {}

local function encode_string(s)
	local escaped = s:gsub('[%c"\\]', function(c)
		local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
		return named[c] or string.format("\\u%04x", c:byte())
	end)
	return '"' .. escaped .. '"'
end

local function is_array(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return n > 0
end

function json.encode(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		-- mpv writes integral values as integers and other doubles with %f.
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return string.format("%d", value)
		end
		return string.format("%f", value)
	elseif kind == "string" then
		return encode_string(value)
	elseif kind == "table" then
		local parts = {}
		if is_array(value) then
			for _, v in ipairs(value) do
				parts[#parts + 1] = json.encode(v)
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(value) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			parts[#parts + 1] = encode_string(k) .. ":" .. json.encode(value[k])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("cannot encode " .. kind)
end

function json.decode(text)
	local pos = 1

	local function skip()
		pos = text:find("[^ \t\r\n]", pos) or #text + 1
	end

	local parse

	local function parse_string()
		local out = {}
		pos = pos + 1
		while true do
			local c = text:sub(pos, pos)
			if c == "" then
				error("unterminated string")
			elseif c == '"' then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				local e = text:sub(pos + 1, pos + 1)
				local simple =
					{ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
				if e == "u" then
					out[#out + 1] = string.char(tonumber(text:sub(pos + 2, pos + 5), 16) % 256)
					pos = pos + 6
				else
					out[#out + 1] = simple[e]
					pos = pos + 2
				end
			else
				out[#out + 1] = c
				pos = pos + 1
			end
		end
	end

	function parse()
		skip()
		local c = text:sub(pos, pos)
		if c == "{" then
			local obj = {}
			pos = pos + 1
			skip()
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while true do
				skip()
				local key = parse_string()
				skip()
				pos = pos + 1 -- colon
				obj[key] = parse()
				skip()
				local sep = text:sub(pos, pos)
				pos = pos + 1
				if sep == "}" then
					return obj
				end
			end
		elseif c == "[" then
			local arr = {}
			pos = pos + 1
			skip()
			if text:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while true do
				arr[#arr + 1] = parse()
				skip()
				local sep = text:sub(pos, pos)
				pos = pos + 1
				if sep == "]" then
					return arr
				end
			end
		elseif c == '"' then
			return parse_string()
		elseif text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		end
		local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		pos = pos + #num
		return tonumber(num)
	end

	return parse()
end

return json
