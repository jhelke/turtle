-- Wide dock tunnel miner wrapper.
-- Usage:
--   wide_dockmine <depth> <width> [right|left] [fuel-margin] [offset <lanes>]
--   wide_dockmine <depth> <width> [fuel-margin] [offset <lanes>]
--   wide_dockmine <depth> <width> [right|left] [fuel-margin] [offset <lanes>] [dockmine <path>]
--
-- Examples:
--   wide_dockmine 32 3
--   wide_dockmine 64 5 left
--   wide_dockmine 64 5 right 48
--   wide_dockmine 64 5 48
--   wide_dockmine 64 3 right 48 offset 2
--   wide_dockmine 64 3 right offset=2
--
-- Dock assumptions:
-- - dockmine.lua is installed next to this script, or available as dockmine.
-- - Turtle starts at the first lane dock, facing the tunnel direction.
-- - The first lane dock has an output chest/barrel behind the turtle.
-- - The first lane dock has a fuel chest/barrel directly below the turtle.
-- - This wrapper owns dock service, fuel policy, and inventory policy.
-- - dockmine.lua is called only in script mode as a movement/mining primitive.

local args = { ... }
local managedTask = type(args[1]) == "table" and args[1] or nil

local depth = tonumber(args[1])
local width = tonumber(args[2])
local side = "right"
local margin = 32
local offset = 0
local dockminePath = nil
local argError = nil

if managedTask and managedTask.mode == "managed-lane" then
  local laneOffset = tonumber(managedTask.laneOffset)

  depth = tonumber(managedTask.targetDepth)
  width = 1
  margin = tonumber(managedTask.fuelMargin) or margin
  offset = laneOffset and math.abs(laneOffset) or nil
  side = laneOffset and laneOffset < 0 and "left" or "right"
  dockminePath = managedTask.dockminePath
end

