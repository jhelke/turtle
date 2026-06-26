-- Managed mining area controller.
-- Usage:
--   mining_area <target-distance> [config-file]
--   mining_area service [config-file]
--   mining_area peripherals
--   mining_area docks [config-file]
--   mining_area discover [config-file] [timeout-seconds]
--   mining_area add-turtle [config-file]
--
-- This runs on a normal computer. It schedules one dock mining job for each
-- configured turtle and services the fuel/output chests connected by modem.

local args = { ... }

local DEFAULT_PROTOCOL = "minecraft-cc-t:mining_area"
local DEFAULT_CONFIG = "mining_area_config"
local DEFAULT_FUEL_ITEM = "minecraft:coal"
local DEFAULT_FUEL_MAX_ITEMS_PER_JOB = 256
local DEFAULT_FUEL_UNITS_PER_ITEM = 80
local DEFAULT_FUEL_MARGIN = 32
local DEFAULT_FUEL_QUERY_TIMEOUT = 5
local DEFAULT_LEFT_LANES = 20
local DEFAULT_RIGHT_LANES = 20
local DEFAULT_SERVICE_INTERVAL = 5
local DEFAULT_STATUS_TIMEOUT = 45
local DEFAULT_HEARTBEAT_INTERVAL = 3
local DEFAULT_DOCK_REGISTRY = "mining_area_docks"
local DEFAULT_DISCOVERY_TIMEOUT = 3
local PLACEHOLDER_CARDINAL_DIRECTION = "Awaiting-User-Input"

local LEGACY_DIRECTIONS = {
  "north",
  "east",
  "south",
  "west",
}

local INVENTORY_CLASSES = {
  "chest",
  "barrel",
}

local INVENTORY_CLASS_LOOKUP = {
  chest = true,
  barrel = true,
}

local function usage()
  print("Usage:")
  print("  mining_area <target-distance> [config-file]")
  print("  mining_area service [config-file]")
  print("  mining_area peripherals")
  print("  mining_area docks [config-file]")
  print("  mining_area discover [config-file] [timeout-seconds]")
  print("  mining_area add-turtle [config-file]")
end

local function isPositiveWholeNumber(value)
  return value and value >= 1 and value == math.floor(value)
end

local function isNonNegativeWholeNumber(value)
  return value and value >= 0 and value == math.floor(value)
end

local function nowSeconds()
  if os.epoch then
    return math.floor(os.epoch("utc") / 1000)
  end

  return math.floor(os.clock())
end

local function formatList(values)
  local out = ""

  for index, value in ipairs(values or {}) do
    if index > 1 then
      out = out .. ", "
    end

    out = out .. tostring(value)
  end

  return out
end

