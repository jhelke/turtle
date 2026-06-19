-- Refuel from all turtle inventory slots.
-- Usage: fuelall

for slot = 1, 16 do
  turtle.select(slot)
  turtle.refuel()
end

turtle.select(1)
print("Fuel: " .. turtle.getFuelLevel() .. " / " .. turtle.getFuelLimit())
