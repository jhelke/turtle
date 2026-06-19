-- Shared junk item policy for mining turtles.
--
-- Usage from another program in the same directory:
--   local junk = dofile("junk_policy")
--   local slot = junk.chooseDropSlot()

local junk = {}

-- Keys are namespaces, values are item paths inside that namespace.
-- This is intentionally conservative. Do not mark an entire namespace as junk:
-- mods often contain both trash blocks and valuable ores.
junk.byNamespace = {
  minecraft = {
    andesite = true,
    basalt = true,
    blackstone = true,
    calcite = true,
    cobbled_deepslate = true,
    cobblestone = true,
    deepslate = true,
    diorite = true,
    dirt = true,
    granite = true,
    gravel = true,
    netherrack = true,
    sand = true,
    tuff = true,
  },
}

-- Exact full item IDs can override or extend namespace rules.
junk.exact = {
  ["minecraft:cobblestone"] = true,
  ["minecraft:cobbled_deepslate"] = true,
}

function junk.splitName(name)
  if type(name) ~= "string" then
    return nil, nil
  end

  return string.match(name, "^([^:]+):(.+)$")
end

function junk.isJunkName(name)
  if junk.exact[name] then
    return true
  end

  local namespace, path = junk.splitName(name)
  local namespaceRules = namespace and junk.byNamespace[namespace]

  return namespaceRules ~= nil and namespaceRules[path] == true
end

function junk.isJunkItem(item)
  return item ~= nil and junk.isJunkName(item.name)
end

function junk.isInventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then
      return false
    end
  end

  return true
end

function junk.findJunkSlots()
  local slots = {}

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if junk.isJunkItem(item) then
      slots[#slots + 1] = {
        slot = slot,
        name = item.name,
        count = item.count,
      }
    end
  end

  return slots
end

function junk.chooseDropSlot()
  if not junk.isInventoryFull() then
    return nil, "inventory is not full"
  end

  local slots = junk.findJunkSlots()

  if #slots <= 1 then
    return nil, "need more than one junk slot before dropping"
  end

  local choice = slots[1]

  for i = 2, #slots do
    local candidate = slots[i]

    -- Drop the smallest junk stack first. This frees one slot while keeping
    -- larger building-block stacks available if you still want them later.
    if candidate.count < choice.count then
      choice = candidate
    end
  end

  return choice.slot, choice
end

function junk.dropChosenSlot(direction)
  direction = direction or "front"

  local previousSlot = turtle.getSelectedSlot()
  local slot, choice = junk.chooseDropSlot()

  if not slot then
    return false, choice
  end

  turtle.select(slot)
  local ok, err

  if direction == "front" then
    ok, err = turtle.drop()
  elseif direction == "up" then
    ok, err = turtle.dropUp()
  elseif direction == "down" then
    ok, err = turtle.dropDown()
  else
    turtle.select(previousSlot)
    return false, "unknown drop direction: " .. tostring(direction)
  end

  turtle.select(previousSlot)

  if not ok then
    return false, err
  end

  return true, choice
end

return junk
