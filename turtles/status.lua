-- Non-moving turtle status report.
-- Usage: status

local args = { ... }

local function usage()
  print("Usage: status")
  print("Shows turtle ID, fuel, and non-empty slots.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return true
end

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