local function usage()
  print("Usage: wide_dockmine <depth> <width> [right|left] [fuel-margin] [offset <lanes>]")
  print("   or: wide_dockmine <depth> <width> [fuel-margin] [offset <lanes>] [dockmine <path>]")
  print("Runs dockmine lanes from one serviced dock.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return true
end

local function isPositiveWholeNumber(value)
  return value and value >= 1 and value == math.floor(value)
end

local function isNonNegativeWholeNumber(value)
  return value and value >= 0 and value == math.floor(value)
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

local function isProtectedBlock(blockName)
  return type(blockName) == "string"
    and string.find(blockName, "torch", 1, true) ~= nil
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

local function fuelNeededFromRun(run)
  local lanesRemaining = width - run + 1
  local sideStepsRemaining = lanesRemaining - 1
  local sideStepsBackToDockLane = offset + width - 1

  return lanesRemaining * depth * 2
    + sideStepsRemaining
    + sideStepsBackToDockLane
    + margin
end

local function fuelNeededBeforeSideStep(nextRun)
  return 1 + fuelNeededFromRun(nextRun)
end

local function fuelNeededBeforeInitialOffset()
  return offset + fuelNeededFromRun(1)
end

local function clearForward()
  local attempts = 0

  while turtle.detect() do
    local found, detail = turtle.inspect()
    local blockName = found and detail and detail.name or ""

    if isProtectedBlock(blockName) then
      return true
    end

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
      print("Could not clear upper side-step block.")
      return false
    end
  end

  return true
end

local function forwardCleared()
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
      print("Could not side-step: " .. tostring(reason))
    end
  end

  return false
end

local function findProtectedItemSlot(preferredSlot)
  if preferredSlot then
    local detail = turtle.getItemDetail(preferredSlot)
    if detail and isProtectedBlock(detail.name) then
      return preferredSlot
    end
  end

  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and isProtectedBlock(detail.name) then
      return slot
    end
  end

  return nil
end

local function findProtectedPickupSlot()
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail
      and isProtectedBlock(detail.name)
      and turtle.getItemSpace(slot) > 0 then
      return slot
    end
  end

  return findEmptySlot()
end

local function moveThroughProtectedBlock(blockName)
  local previousSlot = turtle.getSelectedSlot()
  local pickupSlot = findProtectedPickupSlot()

  if not pickupSlot then
    print("No inventory space to preserve block: " .. blockName)
    return false
  end

  turtle.select(pickupSlot)

  local dug, digReason = turtle.dig()
  if not dug then
    turtle.select(previousSlot)
    print("Could not pick up protected block: " .. tostring(digReason))
    return false
  end

  local protectedSlot = findProtectedItemSlot(pickupSlot)
  if not protectedSlot then
    turtle.select(previousSlot)
    print("Could not retain protected block after digging: " .. blockName)
    return false
  end

  if not forwardCleared() then
    turtle.select(protectedSlot)
    turtle.place()
    turtle.select(previousSlot)
    return false
  end

  turnAround()
  turtle.select(protectedSlot)

  local placed, placeReason = turtle.place()
  if placed then
    turnAround()
    turtle.select(previousSlot)
    return true
  end

  print("Could not place protected block behind turtle: " .. tostring(placeReason))
  print("Returning to restore it in its original position.")

  local returned = turtle.forward()
  turnAround()

  if returned then
    local restored, restoreReason = turtle.place()
    if not restored then
      print("Could not restore protected block: " .. tostring(restoreReason))
    end
  else
    print("Could not return to the protected block's original position.")
  end

  turtle.select(previousSlot)
  return false
end

local function forwardRobust()
  local found, detail = turtle.inspect()
  local blockName = found and detail and detail.name or ""

  if isProtectedBlock(blockName) then
    print("Temporarily relocating protected block: " .. blockName)
    return moveThroughProtectedBlock(blockName)
  end

  return forwardCleared()
end

local currentSideOffset = 0

local function offsetAfterSideStep(direction)
  if direction == side then
    return currentSideOffset + 1
  end

  local offset = currentSideOffset - 1

  if offset < 0 then
    return 0
  end

  return offset
end

local function recordSideStep(direction, moved)
  if not moved then
    return
  end

  if direction == side then
    currentSideOffset = currentSideOffset + 1
  else
    currentSideOffset = currentSideOffset - 1

    if currentSideOffset < 0 then
      currentSideOffset = 0
    end
  end
end

local function stepSide(direction, quiet)
  local nextOffset = offsetAfterSideStep(direction)

  if direction == "right" then
    turtle.turnRight()
  else
    turtle.turnLeft()
  end

  local ok = false
  local moved = false

  if clearForward() and forwardRobust() then
    moved = true

    if nextOffset == 0 then
      if not quiet then
        print("Skipping dock-up clearance on dock lane.")
      end
      ok = true
    else
      ok = clearUp()
    end
  end

  if direction == "right" then
    turtle.turnLeft()
  else
    turtle.turnRight()
  end

  return ok, moved
end

local function moveSideSteps(direction, count, label, quiet)
  for step = 1, count do
    if not quiet then
      print(label .. ": " .. step .. "/" .. count)
    end

    local ok, moved = stepSide(direction, quiet)

    recordSideStep(direction, moved)

    if not ok then
      print("Could not complete side-step " .. step .. "/" .. count .. ".")
      return false
    end
  end

  return true
end

local function oppositeSide(direction)
  if direction == "right" then
    return "left"
  end

  return "right"
end

local function returnToDockLane(distance)
  local returnSide = oppositeSide(side)

  return moveSideSteps(returnSide, distance, "Returning " .. returnSide .. " toward dock lane")
end

local function failAndReturnToDockLane(message)
  print(message)

  if currentSideOffset <= 0 then
    return false
  end

  print("Attempting return to dock lane from side offset " .. currentSideOffset)

  if not returnToDockLane(currentSideOffset) then
    print("Could not return to dock lane. Manual rescue needed.")
  end

  return false
end

local function resolveDockmine()
  if dockminePath and dockminePath ~= "" then
    if fs.exists(dockminePath) and not fs.isDir(dockminePath) then
      return dockminePath
    end

    if shell and shell.resolveProgram then
      local resolved = shell.resolveProgram(dockminePath)

      if resolved then
        return resolved
      end
    end
  end

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

local function runDockmine(program, lane, run, resumeFrom, onProgress)
  print("")
  print("Starting lane " .. lane .. " (" .. run .. "/" .. width .. ")")
  print("Lane depth: " .. depth)

  local chunk, loadErr = loadfile(program)

  if not chunk then
    print("Could not load dockmine.lua: " .. tostring(loadErr))
    return false
  end

  local ok, result

  if resumeFrom ~= nil then
    ok, result = pcall(chunk, {
      mode = "managed-lane",
      targetDepth = depth,
      resumeFrom = resumeFrom,
      onProgress = onProgress,
    })
  else
    ok, result = pcall(chunk, tostring(depth), "script")
  end

  if not ok then
    print("dockmine.lua crashed: " .. tostring(result))
    return false
  end

  if result == false then
    print("dockmine.lua stopped with failure.")
    return false
  end

  if type(result) == "table" and result.ok == false then
    print("dockmine.lua stopped: " .. tostring(result.message))
    return false, result.message, result
  end

  return true, nil, result
end

local function managedLaneResult(ok, complete, clearedThrough, message)
  return {
    ok = ok,
    complete = complete,
    clearedThrough = clearedThrough,
    message = message,
  }
end

local function runManagedLane()
  local laneOffset = tonumber(managedTask.laneOffset)
  local resumeFrom = tonumber(managedTask.resumeFrom) or 0
  local onProgress = managedTask.onProgress

  if not isPositiveWholeNumber(depth) then
    return managedLaneResult(false, false, resumeFrom, "invalid target depth")
  end

  if not laneOffset
    or laneOffset == 0
    or laneOffset ~= math.floor(laneOffset) then
    return managedLaneResult(false, false, resumeFrom, "invalid side lane offset")
  end

  if not isNonNegativeWholeNumber(resumeFrom) or resumeFrom > depth then
    return managedLaneResult(false, false, resumeFrom, "invalid resume depth")
  end

  if margin < 0 or margin ~= math.floor(margin) then
    return managedLaneResult(false, false, resumeFrom, "invalid fuel margin")
  end

  if onProgress ~= nil and type(onProgress) ~= "function" then
    return managedLaneResult(false, false, resumeFrom, "invalid progress callback")
  end

  local dockmineProgram = resolveDockmine()

  if not dockmineProgram then
    return managedLaneResult(false, false, resumeFrom, "dockmine is not installed")
  end

  local clearedThrough = resumeFrom
  local noProgressPasses = 0

  print("Managed lane offset " .. laneOffset
    .. " depth " .. clearedThrough .. "/" .. depth)

  while clearedThrough < depth do
    if not serviceDock() then
      return managedLaneResult(
        false,
        false,
        clearedThrough,
        "could not service dock"
      )
    end

    local requiredFuel = offset * 2 + depth * 2 + margin

    if not ensureFuel(requiredFuel, "for lane offset " .. laneOffset) then
      return managedLaneResult(
        false,
        false,
        clearedThrough,
        "not enough fuel for lane"
      )
    end

    if not moveSideSteps(side, offset, "Moving " .. side .. " to lane", true) then
      local returned = moveSideSteps(
        oppositeSide(side),
        currentSideOffset,
        "Returning to dock lane",
        true
      )

      if returned then
        unloadBehind()
      end

      return managedLaneResult(
        false,
        false,
        clearedThrough,
        returned and "could not reach managed lane" or "could not return to dock lane"
      )
    end

    local before = clearedThrough
    local laneOk, laneMessage, laneResult = runDockmine(
      dockmineProgram,
      offset,
      1,
      clearedThrough,
      onProgress
    )

    if type(laneResult) == "table" then
      clearedThrough = tonumber(laneResult.clearedThrough) or clearedThrough
    end

    if not moveSideSteps(
      oppositeSide(side),
      currentSideOffset,
      "Returning to dock lane",
      true
    ) then
      return managedLaneResult(
        false,
        false,
        clearedThrough,
        "could not return to dock lane"
      )
    end

    if not unloadBehind() then
      return managedLaneResult(
        false,
        false,
        clearedThrough,
        "could not unload at dock"
      )
    end

    if not laneOk then
      return managedLaneResult(
        false,
        false,
        clearedThrough,
        laneMessage or "lane mining failed"
      )
    end

    if type(laneResult) == "table" and laneResult.complete then
      return managedLaneResult(true, true, clearedThrough, "lane target reached")
    end

    if clearedThrough <= before then
      noProgressPasses = noProgressPasses + 1

      if noProgressPasses < 3 then
        print("Lane traversal filled inventory; servicing dock before retry.")
      else
        return managedLaneResult(
          false,
          false,
          clearedThrough,
          "lane made no checkpoint progress after repeated dock service"
        )
      end
    else
      noProgressPasses = 0
    end

    print("Lane paused for dock service at " .. clearedThrough .. "/" .. depth)
  end

  return managedLaneResult(true, true, clearedThrough, "lane target already reached")
end

local seenSide = false
local seenMargin = false
local seenOffset = false
local argIndex = 3

if managedTask then
  if managedTask.mode ~= "managed-lane" then
    return managedLaneResult(false, false, 0, "unsupported internal task")
  end

  return runManagedLane()
end

while args[argIndex] do
  local arg = args[argIndex]

  if arg == "right" or arg == "left" then
    if seenSide then
      argError = "side can only be set once."
      break
    end

    side = arg
    seenSide = true
    argIndex = argIndex + 1
  elseif arg == "offset" then
    if seenOffset then
      argError = "offset can only be set once."
      break
    end

    if not args[argIndex + 1] then
      argError = "offset requires a lane count."
      break
    end

    offset = tonumber(args[argIndex + 1])
    seenOffset = true
    argIndex = argIndex + 2
  elseif string.sub(arg, 1, 7) == "offset=" then
    if seenOffset then
      argError = "offset can only be set once."
      break
    end

    offset = tonumber(string.sub(arg, 8))
    seenOffset = true
    argIndex = argIndex + 1
  elseif arg == "dockmine" then
    if not args[argIndex + 1] then
      argError = "dockmine requires a path."
      break
    end

    dockminePath = args[argIndex + 1]
    argIndex = argIndex + 2
  elseif string.sub(arg, 1, 9) == "dockmine=" then
    dockminePath = string.sub(arg, 10)
    argIndex = argIndex + 1
  else
    local number = tonumber(arg)

    if number and not seenMargin then
      margin = number
      seenMargin = true
      argIndex = argIndex + 1
    elseif number then
      argError = "extra number must use offset <lanes> or offset=<lanes>."
      break
    else
      argError = "unknown argument: " .. tostring(arg)
      break
    end
  end
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

if not isNonNegativeWholeNumber(offset) then
  usage()
  print("offset must be a non-negative whole number.")
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
print("Offset: " .. offset)
print("Side-step: " .. side)
print("Margin: " .. margin)
print("dockmine: " .. dockmineProgram)

if not serviceDock() then
  print("Could not prepare the first-lane dock.")
  return false
end

if offset == 0 then
  if not ensureFuel(fuelNeededForCurrentLaneOnly(), "for lane 1") then
    return false
  end
else
  if not ensureFuel(fuelNeededBeforeInitialOffset(), "for offset and new lanes") then
    return false
  end

  print("Skipping " .. offset .. " previously mined lanes " .. side)

  if not moveSideSteps(side, offset, "Moving " .. side .. " through mined lanes") then
    return failAndReturnToDockLane(
      "Could not move through previously mined lanes."
    )
  end
end

for run = 1, width do
  local lane = offset + run

  if run > 1 or offset > 0 then
    if not ensureFuel(fuelNeededFromRun(run), "from lane " .. lane) then
      return failAndReturnToDockLane("Not enough fuel from lane " .. lane .. ".")
    end
  end

  if not ensureInventoryReady(lane) then
    return failAndReturnToDockLane("Inventory is not ready before lane " .. lane .. ".")
  end

  if not runDockmine(dockmineProgram, lane, run) then
    return failAndReturnToDockLane("Stopping at lane " .. lane .. ".")
  end

  if offset == 0 and run == 1 and width > 1 then
    if not serviceDock() then
      print("Could not prepare the dock before leaving for wider lanes.")
      return false
    end
  end

  if run < width then
    local nextRun = run + 1
    local nextLane = offset + nextRun

    if not ensureInventoryReady(nextLane) then
      return failAndReturnToDockLane(
        "Inventory is not ready before lane " .. nextLane .. "."
      )
    end

    if not ensureFuel(fuelNeededBeforeSideStep(nextRun), "before moving to lane " .. nextLane) then
      return failAndReturnToDockLane("Not enough fuel before moving to lane " .. nextLane .. ".")
    end

    print("Moving " .. side .. " to lane " .. nextLane)

    local stepOk, moved = stepSide(side)

    recordSideStep(side, moved)

    if not stepOk then
      return failAndReturnToDockLane("Could not move to lane " .. nextLane .. ".")
    end
  end
end

local returnDistance = offset + width - 1

if returnDistance > 0 then
  if not ensureFuel(returnDistance, "to return to the dock lane") then
    return failAndReturnToDockLane("Not enough fuel to return to the dock lane.")
  end

  if not returnToDockLane(returnDistance) then
    return false
  end
end

if not unloadBehind() then
  print("Final unload failed.")
  print("Clear the dock output chest, then retry the job.")
  return false
end

print("")
print("wide_dockmine complete")
return true
