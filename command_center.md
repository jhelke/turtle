# Command Center

## Purpose

The command center is the global coordination layer.

It accepts user or system requests and routes them to managed areas. It should
not directly control turtle movement or low-level peripherals.

## Responsibilities

The command center should:

- accept high-level requests
- choose which managed area should handle a request
- track global status and capacity
- receive status reports from managed areas
- display system state to users
- avoid direct worker control

Example request:

```lua
{
  requestId = "req-0001",
  kind = "mine-resources",
  resources = {
    "minecraft:iron_ore",
    "mekanism:osmium_ore",
  },
}
```

The command center decides which managed area is suitable, then sends an
area-level request. The managed area decomposes it into jobs.

## Non-Goals

The command center should not send commands like:

```text
turtle.forward
turtle.dig
turtle.drop
```

Those actions belong inside turtle-local AO enforcement.
