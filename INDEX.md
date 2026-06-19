# Project Index

## Responsibility Stack

This project is moving from one turtle running local scripts toward a layered
automation system.

```text
command_center.md
- user intent
- global routing
- cross-area coordination
- no direct turtle movement authority

managed_area.md
- local resource management
- local job queue
- turtle assignment
- peripherals, machines, chests, screens, and docks

protocol.md
- shared message formats
- request, job, status, and error schemas
- contracts between command center, managed areas, and turtles

mining.md
- mining domain rules
- lane-job generation
- standalone vs managed-area mining behavior
- junk policy and tunnel assumptions

area_of_operations.md
- turtle-local safety envelope
- AO-scoped turtle API
- movement, fuel, dig, and inventory guards
- persisted turtle state

lua_cc_tweaked_quickstart.md
- Lua syntax basics
- CC:Tweaked turtle API basics
- simple local helper programs
```

## Core Terms

`request`:
High-level user or system intent, such as "mine more osmium".

`managed_area`:
A local responsibility boundary controlled by a local computer. It manages local
resources such as turtles, docks, chests, machines, peripherals, and job queues.

`job`:
A bounded unit of work assigned to one worker. For mining, prefer one lane per
job instead of one giant mining campaign.

`task`:
Executable behavior type, such as `mine-lane`, `unload`, or `refuel`.

`turtle_ao`:
The turtle-local Area of Operations. It is enforced on the turtle and prevents
unsafe physical actions even if higher layers send bad jobs.

## Authority Rule

Higher layers request outcomes. Lower layers enforce safety.

```text
command center -> managed area request
managed area -> turtle job
turtle -> AO-guarded local actions
```

Avoid designs where a command center or area computer sends raw movement
commands such as `forward` or `dig` to a turtle.
