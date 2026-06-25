-- Copy this file to the managed-area computer as:
--   mining_area_config
--
-- Then replace all peripheral names and turtle IDs with the names printed by:
--   mining_area peripherals
--
-- Chests and barrels use peripheral names like "minecraft:chest_10".
-- Under storage/fuelStorage, add only the suffix numbers after each prefix.
-- Rednet IDs are only for turtles/computers.

return {
  areaId = "mine_01",
  protocol = "minecraft-cc-t:mining_area",

  fuelItem = "minecraft:coal",
  fuelUnitsPerItem = 80,
  -- Job-start fuel staging asks the turtle for fuel/progress and supplies only
  -- the calculated item count. Set to 0 to disable managed fuel supply.
  fuelMaxItemsPerJob = 64,
  fuelMargin = 32,
  fuelQueryTimeout = 5,

  serviceInterval = 5,
  statusTimeout = 45,
  heartbeatInterval = 5,
  dockRegistryFile = "mining_area_docks",

  -- Mined output storage.
  storage = {
    ["minecraft:chest_"] = {
      10,
      11,
    },

    ["minecraft:barrel_"] = {
      -- 10,
    },
  },

  -- Fuel source storage. The controller pulls fuelItem from these.
  fuelStorage = {
    ["minecraft:chest_"] = {
      -- 12,
    },

    ["minecraft:barrel_"] = {
      12,
    },
  },

  -- Optional static docks. You can leave this empty and use:
  --   mining_area discover
  --   mining_area add-turtle
  --
  -- One enabled dock is enough. Add more entries later to scale toward four
  -- turtles per managed area.
  docks = {
    {
      key = "north",
      cardinalDirection = "north",
      turtleId = 21,
      outputChest = "minecraft:chest_0",
      fuelChest = "minecraft:barrel_0",
      enabled = true,
    },
  },
}
