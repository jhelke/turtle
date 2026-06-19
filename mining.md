# Turtle Mining

## Scope

Mining is a task domain. It defines tunnel shapes, lane jobs, mining-specific
inventory behavior, junk policy, and the transition from standalone turtle use
to managed-area scheduling.

Mining does not own the AO safety model. Turtles should execute mining behavior
through the turtle-local AO runtime once custom movement is introduced.

## Current Goal

The current standalone mining topic starts with a small wrapper around the stock
CC:Tweaked `tunnel` program.

v0 is `preflight`:

```lua
preflight 150
```

It checks:

- argument is a positive whole number
- stock `tunnel` program exists
- turtle appears to have a pickaxe upgrade
- rear output chest/barrel exists by turning around and turning back
- fuel is at least `distance + 10`
- inventory has at least 4 empty slots

Then it runs:

```lua
tunnel <distance>
```

v0 turns in place to check rear output storage. It does not unload or return.
The turtle stays wherever the stock `tunnel` program leaves it.

## Standalone Turtle

Standalone mode means the operator directly starts a turtle program.

Example:

```lua
preflight 150
```

In this mode:

- the human chooses the turtle
- the human places and faces the turtle
- the human starts the task
- the turtle checks local preflight conditions
- the turtle does not receive jobs from a computer

This is the right mode for early learning and v0 scripts.

## Turtle Attached To A Managed Area

Attached mode means a local computer assigns bounded jobs to turtles.

In this mode:

- the managed area computer owns the mining job queue
- each turtle receives one bounded lane job
- the turtle enforces its own AO locally
- the turtle reports status, completion, or failure
- the area computer assigns the next job to the next free turtle

The managed area should own lane alternation:

```text
0, -4, 4, -8, 8, -12, 12
```

The turtle should not own the whole campaign. It should execute one lane job and
return a result.

Example lane job:

```lua
{
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

This cut makes scaling natural: one turtle, two turtles, or more turtles can all
pull from the same queue of lane jobs.

## Dock Assumption

The turtle starts facing the tunnel direction.

```text
[output chest] [turtle -> tunnel direction]
```

From the turtle's perspective, the output chest is behind it. CC:Tweaked has
front/up/down inspect/drop APIs, but no direct "inspect behind" API. Any script
that verifies or unloads into the rear chest must turn around first.

v0 does the smallest safe version of this: turn around, inspect for a
chest/barrel, turn back to the tunnel direction.

## Program Files

Create each mining-related program in-game:

```lua
edit preflight
edit junk_policy
edit junkscan
```

Use the matching files from `turtles/` as the source text.

## Junk Policy

For v1, keep junk detection in one shared file:

```lua
local junk = dofile("junk_policy")
```

The policy uses item IDs like:

```lua
minecraft:cobblestone
mekanism:osmium_ore
```

The part before `:` is the namespace. `minecraft` is vanilla. Modded items use
their mod ID as the namespace, such as `mekanism`.

Do not treat a whole namespace as junk. Mods contain both junk blocks and
valuable ores. Prefer this structure:

```lua
junk.byNamespace = {
  minecraft = {
    cobblestone = true,
    cobbled_deepslate = true,
    dirt = true,
  },
}
```

When inventory is full, v1 can use:

```lua
local ok, result = junk.dropChosenSlot("front")
```

The helper only chooses a drop slot if all 16 slots are full and more than one
slot contains known junk. It drops the smallest junk stack first.

Supported drop directions are:

```lua
junk.dropChosenSlot("front")
junk.dropChosenSlot("up")
junk.dropChosenSlot("down")
```

Use `junkscan` to see what the policy would drop without dropping anything.

## Planned Versions

v0:

- preflight checks
- rear output chest check
- call stock `tunnel <distance>`
- no custom mining movement

v1:

- custom tunnel or lane control
- return to starting position when the job is finished
- use junk policy when inventory is full
- execute through turtle-local AO guards

v1.1:

- calculate safe range from available fuel
- reserve enough fuel to return home
