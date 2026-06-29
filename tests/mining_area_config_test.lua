return {
  areaId = "test_area",
  protocol = "minecraft-cc-t:mining_area",
  fuelMaxItemsPerJob = 0,
  fuelUnitsPerItem = 80,
  fuelMargin = 2,
  fuelQueryTimeout = 2,
  leftLanes = 1,
  rightLanes = 1,
  serviceInterval = 5,
  statusTimeout = 45,
  heartbeatInterval = 3,
  dockRegistryFile = "test_docks",
  laneCheckpointFile = "test_lane_checkpoints",
  storage = {
    "storage",
  },
  docks = {
    {
      key = "north",
      cardinalDirection = "north",
      turtleId = 21,
      outputChest = "output",
      enabled = true,
    },
  },
}
