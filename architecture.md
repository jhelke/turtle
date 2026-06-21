# Architecture Notes

This project is moving from one turtle running local scripts toward a layered
automation system.

## Core Terms

`player_request`:
A player-submitted request for an outcome, such as "mine more osmium".

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
command center -> managed area player_request
managed area -> turtle job
turtle -> AO-guarded local actions
```

Avoid designs where a command center or area computer sends raw movement
commands such as `forward` or `dig` to a turtle.

When one script calls another script as a task primitive, the called script owns
movement, block interaction, and task-local inventory mechanics required for
that interaction. The caller owns resource policy, scheduling, persistence, and
recovery.
