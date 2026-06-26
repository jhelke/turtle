-- Minimal AO wiring example.
--
-- This is not a mining task. It only shows how task code should receive the
-- AO-scoped turtle wrapper instead of using raw turtle.forward().

local args = { ... }

local function usage()
  print("Usage: ao_example")
  print("Runs one guarded AO forward-move example.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return true
end

local runtime = dofile("ao_runtime")

local ao = runtime.create({
  name = "dock_a",
  heading = "east",
  reserveFuel = 32,
  bounds = {
    minForward = 0,
    maxForward = 160,
    minRight = -28,
    maxRight = 28,
    minUp = 0,
    maxUp = 1,
  },
})

dofile("ao_movement_guard").attach(ao)
dofile("ao_fuel_guard").attach(ao)

ao.setReturnCost(function(state)
  return math.abs(state.position.forward)
    + math.abs(state.position.right)
    + math.abs(state.position.up)
end)

local t = ao.turtle()

local ok, err = t.forward()

if not ok then
  print("AO refused action: " .. tostring(err))
else
  print("Moved safely")
end
