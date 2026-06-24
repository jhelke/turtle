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

## First Mining Area Implementation

The first runnable managed area is the mining-only controller:

```text
computers/mining_area.lua
```

It owns one or more dock workers. A mature area can use four cardinal docks:

```text
north
east
south
west
```

For early sessions, one enabled dock is enough. Auto-discovered turtles can be
registered first with `cardinalDirection = "Awaiting-User-Input"` and then
finished later through the manual dock dialog.

Run it on the managed-area computer with a target distance:

```lua
mining_area 150
```

The target distance is absolute per dock. If a turtle's `.dockmine_progress`
already says `40`, a `mining_area 150` run asks that turtle to mine `110` more
blocks. If progress is already at or past the target, the worker reports
complete without mining.

The computer does not send movement commands. It sends one `mine-distance` job
to each turtle and keeps servicing local peripherals:

- fills each dock's fuel chest from configured fuel storage
- empties each dock's output chest into configured storage
- tracks turtle status until all enabled docks complete, fail, or go offline

The computer needs a local config file copied from:

```text
computers/mining_area_config.example.lua
```

Use this on the computer to discover peripheral names:

```lua
mining_area peripherals
```

Use this to test chest servicing without starting turtles:

```lua
mining_area service
```

Use this to discover running mining workers:

```lua
mining_area discover
```

Use this to manually add or finish a turtle dock entry:

```lua
mining_area add-turtle
```

Use this to inspect configured, discovered, and disabled docks:

```lua
mining_area docks
```

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
