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
-- - The first lane dock has an output chest/barrel behind the turtle.
-- - The first lane dock has a fuel chest/barrel directly below the turtle.
-- - This wrapper owns dock service, fuel policy, and inventory policy.
-- - dockmine.lua is called only in script mode as a movement/mining primitive.

local args = { ... }

local depth = tonumber(args[1])
local width = tonumber(args[2])
local side = "right"
local margin = 32
local argError = nil

local function usage()
  print("Usage: wide_dockmine <depth> <width> [right|left] [fuel-margin]")
  print("   or: wide_dockmine <depth> <width> [fuel-margin]")
end

local function isPositiveWholeNumber(value)
  return value and value >= 1 and value == math.floor(value)
end

local function turnAround()
  turtle.turnLeft()
  turtle.turnLeft()
end

local function fuelLevel()
  local level = turtle.getFuelLevel()

  if level == "unlimited" then
    return math.huge
  end

  return level
end

local function fuelLimit()
  local limit = turtle.getFuelLimit()

  if limit == "unlimited" then
    return math.huge
  end

  return limit
end

local function isLikelyInventoryBlock(blockName)
  return type(blockName) == "string"
    and (string.find(blockName, "chest") ~= nil
      or string.find(blockName, "barrel") ~= nil)
end

local function emptySlotCount()
  local count = 0

  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then
      count = count + 1
    end
  end

  return count
end

local function findEmptySlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then
      return slot
    end
  end

  return nil
end

local function refuelFromInventory()
  if turtle.getFuelLevel() == "unlimited" then
    return
  end

  local previousSlot = turtle.getSelectedSlot()

  for slot = 1, 16 do
    turtle.select(slot)
    turtle.refuel()
  end

  turtle.select(previousSlot)
end

local function checkFuelChestBelow()
  local found, detail = turtle.inspectDown()
  local blockName = found and detail and detail.name or ""

  if not found then
    return false, "no fuel chest below turtle"
  end

  if not isLikelyInventoryBlock(blockName) then
    return false, "block below is " .. blockName .. ", not a chest/barrel"
  end

  return true, blockName
end

local function refuelFromChestBelow()
  if turtle.getFuelLevel() == "unlimited" then
    return true
  end

  local chestOk, chestMessage = checkFuelChestBelow()

  if not chestOk then
    print("Fuel chest check failed: " .. chestMessage)
    return false
  end

  refuelFromInventory()

  while fuelLevel() < fuelLimit() do
    local freeSlot = findEmptySlot()

    if not freeSlot then
      return true
    end

    turtle.select(freeSlot)

    local ok = turtle.suckDown(1)

    if not ok then
      break
    end

    local isFuel = turtle.refuel(0)

    if isFuel then
      turtle.refuel(1)
    else
      turtle.dropDown()
      print("Non-fuel item in fuel chest below.")
      break
    end
  end

  turtle.select(1)
  return true
end

local function checkOutputBehind()
  turnAround()

  local found, detail = turtle.inspect()
  local blockName = found and detail and detail.name or ""

  turnAround()

  if not found then
    return false, "no output chest behind turtle"
  end

  if not isLikelyInventoryBlock(blockName) then
    return false, "rear block is " .. blockName .. ", not a chest/barrel"
  end

  return true, blockName
end

local function unloadBehind()
  local outputOk, outputMessage = checkOutputBehind()

  if not outputOk then
    print("Output chest check failed: " .. outputMessage)
    return false
  end

  refuelFromInventory()
  turnAround()

  local allUnloaded = true
  local previousSlot = turtle.getSelectedSlot()

  for slot = 1, 16 do
    turtle.select(slot)

    if turtle.getItemCount(slot) > 0 then
      turtle.drop()

      if turtle.getItemCount(slot) > 0 then
        allUnloaded = false
      end
    end
  end

  turtle.select(previousSlot)
  turnAround()

  return allUnloaded
end

