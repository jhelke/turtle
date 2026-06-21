# Lua Runtime in CC:Tweaked

This project targets turtles running:

```text
cc-tweaked-1.20.1-forge-1.119.0
```

CC:Tweaked uses the Cobalt Lua runtime. For turtle programs, treat the language as
Lua 5.2 with selected compatibility features from Lua 5.3 and older Lua versions.

Official reference:

```text
https://tweaked.cc/reference/feature_compat.html
```

## Version

On a turtle, this should report:

```lua
print(_VERSION)
```

Expected output:

```text
Lua 5.2
```

## Type System

Lua is dynamically typed. Variables do not have fixed types; values do.

```lua
local x = 1
x = "hello" -- valid Lua
```

Lua is runtime-checked and mostly strongly typed. Invalid operations generally fail
at runtime instead of being caught before the program starts.

```lua
local t = {}
print(t + 1) -- runtime error
```

There is no standard static type checking in CC:Tweaked Lua.

## Practical Guarantees

- Pure Lua code is memory-safe at the language level.
- Execution is cooperative, not preemptively threaded.
- Coroutines and APIs such as `parallel` interleave only when code yields.
- Runtime errors stop the current program unless handled with `pcall` or `xpcall`.
- `nil` represents absence and is a common source of runtime mistakes.

## Important Compatibility Notes

- Do not assume full Lua 5.3 semantics.
- Lua 5.3 integer subtypes are not supported.
- Lua 5.3 native bitwise operators are not supported.
- Use `bit32` for bit operations.
- `collectgarbage` is not available in CC:Tweaked.
- `os.execute` and `os.exit` are not available in CC:Tweaked.
- Some Lua 5.3 library features are available, such as `utf8`, `table.move`, and
  `string.pack` / `string.unpack`.

