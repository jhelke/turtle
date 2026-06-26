-- Show which inventory slots match junk_policy.
-- Usage: junkscan

local args = { ... }

local function usage()
  print("Usage: junkscan")
  print("Reports inventory slots matching junk_policy.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return true
end

local junk = dofile("junk_policy")

print("Junk scan")
print("Inventory full: " .. tostring(junk.isInventoryFull()))

local slots = junk.findJunkSlots()

if #slots == 0 then
  print("No junk slots found")
else
  for i = 1, #slots do
    local item = slots[i]
    print("Slot " .. item.slot .. ": " .. item.count .. "x " .. item.name)
  end
end

local dropSlot, choice = junk.chooseDropSlot()

if dropSlot then
  print("Would drop slot " .. dropSlot .. ": " .. choice.count .. "x " .. choice.name)
else
  print("Would not drop: " .. choice)
end
