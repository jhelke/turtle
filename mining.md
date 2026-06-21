# Turtle Mining

## Scope

Mining is a task domain. It defines tunnel shapes, lane jobs, mining-specific
inventory behavior, junk policy, and the transition from standalone turtle use
to managed-area scheduling.

Mining does not own the AO safety model. Turtles should execute mining behavior
through the turtle-local AO runtime once custom movement is introduced.

## Current Standalone Programs

The standalone mining topic starts with a small wrapper around the stock
CC:Tweaked `tunnel` program and then moves to a custom fixed-dock miner.

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

v1 standalone is `dockmine`:

```lua
dockmine 8
dockmine 32
dockmine
```

It mines a 1-wide, 2-high straight tunnel from a fixed dock. It saves progress
in `.dockmine_progress`, returns to the dock when inventory fills or fuel reaches
the return threshold, unloads into the output chest behind the turtle, refuels
from the fuel chest below the turtle, and resumes from the saved tunnel face.

Use `dockmine 8` first on each turtle. Run without a limit only after the dock,
rear output chest, below fuel chest, unloading, refuelling, and return behavior
are confirmed.

## Mining Script Mode

`dockmine` can also run as a task primitive for another script:

```lua
dockmine 32 script
```

Script mode follows the cross-task rule from `architecture.md`: the called
script is responsible for movement, block interaction, and task-local inventory
mechanics required for that interaction. For `dockmine`, that means mining a
bounded 1-wide, 2-high lane and returning to the script start position.

Task-local inventory mechanics include selecting required slots, consuming
explicitly allowed blocks, restoring the selected slot when practical, and
failing cleanly when required inventory is missing or full.

The caller owns resource policy and orchestration:

- dock checks
- unloading
- refuelling
- fuel policy
- inventory policy, such as junk rules and empty-slot thresholds
- progress tracking
- lane scheduling
- retry and recovery behavior

`wide_dockmine` uses this contract. It services the real dock, checks fuel and
inventory, moves between lanes, and calls `dockmine <depth> script` for each
bounded lane.

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

`dockmine` uses the same rear-output assumption and also expects a fuel
chest/barrel directly below the turtle:

```text
Top view:

[output chest] [turtle -> tunnel direction]

Side view:

       tunnel direction
             ^
             |
        [turtle]
             |
      [fuel chest below]
```

For the four-cardinal dock setup, each turtle owns one direction, one output
chest behind it, one fuel chest below it, and one local `.dockmine_progress`
file.

## Program Files

Create each mining-related program in-game:

```lua
edit preflight
edit dockmine
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

- `dockmine` fixed-dock straight tunnel control
- return to starting position when the job is finished
- unload into the rear output chest
- refuel from the chest below the turtle
- save progress in `.dockmine_progress`

not v1:

- shared tunnel coordination
- collision logic
- central controller
- moving the dock forward
- side-branch mining
- wireless status reporting
- executing through turtle-local AO guards

v1.1:

- calculate safe range from available fuel
- reserve enough fuel to return home
