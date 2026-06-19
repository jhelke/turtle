# Lua and CC:Tweaked Turtle Quickstart

## Paste Into A Turtle

Create a program in-game:

```lua
edit status
edit fuelall
```

Use the matching files from `turtles/` as the source text.

## Lua Syntax Basics

```lua
local distance = 150
local name = "miner-01"
local ready = true

print("Turtle: " .. name)
print("Distance: " .. distance)
```

String joining uses `..`, not `+`.

```lua
if distance > 0 then
  print("ok")
else
  print("bad distance")
end
```

Loops:

```lua
for slot = 1, 16 do
  print(slot)
end
```

Functions:

```lua
local function isEmpty(slot)
  return turtle.getItemCount(slot) == 0
end
```

Tables:

```lua
local args = { ... }
local first = args[1]
```

Lua lists start at `1`, not `0`.

## Turtle API Basics

Movement:

```lua
turtle.forward()
turtle.back()
turtle.up()
turtle.down()
turtle.turnLeft()
turtle.turnRight()
```

Mining:

```lua
turtle.detect()
turtle.dig()
turtle.inspect()
```

Inventory:

```lua
turtle.select(1)
turtle.getItemCount(1)
turtle.getItemDetail(1)
turtle.drop()
turtle.suck()
```

Fuel:

```lua
turtle.getFuelLevel()
turtle.getFuelLimit()
turtle.refuel()
```

## Error Handling Habit

Most turtle actions can fail. Check their return values:

```lua
local ok, err = turtle.forward()

if not ok then
  print("Could not move: " .. tostring(err))
end
```

## Official Docs

- Turtle API: https://tweaked.cc/module/turtle.html
- Shell API: https://tweaked.cc/module/shell.html
- Filesystem API: https://tweaked.cc/module/fs.html
