-- Managed mining area controller.
-- Usage:
--   mining_area <target-distance> [config-file]
--   mining_area service [config-file]
--   mining_area peripherals
--   mining_area docks [config-file]
--   mining_area progress [config-file]
--   mining_area discover [config-file] [timeout-seconds]
--   mining_area add-turtle [config-file]
--
-- This runs on a normal computer. It schedules one resumable lane job at a
-- time for each configured turtle and services fuel/output chests by modem.

local args = { ... }

local DEFAULT_PROTOCOL = "minecraft-cc-t:mining_area"
local DEFAULT_CONFIG = "mining_area_config"
local LEGACY_DEFAULT_FUEL_ITEM = "minecraft:coal"
local DEFAULT_FUEL_ITEMS = {
  ["minecraft:coal"] = 80,
  ["silentgear:netherwood_charcoal"] = 120,
}
local DEFAULT_FUEL_MAX_ITEMS_PER_JOB = 256
-- Used by legacy singular fuelItem configurations.
local DEFAULT_FUEL_UNITS_PER_ITEM = 80
local DEFAULT_FUEL_MARGIN = 32
local DEFAULT_FUEL_QUERY_TIMEOUT = 5
local DEFAULT_LEFT_LANES = 20
local DEFAULT_RIGHT_LANES = 20
local DEFAULT_SERVICE_INTERVAL = 5
local DEFAULT_STATUS_TIMEOUT = 45
local DEFAULT_HEARTBEAT_INTERVAL = 3
local DEFAULT_DOCK_REGISTRY = "mining_area_docks"
local DEFAULT_LANE_CHECKPOINTS = "mining_area_lane_checkpoints"
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
  print("  mining_area progress [config-file]")
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

local function fuelItemSpecs(value, fallbackUnits)
  local specs = {}
  local seen = {}

  local function add(name, units)
    if type(name) ~= "string" or name == "" or seen[name] then
      return
    end

    seen[name] = true
    specs[#specs + 1] = {
      name = name,
      units = tonumber(units),
    }
  end

  if type(value) == "string" then
    add(value, DEFAULT_FUEL_ITEMS[value] or fallbackUnits)
  elseif type(value) == "table" then
    for _, entry in ipairs(value) do
      if type(entry) == "string" then
        add(entry, DEFAULT_FUEL_ITEMS[entry] or fallbackUnits)
      elseif type(entry) == "table" then
        add(entry.name or entry[1], entry.units or entry.fuelUnits or entry[2])
      end
    end

    for name, units in pairs(value) do
      if type(name) == "string" then
        add(name, units)
      end
    end
  end

  table.sort(specs, function(left, right)
    local leftUnits = left.units or 0
    local rightUnits = right.units or 0
    if leftUnits == rightUnits then
      return left.name < right.name
    end
    return leftUnits > rightUnits
  end)

  return specs
end

local function configuredFuelItems(dock, config)
  local value
  local fallbackUnits

  if dock and dock.fuelItems ~= nil then
    value = dock.fuelItems
    fallbackUnits = dock.fuelUnitsPerItem or config.fuelUnitsPerItem
  elseif dock and dock.fuelItem ~= nil then
    value = dock.fuelItem
    fallbackUnits = dock.fuelUnitsPerItem or config.fuelUnitsPerItem
  elseif config.fuelItems ~= nil then
    value = config.fuelItems
    fallbackUnits = config.fuelUnitsPerItem
  else
    value = config.fuelItem
    fallbackUnits = config.fuelUnitsPerItem
  end

  -- Existing configs used the singular coal default. Expand that legacy value
  -- to the current default allowlist without requiring an in-game config edit.
  if value == nil or value == LEGACY_DEFAULT_FUEL_ITEM then
    value = DEFAULT_FUEL_ITEMS
  end

  return fuelItemSpecs(value, fallbackUnits or DEFAULT_FUEL_UNITS_PER_ITEM)
end

