-- Copy this file to the managed-area computer as:
--   mining_area_config
--
-- Then replace all peripheral names and turtle IDs with the names printed by:
--   mining_area peripherals

return {
  areaId = "mine_01",
  protocol = "minecraft-cc-t:mining_area",

  fuelItem = "minecraft:coal",
  fuelTargetItems = 64,
  fuelMargin = 32,

  serviceInterval = 5,
  statusTimeout = 45,
  heartbeatInterval = 5,
  dockRegistryFile = "mining_area_docks",

  storageChests = {
    "minecraft:chest_10",
    "minecraft:chest_11",
  },

  fuelStorageChests = {
    "minecraft:barrel_12",
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
