-- Non-moving turtle status report.
-- Usage: status

print("Label: " .. tostring(os.getComputerLabel()))
print("ID: " .. os.getComputerID())
print("Fuel: " .. turtle.getFuelLevel() .. " / " .. turtle.getFuelLimit())

local used = 0

for slot = 1, 16 do
  local count = turtle.getItemCount(slot)

  if count > 0 then
    used = used + 1
    local detail = turtle.getItemDetail(slot)
    local name = detail and detail.name or "unknown"

    print("Slot " .. slot .. ": " .. count .. "x " .. name)
  end
end

print("Used slots: " .. used .. " / 16")
