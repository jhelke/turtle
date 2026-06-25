-- Standalone cardinal tunnel miner for a fixed dock.
-- Usage:
--   dockmine 8
--   dockmine 32
--   dockmine 32 script
--   dockmine 32 48 script
--   dockmine
--
-- Dock assumptions:
-- - Turtle starts at the dock facing the tunnel direction.
-- - Output chest/barrel is directly behind the turtle.
-- - Fuel chest/barrel is directly below the turtle.
-- - The script owns .dockmine_progress on this turtle.
-- - Script mode is a caller-owned primitive: it performs only movement and
--   block mining/placing work. It does not use dock service, progress state,
--   fuel policy, or inventory policy.
--
-- The tunnel shape is 1 wide x 2 high. This is not the same shape as the
-- stock CC:Tweaked tunnel program.

-- GLOBALS

local args = { ... }
local maxNewBlocks = nil
local margin = 32
local scriptMode = false
local argError = nil
local stateFile = ".dockmine_progress"

local function turnAround()
  turtle.turnLeft()
  turtle.turnLeft()
end

-- FUNCTIONS

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

local function isProtectedBlock(blockName)
  return type(blockName) == "string"
    and string.find(blockName, "torch", 1, true) ~= nil
end

local function readProgress()
  if not fs.exists(stateFile) then
    return 0
  end

  local file = fs.open(stateFile, "r")

  if not file then
    return 0
  end

  local content = file.readAll()
  file.close()

  return tonumber(content) or 0
end

local function writeProgress(progress)
  local file = fs.open(stateFile, "w")

  if not file then
    print("Could not write progress file.")
    return false
  end

  file.write(tostring(progress))
  file.close()

  return true
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

    local ok = turtle.suckDown()

    if not ok then
      break
    end

    local isFuel = turtle.refuel(0)

    if isFuel then
      turtle.refuel()

      if turtle.getItemCount(freeSlot) > 0 then
        turtle.dropDown()
      end
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

local function clearForward()
  local attempts = 0

  while turtle.detect() do
    local found, detail = turtle.inspect()
    local blockName = found and detail and detail.name or ""

    if isProtectedBlock(blockName) then
      print("Protected pass-through block in front: " .. blockName)
      return true
    end

    turtle.dig()
    sleep(0.2)

    attempts = attempts + 1

    if attempts > 20 then
      print("Could not clear forward block.")
      return false
    end
  end

  return true
end

local function clearUp()
  local attempts = 0

  while turtle.detectUp() do
    local found, detail = turtle.inspectUp()
    local blockName = found and detail and detail.name or ""

    if isProtectedBlock(blockName) then
      print("Protected pass-through block above: " .. blockName)
      return true
    end

    turtle.digUp()
    sleep(0.2)

    attempts = attempts + 1

    if attempts > 20 then
      print("Could not clear upper block.")
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

    local found, detail = turtle.inspect()
    local blockName = found and detail and detail.name or ""

    if isProtectedBlock(blockName) then
      print("Protected block in front: " .. blockName)
      return false
    end

    turtle.dig()
    sleep(0.3)

    if attempt == 5 then
      print("Could not move forward: " .. tostring(reason))
    end
  end

  return false
end

local function moveToFace(progress)
  print("Moving to tunnel face: " .. progress .. " blocks")

  local moved = 0

  for _ = 1, progress do
    if not clearForward() then
      return false, moved
    end

    if not forwardRobust() then
      return false, moved
    end

    moved = moved + 1
  end

  return true, moved
end

local function returnHome(distance)
  print("Returning home: " .. distance .. " blocks")

  turnAround()

  for _ = 1, distance do
    if not clearForward() then
      print("Return blocked.")
      return false
    end

    if not forwardRobust() then
      print("Could not return home.")
      return false
    end
  end

  turnAround()
  return true
end

local function canReachFaceAndReturn(progress)
  return fuelLevel() >= (progress * 2 + margin + 2)
end

local function canMineOneMoreAndReturn(distanceFromDock)
  return fuelLevel() >= (distanceFromDock + 2 + margin)
end

local function mineOneStep()
  if not clearForward() then
    return false, false
  end

  if not forwardRobust() then
    return false, false
  end

  if not clearUp() then
    return false, true
  end

  return true, true
end

