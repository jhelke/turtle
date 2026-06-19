# Area Of Operations

## Purpose

An Area of Operations, or AO, is a turtle-local safety boundary.

The goal is belt-and-suspenders safety: task code can have bugs, but movement
should still be guarded by a separate layer which prevents runaway turtles.

Mining is the first task using this idea, but AO is not mining-specific. The AO
runtime should eventually guard any turtle action that can affect the world.

AO is not the same as a `managed_area`. A managed area is controlled by a local
computer and may coordinate several turtles, machines, chests, and peripherals.
A turtle AO is enforced by one turtle for its own physical safety.

## Command Model

User-facing commands should separate AO, task, and orientation:

```text
run_task dock_a auto-mine-tunnel east
```

Meaning:

- `dock_a` selects the AO safety envelope
- `auto-mine-tunnel` selects the task pattern
- `east` means "assume the turtle is currently facing east"

Without GPS, the turtle does not discover east. The operator initializes that
fact by placing and facing the turtle correctly before running the command.

AO code should not implement mining or scheduling. AO code enforces safety. Task
code decides physical task behavior. Managed area computers decide which job is
assigned to which turtle.

## Naming

Use full names for docs:

```text
area_of_operations.md
```

Use topic prefixes for code:

```text
ao_runtime.lua
ao_movement_guard.lua
ao_dig_guard.lua
ao_inventory_guard.lua
ao_fuel_guard.lua
```

The prefix makes the topic relationship obvious while keeping each guard focused.

`ao_runtime.lua` is the root AO context. Guards attach to it.

```lua
local runtime = dofile("ao_runtime")
local ao = runtime.create({
  name = "dock_a",
  heading = "east",
  bounds = bounds,
  reserveFuel = 32,
})

dofile("ao_movement_guard").attach(ao)
dofile("ao_fuel_guard").attach(ao)

local t = ao.turtle()
t.forward()
```

Task code should receive the AO-scoped turtle wrapper, not the raw global
`turtle` API. That lets AO eventually scope all turtle actions.

Current skeleton files:

```text
turtles/ao_runtime.lua        -- root AO context and scoped turtle wrapper
turtles/ao_movement_guard.lua -- movement prediction, bounds, state update
turtles/ao_fuel_guard.lua     -- return-fuel invariant
turtles/ao_example.lua        -- minimal wiring example
```

## Movement Guard

The first AO guard should be `ao_movement_guard.lua`.

Its job is to guard and track turtle movement:

```lua
local t = ao.turtle()

t.forward()
t.back()
t.up()
t.down()
t.turnLeft()
t.turnRight()
```

Task code should call the AO-scoped turtle wrapper instead of raw movement:

```lua
local t = ao.turtle()

t.forward()
```

That gives the AO layer a chance to check bounds before every movement.

## Tracked State

The movement guard should track position relative to the start using AO-local
coordinates:

```text
forward = tunnel-direction offset
right = lateral offset
up = vertical offset
facing = north/east/south/west
```

The start position is always:

```text
forward = 0
right = 0
up = 0
facing = start direction
```

This does not require GPS. It is dead-reckoning from the turtle's own successful
movement calls.

For `heading = east`:

```text
forward = east
left = north
right = south
up = world up
```

## Bounds

An AO definition should include limits:

```lua
local bounds = {
  minForward = 0,
  maxForward = 160,
  minRight = -28,
  maxRight = 28,
  minUp = 0,
  maxUp = 1,
}
```

For a simple tunnel miner, this means:

- do not go behind the starting dock
- do not go farther than the planned tunnel distance
- do not drift sideways beyond allowed branch width
- do not climb or descend beyond allowed tunnel height

AO bounds should be stricter than task intent, but slightly larger than the
normal planned path. For example, a task may mine 150 blocks while the AO allows
160, giving room for return and recovery without allowing runaway movement.

## Task Pattern Example

`auto-mine-tunnel` is a mining task, not an AO.

Example task config:

```lua
local task = {
  laneLength = 150,
  laneWidth = 3,
  laneHeight = 2,
  laneSpacing = 4,
  maxNorthOffset = 24,
  maxSouthOffset = 24,
}
```

The pattern:

- mine a 3x2 tunnel forward
- return to the start position
- mine next lane north of start
- return to the start position
- mine next lane south of start
- repeat north/south until both offset limits are hit

The AO guard still checks every movement before it happens.

## Return Fuel

Return-home safety is a core invariant.

At minimum, a task should not start a lane unless:

```text
fuel >= estimated_lane_cost + distance_to_origin + reserve
```

`ao_runtime.lua` owns the return-cost function:

```lua
ao.setReturnCost(function(state)
  return math.abs(state.position.forward)
    + math.abs(state.position.right)
    + math.abs(state.position.up)
end)
```

`ao_fuel_guard.lua` should enforce this before every movement:

```text
fuel_after_move >= distance_to_origin_after_move + reserve
```

This makes every successful move still leave enough fuel to return home.

The first implementation can use Manhattan distance in AO-local coordinates:

```text
distance_to_origin = abs(position.forward)
  + abs(position.right)
  + abs(position.up)
```

This ignores turning cost because turtle turns do not consume fuel.

## Persistence

Dead-reckoned position is only useful if it survives interruption.

The AO runtime should save state after every successful state-changing action:

```lua
{
  ao = "dock_a",
  position = {
    forward = 37,
    right = -4,
    up = 0,
  },
  facing = "east",
  status = "running",
}
```

If the turtle reboots and saved state exists, it should not silently start a new
task. It should require an explicit resume or reset command.

Safe defaults:

- `resume` trusts saved AO state and continues recovery/task logic
- `reset` clears saved state only when the turtle is physically back at origin
- missing or corrupt state stops the program

## Failure Rules

If the guard cannot prove a movement is safe, it should refuse the movement.

Examples:

- requested move would leave bounds
- movement failed and position is uncertain
- fuel is below the configured reserve
- guard state was not initialized

When uncertain, stop and print a clear message. A stopped turtle is easier to
recover than a runaway turtle.

## Future Guards

AO can grow beyond movement:

```text
ao_dig_guard.lua       -- refuse to dig protected block IDs or tags
ao_fuel_guard.lua      -- enforce return-fuel reserve
ao_inventory_guard.lua -- enforce reserved slots or unload rules
```

Example dig guard rule:

```lua
neverDig = {
  ["minecraft:chest"] = true,
  ["minecraft:barrel"] = true,
}
```

This keeps task code focused on the job while AO guards enforce safety rules.
