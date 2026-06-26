-- Refuel from all turtle inventory slots.
-- Usage: fuelall

local args = { ... }

local function usage()
  print("Usage: fuelall")
  print("Consumes fuel from all turtle inventory slots.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return true
end

for slot = 1, 16 do
  turtle.select(slot)
  turtle.refuel()
end

turtle.select(1)
print("Fuel: " .. turtle.getFuelLevel() .. " / " .. turtle.getFuelLimit())
