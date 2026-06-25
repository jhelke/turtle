# Project Index

## Responsibility Stack

Reminder map for the layered turtle automation project. Details live in the
linked topic files.

```text
architecture.md
- core terms, authority rule, and layer boundaries

command_center.md
- player_request intake
- global routing
- cross-area coordination
- no direct turtle movement authority

managed_area.md
- local resource management
- local job queue
- turtle assignment
- peripherals, machines, chests, screens, and docks
- first mining-only controller in computers/mining_area.lua

protocol.md
- shared message formats
- inter-system request, job, status, and error schemas
- contracts between command center, managed areas, and turtles

mining.md
- mining domain rules
- lane-job generation
- standalone vs managed-area mining behavior
- junk policy and tunnel assumptions
- managed cardinal mining worker in turtles/mining_worker.lua

storage.md
- storage philosophy and roadmap
- Refined Storage boundary
- v1/v2/end-game responsibility split

storage_taxonomy_v1.md
- canonical manual chest taxonomy
- label format and category paths

storage_system_v1.md
- intake, routing, overflow, and index scanner behavior
- searchable visibility without retrieval

area_of_operations.md
- turtle-local safety envelope
- AO-scoped turtle API
- movement, fuel, dig, and inventory guards
- persisted turtle state

lua_cc_tweaked_quickstart.md
- Lua syntax basics
- CC:Tweaked turtle API basics
- simple local helper programs

turtle_wget_runbook.md
- check wget and HTTP access on turtles
- fetch dockmine as a local program
- run and reset dockmine safely

lua_runtime.md
- CC:Tweaked Lua runtime version
- type system and execution guarantees
- Lua 5.2/5.3 compatibility notes
```

## Core Terms

`player_request`: player-submitted request for an outcome.

`managed_area`: local computer plus local resources and worker scheduling.

`job`: bounded unit of work assigned to one worker.

`task`: executable behavior type, such as `mine-lane`, `unload`, or `refuel`.

`turtle_ao`: turtle-local safety envelope enforced before physical actions.