local function runScriptMode(depth)
  local moved = 0

  print("dockmine script mode starting")
  print("Depth: " .. depth)
  print("Fuel: " .. tostring(turtle.getFuelLevel()))

  for step = 1, depth do
    local stepOk, didMove = mineOneStep()

    if didMove then
      moved = moved + 1
    end

    if not stepOk then
      print("Script mode failed at step " .. step .. ".")

      if moved > 0 then
        if not returnHome(moved) then
          print("Could not return to script start. Manual rescue needed.")
          return false
        end
      end

      return false
    end

    if step % 16 == 0 then
      print("Script mode mined blocks: " .. step)
      print("Fuel: " .. tostring(turtle.getFuelLevel()))
    end
  end

  if not returnHome(moved) then
    print("Could not return to script start. Manual rescue needed.")
    return false
  end

  print("dockmine script mode complete")
  return true
end

local function isScriptModeArg(value)
  return value == "script"
    or value == "--script"
    or value == "--script-mode"
    or value == "--skip-dock-checks"
end

local function usage()
  print("Usage: dockmine [max-new-blocks] [fuel-margin] [script]")
  print("Mines a 1x2 tunnel from a fixed dock.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return true
end

if args[1] then
  maxNewBlocks = tonumber(args[1])

  if not maxNewBlocks then
    argError = "max-new-blocks must be a positive whole number."
  end
end

if args[2] then
  if isScriptModeArg(args[2]) then
    scriptMode = true
  else
    margin = tonumber(args[2])

    if not margin then
      argError = "fuel-margin must be a non-negative whole number."
    end
  end
end

if args[3] then
  if isScriptModeArg(args[3]) then
    scriptMode = true
  else
    argError = "third argument must be script mode."
  end
end

if args[4] then
  argError = "too many arguments."
end

if argError then
  usage()
  print(argError)
  return false
end

if maxNewBlocks and (maxNewBlocks < 1 or maxNewBlocks ~= math.floor(maxNewBlocks)) then
  usage()
  print("max-new-blocks must be a positive whole number.")
  return false
end

if margin < 0 or margin ~= math.floor(margin) then
  usage()
  print("fuel-margin must be a non-negative whole number.")
  return false
end

if scriptMode and not maxNewBlocks then
  usage()
  print("script mode requires max-new-blocks.")
  return false
end

if scriptMode then
  return runScriptMode(maxNewBlocks)
end

-- EXECUTION CODE

local progress = readProgress()
local minedThisRun = 0

print("dockmine starting")
print("Saved tunnel progress: " .. progress)
print("Fuel: " .. tostring(turtle.getFuelLevel()))
print("Margin: " .. margin)

while true do
  print("")
  print("At dock. Progress: " .. progress)

  if not unloadBehind() then
    print("Output chest is full, missing, or blocked. Stopping at dock.")
    return false
  end

  if not refuelFromChestBelow() then
    print("Fuel chest is missing or invalid. Stopping at dock.")
    return false
  end

  refuelFromInventory()

  print("Fuel after refuel: " .. tostring(turtle.getFuelLevel()))

  if maxNewBlocks and minedThisRun >= maxNewBlocks then
    print("Reached test limit: " .. maxNewBlocks)
    return true
  end

  if not canReachFaceAndReturn(progress) then
    print("Not enough fuel to reach face and return.")
    print("Fuel: " .. fuelLevel())
    print("Needed: " .. (progress * 2 + margin + 2))
    return false
  end

  local faceOk, movedToFace = moveToFace(progress)

  if not faceOk then
    print("Failed while moving to face. Manual rescue needed.")

    if movedToFace and movedToFace > 0 then
      print("Returning from partial face approach.")

      if not returnHome(movedToFace) then
        print("Could not return to dock. Manual rescue needed.")
      end
    end

    return false
  end

  local reason = "unknown"

  while true do
    refuelFromInventory()

    if maxNewBlocks and minedThisRun >= maxNewBlocks then
      reason = "test limit reached"
      break
    end

    if emptySlotCount() < 2 then
      reason = "inventory full or near full"
      break
    end

    if not canMineOneMoreAndReturn(progress) then
      reason = "fuel return threshold"
      break
    end

    local stepOk, moved = mineOneStep()

    if moved then
      progress = progress + 1
      minedThisRun = minedThisRun + 1

      if not writeProgress(progress) then
        print("Progress could not be saved. Returning before continuing.")
        reason = "progress save failed"
        break
      end
    end

    if not stepOk then
      reason = "blocked or failed mining"
      break
    end

    if minedThisRun % 16 == 0 then
      print("Mined new blocks: " .. minedThisRun)
      print("Total tunnel progress: " .. progress)
      print("Fuel: " .. fuelLevel())
    end
  end

  print("Returning because: " .. reason)

  if not returnHome(progress) then
    print("Could not return to dock. Manual rescue needed.")
    return false
  end
end
