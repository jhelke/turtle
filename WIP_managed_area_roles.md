# WIP Managed Area Roles

## Current Agreement

A physical CC:Tweaked computer can host one or more roles, but each role should
have a clear responsibility boundary.

```text
command_center
-> routes player_request

inventory_index_area
-> owns searchable knowledge of inventories

mining_area
-> owns turtle docks, lane jobs, mining defaults/guardrails
```

This is a role model, not necessarily one computer per role. A single computer
may host multiple roles when that is practical, but the code and protocol should
still keep the responsibilities separate.

## Role Sketch

`command_center`:

- accepts `player_request`s
- decides which area or role should handle the request
- coordinates across areas
- does not send raw turtle movement commands

`inventory_index_area`:

- owns searchable inventory knowledge
- scans or receives inventory state
- answers item location and quantity questions
- may support reservation later
- does not decide mining lane shape or turtle movement

`mining_area`:

- owns turtle docks
- owns mining lane job generation
- tracks mining workers and job state
- applies mining defaults
- validates mining guardrails
- may query an inventory index for fuel or storage context

## Open Questions

- What is the smallest shared contract all roles must expose?
- Are `inventory_index_area` and `mining_area` both managed areas, or are they
  better described as area roles hosted by a computer?
- How should roles discover each other on the local network?
- Should one process own all roles on a computer, or should each role be a
  separate program with message passing?
- How should role state be persisted across reboots?
- What is the right naming convention for defaults and guardrails without
  relying on types?
- Which guardrails must also be enforced turtle-side by AO?
- How much should a mining area know about storage versus asking the
  inventory index?

## Naming Direction

Avoid ambiguous structures like:

```lua
defaults = {
  mining = {},
}

limits = {
  mining = {},
}
```

Prefer names that include the semantic role:

```lua
mineLaneDefaults = {}
mineLaneGuardrails = {}
inventoryIndexDefaults = {}
inventoryIndexGuardrails = {}
```

This naming is still tentative. The goal is to make the Lua tables readable
without a type system.

## Next Discussion

Develop the concrete implementation shape without assuming too much too early.
Start from the agreed role boundaries, then decide:

- file/module layout
- process layout
- message contracts
- persistence format
- naming conventions for defaults versus guardrails
