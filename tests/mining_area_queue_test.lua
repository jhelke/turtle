local function assertEqual(actual, expected, label)
  if actual ~= expected then
    error(label .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 0)
  end
end

local hostOpen = io.open
local virtualFiles = {}
local serialized = {}
local nextSerialized = 0
local events = {}
local timerId = 0
local dispatchedOffsets = {}

local function queueEvent(...)
  events[#events + 1] = { ... }
end

_G.fs = {
  exists = function(path)
    if virtualFiles[path] ~= nil then
      return true
    end

    local file = hostOpen(path, "r")

    if file then
      file:close()
      return true
    end

    return false
  end,
  isDir = function()
    return false
  end,
  open = function(path, mode)
    if mode == "r" then
      local content = virtualFiles[path]

      if content == nil then
        return nil
      end

      return {
        readAll = function()
          return content
        end,
        close = function()
        end,
      }
    end

    local content = ""

    return {
      write = function(value)
        content = content .. tostring(value)
      end,
      close = function()
        virtualFiles[path] = content
      end,
    }
  end,
  delete = function(path)
    virtualFiles[path] = nil
  end,
  move = function(from, to)
    virtualFiles[to] = virtualFiles[from]
    virtualFiles[from] = nil
  end,
}

_G.textutils = {
  serialize = function(value)
    nextSerialized = nextSerialized + 1
    local key = "serialized:" .. nextSerialized
    serialized[key] = value
    return key
  end,
  unserialize = function(value)
    return serialized[value]
  end,
}

local inventories = {}

local function inventory()
  return {
    list = function()
      return {}
    end,
    pushItems = function()
      return 0
    end,
  }
end

inventories.output = inventory()
inventories.storage = inventory()

_G.peripheral = {
  getNames = function()
    return {
      "left",
      "output",
      "storage",
    }
  end,
  getType = function(name)
    if name == "left" then
      return "modem"
    end

    if inventories[name] then
      return "minecraft:chest"
    end

    return nil
  end,
  wrap = function(name)
    return inventories[name]
  end,
}

_G.rs = {
  getSides = function()
    return {
      "left",
      "right",
      "top",
      "bottom",
      "front",
      "back",
    }
  end,
}

local protocol = "minecraft-cc-t:mining_area"

_G.rednet = {
  isOpen = function()
    return true
  end,
  open = function()
  end,
  send = function(target, message, sentProtocol)
    assertEqual(target, 21, "rednet target")
    assertEqual(sentProtocol, protocol, "rednet protocol")

    if message.type == "fuel-query" then
      queueEvent("rednet_message", 21, {
        type = "fuel-report",
        queryId = message.queryId,
        jobId = message.jobId,
        turtleId = 21,
        fuel = "unlimited",
        fuelLimit = "unlimited",
        progress = 0,
      }, protocol)
    elseif message.type == "job" then
      local params = message.params
      dispatchedOffsets[#dispatchedOffsets + 1] = params.laneOffset

      queueEvent("rednet_message", 21, {
        type = "turtle-status",
        turtleId = 21,
        jobId = message.jobId,
        status = "running",
        message = "mining lane " .. params.laneOffset,
        fuel = "unlimited",
        laneId = params.laneId,
        laneOffset = params.laneOffset,
        clearedThrough = params.resumeFrom,
        targetDistance = params.targetDistance,
      }, protocol)
      queueEvent("rednet_message", 21, {
        type = "turtle-status",
        turtleId = 21,
        jobId = message.jobId,
        status = "complete",
        message = "lane target reached",
        fuel = "unlimited",
        laneId = params.laneId,
        laneOffset = params.laneOffset,
        clearedThrough = params.targetDistance,
        targetDistance = params.targetDistance,
      }, protocol)
    else
      error("unexpected rednet message: " .. tostring(message.type), 0)
    end

    return true
  end,
}

local hostClock = os.clock

_G.os = {
  getComputerID = function()
    return 7
  end,
  epoch = function()
    return 1000000
  end,
  clock = hostClock,
  startTimer = function()
    timerId = timerId + 1
    return timerId
  end,
  pullEvent = function()
    if #events == 0 then
      error("controller waited with no queued test event", 0)
    end

    local event = events[1]
    table.remove(events, 1)
    return table.unpack(event)
  end,
}

_G.shell = {
  resolveProgram = function()
    return nil
  end,
}

_G.write = function()
end

_G.read = function()
  return ""
end

local miningArea = assert(loadfile("computers/mining_area.lua"))
local result = miningArea("5", "tests/mining_area_config_test.lua")

assertEqual(result, true, "mining area result")
assertEqual(#dispatchedOffsets, 3, "dispatched lane count")
assertEqual(dispatchedOffsets[1], 0, "center lane order")
assertEqual(dispatchedOffsets[2], -1, "left lane order")
assertEqual(dispatchedOffsets[3], 1, "right lane order")

local ledgerToken = virtualFiles.test_lane_checkpoints
local ledger = serialized[ledgerToken]
local completed = 0

for _, lane in pairs(ledger.lanes) do
  assertEqual(lane.clearedThrough, 5, "persisted lane checkpoint")
  assertEqual(lane.state, "complete", "persisted lane state")
  completed = completed + 1
end

assertEqual(completed, 3, "persisted lane count")

local secondMiningArea = assert(loadfile("computers/mining_area.lua"))
local secondResult = secondMiningArea("5", "tests/mining_area_config_test.lua")

assertEqual(secondResult, true, "resumed mining area result")
assertEqual(#dispatchedOffsets, 3, "completed lanes were not redispatched")
print("mining_area_queue_test: ok")
