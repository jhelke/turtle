# Protocol

## Purpose

`protocol.md` defines the message contracts between layers:

- command center
- managed area computers
- worker turtles

Keep message shapes here so domain docs do not each invent their own protocol.

## Request

A request describes high-level intent.

```lua
{
  type = "request",
  requestId = "req-0001",
  kind = "mine-resources",
  params = {
    resources = {
      "minecraft:iron_ore",
      "mekanism:osmium_ore",
    },
  },
}
```

Requests usually travel from command center to managed area.

## Job

A job is a bounded unit of work for one turtle.

```lua
{
  type = "job",
  jobId = "dock_a-lane-004",
  task = "mine-lane",
  ao = "dock_a",
  heading = "east",
  params = {
    laneOffset = -8,
    laneLength = 150,
    laneWidth = 3,
    laneHeight = 2,
  },
}
```

Jobs usually travel from managed area to turtle.

The first cardinal mining area also supports a `mine-distance` job. It is a
straight dock job where `targetDistance` is the absolute desired
`.dockmine_progress` value on that turtle:

```lua
{
  type = "job",
  jobId = "mine_01-east-12345",
  task = "mine-distance",
  heading = "east",
  turtleId = 22,
  params = {
    targetDistance = 150,
    laneLength = 150,
    laneOffset = 0,
    laneWidth = 1,
    laneHeight = 2,
  },
}
```

## Job-Start Fuel Query

Before sending a job that uses managed fuel supply, the managed-area computer
asks the idle worker for its current dock-progress and fuel state:

```lua
{
  type = "fuel-query",
  queryId = "mine_01-east-12345-fuel",
  jobId = "mine_01-east-12345",
  turtleId = 22,
  params = {
    targetDistance = 150,
    fuelMargin = 32,
  },
}
```

The worker replies before the job is dispatched:

```lua
{
  type = "fuel-report",
  queryId = "mine_01-east-12345-fuel",
  jobId = "mine_01-east-12345",
  turtleId = 22,
  fuel = 842,
  fuelLimit = 20000,
  progress = 37,
}
```

The manager uses this report to stage only the calculated number of fuel items
in the dock fuel chest. The periodic service loop should not top up fuel.

## Turtle Status

```lua
{
  type = "turtle-status",
  turtleId = 12,
  jobId = "dock_a-lane-004",
  status = "running",
  fuel = 842,
  progress = 37,
  position = {
    forward = 37,
    right = -8,
    up = 0,
  },
}
```

Valid status values should start simple:

```text
idle
running
complete
failed
offline
```

## Error

```lua
{
  type = "error",
  jobId = "dock_a-lane-004",
  turtleId = 12,
  code = "ao_bounds_refused",
  message = "movement would leave AO bounds",
}
```

Errors should be explicit enough for the managed area computer to decide whether
to retry, mark the job failed, or require human recovery.
