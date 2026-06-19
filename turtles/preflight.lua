-- v0 preflight wrapper for CC:Tweaked mining turtles.
-- Usage: preflight 150
--
-- This script does not change the turtle's position. It briefly turns around
-- to verify rear output storage, turns back, then passes the distance through
-- to the stock turtle tunnel program.

local args = { ... }
local rawDistance = args[1]
local distance = tonumber(rawDistance)

local function fail(message)
  print("Preflight failed: " .. message)
  return false
end

local function check(condition, message)
  if condition then
    print("[ok] " .. message)
    return true
  end

  print("[fail] " .. message)
  return false
end

local function countUsedSlots()
  local used = 0

  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      used = used + 1
    end
  end

  return used
end

local function hasLikelyPickaxe()
  local left = turtle.getEquippedLeft and turtle.getEquippedLeft()
  local right = turtle.getEquippedRight and turtle.getEquippedRight()
  local leftName = left and left.name or ""
  local rightName = right and right.name or ""

  return string.find(leftName, "pickaxe") ~= nil
    or string.find(rightName, "pickaxe") ~= nil
end

local function isLikelyOutputChest(blockName)
  return string.find(blockName, "chest") ~= nil
    or string.find(blockName, "barrel") ~= nil
end

local function turnRightOrReport()
  local ok, err = turtle.turnRight()

  if not ok then
    return false, tostring(err)
  end

  return true
end

local function turnAround()
  local ok, err = turnRightOrReport()

  if not ok then
    return false, err
  end

  ok, err = turnRightOrReport()

  if not ok then
    return false, err
  end

  return true
end

local function checkRearOutputChest()
  local turnedAround, turnErr = turnAround()

  if not turnedAround then
    return false, "could not turn around to check rear output chest: " .. turnErr
  end

  local found, detail = turtle.inspect()
  local blockName = found and detail and detail.name or ""
  local chestOk = found and isLikelyOutputChest(blockName)
  local turnBackOk, turnBackErr = turnAround()

  if not turnBackOk then
    return false, "checked rear block but could not turn back to tunnel direction: " .. turnBackErr
  end

  if not found then
    return false, "no block behind turtle for output chest"
  end

  if not chestOk then
    return false, "rear block is " .. blockName .. ", not a chest/barrel"
  end

  return true, "rear output storage found: " .. blockName
end

local function printHeader()
  print("Tunnel preflight")
  print("Label: " .. tostring(os.getComputerLabel()))
  print("ID: " .. os.getComputerID())
end

printHeader()

if not turtle then
  return fail("this program must run on a turtle")
end

if not rawDistance then
  print("Usage: preflight <distance>")
  print("Example: preflight 150")
  return false
end

if not distance or distance < 1 or distance ~= math.floor(distance) then
  return fail("distance must be a positive whole number")
end

local ok = true
local tunnelProgram = shell.resolveProgram("tunnel")
local fuelLevel = turtle.getFuelLevel()
local usedSlots = countUsedSlots()
local minFuel = distance + 10
local rearChestOk, rearChestMessage = checkRearOutputChest()

ok = check(tunnelProgram ~= nil, "stock tunnel program is available") and ok
ok = check(hasLikelyPickaxe(), "mining pickaxe upgrade appears equipped") and ok
ok = check(rearChestOk, rearChestMessage) and ok

if fuelLevel == "unlimited" then
  ok = check(true, "fuel is unlimited")
else
  ok = check(fuelLevel >= minFuel, "fuel " .. fuelLevel .. " >= " .. minFuel .. " minimum") and ok
end

ok = check(usedSlots <= 12, "inventory has at least 4 empty slots") and ok

print("[info] distance: " .. distance)
print("[info] output chest is behind and was checked by turning in place")
print("[info] v0 will not return home after tunnel finishes")

if not ok then
  return fail("fix failed checks before mining")
end

print("Starting: tunnel " .. distance)
return shell.run("tunnel", tostring(distance))
