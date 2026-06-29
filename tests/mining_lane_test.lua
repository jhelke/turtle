local function assertEqual(actual, expected, label)
  if actual ~= expected then
    error(label .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 0)
  end
end

local state = {
  x = 0,
  z = 0,
  direction = 0,
  selected = 1,
  slots = {},
  dropped = 0,
}

local function reset()
  state.x = 0
  state.z = 0
  state.direction = 0
  state.selected = 1
  state.slots = {}
  state.dropped = 0
end

local function frontPosition()
  if state.direction == 0 then
    return state.x, state.z + 1
  elseif state.direction == 1 then
    return state.x + 1, state.z
  elseif state.direction == 2 then
    return state.x, state.z - 1
  end

  return state.x - 1, state.z
end

local function fillSlots(count)
  state.slots = {}

  for slot = 1, count do
    state.slots[slot] = 1
  end
end

_G.sleep = function()
end

_G.fs = {
  exists = function(path)
    local file = io.open(path, "r")

    if file then
      file:close()
      return true
    end

    return false
  end,
  isDir = function()
    return false
  end,
}

_G.shell = nil

_G.turtle = {
  getFuelLevel = function()
    return "unlimited"
  end,
  getFuelLimit = function()
    return "unlimited"
  end,
  getSelectedSlot = function()
    return state.selected
  end,
  select = function(slot)
    state.selected = slot
    return true
  end,
  getItemCount = function(slot)
    return state.slots[slot or state.selected] or 0
  end,
  getItemSpace = function(slot)
    return 64 - (state.slots[slot or state.selected] or 0)
  end,
  getItemDetail = function(slot)
    if (state.slots[slot or state.selected] or 0) > 0 then
      return {
        name = "minecraft:cobblestone",
        count = state.slots[slot or state.selected],
      }
    end

    return nil
  end,
  turnLeft = function()
    state.direction = (state.direction + 3) % 4
    return true
  end,
  turnRight = function()
    state.direction = (state.direction + 1) % 4
    return true
  end,
  forward = function()
    state.x, state.z = frontPosition()
    return true
  end,
  detect = function()
    return false
  end,
  detectUp = function()
    return false
  end,
  inspect = function()
    local x, z = frontPosition()

    if x == 0 and z == -1 then
      return true, {
        name = "minecraft:chest",
      }
    end

    return false
  end,
  inspectUp = function()
    return false
  end,
  inspectDown = function()
    return false
  end,
  dig = function()
    return true
  end,
  digUp = function()
    return true
  end,
  attack = function()
    return true
  end,
  place = function()
    return true
  end,
  refuel = function()
    return false
  end,
  suckDown = function()
    return false
  end,
  dropDown = function()
    return true
  end,
  drop = function()
    local x, z = frontPosition()

    if x ~= 0 or z ~= -1 then
      return false, "no output inventory"
    end

    if (state.slots[state.selected] or 0) > 0 then
      state.slots[state.selected] = 0
      state.dropped = state.dropped + 1
    end

    return true
  end,
}

reset()

local dockmine = assert(loadfile("turtles/dockmine.lua"))
local firstProgress = {}
local firstResult = dockmine({
  mode = "managed-lane",
  targetDepth = 5,
  resumeFrom = 0,
  onProgress = function(step)
    firstProgress[#firstProgress + 1] = step

    if step == 3 then
      fillSlots(15)
    end

    return true
  end,
})

assertEqual(firstResult.ok, true, "partial dockmine result")
assertEqual(firstResult.complete, false, "partial dockmine completion")
assertEqual(firstResult.clearedThrough, 3, "partial dockmine checkpoint")
assertEqual(state.x, 0, "partial dockmine lateral position")
assertEqual(state.z, 0, "partial dockmine depth position")
assertEqual(state.direction, 0, "partial dockmine direction")

fillSlots(0)

local secondResult = dockmine({
  mode = "managed-lane",
  targetDepth = 5,
  resumeFrom = firstResult.clearedThrough,
  onProgress = function()
    return true
  end,
})

assertEqual(secondResult.ok, true, "resumed dockmine result")
assertEqual(secondResult.complete, true, "resumed dockmine completion")
assertEqual(secondResult.clearedThrough, 5, "resumed dockmine checkpoint")
assertEqual(state.z, 0, "resumed dockmine depth position")
assertEqual(state.direction, 0, "resumed dockmine direction")

reset()

local wideDockmine = assert(loadfile("turtles/wide_dockmine.lua"))
local reportedProgress = 0
local wideResult = wideDockmine({
  mode = "managed-lane",
  targetDepth = 5,
  laneOffset = -2,
  resumeFrom = 0,
  fuelMargin = 2,
  dockminePath = "turtles/dockmine.lua",
  onProgress = function(step)
    reportedProgress = step

    if step == 3 or step == 4 then
      fillSlots(15)
    end

    return true
  end,
})

assertEqual(wideResult.ok, true, "wide managed lane result")
assertEqual(wideResult.complete, true, "wide managed lane completion")
assertEqual(wideResult.clearedThrough, 5, "wide managed lane checkpoint")
assertEqual(reportedProgress, 5, "wide managed lane callback")
assertEqual(state.x, 0, "wide managed lane lateral position")
assertEqual(state.z, 0, "wide managed lane depth position")
assertEqual(state.direction, 0, "wide managed lane direction")
assertEqual(state.dropped > 0, true, "wide managed lane unload")

print("mining_lane_test: ok")