local function formatFuelItems(items)
  local values = {}

  for _, item in ipairs(items or {}) do
    values[#values + 1] = item.name .. "=" .. tostring(item.units)
  end

  return formatList(values)
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
    fuelItems = DEFAULT_FUEL_ITEMS,
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
    laneCheckpointFile = DEFAULT_LANE_CHECKPOINTS,
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
  if config.fuelItems == nil and config.fuelItem == nil then
    config.fuelItems = DEFAULT_FUEL_ITEMS
  end
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
  config.laneCheckpointFile = config.laneCheckpointFile or DEFAULT_LANE_CHECKPOINTS
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

local function laneCheckpointPath(config)
  return config.laneCheckpointFile or DEFAULT_LANE_CHECKPOINTS
end

local function emptyLaneCheckpoints()
  return {
    version = 1,
    lanes = {},
  }
end

local function loadLaneCheckpoints(config)
  local path = laneCheckpointPath(config)
  local found = false
  local candidates = {
    path,
    path .. ".tmp",
    path .. ".bak",
  }

  for _, candidate in ipairs(candidates) do
    if fs.exists(candidate) then
      found = true

      local file = fs.open(candidate, "r")

      if file then
        local content = file.readAll()
        file.close()

        local data = textutils.unserialize(content)

        if type(data) == "table" and type(data.lanes) == "table" then
          data.version = 1
          return data, path
        end
      end
    end
  end

  if not found then
    return emptyLaneCheckpoints(), path
  end

  return nil, path, "lane checkpoints are unreadable: " .. path
end

local function saveLaneCheckpoints(config, checkpoints)
  local path = laneCheckpointPath(config)
  local tempPath = path .. ".tmp"
  local backupPath = path .. ".bak"
  local file = fs.open(tempPath, "w")

  if not file then
    return false, "could not write lane checkpoints: " .. tempPath
  end

  file.write(textutils.serialize(checkpoints))
  file.close()

  if fs.exists(backupPath) then
    fs.delete(backupPath)
  end

  if fs.exists(path) then
    fs.move(path, backupPath)
  end

  local moved, moveMessage = pcall(fs.move, tempPath, path)

  if not moved then
    if fs.exists(backupPath) and not fs.exists(path) then
      fs.move(backupPath, path)
    end

    return false, "could not replace lane checkpoints: " .. tostring(moveMessage)
  end

  if fs.exists(backupPath) then
    fs.delete(backupPath)
  end

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
  dock.key = tostring(
    dock.key
      or dock.turtleId
      or dock.rednetId
      or dock.rednetAddress
      or dock.name
      or dock.label
      or fallbackKey
      or "dock"
  )
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
    local fuelItems = configuredFuelItems(dock, config)

    if #fuelItems == 0 then
      return false, direction .. " dock needs at least one fuelItems entry"
    end

    for _, fuelItem in ipairs(fuelItems) do
      if not isPositiveWholeNumber(fuelItem.units) then
        return false,
          direction .. " fuel item " .. fuelItem.name .. " needs positive whole units"
      end
    end

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
  if type(config.laneCheckpointFile) ~= "string"
    or config.laneCheckpointFile == "" then
    return false, "laneCheckpointFile must be a file path"
  end

  local fuelItems = configuredFuelItems(nil, config)

  if #fuelItems == 0 then
    return false, "fuelItems must contain at least one item name"
  end

  for _, fuelItem in ipairs(fuelItems) do
    if not isPositiveWholeNumber(fuelItem.units) then
      return false, "fuel item " .. fuelItem.name .. " needs positive whole units"
    end
  end

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

local function inspectFuelInventory(inventoryName, fuelItems)
  local state = {
    counts = {},
    totalItems = 0,
    totalUnits = 0,
  }

  for _, fuelItem in ipairs(fuelItems) do
    local count, message = countItem(inventoryName, fuelItem.name)

    if message then
      return nil, message
    end

    state.counts[fuelItem.name] = count
    state.totalItems = state.totalItems + count
    state.totalUnits = state.totalUnits + count * fuelItem.units
  end

  return state
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

local function laneIdFor(config, dock, laneOffset)
  local name = dockDisplayName(dock)
  return config.areaId .. "/" .. tostring(dock.key or name)
    .. "/lane/" .. tostring(laneOffset)
end

local function laneJobSuffix(laneOffset)
  if laneOffset < 0 then
    return "m" .. tostring(math.abs(laneOffset))
  end

  if laneOffset > 0 then
    return "p" .. tostring(laneOffset)
  end

  return "0"
end

local function makeLaneJob(
  config,
  dock,
  targetDistance,
  runId,
  laneOffset,
  resumeFrom
)
  local name = dockDisplayName(dock)
  local heading = dock.cardinalDirection or PLACEHOLDER_CARDINAL_DIRECTION
  local laneId = laneIdFor(config, dock, laneOffset)

  return {
    type = "job",
    jobId = config.areaId .. "-" .. name .. "-" .. runId
      .. "-lane-" .. laneJobSuffix(laneOffset),
    task = "mine-lane",
    ao = dock.ao or name,
    heading = heading,
    turtleId = dock.turtleId,
    params = {
      laneId = laneId,
      targetDistance = targetDistance,
      laneLength = targetDistance,
      resumeFrom = resumeFrom,
      laneOffset = laneOffset,
      laneWidth = 1,
      laneHeight = 2,
      fuelMargin = dock.fuelMargin or config.fuelMargin,
      heartbeatInterval = config.heartbeatInterval,
    },
  }
end

local function laneOffsetsForDock(dock, config)
  local leftLanes, rightLanes = configuredSideLanes(dock, config)
  local offsets = { 0 }
  local widest = math.max(leftLanes, rightLanes)

  for distance = 1, widest do
    if distance <= leftLanes then
      offsets[#offsets + 1] = -distance
    end

    if distance <= rightLanes then
      offsets[#offsets + 1] = distance
    end
  end

  return offsets
end

local function makeWorkers(config, targetDistance, checkpoints)
  local workers = {}
  local runId = makeRunId()

  for _, dock in ipairs(config.activeDocks or {}) do
    local name = dockDisplayName(dock)
    local jobs = {}

    for _, laneOffset in ipairs(laneOffsetsForDock(dock, config)) do
      local laneId = laneIdFor(config, dock, laneOffset)
      local checkpoint = checkpoints.lanes[laneId] or {}
      local clearedThrough = tonumber(checkpoint.clearedThrough) or 0

      checkpoint.laneId = laneId
      checkpoint.areaId = config.areaId
      checkpoint.dockId = tostring(dock.key or name)
      checkpoint.heading = dock.cardinalDirection
      checkpoint.laneOffset = laneOffset
      checkpoint.targetDistance = targetDistance
      checkpoint.clearedThrough = clearedThrough
      checkpoint.state = clearedThrough >= targetDistance and "complete" or "pending"
      checkpoint.updatedAt = checkpoint.updatedAt or nowSeconds()
      checkpoints.lanes[laneId] = checkpoint

      if clearedThrough < targetDistance then
        jobs[#jobs + 1] = makeLaneJob(
          config,
          dock,
          targetDistance,
          runId,
          laneOffset,
          clearedThrough
        )
      end
    end

    workers[#workers + 1] = {
      direction = name,
      dock = dock,
      turtleId = dock.turtleId,
      state = #jobs > 0 and "queued" or "complete",
      jobs = jobs,
      jobIndex = 1,
      job = jobs[1],
      completedJobs = 0,
      totalJobs = #jobs,
      lastSeen = nil,
      lastMessage = #jobs > 0 and "queued" or "all lanes already complete",
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
    if worker.job then
      local query = makeFuelQuery(worker)

      worker.fuelQueryId = query.queryId
      worker.state = "fuel-query"
      worker.lastSent = nowSeconds()
      worker.lastMessage = "fuel query sent"
      pending[query.queryId] = worker
      pendingCount = pendingCount + 1

      print("Querying fuel for " .. worker.direction
        .. " turtle=" .. tostring(worker.turtleId))
      rednet.send(worker.turtleId, query, config.protocol)
    end
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

          if worker and worker.fuelQueryId and pending[worker.fuelQueryId] then
            worker.state = "failed"
            worker.lastMessage = tostring(message.code or "error")
              .. ": " .. tostring(message.message or "")
            print(worker.direction .. ": failed: " .. worker.lastMessage)
            pending[worker.fuelQueryId] = nil
            pendingCount = pendingCount - 1
          end
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

local function calculateJobFuelNeed(worker, report, config)
  local fuelMargin = configuredFuelMargin(worker.dock, config)

  if not fuelMargin or fuelMargin < 0 or fuelMargin ~= math.floor(fuelMargin) then
    return nil, "fuelMargin must be a non-negative whole number"
  end

  local totalFuel = 0
  local maxPhaseFuel = 0
  local pendingJobs = 0

  for index = worker.jobIndex or 1, #(worker.jobs or {}) do
    local job = worker.jobs[index]
    local params = job.params or {}
    local targetDistance = tonumber(params.targetDistance or params.laneLength)
    local laneOffset = tonumber(params.laneOffset or 0) or 0
    local progress = tonumber(params.resumeFrom) or 0

    if not targetDistance then
      return nil, "lane job target distance is missing"
    end

    if laneOffset == 0 then
      progress = math.max(progress, tonumber(report.progress) or 0)
      params.resumeFrom = progress
    end

    if progress < targetDistance then
      local phaseFuel

      if laneOffset == 0 then
        phaseFuel = targetDistance * 2 + fuelMargin + 2
      else
        phaseFuel = targetDistance * 2
          + math.abs(laneOffset) * 2
          + fuelMargin
      end

      totalFuel = totalFuel + phaseFuel
      maxPhaseFuel = math.max(maxPhaseFuel, phaseFuel)
      pendingJobs = pendingJobs + 1
    end
  end

  return {
    totalFuel = totalFuel,
    maxPhaseFuel = maxPhaseFuel,
    progress = tonumber(report.progress) or 0,
    pendingJobs = pendingJobs,
  }
end

local function calculateJobFuelPlan(worker, config)
  local maxItems = configuredFuelMaxItems(worker.dock, config) or 0

  if maxItems <= 0 then
    return {
      neededFuel = 0,
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
      neededFuel = 0,
      message = "turtle fuel is unlimited",
    }
  end

  if not currentFuel then
    return nil, "fuel report did not include numeric fuel"
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

  return {
    neededFuel = neededFuel,
    targetFuel = targetFuel,
    currentFuel = currentFuel,
    progress = need.progress,
    pendingJobs = need.pendingJobs,
    message = "needs " .. neededFuel .. " fuel units",
  }
end

local function reconcileDockFuel(direction, dock, config, neededFuel)
  local fuelItems = configuredFuelItems(dock, config)
  local fuelLabel = formatFuelItems(fuelItems)
  local state, inspectMessage = inspectFuelInventory(dock.fuelChest, fuelItems)

  if not state then
    return false, inspectMessage
  end

  local fuelSources = configuredFuelSources(dock, config)
  local maxItems = configuredFuelMaxItems(dock, config) or 0

  -- Return whole surplus items without dropping below the required fuel.
  for index = #fuelItems, 1, -1 do
    local fuelItem = fuelItems[index]
    local removable = math.floor((state.totalUnits - neededFuel) / fuelItem.units)
    local count = math.min(state.counts[fuelItem.name] or 0, removable)

    if count > 0 then
      local moved, remaining, moveMessage = moveItemsToTargets(
        dock.fuelChest,
        fuelSources,
        fuelItem.name,
        count
      )

      if moveMessage then
        return false, moveMessage
      end

      if remaining > 0 then
        return false,
          direction .. " could not return " .. remaining .. " surplus "
          .. fuelItem.name
      end

      state.counts[fuelItem.name] = state.counts[fuelItem.name] - moved
      state.totalItems = state.totalItems - moved
      state.totalUnits = state.totalUnits - moved * fuelItem.units
    end
  end

  -- Prefer higher-value fuel, then fall back through the configured mapping.
  if state.totalUnits < neededFuel then
    for _, fuelItem in ipairs(fuelItems) do
      for _, sourceName in ipairs(fuelSources) do
        if state.totalUnits >= neededFuel or state.totalItems >= maxItems then
          break
        end

        local missingUnits = neededFuel - state.totalUnits
        local itemCapacity = maxItems - state.totalItems
        local requestedItems = math.min(
          itemCapacity,
          math.ceil(missingUnits / fuelItem.units)
        )

        local moved, _, moveMessage = moveItemsToTargets(
          sourceName,
          { dock.fuelChest },
          fuelItem.name,
          requestedItems
        )

        if moveMessage then
          return false, moveMessage
        end

        state.counts[fuelItem.name] = (state.counts[fuelItem.name] or 0) + moved
        state.totalItems = state.totalItems + moved
        state.totalUnits = state.totalUnits + moved * fuelItem.units
      end

      if state.totalUnits >= neededFuel then
        break
      end
    end

  end

  if state.totalUnits < neededFuel then
    return false,
      direction .. " fuel short: need " .. neededFuel .. " units, staged "
      .. state.totalUnits .. " in " .. state.totalItems .. "/" .. maxItems
      .. " items (" .. fuelLabel .. ")"
  end

  if state.totalItems > maxItems then
    return false,
      direction .. " fuel needs " .. state.totalItems
      .. " items, above fuelMaxItemsPerJob " .. maxItems
  end

  return true,
    "staged " .. state.totalUnits .. " fuel units in "
    .. state.totalItems .. " items"
end

local function prepareJobFuel(workers, config)
  local allOk = true

  for _, worker in ipairs(workers) do
    if not worker.job then
      worker.lastMessage = "all lanes already complete"
    else
      local plan, planMessage = calculateJobFuelPlan(worker, config)

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
          plan.neededFuel
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
  end

  return allOk
end

local function sendCurrentJob(worker, protocol)
  if not worker.job then
    worker.state = "complete"
    worker.lastMessage = "all queued lanes complete"
    return
  end

  local params = worker.job.params or {}

  print(worker.direction
    .. ": starting lane " .. tostring(params.laneOffset)
    .. " from " .. tostring(params.resumeFrom or 0)
    .. "/" .. tostring(params.targetDistance))
  rednet.send(worker.turtleId, worker.job, protocol)
  worker.state = "sent"
  worker.lastSent = nowSeconds()
  worker.lastMessage = "lane job sent"
  worker.lastPrintedMessage = nil
end

local function sendJobs(workers, protocol)
  for _, worker in ipairs(workers) do
    if worker.job then
      sendCurrentJob(worker, protocol)
    end
  end
end

local function recordLaneCheckpoint(config, checkpoints, worker, message)
  if not config or not checkpoints or not worker.job then
    return true
  end

  local params = worker.job.params or {}
  local laneId = message.laneId
  local expectedLaneId = params.laneId

  if type(laneId) ~= "string" or laneId ~= expectedLaneId then
    return false, "status laneId does not match active job"
  end

  local clearedThrough = tonumber(message.clearedThrough)
  local targetDistance = tonumber(params.targetDistance)

  if not clearedThrough
    or clearedThrough < 0
    or clearedThrough ~= math.floor(clearedThrough)
    or clearedThrough > targetDistance then
    return false, "invalid lane checkpoint " .. tostring(message.clearedThrough)
  end

  local entry = checkpoints.lanes[laneId] or {
    laneId = laneId,
    areaId = config.areaId,
    dockId = tostring(worker.dock.key or worker.direction),
    laneOffset = params.laneOffset,
    targetDistance = targetDistance,
    clearedThrough = 0,
  }
  local previous = tonumber(entry.clearedThrough) or 0
  local changed = false

  if clearedThrough > previous then
    entry.clearedThrough = clearedThrough
    changed = true
  end

  local nextState = entry.state

  if message.type == "error" or message.status == "failed" then
    nextState = "failed"
  elseif message.status == "complete" and entry.clearedThrough >= targetDistance then
    nextState = "complete"
  elseif entry.clearedThrough < targetDistance then
    nextState = "in-progress"
  end

  if entry.state ~= nextState then
    entry.state = nextState
    changed = true
  end

  entry.jobId = worker.job.jobId
  entry.assignedTurtleId = worker.turtleId
  entry.targetDistance = targetDistance

  if changed then
    entry.updatedAt = nowSeconds()
    checkpoints.lanes[laneId] = entry

    local saved, saveMessage = saveLaneCheckpoints(config, checkpoints)

    if not saved then
      return false, saveMessage
    end
  else
    checkpoints.lanes[laneId] = entry
  end

  params.resumeFrom = math.max(tonumber(params.resumeFrom) or 0, entry.clearedThrough)
  return true
end

function handleStatus(workers, senderId, message, config, checkpoints)
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

  if worker.job
    and message.jobId
    and message.jobId ~= worker.job.jobId then
    return
  end

  worker.lastSeen = nowSeconds()

  local checkpointOk, checkpointMessage = recordLaneCheckpoint(
    config,
    checkpoints,
    worker,
    message
  )

  if not checkpointOk then
    worker.state = "failed"
    worker.lastMessage = checkpointMessage
    print(worker.direction .. ": failed: " .. checkpointMessage)
    return
  end

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
  worker.progress = message.clearedThrough or message.progress
  worker.fuel = message.fuel
  worker.lastMessage = message.message or worker.state

  if message.status == "complete" then
    local finishedJob = worker.job
    local params = finishedJob and finishedJob.params or {}
    local targetDistance = tonumber(params.targetDistance)
    local clearedThrough = tonumber(message.clearedThrough) or 0

    if not targetDistance or clearedThrough < targetDistance then
      worker.state = "failed"
      worker.lastMessage = "lane completion reported below target"
      print(worker.direction .. ": failed: " .. worker.lastMessage)
      return
    end

    worker.completedJobs = worker.completedJobs + 1
    print(worker.direction
      .. ": lane " .. tostring(params.laneOffset)
      .. " complete (" .. worker.completedJobs .. "/" .. worker.totalJobs .. ")")

    worker.jobIndex = worker.jobIndex + 1
    worker.job = worker.jobs[worker.jobIndex]

    if not worker.job then
      worker.state = "complete"
      worker.lastMessage = "all queued lanes complete"
      return
    end

    local outputOk, outputMessage = serviceDock(
      worker.direction,
      worker.dock,
      config
    )

    if not outputOk then
      worker.state = "failed"
      worker.lastMessage = outputMessage
      return
    end

    local nextEntry = checkpoints.lanes[worker.job.params.laneId]

    if nextEntry then
      worker.job.params.resumeFrom = tonumber(nextEntry.clearedThrough) or 0
    end

    sendCurrentJob(worker, config.protocol)
  elseif message.status == "running"
    and type(message.message) == "string"
    and string.sub(message.message, 1, 7) == "mining "
    and worker.lastPrintedMessage ~= message.message then
    worker.lastPrintedMessage = message.message
    print(worker.direction .. ": " .. message.message)
  end
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
      .. " lanes=" .. tostring(worker.completedJobs or 0)
      .. "/" .. tostring(worker.totalJobs or 0)
      .. " progress=" .. tostring(worker.progress or "?")
      .. " message=" .. tostring(worker.lastMessage))
  end
end

local function printLaneProgress(config)
  local checkpoints, path, checkpointMessage = loadLaneCheckpoints(config)

  if not checkpoints then
    print(checkpointMessage)
    return false
  end

  local lanes = {}

  for _, lane in pairs(checkpoints.lanes) do
    if lane.areaId == config.areaId then
      lanes[#lanes + 1] = lane
    end
  end

  table.sort(lanes, function(left, right)
    local leftDock = tostring(left.dockId or "")
    local rightDock = tostring(right.dockId or "")

    if leftDock == rightDock then
      return (tonumber(left.laneOffset) or 0) < (tonumber(right.laneOffset) or 0)
    end

    return leftDock < rightDock
  end)

  print("Lane checkpoints: " .. path)

  if #lanes == 0 then
    print("No lane checkpoints for " .. config.areaId .. ".")
    return true
  end

  for _, lane in ipairs(lanes) do
    print(tostring(lane.dockId)
      .. " lane=" .. tostring(lane.laneOffset)
      .. " " .. tostring(lane.clearedThrough or 0)
      .. "/" .. tostring(lane.targetDistance or "?")
      .. " " .. tostring(lane.state or "unknown"))
  end

  return true
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
  print("Fuel items: " .. formatFuelItems(configuredFuelItems(nil, config)))
  print("Storage: " .. formatList(configuredStorageTargets(nil, config)))
  print("Default side lanes: left=" .. tostring(config.leftLanes)
    .. " right=" .. tostring(config.rightLanes))
  print("Lane checkpoints: " .. laneCheckpointPath(config))
  print("")

  print("Initial dock service")
  if not serviceAll(config) then
    print("Initial dock service failed. Fix fuel/output storage before mining.")
    return false
  end

  local checkpoints, _, checkpointMessage = loadLaneCheckpoints(config)

  if not checkpoints then
    print(checkpointMessage)
    return false
  end

  local workers = makeWorkers(config, targetDistance, checkpoints)
  local checkpointsSaved, saveMessage = saveLaneCheckpoints(config, checkpoints)

  if not checkpointsSaved then
    print(saveMessage)
    return false
  end

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
        handleStatus(workers, senderId, message, config, checkpoints)
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

  if not serviceAll(config) then
    print("Final output transfer failed.")
    print("Fix the output/storage chests, then run mining_area service.")
    return false
  end

  print("Mining complete. Final output moved to configured storage.")
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

  if command == "progress" then
    local configPath = args[2] or DEFAULT_CONFIG
    local config, configError = loadConfig(configPath)

    if not config then
      print(configError)
      return false
    end

    return printLaneProgress(config)
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
