-- Show which inventory slots match junk_policy.
-- Usage: junkscan

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
