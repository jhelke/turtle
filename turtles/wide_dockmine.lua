-- Wide dock tunnel miner wrapper.
-- Usage:
--   wide_dockmine <depth> <width> [right|left] [fuel-margin]
--   wide_dockmine <depth> <width> [fuel-margin]
--
-- Examples:
--   wide_dockmine 32 3
--   wide_dockmine 64 5 left
--   wide_dockmine 64 5 right 48
--   wide_dockmine 64 5 48
--
-- Dock assumptions:
-- - dockmine.lua is installed next to this script, or available as dockmine.
-- - Turtle starts at the first lane dock, facing the tunnel direction.
-- - Each lane dock has an output chest/barrel behind the turtle.
-- - Each lane dock has a fuel chest/barrel directly below the turtle.
-- - The script owns .dockmine_progress while it is running.

local args = { ... }

local depth = tonumber(args[1])
local width = tonumber(args[2])
local side = "right"
local margin = 32
local argError = nil
local stateFile = ".dockmine_progress"

local function usage()
  print("Usage: wide_dockmine <depth> <width> [right|left] [fuel-margin]")
  print("   or: wide_dockmine <depth> <width> [fuel-margin]")
end

local function isPositiveWholeNumber(value)
  return value and value >= 1 and value == math.floor(value)
end

local function clearForward()
  local attempts = 0

  while turtle.detect() do
    turtle.dig()
    sleep(0.2)

    attempts = attempts + 1

    if attempts > 20 then
      print("Could not clear side-step block.")
      return false
    end
  end

  return true
end

local function forwardRobust()
  for attempt = 1, 5 do
    local ok, reason = turtle.forward()

    if ok then
      return true
    end

    turtle.attack()
    turtle.dig()
    sleep(0.3)

    if attempt == 5 then
      print("Could not side-step: " .. tostring(reason))
    end
  end

  return false
end

local function stepSide(direction)
  if direction == "right" then
    turtle.turnRight()
  else
    turtle.turnLeft()
  end

  local ok = clearForward() and forwardRobust()

  if direction == "right" then
    turtle.turnLeft()
  else
    turtle.turnRight()
  end

  return ok
end

local function resolveDockmine()
  local candidates = {
    "dockmine",
    "dockmine.lua",
  }

  if shell and shell.getRunningProgram then
    local runningProgram = shell.getRunningProgram()
    local runningDir = runningProgram and fs.getDir(runningProgram) or ""

    if runningDir ~= "" then
      candidates[#candidates + 1] = fs.combine(runningDir, "dockmine")
      candidates[#candidates + 1] = fs.combine(runningDir, "dockmine.lua")
    end
  end

  for _, candidate in ipairs(candidates) do
    if shell and shell.resolveProgram then
      local resolved = shell.resolveProgram(candidate)

      if resolved then
        return resolved
      end
    end

    if fs.exists(candidate) and not fs.isDir(candidate) then
      return candidate
    end
  end

  return nil
end

local function resetDockmineProgress()
  if fs.exists(stateFile) then
    fs.delete(stateFile)
  end
end

local function runDockmine(program, lane)
  print("")
  print("Starting lane " .. lane .. "/" .. width)
  print("Lane depth: " .. depth)

  resetDockmineProgress()

  local chunk, loadErr = loadfile(program)

  if not chunk then
    print("Could not load dockmine.lua: " .. tostring(loadErr))
    return false
  end

  local ok, result = pcall(chunk, tostring(depth), tostring(margin))

  if not ok then
    print("dockmine.lua crashed: " .. tostring(result))
    return false
  end

  if result == false then
    print("dockmine.lua stopped with failure.")
    return false
  end

  return true
end

if args[3] == "right" or args[3] == "left" then
  side = args[3]

  if args[4] then
    margin = tonumber(args[4])

    if not margin then
      argError = "fuel-margin must be a non-negative whole number."
    end
  end
elseif args[3] then
  margin = tonumber(args[3])

  if not margin then
    argError = "third argument must be right, left, or a fuel margin."
  end
end

if args[5] then
  argError = "too many arguments."
end

if not isPositiveWholeNumber(depth) or not isPositiveWholeNumber(width) then
  usage()
  print("depth and width must be positive whole numbers.")
  return false
end

if argError then
  usage()
  print(argError)
  return false
end

if margin < 0 or margin ~= math.floor(margin) then
  usage()
  print("fuel-margin must be a non-negative whole number.")
  return false
end

local dockmineProgram = resolveDockmine()

if not dockmineProgram then
  print("Could not find dockmine.lua next to this script or on the shell path.")
  return false
end

print("wide_dockmine starting")
print("Depth: " .. depth)
print("Width: " .. width)
print("Side-step: " .. side)
print("Margin: " .. margin)
print("dockmine: " .. dockmineProgram)

for lane = 1, width do
  if not runDockmine(dockmineProgram, lane) then
    print("Stopping at lane " .. lane .. ".")
    return false
  end

  if lane < width then
    print("Moving " .. side .. " to lane " .. (lane + 1))

    if not stepSide(side) then
      print("Could not move to lane " .. (lane + 1) .. ".")
      return false
    end
  end
end

resetDockmineProgress()

print("")
print("wide_dockmine complete")
return true
