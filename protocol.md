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

## Turtle Status

```lua
{
  type = "turtle-status",
  turtleId = 12,
  jobId = "dock_a-lane-004",
  status = "running",
  fuel = 842,
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