local function appendInventoryName(names, seen, name)
  if type(name) ~= "string" or name == "" or seen[name] then
    return
  end

  names[#names + 1] = name
  seen[name] = true
end

local function appendInventoryNames(names, seen, value)
  if type(value) == "string" then
    appendInventoryName(names, seen, value)
    return
  end

  if type(value) ~= "table" then
    return
  end

  for _, name in ipairs(value) do
    appendInventoryNames(names, seen, name)
  end
end

local function appendPrefixedInventoryNames(names, seen, prefix, suffixes)
  if type(prefix) ~= "string" or prefix == "" or type(suffixes) ~= "table" then
    return
  end

  for _, suffix in ipairs(suffixes) do
    if type(suffix) == "number" or type(suffix) == "string" then
      appendInventoryName(names, seen, prefix .. tostring(suffix))
    end
  end
end

local function inventoryNames(value)
  local names = {}
  local seen = {}

  if type(value) == "table" then
    appendInventoryNames(names, seen, value)

    for prefix, suffixes in pairs(value) do
      if type(prefix) == "string" and not INVENTORY_CLASS_LOOKUP[prefix] then
        appendPrefixedInventoryNames(names, seen, prefix, suffixes)
      end
    end

    for _, className in ipairs(INVENTORY_CLASSES) do
      appendInventoryNames(names, seen, value[className])
    end
  else
    appendInventoryNames(names, seen, value)
  end

  return names
end

local function configuredStorageTargets(dock, config)
  if dock and (dock.storage ~= nil or dock.storageChests ~= nil) then
    return inventoryNames(dock.storage or dock.storageChests)
  end

  return inventoryNames(config.storage or config.storageChests)
end

local function configuredFuelSources(dock, config)
  if dock and (dock.fuelStorage ~= nil or dock.fuelStorageChests ~= nil) then
    return inventoryNames(dock.fuelStorage or dock.fuelStorageChests)
  end

  return inventoryNames(config.fuelStorage or config.fuelStorageChests)
end

local function configuredFuelMaxItems(dock, config)
  if dock and dock.fuelMaxItemsPerJob ~= nil then
    return tonumber(dock.fuelMaxItemsPerJob)
  end

  if dock and dock.fuelTargetItems ~= nil then
    return tonumber(dock.fuelTargetItems)
  end

  if config.fuelMaxItemsPerJob ~= nil then
    return tonumber(config.fuelMaxItemsPerJob)
  end

  return tonumber(config.fuelTargetItems)
end

local function configuredFuelUnitsPerItem(dock, config)
  if dock and dock.fuelUnitsPerItem ~= nil then
    return tonumber(dock.fuelUnitsPerItem)
  end

  return tonumber(config.fuelUnitsPerItem)
end

local function configuredFuelMargin(dock, config)
  if dock and dock.fuelMargin ~= nil then
    return tonumber(dock.fuelMargin)
  end

  return tonumber(config.fuelMargin)
end

local function configuredLeftLanes(dock, config)
  if dock and dock.leftLanes ~= nil then
    return tonumber(dock.leftLanes)
  end

  return tonumber(config.leftLanes)
end

local function configuredRightLanes(dock, config)
  if dock and dock.rightLanes ~= nil then
    return tonumber(dock.rightLanes)
  end

  return tonumber(config.rightLanes)
end

local function configuredSideLanes(dock, config)
  return configuredLeftLanes(dock, config) or 0,
    configuredRightLanes(dock, config) or 0
end

local function isBlank(value)
  return value == nil or tostring(value) == ""
end

local function containsLegacyDirection(value)
  for _, direction in ipairs(LEGACY_DIRECTIONS) do
    if value == direction then
      return true
    end
  end

  return false
end

local function dockDisplayName(dock)
  if dock.name and dock.name ~= "" then
    return dock.name
  end

  if dock.label and dock.label ~= "" then
    return dock.label
  end

  if dock.cardinalDirection and dock.cardinalDirection ~= "" then
    return dock.cardinalDirection
  end

  if dock.turtleId then
    return "turtle-" .. tostring(dock.turtleId)
  end

  return dock.key or "dock"
end

local function makeDefaultConfig(configPath)
  return {
    configPath = configPath or DEFAULT_CONFIG,
    areaId = "mining_area_" .. os.getComputerID(),
    protocol = DEFAULT_PROTOCOL,
    fuelItem = DEFAULT_FUEL_ITEM,
    fuelMaxItemsPerJob = DEFAULT_FUEL_MAX_ITEMS_PER_JOB,
    fuelUnitsPerItem = DEFAULT_FUEL_UNITS_PER_ITEM,
    fuelMargin = DEFAULT_FUEL_MARGIN,
    fuelQueryTimeout = DEFAULT_FUEL_QUERY_TIMEOUT,
    leftLanes = DEFAULT_LEFT_LANES,
    rightLanes = DEFAULT_RIGHT_LANES,
    serviceInterval = DEFAULT_SERVICE_INTERVAL,
    statusTimeout = DEFAULT_STATUS_TIMEOUT,
    heartbeatInterval = DEFAULT_HEARTBEAT_INTERVAL,
    dockRegistryFile = DEFAULT_DOCK_REGISTRY,
    docks = {},
  }
end

local function listPeripherals()
  local names = peripheral.getNames()
  table.sort(names)

  print("Connected peripherals:")

  for _, name in ipairs(names) do
    print("  " .. name .. " (" .. tostring(peripheral.getType(name)) .. ")")
  end
end

local function resolveConfigPath(path)
  if fs.exists(path) and not fs.isDir(path) then
    return path
  end

  if fs.exists(path .. ".lua") and not fs.isDir(path .. ".lua") then
    return path .. ".lua"
  end

  if shell and shell.resolveProgram then
    local resolved = shell.resolveProgram(path)

    if resolved then
      return resolved
    end
  end

  return nil
end

local function loadConfig(path)
  local resolved = resolveConfigPath(path)

  if not resolved then
    return nil, "config file not found: " .. path
  end

  local chunk, loadErr = loadfile(resolved)

  if not chunk then
    return nil, "could not load config: " .. tostring(loadErr)
  end

  local ok, config = pcall(chunk)

  if not ok then
    return nil, "config crashed: " .. tostring(config)
  end

  if type(config) ~= "table" then
    return nil, "config must return a table"
  end

  config.configPath = resolved
  config.areaId = config.areaId or ("mining_area_" .. os.getComputerID())
  config.protocol = config.protocol or DEFAULT_PROTOCOL
  config.fuelItem = config.fuelItem or DEFAULT_FUEL_ITEM
  config.fuelTargetItems = tonumber(config.fuelTargetItems)
  config.fuelMaxItemsPerJob = tonumber(config.fuelMaxItemsPerJob)

  if config.fuelMaxItemsPerJob == nil then
    config.fuelMaxItemsPerJob = config.fuelTargetItems
  end

  if config.fuelMaxItemsPerJob == nil then
    config.fuelMaxItemsPerJob = DEFAULT_FUEL_MAX_ITEMS_PER_JOB
  end

  if config.fuelTargetItems == nil then
    config.fuelTargetItems = config.fuelMaxItemsPerJob
  end

  config.fuelUnitsPerItem = tonumber(config.fuelUnitsPerItem) or DEFAULT_FUEL_UNITS_PER_ITEM
  config.serviceInterval = tonumber(config.serviceInterval) or DEFAULT_SERVICE_INTERVAL
  config.statusTimeout = tonumber(config.statusTimeout) or DEFAULT_STATUS_TIMEOUT
  config.heartbeatInterval = tonumber(config.heartbeatInterval) or DEFAULT_HEARTBEAT_INTERVAL
  config.fuelQueryTimeout = tonumber(config.fuelQueryTimeout) or DEFAULT_FUEL_QUERY_TIMEOUT
  config.fuelMargin = tonumber(config.fuelMargin) or DEFAULT_FUEL_MARGIN
  config.leftLanes = tonumber(config.leftLanes)
  config.rightLanes = tonumber(config.rightLanes)

  if config.leftLanes == nil then
    config.leftLanes = DEFAULT_LEFT_LANES
  end

  if config.rightLanes == nil then
    config.rightLanes = DEFAULT_RIGHT_LANES
  end

  config.dockRegistryFile = config.dockRegistryFile or DEFAULT_DOCK_REGISTRY
  config.docks = config.docks or {}

  return config
end

local function loadConfigOrDefault(path)
  local config, message = loadConfig(path)

  if config then
    return config
  end

  print(message)
  print("Using default settings for this command.")
  return makeDefaultConfig(path)
end

local function dockRegistryPath(config)
  return config.dockRegistryFile or DEFAULT_DOCK_REGISTRY
end

local function emptyDockRegistry()
  return {
    docks = {},
  }
end

local function loadDockRegistry(config)
  local path = dockRegistryPath(config)

  if not fs.exists(path) then
    return emptyDockRegistry(), path
  end

  local file = fs.open(path, "r")

  if not file then
    return emptyDockRegistry(), path, "could not open dock registry: " .. path
  end

  local content = file.readAll()
  file.close()

  local data = textutils.unserialize(content)

  if type(data) ~= "table" then
    return emptyDockRegistry(), path, "dock registry is not a serialized table: " .. path
  end

  if type(data.docks) == "table" then
    return data, path
  end

  return {
    docks = data,
  }, path
end

local function saveDockRegistry(config, registry)
  local path = dockRegistryPath(config)
  local file = fs.open(path, "w")

  if not file then
    return false, "could not write dock registry: " .. path
  end

  file.write(textutils.serialize(registry))
  file.close()

  return true, path
end

local function normalizeDock(rawDock, source, fallbackKey, fallbackCardinalDirection, defaultEnabled)
  if type(rawDock) ~= "table" then
    return nil
  end

  local dock = {}

  for key, value in pairs(rawDock) do
    dock[key] = value
  end

  dock.source = source
  dock.key = tostring(dock.key or dock.name or dock.label or fallbackKey or dock.turtleId or "dock")
  dock.label = dock.label or dock.computerLabel
  dock.turtleId = tonumber(dock.turtleId or dock.rednetId or dock.rednetAddress)
  dock.rednetId = tonumber(dock.rednetId or dock.rednetAddress or dock.turtleId)
  dock.cardinalDirection = dock.cardinalDirection
    or dock.cardinal_direction
    or dock.direction
    or dock.heading
    or fallbackCardinalDirection
    or PLACEHOLDER_CARDINAL_DIRECTION
  dock.direction = dock.cardinalDirection
  dock.heading = dock.cardinalDirection

  if dock.enabled == nil then
    dock.enabled = defaultEnabled
  end

  return dock
end

local function addDockToList(docks, dock)
  if not dock then
    return
  end

  for _, existing in ipairs(docks) do
    if dock.turtleId and existing.turtleId == dock.turtleId then
      for key, value in pairs(dock) do
        if value ~= nil and value ~= "" then
          existing[key] = value
        end
      end

      return
    end
  end

  docks[#docks + 1] = dock
end

local function collectConfiguredDocks(config, includeDisabled)
  local docks = {}
  local configured = config.docks or {}

  for index, rawDock in ipairs(configured) do
    local dock = normalizeDock(rawDock, "config", "dock_" .. index, nil, true)

    if dock and (includeDisabled or dock.enabled ~= false) then
      addDockToList(docks, dock)
    end
  end

  for _, direction in ipairs(LEGACY_DIRECTIONS) do
    if configured[direction] then
      local dock = normalizeDock(configured[direction], "config", direction, direction, true)

      if dock and (includeDisabled or dock.enabled ~= false) then
        addDockToList(docks, dock)
      end
    end
  end

  for key, rawDock in pairs(configured) do
    if type(key) ~= "number" and not containsLegacyDirection(key) then
      local fallbackCardinalDirection = nil

      if type(rawDock) == "table" and type(key) == "string" and key ~= "" then
        fallbackCardinalDirection = rawDock.cardinalDirection or rawDock.cardinal_direction
      end

      local dock = normalizeDock(rawDock, "config", tostring(key), fallbackCardinalDirection, true)

      if dock and (includeDisabled or dock.enabled ~= false) then
        addDockToList(docks, dock)
      end
    end
  end

  return docks
end

local function collectRegistryDocks(config, includeDisabled)
  local registry, _, registryMessage = loadDockRegistry(config)
  local docks = {}

  if registryMessage then
    return docks, registryMessage
  end

  for index, rawDock in ipairs(registry.docks or {}) do
    local dock = normalizeDock(rawDock, "registry", "registry_" .. index, nil, false)

    if dock and (includeDisabled or dock.enabled ~= false) then
      addDockToList(docks, dock)
    end
  end

  return docks
end

local function collectDocks(config, includeDisabled)
  local docks = collectConfiguredDocks(config, includeDisabled)
  local registryDocks, registryMessage = collectRegistryDocks(config, includeDisabled)

  if registryMessage then
    return nil, registryMessage
  end

  for _, dock in ipairs(registryDocks) do
    addDockToList(docks, dock)
  end

  return docks
end

local function prepareActiveDocks(config)
  local docks, message = collectDocks(config, false)

  if not docks then
    return false, message
  end

  if #docks == 0 then
    return false,
      "no enabled docks configured; use mining_area add-turtle or enable a dock in config"
  end

  config.activeDocks = docks
  return true
end

local function wrapInventory(name)
  if type(name) ~= "string" or name == "" then
    return nil, "missing peripheral name"
  end

  local inventory = peripheral.wrap(name)

  if not inventory then
    return nil, "peripheral not found: " .. name
  end

  if type(inventory.list) ~= "function" or type(inventory.pushItems) ~= "function" then
    return nil, name .. " is not an inventory peripheral"
  end

  return inventory
end

local function validateDock(direction, dock, config)
  if type(dock) ~= "table" then
    return false, direction .. " dock config is missing"
  end

  local rawFuelTargetItems = dock.fuelTargetItems
  local rawFuelMaxItemsPerJob = dock.fuelMaxItemsPerJob
  local rawFuelUnitsPerItem = dock.fuelUnitsPerItem
  local rawLeftLanes = dock.leftLanes
  local rawRightLanes = dock.rightLanes
  dock.turtleId = tonumber(dock.turtleId)
  dock.fuelTargetItems = tonumber(dock.fuelTargetItems)
  dock.fuelMaxItemsPerJob = tonumber(dock.fuelMaxItemsPerJob)
  dock.fuelUnitsPerItem = tonumber(dock.fuelUnitsPerItem)
  dock.fuelMargin = tonumber(dock.fuelMargin)
  dock.leftLanes = tonumber(dock.leftLanes)
  dock.rightLanes = tonumber(dock.rightLanes)

  if dock.fuelMaxItemsPerJob == nil and rawFuelMaxItemsPerJob == nil then
    dock.fuelMaxItemsPerJob = dock.fuelTargetItems
  end

  if type(dock.turtleId) ~= "number" then
    return false, direction .. " dock turtleId must be a number"
  end

  if type(dock.outputChest) ~= "string" then
    return false, direction .. " dock outputChest must be a peripheral name"
  end

  if rawFuelTargetItems ~= nil and dock.fuelTargetItems == nil then
    return false, direction .. " dock fuelTargetItems must be a non-negative whole number"
  end

  if rawFuelMaxItemsPerJob ~= nil and dock.fuelMaxItemsPerJob == nil then
    return false, direction .. " dock fuelMaxItemsPerJob must be a non-negative whole number"
  end

  if rawFuelUnitsPerItem ~= nil and dock.fuelUnitsPerItem == nil then
    return false, direction .. " dock fuelUnitsPerItem must be a positive whole number"
  end

  if rawLeftLanes ~= nil and dock.leftLanes == nil then
    return false, direction .. " dock leftLanes must be a non-negative whole number"
  end

  if rawRightLanes ~= nil and dock.rightLanes == nil then
    return false, direction .. " dock rightLanes must be a non-negative whole number"
  end

  if dock.fuelMaxItemsPerJob ~= nil
    and not isNonNegativeWholeNumber(dock.fuelMaxItemsPerJob) then
    return false, direction .. " dock fuelMaxItemsPerJob must be a non-negative whole number"
  end

  if dock.fuelUnitsPerItem ~= nil
    and not isPositiveWholeNumber(dock.fuelUnitsPerItem) then
    return false, direction .. " dock fuelUnitsPerItem must be a positive whole number"
  end

  if dock.leftLanes ~= nil and not isNonNegativeWholeNumber(dock.leftLanes) then
    return false, direction .. " dock leftLanes must be a non-negative whole number"
  end

  if dock.rightLanes ~= nil and not isNonNegativeWholeNumber(dock.rightLanes) then
    return false, direction .. " dock rightLanes must be a non-negative whole number"
  end

  local storageChests = configuredStorageTargets(dock, config)

  if #storageChests == 0 then
    return false, direction .. " dock needs storage/storageChests configured"
  end

  local fuelTarget = configuredFuelMaxItems(dock, config) or 0

  if fuelTarget > 0 then
    if type(dock.fuelChest) ~= "string" then
      return false, direction .. " dock fuelChest must be a peripheral name"
    end

    local fuelSources = configuredFuelSources(dock, config)

    if #fuelSources == 0 then
      return false, direction .. " dock needs fuelStorage/fuelStorageChests configured"
    end
  end

  return true
end

local function validateConfig(config)
  if not isNonNegativeWholeNumber(config.fuelMaxItemsPerJob) then
    return false, "fuelMaxItemsPerJob must be a non-negative whole number"
  end

  if not isPositiveWholeNumber(config.fuelUnitsPerItem) then
    return false, "fuelUnitsPerItem must be a positive whole number"
  end

  if config.fuelMargin < 0 or config.fuelMargin ~= math.floor(config.fuelMargin) then
    return false, "fuelMargin must be a non-negative whole number"
  end

  if not isPositiveWholeNumber(config.fuelQueryTimeout) then
    return false, "fuelQueryTimeout must be a positive whole number"
  end

  if not isNonNegativeWholeNumber(config.leftLanes) then
    return false, "leftLanes must be a non-negative whole number"
  end

  if not isNonNegativeWholeNumber(config.rightLanes) then
    return false, "rightLanes must be a non-negative whole number"
  end

  if not isPositiveWholeNumber(config.serviceInterval) then
    return false, "serviceInterval must be a positive whole number"
  end

  if not isPositiveWholeNumber(config.statusTimeout) then
    return false, "statusTimeout must be a positive whole number"
  end

  if not isPositiveWholeNumber(config.heartbeatInterval) then
    return false, "heartbeatInterval must be a positive whole number"
  end

  local activeOk, activeMessage = prepareActiveDocks(config)

  if not activeOk then
    return false, activeMessage
  end

  for _, dock in ipairs(config.activeDocks) do
    local ok, message = validateDock(dockDisplayName(dock), dock, config)

    if not ok then
      return false, message
    end
  end

  return true
end

local function checkInventoryPresent(name, seen, errors)
  if seen[name] then
    return
  end

  seen[name] = true

  local inventory, message = wrapInventory(name)

  if not inventory then
    errors[#errors + 1] = message
  end
end

local function checkConfiguredPeripherals(config)
  local seen = {}
  local errors = {}

  for _, dock in ipairs(config.activeDocks or {}) do
    checkInventoryPresent(dock.outputChest, seen, errors)

    for _, storageChest in ipairs(configuredStorageTargets(dock, config)) do
      checkInventoryPresent(storageChest, seen, errors)
    end

    if (configuredFuelMaxItems(dock, config) or 0) > 0 then
      checkInventoryPresent(dock.fuelChest, seen, errors)

      for _, fuelSource in ipairs(configuredFuelSources(dock, config)) do
        checkInventoryPresent(fuelSource, seen, errors)
      end
    end
  end

  if #errors > 0 then
    return false, errors
  end

  return true
end

local function countItem(inventoryName, itemName)
  local inventory, message = wrapInventory(inventoryName)

  if not inventory then
    return 0, message
  end

  local total = 0

  for _, item in pairs(inventory.list()) do
    if item.name == itemName then
      total = total + item.count
    end
  end

  return total
end

local function moveItemsToTargets(sourceName, targetNames, itemName, limit)
  local source, message = wrapInventory(sourceName)

  if not source then
    return 0, limit or 0, message
  end

  for _, targetName in ipairs(targetNames) do
    local target, targetMessage = wrapInventory(targetName)

    if not target then
      return 0, limit or 0, targetMessage
    end
  end

  local movedTotal = 0
  local wantedRemaining = limit
  local snapshot = source.list()

  for slot, item in pairs(snapshot) do
    if not itemName or item.name == itemName then
      local slotRemaining = item.count

      if wantedRemaining and wantedRemaining < slotRemaining then
        slotRemaining = wantedRemaining
      end

      for _, targetName in ipairs(targetNames) do
        if slotRemaining <= 0 then
          break
        end

        local moved = source.pushItems(targetName, slot, slotRemaining) or 0
        movedTotal = movedTotal + moved
        slotRemaining = slotRemaining - moved

        if wantedRemaining then
          wantedRemaining = wantedRemaining - moved

          if wantedRemaining <= 0 then
            return movedTotal, 0
          end
        end
      end
    end
  end

  return movedTotal, wantedRemaining or 0
end

local function inventoryHasItems(inventoryName)
  local inventory, message = wrapInventory(inventoryName)

  if not inventory then
    return true, message
  end

  for _, item in pairs(inventory.list()) do
    if item.count > 0 then
      return true
    end
  end

  return false
end

local function cleanOutput(dock, config)
  local storageChests = configuredStorageTargets(dock, config)
  local _, _, moveMessage = moveItemsToTargets(dock.outputChest, storageChests)

  if moveMessage then
    return false, moveMessage
  end

  local hasItems, inspectMessage = inventoryHasItems(dock.outputChest)

  if inspectMessage then
    return false, inspectMessage
  end

  if hasItems then
    return false, "output chest still has items after cleaning"
  end

  return true
end

local function serviceDock(direction, dock, config)
  local outputOk, outputMessage = cleanOutput(dock, config)

  if outputOk then
    if dock._outputServiceError then
      print(direction .. ": output service recovered")
    end

    dock._outputServiceError = nil
  elseif dock._outputServiceError ~= outputMessage then
    dock._outputServiceError = outputMessage
    print(direction .. ": output service failed: " .. outputMessage)
    print("Check the " .. direction .. " output and storage chests.")
  end

  return outputOk
end

local function serviceAll(config, reportResult)
  local allOk = true

  for _, dock in ipairs(config.activeDocks or {}) do
    local ok = serviceDock(dockDisplayName(dock), dock, config)
    allOk = allOk and ok
  end

  if reportResult then
    if allOk then
      print("Dock service complete: all outputs clean.")
    else
      print("Dock service failed. Fix the output/storage errors above.")
    end
  end

  return allOk
end

local function openRednet()
  local opened = 0

  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      if not rednet.isOpen(side) then
        rednet.open(side)
      end

      opened = opened + 1
    end
  end

  return opened > 0
end

local function makeRunId()
  return tostring(os.getComputerID()) .. "-" .. tostring(nowSeconds())
end

local function makeJob(config, dock, targetDistance, runId)
  local name = dockDisplayName(dock)
  local heading = dock.cardinalDirection or PLACEHOLDER_CARDINAL_DIRECTION
  local leftLanes, rightLanes = configuredSideLanes(dock, config)
  local task = "mine-distance"

  if leftLanes > 0 or rightLanes > 0 then
    task = "mine-area"
  end

  return {
    type = "job",
    jobId = config.areaId .. "-" .. name .. "-" .. runId,
    task = task,
    ao = dock.ao or name,
    heading = heading,
    turtleId = dock.turtleId,
    params = {
      targetDistance = targetDistance,
      laneLength = targetDistance,
      laneOffset = 0,
      laneWidth = 1,
      laneHeight = 2,
      leftLanes = leftLanes,
      rightLanes = rightLanes,
      fuelMargin = dock.fuelMargin or config.fuelMargin,
      heartbeatInterval = config.heartbeatInterval,
    },
  }
end

local function makeWorkers(config, targetDistance)
  local workers = {}
  local runId = makeRunId()

  for _, dock in ipairs(config.activeDocks or {}) do
    local name = dockDisplayName(dock)

    workers[#workers + 1] = {
      direction = name,
      dock = dock,
      turtleId = dock.turtleId,
      state = "queued",
      job = makeJob(config, dock, targetDistance, runId),
      lastSeen = nil,
      lastMessage = "queued",
    }
  end

  return workers
end

local function workerForSender(workers, senderId, message)
  local turtleId = tonumber(message and message.turtleId) or senderId

  for _, worker in pairs(workers) do
    if worker.turtleId == turtleId then
      return worker
    end
  end

  return nil
end

local handleStatus

local function makeFuelQuery(worker)
  return {
    type = "fuel-query",
    queryId = worker.job.jobId .. "-fuel",
    jobId = worker.job.jobId,
    turtleId = worker.turtleId,
    params = {
      targetDistance = worker.job.params.targetDistance,
      laneLength = worker.job.params.laneLength,
      fuelMargin = worker.job.params.fuelMargin,
    },
  }
end

local function queryFuelReports(workers, config)
  local pending = {}
  local pendingCount = 0

  for _, worker in ipairs(workers) do
    local query = makeFuelQuery(worker)

    worker.fuelQueryId = query.queryId
    worker.state = "fuel-query"
    worker.lastSent = nowSeconds()
    worker.lastMessage = "fuel query sent"
    pending[query.queryId] = worker
    pendingCount = pendingCount + 1

    print("Querying fuel for " .. worker.direction .. " turtle=" .. tostring(worker.turtleId))
    rednet.send(worker.turtleId, query, config.protocol)
  end

  local timeout = tonumber(config.fuelQueryTimeout) or DEFAULT_FUEL_QUERY_TIMEOUT
  local timer = os.startTimer(timeout)

  while pendingCount > 0 do
    local event = { os.pullEvent() }

    if event[1] == "timer" and event[2] == timer then
      break
    end

    if event[1] == "rednet_message" then
      local senderId = event[2]
      local message = event[3]
      local protocol = event[4]

      if protocol == config.protocol and type(message) == "table" then
        if message.type == "fuel-report" then
          local worker = pending[message.queryId]

          if worker and workerForSender(workers, senderId, message) == worker then
            worker.fuelReport = message
            worker.fuel = message.fuel
            worker.fuelLimit = message.fuelLimit
            worker.progress = message.progress
            worker.lastSeen = nowSeconds()
            worker.state = "fuel-ready"
            worker.lastMessage = "fuel report received"
            pending[message.queryId] = nil
            pendingCount = pendingCount - 1

            print(worker.direction
              .. ": fuel=" .. tostring(message.fuel)
              .. " limit=" .. tostring(message.fuelLimit)
              .. " progress=" .. tostring(message.progress))
          end
        elseif message.type == "error" then
          local worker = workerForSender(workers, senderId, message)

          handleStatus(workers, senderId, message)

          if worker and worker.fuelQueryId and pending[worker.fuelQueryId] then
            pending[worker.fuelQueryId] = nil
            pendingCount = pendingCount - 1
          end
        elseif message.type == "turtle-status" then
          handleStatus(workers, senderId, message)
        end
      end
    end
  end

  if pendingCount > 0 then
    for _, worker in pairs(pending) do
      worker.state = "offline"
      worker.lastMessage = "no fuel report for " .. tostring(timeout) .. " seconds"
      print(worker.direction .. ": offline: " .. worker.lastMessage)
    end

    return false
  end

  for _, worker in ipairs(workers) do
    if worker.state == "failed" or worker.state == "offline" then
      return false
    end
  end

  return true
end

local function numericFuel(value)
  if value == "unlimited" then
    return math.huge
  end

  return tonumber(value)
end

local function sideRunFuelNeeded(depth, lanes, margin)
  if lanes <= 0 then
    return 0
  end

  local offset = 1
  local sideStepsRemaining = lanes - 1
  local sideStepsBackToDockLane = offset + lanes - 1

  return offset
    + lanes * depth * 2
    + sideStepsRemaining
    + sideStepsBackToDockLane
    + margin
end

local function calculateJobFuelNeed(worker, report, config)
  local params = worker.job.params or {}
  local targetDistance = tonumber(params.targetDistance or params.laneLength)
  local progress = tonumber(report.progress) or 0
  local fuelMargin = configuredFuelMargin(worker.dock, config)

  if not targetDistance then
    return nil, "job target distance is missing"
  end

  if not fuelMargin or fuelMargin < 0 or fuelMargin ~= math.floor(fuelMargin) then
    return nil, "fuelMargin must be a non-negative whole number"
  end

  local centerFuel = 0

  if progress < targetDistance then
    centerFuel = targetDistance * 2 + fuelMargin + 2
  end

  local leftLanes = tonumber(params.leftLanes) or 0
  local rightLanes = tonumber(params.rightLanes) or 0
  local leftFuel = 0
  local rightFuel = 0

  if worker.job.task == "mine-area" then
    leftFuel = sideRunFuelNeeded(targetDistance, leftLanes, fuelMargin)
    rightFuel = sideRunFuelNeeded(targetDistance, rightLanes, fuelMargin)
  end

  return {
    totalFuel = centerFuel + leftFuel + rightFuel,
    maxPhaseFuel = math.max(centerFuel, leftFuel, rightFuel),
    targetDistance = targetDistance,
    progress = progress,
    centerFuel = centerFuel,
    leftFuel = leftFuel,
    rightFuel = rightFuel,
  }
end

local function calculateJobFuelItems(worker, config)
  local maxItems = configuredFuelMaxItems(worker.dock, config) or 0

  if maxItems <= 0 then
    return {
      requestedItems = 0,
      message = "fuel management disabled",
    }
  end

  local report = worker.fuelReport

  if type(report) ~= "table" then
    return nil, "missing fuel report"
  end

  local currentFuel = numericFuel(report.fuel)
  local fuelLimit = numericFuel(report.fuelLimit)

  if currentFuel == math.huge or fuelLimit == math.huge then
    return {
      requestedItems = 0,
      message = "turtle fuel is unlimited",
    }
  end

  if not currentFuel then
    return nil, "fuel report did not include numeric fuel"
  end

  local fuelUnitsPerItem = configuredFuelUnitsPerItem(worker.dock, config)

  if not isPositiveWholeNumber(fuelUnitsPerItem) then
    return nil, "fuelUnitsPerItem must be a positive whole number"
  end

  local need, needMessage = calculateJobFuelNeed(worker, report, config)

  if not need then
    return nil, needMessage
  end

  if fuelLimit and fuelLimit ~= math.huge and need.maxPhaseFuel > fuelLimit then
    return nil,
      "job phase needs " .. tostring(need.maxPhaseFuel)
      .. " fuel, above turtle fuel limit " .. tostring(fuelLimit)
  end

  if need.totalFuel <= 0 then
    return {
      requestedItems = 0,
      neededFuel = 0,
      targetFuel = 0,
      progress = need.progress,
      message = "target already reached",
    }
  end

  local targetFuel = need.totalFuel
  local neededFuel = targetFuel - currentFuel

  if neededFuel < 0 then
    neededFuel = 0
  end

  local requestedItems = math.ceil(neededFuel / fuelUnitsPerItem)

  if requestedItems > maxItems then
    return nil,
      "job needs " .. requestedItems .. " fuel items, above fuelMaxItemsPerJob "
      .. tostring(maxItems)
  end

  return {
    requestedItems = requestedItems,
    neededFuel = neededFuel,
    targetFuel = targetFuel,
    currentFuel = currentFuel,
    progress = need.progress,
    centerFuel = need.centerFuel,
    leftFuel = need.leftFuel,
    rightFuel = need.rightFuel,
    message = "needs " .. requestedItems .. " fuel items",
  }
end

local function reconcileDockFuel(direction, dock, config, requestedItems)
  local fuelItem = dock.fuelItem or config.fuelItem
  local currentItems, countMessage = countItem(dock.fuelChest, fuelItem)

  if countMessage then
    return false, countMessage
  end

  local fuelSources = configuredFuelSources(dock, config)

  if currentItems > requestedItems then
    local surplus = currentItems - requestedItems
    local moved, remaining, moveMessage = moveItemsToTargets(
      dock.fuelChest,
      fuelSources,
      fuelItem,
      surplus
    )

    if moveMessage then
      return false, moveMessage
    end

    if remaining > 0 then
      return false,
        direction .. " dock fuel chest has " .. surplus .. " excess "
        .. fuelItem .. "; moved back " .. moved .. ", still excess " .. remaining
    end

    currentItems = requestedItems
  end

  if currentItems < requestedItems then
    local needed = requestedItems - currentItems
    local moved = 0

    for _, sourceName in ipairs(fuelSources) do
      if needed <= 0 then
        break
      end

      local sourceMoved, remaining, moveMessage = moveItemsToTargets(
        sourceName,
        { dock.fuelChest },
        fuelItem,
        needed
      )

      if moveMessage then
        return false, moveMessage
      end

      moved = moved + sourceMoved
      needed = remaining
    end

    if needed > 0 then
      return false,
        direction .. " fuel short: requested " .. requestedItems .. " "
        .. fuelItem .. ", moved " .. moved .. ", still need " .. needed
    end
  end

  return true, "staged " .. requestedItems .. " " .. fuelItem .. " for job"
end

local function prepareJobFuel(workers, config)
  local allOk = true

  for _, worker in ipairs(workers) do
    local plan, planMessage = calculateJobFuelItems(worker, config)

    if not plan then
      worker.state = "failed"
      worker.lastMessage = planMessage
      print(worker.direction .. ": failed: " .. planMessage)
      allOk = false
    elseif (configuredFuelMaxItems(worker.dock, config) or 0) <= 0
      or plan.message == "turtle fuel is unlimited" then
      worker.lastMessage = plan.message
      print(worker.direction .. ": " .. plan.message)
    else
      local ok, fuelMessage = reconcileDockFuel(
        worker.direction,
        worker.dock,
        config,
        plan.requestedItems
      )

      worker.lastMessage = fuelMessage

      if ok then
        print(worker.direction .. ": " .. fuelMessage
          .. " (" .. tostring(plan.neededFuel) .. " fuel units needed)")
      else
        worker.state = "failed"
        print(worker.direction .. ": failed: " .. fuelMessage)
        allOk = false
      end
    end
  end

  return allOk
end

local function sendJobs(workers, protocol)
  for _, worker in ipairs(workers) do
    print("Sending " .. worker.job.jobId .. " to turtle " .. worker.turtleId)
    rednet.send(worker.turtleId, worker.job, protocol)
    worker.state = "sent"
    worker.lastSent = nowSeconds()
    worker.lastMessage = "job sent"
  end
end

function handleStatus(workers, senderId, message)
  if type(message) ~= "table" then
    return
  end

  if message.type ~= "turtle-status" and message.type ~= "error" then
    return
  end

  local worker = workerForSender(workers, senderId, message)

  if not worker then
    print("Ignoring status from unknown turtle " .. tostring(senderId))
    return
  end

  worker.lastSeen = nowSeconds()

  if message.type == "error" then
    worker.state = "failed"
    worker.lastMessage = tostring(message.code or "error") .. ": " .. tostring(message.message or "")
    print(worker.direction .. ": failed: " .. worker.lastMessage)
    return
  end

  if (worker.state == "complete" or worker.state == "failed")
    and message.status == "idle" then
    return
  end

  worker.state = message.status or worker.state
  worker.progress = message.progress
  worker.fuel = message.fuel
  worker.lastMessage = message.message or worker.state

  print(worker.direction .. ": " .. worker.state
    .. " progress=" .. tostring(worker.progress)
    .. " fuel=" .. tostring(worker.fuel)
    .. " " .. tostring(worker.lastMessage))
end

local function checkTimeouts(workers, timeout)
  local now = nowSeconds()

  for _, worker in ipairs(workers) do
    if worker.state ~= "complete"
      and worker.state ~= "failed"
      and worker.state ~= "offline" then
      local lastContact = worker.lastSeen or worker.lastSent or now

      if now - lastContact > timeout then
        worker.state = "offline"
        worker.lastMessage = "no status for " .. timeout .. " seconds"
        print(worker.direction .. ": offline: " .. worker.lastMessage)
      end
    end
  end
end

local function allFinished(workers)
  for _, worker in ipairs(workers) do
    local state = worker.state

    if state ~= "complete" and state ~= "failed" and state ~= "offline" then
      return false
    end
  end

  return true
end

local function printSummary(workers)
  print("")
  print("Mining area summary:")

  for _, worker in ipairs(workers) do
    print("  " .. worker.direction
      .. " turtle=" .. tostring(worker.turtleId)
      .. " state=" .. tostring(worker.state)
      .. " progress=" .. tostring(worker.progress or "?")
      .. " message=" .. tostring(worker.lastMessage))
  end
end

local function findRegistryDock(registry, turtleId)
  for _, dock in ipairs(registry.docks or {}) do
    local existingId = tonumber(dock.turtleId or dock.rednetId or dock.rednetAddress)

    if existingId and existingId == turtleId then
      return dock
    end
  end

  return nil
end

local function upsertRegistryDock(registry, update)
  local turtleId = tonumber(update.turtleId or update.rednetId or update.rednetAddress)
  local existing = turtleId and findRegistryDock(registry, turtleId)

  if existing then
    for key, value in pairs(update) do
      if value ~= nil and value ~= "" then
        existing[key] = value
      end
    end

    return existing, false
  end

  registry.docks = registry.docks or {}
  registry.docks[#registry.docks + 1] = update
  return update, true
end

local function printDock(dock, index)
  local enabled = dock.enabled ~= false and "enabled" or "disabled"

  print(tostring(index) .. ". " .. dockDisplayName(dock)
    .. " [" .. enabled .. "]"
    .. " source=" .. tostring(dock.source or "?")
    .. " turtle=" .. tostring(dock.turtleId or "?")
    .. " rednet=" .. tostring(dock.rednetId or "?")
    .. " direction=" .. tostring(dock.cardinalDirection or PLACEHOLDER_CARDINAL_DIRECTION)
    .. " output=" .. tostring(dock.outputChest or "?")
    .. " fuel=" .. tostring(dock.fuelChest or "?"))
end

local function listDocks(config)
  local docks, message = collectDocks(config, true)

  if not docks then
    print(message)
    return false
  end

  print("Dock registry: " .. dockRegistryPath(config))

  if #docks == 0 then
    print("No configured or registered docks.")
    return true
  end

  for index, dock in ipairs(docks) do
    printDock(dock, index)
  end

  return true
end

local function promptString(label, defaultValue, required)
  while true do
    if defaultValue and defaultValue ~= "" then
      write(label .. " [" .. tostring(defaultValue) .. "]: ")
    else
      write(label .. ": ")
    end

    local value = read()

    if value == "" then
      value = defaultValue
    end

    if not required or not isBlank(value) then
      return value
    end

    print(label .. " is required.")
  end
end

local function promptNumber(label, defaultValue)
  while true do
    local value = promptString(label, defaultValue, true)
    local number = tonumber(value)

    if number and number == math.floor(number) then
      return number
    end

    print(label .. " must be a whole number.")
  end
end

local function promptYesNo(label, defaultValue)
  local defaultText = defaultValue and "y" or "n"

  while true do
    local value = string.lower(tostring(promptString(label .. " (y/n)", defaultText, true)))

    if value == "y" or value == "yes" then
      return true
    end

    if value == "n" or value == "no" then
      return false
    end

    print("Answer y or n.")
  end
end

local function addTurtleDialog(config)
  local registry, path, registryMessage = loadDockRegistry(config)

  if registryMessage then
    print(registryMessage)
    return false
  end

  print("Add turtle to managed-area dock registry")
  print("Registry: " .. path)

  local turtleId = promptNumber("Turtle rednet ID", nil)
  local existing = findRegistryDock(registry, turtleId) or {}
  local label = promptString("Label", existing.label, false)
  local cardinalDirection = promptString(
    "Cardinal direction",
    existing.cardinalDirection or PLACEHOLDER_CARDINAL_DIRECTION,
    true
  )
  local enabled = promptYesNo("Enable for mining runs", existing.enabled ~= false)
  local outputChest = promptString("Output chest peripheral", existing.outputChest, enabled)
  local fuelChestRequired = enabled and (configuredFuelMaxItems(existing, config) or 0) > 0
  local fuelChest = promptString("Fuel chest peripheral", existing.fuelChest, fuelChestRequired)

  local entry = {
    turtleId = turtleId,
    rednetId = turtleId,
    label = label,
    cardinalDirection = cardinalDirection,
    outputChest = outputChest,
    fuelChest = fuelChest,
    enabled = enabled,
    addedAt = existing.addedAt or nowSeconds(),
    updatedAt = nowSeconds(),
  }

  local _, created = upsertRegistryDock(registry, entry)
  local ok, saveMessage = saveDockRegistry(config, registry)

  if not ok then
    print(saveMessage)
    return false
  end

  if created then
    print("Added turtle " .. turtleId .. " to " .. saveMessage)
  else
    print("Updated turtle " .. turtleId .. " in " .. saveMessage)
  end

  return true
end

local function discoverTurtles(config, timeout)
  timeout = tonumber(timeout) or DEFAULT_DISCOVERY_TIMEOUT

  if timeout < 1 then
    timeout = DEFAULT_DISCOVERY_TIMEOUT
  end

  local registry, path, registryMessage = loadDockRegistry(config)

  if registryMessage then
    print(registryMessage)
    return false
  end

  if not openRednet() then
    print("No modem side found. Attach a modem to the managed-area computer.")
    return false
  end

  print("Discovering mining workers for " .. timeout .. " seconds...")
  rednet.broadcast({
    type = "mining-area-discover",
    areaId = config.areaId,
  }, config.protocol)

  local timer = os.startTimer(timeout)
  local found = {}

  while true do
    local event = { os.pullEvent() }

    if event[1] == "timer" and event[2] == timer then
      break
    end

    if event[1] == "rednet_message" then
      local senderId = event[2]
      local message = event[3]
      local protocol = event[4]

      if protocol == config.protocol
        and type(message) == "table"
        and message.type == "mining-worker-hello" then
        local turtleId = tonumber(message.turtleId or senderId)

        if turtleId and not found[turtleId] then
          found[turtleId] = true

          local existing = findRegistryDock(registry, turtleId)
          local update = {
            turtleId = turtleId,
            rednetId = senderId,
            label = message.label,
            fuel = message.fuel,
            progress = message.progress,
            lastSeen = nowSeconds(),
          }

          if not existing then
            update.cardinalDirection = PLACEHOLDER_CARDINAL_DIRECTION
            update.enabled = false
            update.discoveredAt = nowSeconds()
          end

          local _, created = upsertRegistryDock(registry, update)

          if created then
            print("Discovered turtle " .. turtleId
              .. " label=" .. tostring(message.label)
              .. " direction=" .. PLACEHOLDER_CARDINAL_DIRECTION)
          else
            print("Updated discovered turtle " .. turtleId
              .. " label=" .. tostring(message.label))
          end
        end
      end
    end
  end

  local ok, saveMessage = saveDockRegistry(config, registry)

  if not ok then
    print(saveMessage)
    return false
  end

  print("Saved dock registry: " .. saveMessage)
  print("Use mining_area docks to review entries.")
  print("Use mining_area add-turtle to assign direction and chests.")
  return true
end

local function runMiningArea(config, targetDistance)
  local ok, errors = checkConfiguredPeripherals(config)

  if not ok then
    print("Peripheral check failed:")

    for _, message in ipairs(errors) do
      print("  " .. message)
    end

    return false
  end

  if not openRednet() then
    print("No modem side found. Attach a modem to the managed-area computer.")
    return false
  end

  print("Managed mining area: " .. config.areaId)
  print("Config: " .. config.configPath)
  print("Protocol: " .. config.protocol)
  print("Target distance: " .. targetDistance)
  print("Fuel item: " .. config.fuelItem)
  print("Storage: " .. formatList(configuredStorageTargets(nil, config)))
  print("Default side lanes: left=" .. tostring(config.leftLanes)
    .. " right=" .. tostring(config.rightLanes))
  print("")

  print("Initial dock service")
  if not serviceAll(config) then
    print("Initial dock service failed. Fix fuel/output storage before mining.")
    return false
  end

  local workers = makeWorkers(config, targetDistance)

  print("Initial fuel query")
  if not queryFuelReports(workers, config) then
    print("Fuel query failed. Fix worker connectivity before mining.")
    printSummary(workers)
    return false
  end

  print("Job-start fuel staging")
  if not prepareJobFuel(workers, config) then
    print("Job-start fuel staging failed. Fix fuel storage before mining.")
    printSummary(workers)
    return false
  end

  sendJobs(workers, config.protocol)

  local serviceTimer = os.startTimer(config.serviceInterval)
  local checkTimer = os.startTimer(1)

  while not allFinished(workers) do
    local event = { os.pullEvent() }

    if event[1] == "rednet_message" then
      local senderId = event[2]
      local message = event[3]
      local protocol = event[4]

      if protocol == config.protocol then
        handleStatus(workers, senderId, message)
      end
    elseif event[1] == "timer" and event[2] == serviceTimer then
      serviceAll(config)
      serviceTimer = os.startTimer(config.serviceInterval)
    elseif event[1] == "timer" and event[2] == checkTimer then
      checkTimeouts(workers, config.statusTimeout)
      checkTimer = os.startTimer(1)
    end
  end

  printSummary(workers)

  for _, worker in ipairs(workers) do
    if worker.state ~= "complete" then
      return false
    end
  end

  return true
end

local function main()
  if args[1] == "-h" or args[1] == "--help" then
    usage()
    return true
  end

  if args[1] == "peripherals" or args[1] == "list-peripherals" then
    listPeripherals()
    return true
  end

  local command = args[1]

  if command == "docks" or command == "list-docks" then
    local configPath = args[2] or DEFAULT_CONFIG
    local config = loadConfigOrDefault(configPath)

    return listDocks(config)
  end

  if command == "discover" then
    local configPath = DEFAULT_CONFIG
    local timeoutArg = args[3]

    if args[2] and tonumber(args[2]) then
      timeoutArg = args[2]
    elseif args[2] then
      configPath = args[2]
    end

    local config = loadConfigOrDefault(configPath)

    return discoverTurtles(config, timeoutArg)
  end

  if command == "add-turtle" or command == "add-dock" then
    local configPath = args[2] or DEFAULT_CONFIG
    local config = loadConfigOrDefault(configPath)

    return addTurtleDialog(config)
  end

  if command == "service" then
    local configPath = args[2] or DEFAULT_CONFIG
    local config, configError = loadConfig(configPath)

    if not config then
      print(configError)
      return false
    end

    local valid, validationMessage = validateConfig(config)

    if not valid then
      print(validationMessage)
      return false
    end

    local peripheralsOk, peripheralErrors = checkConfiguredPeripherals(config)

    if not peripheralsOk then
      print("Peripheral check failed:")

      for _, message in ipairs(peripheralErrors) do
        print("  " .. message)
      end

      return false
    end

    return serviceAll(config, true)
  end

  local targetDistance = tonumber(args[1])
  local configPath = args[2] or DEFAULT_CONFIG

  if not args[1] then
    write("Target distance from each dock: ")
    targetDistance = tonumber(read())
  end

  if not isPositiveWholeNumber(targetDistance) then
    usage()
    print("target-distance must be a positive whole number.")
    return false
  end

  local config, configError = loadConfig(configPath)

  if not config then
    print(configError)
    return false
  end

  local valid, validationMessage = validateConfig(config)

  if not valid then
    print(validationMessage)
    return false
  end

  return runMiningArea(config, targetDistance)
end

local ok, result = pcall(main)

if not ok then
  print("mining_area crashed: " .. tostring(result))
  return false
end

return result
