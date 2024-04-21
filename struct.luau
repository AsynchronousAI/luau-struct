--!native
--!optimize 2
--!strict

local struct = {}

function struct.pack(format: string, size: number?, ...)
	local predictedSize = size or 2048
	local vars = {...}

	local stream = buffer.create(predictedSize)
	local endianness = true

	local ind = 0

	for i = 1, format:len() do
		local opt = (format:sub(i, i) :: string)

		if opt == '<' then
			endianness = true
		elseif opt == '>' then
			endianness = false
		elseif opt:find('[bBhHiIlL]') then
			local n = opt:find('[hH]') and 2 or opt:find('[iI]') and 4 or opt:find('[lL]') and 8 or 1
			local val = (tonumber(table.remove(vars, 1)) :: number)

			local bytes = {}
			for j = 1, n do
				table.insert(bytes, string.char(val % (2 ^ 8)))
				val = math.floor(val / (2 ^ 8))
			end
			local data
			if not endianness then
				data = string.reverse(table.concat(bytes))
			else
				data = table.concat(bytes)
			end
			buffer.writestring(stream, ind, data)
			ind += #data
		elseif opt:find('[fd]') then
			local val = (tonumber(table.remove(vars, 1))  :: number)
			local sign = 0

			if val < 0 then
				sign = 1
				val = (-val :: number)
			end

			local mantissa, exponent = math.frexp(val)
			if val == 0 then
				mantissa = 0
				exponent = 0
			else
				mantissa = (mantissa * 2 - 1) * math.ldexp(0.5, (opt == 'd') and 53 or 24)
				exponent = exponent + ((opt == 'd') and 1022 or 126)
			end

			local bytes = {}
			if opt == 'd' then
				val = mantissa
				for i = 1, 6 do
					table.insert(bytes, string.char(math.floor(val) % (2 ^ 8)))
					val = math.floor(val / (2 ^ 8))
				end
			else
				table.insert(bytes, string.char(math.floor(mantissa) % (2 ^ 8)))
				val = math.floor(mantissa / (2 ^ 8))
				table.insert(bytes, string.char(math.floor(val) % (2 ^ 8)))
				val = math.floor(val / (2 ^ 8))
			end

			table.insert(bytes, string.char(math.floor(exponent * ((opt == 'd') and 16 or 128) + val) % (2 ^ 8)))
			val = math.floor((exponent * ((opt == 'd') and 16 or 128) + val) / (2 ^ 8))
			table.insert(bytes, string.char(math.floor(sign * 128 + val) % (2 ^ 8)))
			val = math.floor((sign * 128 + val) / (2 ^ 8))

			local data
			if not endianness then
				data = string.reverse(table.concat(bytes))
			else
				data = table.concat(bytes)
			end
			buffer.writestring(stream, ind, data)
			ind += #data
		elseif opt == 's' then
			local data = tostring(table.remove(vars, 1))

			buffer.writestring(stream, ind, data)
			ind += #data
			buffer.writestring(stream, ind, string.char(0))
			ind += 1
		elseif opt == 'c' then
			local n = format:sub(i + 1):match('%d+')
			local str = tostring(table.remove(vars, 1))
			local len = (tonumber(n) :: number)
			if len <= 0 then
				len = str:len()
			end
			if len - str:len() > 0 then
				str = str .. string.rep(' ', len - str:len())
			end
			local data = str:sub(1, len)
			buffer.writestring(stream, ind, data)
			ind += #data
			i = i + (n :: string):len()
		end
	end

	return stream
end

function struct.unpack(format: string, stream: buffer, pos: number?)
	local vars = {}
	local iterator = pos or 1
	local endianness = true

	for i = 1, format:len() do
		local opt: string = format:sub(i, i)

		if opt == '<' then
			endianness = true
		elseif opt == '>' then
			endianness = false
		elseif opt:find('[bBhHiIlL]') then
			local n = opt:find('[hH]') and 2 or opt:find('[iI]') and 4 or opt:find('[lL]') and 8 or 1
			local signed = opt:lower() == opt

			local val = 0
			for j = 1, n do
				local byte = buffer.readi8(stream, iterator)
				if endianness then
					val = val + byte * (2 ^ ((j - 1) * 8))
				else
					val = val + byte * (2 ^ ((n - j) * 8))
				end
				iterator = iterator + 1
			end

			if signed and val >= 2 ^ (n * 8 - 1) then
				val = val - 2 ^ (n * 8)
			end

			table.insert(vars, math.floor(val))
		elseif opt:find('[fd]') then
			local n = if (opt == 'd') then 8 else 4
			local x = --[[stream:sub(iterator, iterator + n - 1)]] buffer.readstring(stream, iterator, n)
			iterator = iterator + n

			if not endianness then
				x = string.reverse(x)
			end

			local sign = 1
			local mantissa = string.byte(x, (opt == 'd') and 7 or 3) % ((opt == 'd') and 16 or 128)
			for i = n - 2, 1, -1 do
				mantissa = mantissa * (2 ^ 8) + string.byte(x, i)
			end

			if string.byte(x, n) > 127 then
				sign = -1
			end

			local exponent = (string.byte(x, n) % 128) * ((opt == 'd') and 16 or 2) + math.floor(string.byte(x, n - 1) / ((opt == 'd') and 16 or 128))
			if exponent == 0 then
				table.insert(vars, 0.0)
			else
				mantissa = (math.ldexp(mantissa, (opt == 'd') and -52 or -23) + 1) * sign
				table.insert(vars, math.ldexp(mantissa, exponent - ((opt == 'd') and 1023 or 127)))
			end
		elseif opt == 's' then
			local bytes = {}
			for j = iterator, buffer.len(stream) do
				local val = buffer.readstring(stream, j, 1)
				if val == string.char(0) or val == '' then
					break
				end

				table.insert(bytes, val)
			end

			local str = table.concat(bytes)
			iterator = iterator + str:len() + 1
			table.insert(vars, str)
		elseif opt == 'c' then
			local val = buffer.readstring(stream, i + 1, 1)
			local n: string = (val:match('%d+') :: string)
			local len = (tonumber(n) :: number)
			if len <= 0 then
				len = (table.remove(vars) :: number)
			end

			val = buffer.readstring(stream, iterator, len)
			table.insert(vars, val)
			iterator = iterator + len
			i = i + n:len()
		end
	end

	return unpack(vars)
end

return struct
