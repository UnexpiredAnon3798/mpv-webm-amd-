-- Minimal JSON encode/decode for the golden harness. Stands in for
-- mp.utils.parse_json/format_json and lets scenarios build script-message
-- payloads. Object keys are emitted sorted so transcripts are deterministic.

local json = {}

-- Doubles hold every integer exactly up to 2^53.
local LARGEST_EXACT_INTEGER = 2 ^ 53
-- A \u escape is followed by 4 hexadecimal digits.
local UNICODE_ESCAPE_DIGITS = 4
local BYTE_VALUES = 256

local ESCAPES_FOR_ENCODING = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local ESCAPES_FOR_DECODING =
	{ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function encode_string(text)
	local escaped = text:gsub('[%c"\\]', function(character)
		return ESCAPES_FOR_ENCODING[character] or string.format("\\u%04x", character:byte())
	end)
	return '"' .. escaped .. '"'
end

local function is_array(value)
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return count > 0
end

function json.encode(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		-- mpv writes integral values as integers and other doubles with %f.
		if value == math.floor(value) and math.abs(value) < LARGEST_EXACT_INTEGER then
			return string.format("%d", value)
		end
		return string.format("%f", value)
	elseif kind == "string" then
		return encode_string(value)
	elseif kind == "table" then
		local parts = {}
		if is_array(value) then
			for _, item in ipairs(value) do
				parts[#parts + 1] = json.encode(item)
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for key in pairs(value) do
			keys[#keys + 1] = tostring(key)
		end
		table.sort(keys)
		for _, key in ipairs(keys) do
			parts[#parts + 1] = encode_string(key) .. ":" .. json.encode(value[key])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("cannot encode " .. kind)
end

function json.decode(text)
	local position = 1

	local function current_character()
		return text:sub(position, position)
	end

	local function skip_whitespace()
		position = text:find("[^ \t\r\n]", position) or #text + 1
	end

	-- Moves past the literal when it comes next, and says whether it did.
	local function consume(literal)
		if text:sub(position, position + #literal - 1) == literal then
			position = position + #literal
			return true
		end
		return false
	end

	local parse_value

	local function parse_string()
		local characters = {}
		consume('"')
		while true do
			local character = current_character()
			if character == "" then
				error("unterminated string")
			elseif consume('"') then
				return table.concat(characters)
			elseif consume("\\u") then
				local hex_digits = text:sub(position, position + UNICODE_ESCAPE_DIGITS - 1)
				characters[#characters + 1] = string.char(tonumber(hex_digits, 16) % BYTE_VALUES)
				position = position + UNICODE_ESCAPE_DIGITS
			elseif consume("\\") then
				characters[#characters + 1] = ESCAPES_FOR_DECODING[current_character()]
				position = position + 1
			else
				characters[#characters + 1] = character
				position = position + 1
			end
		end
	end

	-- Parses items separated by commas until the closing character.
	local function parse_items(closing, parse_item)
		skip_whitespace()
		if consume(closing) then
			return
		end
		while true do
			skip_whitespace()
			parse_item()
			skip_whitespace()
			if consume(closing) then
				return
			end
			consume(",")
		end
	end

	function parse_value()
		skip_whitespace()
		if consume("{") then
			local object = {}
			parse_items("}", function()
				local key = parse_string()
				skip_whitespace()
				consume(":")
				object[key] = parse_value()
			end)
			return object
		elseif consume("[") then
			local array = {}
			parse_items("]", function()
				array[#array + 1] = parse_value()
			end)
			return array
		elseif current_character() == '"' then
			return parse_string()
		elseif consume("true") then
			return true
		elseif consume("false") then
			return false
		elseif consume("null") then
			return nil
		end
		local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
		position = position + #number
		return tonumber(number)
	end

	return parse_value()
end

return json
