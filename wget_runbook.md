# Turtle wget Runbook

Use this to check whether a server turtle can fetch scripts over HTTP and then
install `dockmine` for local execution.

## Goal

Download the script onto each turtle as a local program:

```lua
dockmine
```

Prefer downloading first, then running locally. Avoid `wget run` for operational
mining scripts because it does not leave you with an obvious local file to
inspect, edit, or rerun.

## Check wget Availability

On the turtle, run:

```lua
wget
```

If `wget` exists, it should print usage text.

If the shell says there is no such program, use the manual paste fallback:

```lua
edit dockmine
```

Then paste the contents of `turtles/dockmine.lua`.

## Check HTTP Access

Use a small known URL first:

```lua
wget https://example.com wget-test
```

Expected success:

```text
Downloaded as wget-test
```

Then clean up:

```lua
delete wget-test
```

If it fails, HTTP may be disabled or blocked by server config. In that case,
use `edit dockmine` and paste manually.

## Fetch dockmine

After this repo is pushed somewhere with a raw file URL, download the script:

```lua
wget <raw-dockmine-url> dockmine
```

Example shape for GitHub:

```lua
wget https://raw.githubusercontent.com/<user>/<repo>/<branch>/turtles/dockmine.lua dockmine
```

Then confirm the file exists:

```lua
list
```

Optionally inspect it:

```lua
edit dockmine
```

## Run Local Tests

Make sure the turtle is at the dock, facing the tunnel direction, with output
storage behind it and fuel storage below it.

Run:

```lua
dockmine 8
```

If that works:

```lua
dockmine 32
```

Then:

```lua
dockmine
```

## Reset Progress

Only reset progress when the turtle is physically back at the dock and facing
the tunnel direction.

```lua
delete .dockmine_progress
```

After deleting progress, the next `dockmine` run starts from tunnel progress
`0`.
