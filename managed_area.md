# Managed Area

## Purpose

A managed area is a local operational responsibility boundary.

It is usually controlled by one local computer placed near the resources it
manages. Those resources may include:

- turtles
- turtle docks
- chests and item buffers
- machines
- buildings or blocks
- monitors and other peripherals

The managed area computer owns local scheduling. It does not directly control
raw turtle movement.

## Responsibilities

The managed area computer should:

- maintain a local job queue
- track worker turtles as idle, running, failed, or offline
- assign one bounded job at a time to an idle turtle
- track local resources and storage points
- report area status upward to a command center
- decompose area-level work into turtle-sized jobs

For mining, the managed area should generate lane jobs:

```text
offset 0
offset -4
offset 4
offset -8
offset 8
```

Each lane job can be assigned to whichever turtle is free next.

## Relationship To Turtle AO

The managed area can define or select AO configs, but the turtle enforces its AO
locally.

The area computer sends:

```lua
{
  jobId = "dock_a-lane-004",
  task = "mine-lane",
  ao = "dock_a",
  heading = "east",
  params = {
    laneOffset = -8,
    laneLength = 150,
  },
}
```

The turtle receives the job, creates its local AO runtime, attaches guards, and
executes through the AO-scoped turtle API.

## Scaling Path

Start simple:

```text
one computer -> one turtle
```

Then scale to:

```text
one computer -> several turtles
```

Later:

```text
command center -> several managed areas -> several turtles per area
```

The contract should stay the same: managed areas assign jobs, turtles enforce
local safety, and higher layers do not send raw movement commands.
