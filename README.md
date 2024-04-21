# luau-struct
A super fast and lightweight struct implementation in luau using buffers. 

- "b" a signed char.
- "B" an unsigned char.
- "h" a signed short (2 bytes).
- "H" an unsigned short (2 bytes).
- "i" a signed int (4 bytes).
- "I" an unsigned int (4 bytes).
- "l" a signed long (8 bytes).
- "L" an unsigned long (8 bytes).
- "f" a float (4 bytes).
- "d" a double (8 bytes).
- "s" a zero-terminated string.
- "cn" a sequence of exactly n chars corresponding to a single Lua string (if n <= 0 then for packing - the string length is taken, unpacking - the number value of the previous unpacked value which is not returned).

```lua
local packed: buffer = struct.pack('<LI', 123456789123456789, 123456789)
local L, I = struct.unpack('<LI', packed)
print(L, I)

print(buffer.tostring(packed))
```