local function serviceDock()
  print("Servicing first-lane dock.")

  if not unloadBehind() then
    print("Output chest is full, missing, or blocked.")
    return false
  end

  if not refuelFromChestBelow() then
    print("Fuel chest is missing or invalid.")
    return false
  end

  refuelFromInventory()
  print("Fuel after dock service: " .. tostring(turtle.getFuelLevel()))

  return true
end

local function ensureFuel(required, context)
  if fuelLevel() >= required then
    return true
  end

  print("Not enough fuel " .. context .. ".")
  print("Fuel: " .. fuelLevel())
  print("Needed: " .. required)
  return false
end

local function ensureInventoryReady(lane)
  if emptySlotCount() >= 2 then
    return true
  end

  print("Inventory is full or near full before lane " .. lane .. ".")
  return false
end

local function fuelNeededForCurrentLaneOnly()
  return depth * 2 + margin
end

local function fuelNeededFromCurrentLane(lane)
  local lanesRemaining = width - lane + 1
  local sideStepsRemaining = lanesRemaining - 1
  local sideStepsBackToDockLane = width - lane

  return lanesRemaining * depth * 2
    + sideStepsRemaining
    + sideStepsBackToDockLane
    + margin
end

local function fuelNeededBeforeSideStep(nextLane)
  return 1 + fuelNeededFromCurrentLane(nextLane)
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

local function clearUp()
  local attempts = 0

  while turtle.detectUp() do
    turtle.digUp()
    sleep(0.2)

    attempts = attempts + 1

    if attempts > 20 then
      print("Could not clear upper side-step block.")
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

  local ok = clearForward() and forwardRobust() and clearUp()

  if direction == "right" then
    turtle.turnLeft()
  else
    turtle.turnRight()
  end

  return ok
end

local function oppositeSide(direction)
  if direction == "right" then
    return "left"
  end

  return "right"
end

local function returnToDockLane()
  local returnSide = oppositeSide(side)

  for offset = width - 1, 1, -1 do
    print("Returning " .. returnSide .. " toward dock lane")

    if not stepSide(returnSide) then
      print("Could not return to dock lane from offset " .. offset .. ".")
      return false
    end
  end

  return true
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

local function runDockmine(program, lane)
  print("")
  print("Starting lane " .. lane .. "/" .. width)
  print("Lane depth: " .. depth)

  local chunk, loadErr = loadfile(program)

  if not chunk then
    print("Could not load dockmine.lua: " .. tostring(loadErr))
    return false
  end

  local ok, result = pcall(chunk, tostring(depth), "script")

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

if not serviceDock() then
  print("Could not prepare the first-lane dock.")
  return false
end

if not ensureFuel(fuelNeededForCurrentLaneOnly(), "for lane 1") then
  return false
end

if not ensureInventoryReady(1) then
  return false
end

if not runDockmine(dockmineProgram, 1) then
  print("Stopping at lane 1.")
  return false
end

if width > 1 then
  if not serviceDock() then
    print("Could not prepare the dock before leaving for wider lanes.")
    return false
  end

  if not ensureFuel(fuelNeededBeforeSideStep(2), "for remaining lanes") then
    return false
  end
end

for lane = 2, width do
  if not ensureInventoryReady(lane) then
    return false
  end

  if not ensureFuel(fuelNeededBeforeSideStep(lane), "before moving to lane " .. lane) then
    return false
  end

  print("Moving " .. side .. " to lane " .. lane)

  if not stepSide(side) then
    print("Could not move to lane " .. lane .. ".")
    return false
  end

  if not ensureFuel(fuelNeededFromCurrentLane(lane), "from lane " .. lane) then
    return false
  end

  if not ensureInventoryReady(lane) then
    return false
  end

  if not runDockmine(dockmineProgram, lane) then
    print("Stopping at lane " .. lane .. ".")
    return false
  end
end

if width > 1 then
  if not ensureFuel(width - 1, "to return to the dock lane") then
    return false
  end

  if not returnToDockLane() then
    return false
  end
end

print("")
print("wide_dockmine complete")
return true
