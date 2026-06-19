-- AO movement guard.
--
-- Design rationale:
-- - This guard owns position/facing prediction and bounds checks.
-- - It does not own fuel policy, persistence, digging, or task behavior.
-- - It updates AO state only after raw turtle movement succeeds.

local movement = {}

local directions = { "north", "east", "south", "west" }
local directionIndex = {
  north = 1,
  east = 2,
  south = 3,
  west = 4,
}

local function turn(facing, delta)
  local index = directionIndex[facing]

  if not index then
    return facing
  end

  return directions[((index - 1 + delta) % 4) + 1]
end

local function worldVector(facing)
  if facing == "north" then
    return 1, 0
  elseif facing == "east" then
    return 0, 1
  elseif facing == "south" then
    return -1, 0
  elseif facing == "west" then
    return 0, -1
  end

  return 0, 0
end

local function movementDelta(originFacing, facing, actionName)
  local sign = 1

  if actionName == "back" then
    sign = -1
  end

  if actionName == "up" then
    return 0, 0, 1
  elseif actionName == "down" then
    return 0, 0, -1
  end

  local moveNorth, moveEast = worldVector(facing)
  local forwardNorth, forwardEast = worldVector(originFacing)
  local rightNorth, rightEast = worldVector(turn(originFacing, 1))

  local df = (moveNorth * forwardNorth + moveEast * forwardEast) * sign
  local dr = (moveNorth * rightNorth + moveEast * rightEast) * sign

  return df, dr, 0
end

local function insideBounds(position, bounds)
  if not bounds then
    return true
  end

  return position.forward >= (bounds.minForward or -math.huge)
    and position.forward <= (bounds.maxForward or math.huge)
    and position.right >= (bounds.minRight or -math.huge)
    and position.right <= (bounds.maxRight or math.huge)
    and position.up >= (bounds.minUp or -math.huge)
    and position.up <= (bounds.maxUp or math.huge)
end

function movement.attach(ao)
  local guard = {}

  function guard.planAction(_, action)
    if action.kind == "turn" then
      if action.name == "turnLeft" then
        action.nextState.facing = turn(action.nextState.facing, -1)
      elseif action.name == "turnRight" then
        action.nextState.facing = turn(action.nextState.facing, 1)
      end

      return true
    end

    if action.kind ~= "move" then
      return true
    end

    local df, dr, du = movementDelta(ao.settings().heading, action.nextState.facing, action.name)
    action.nextState.position.forward = action.nextState.position.forward + df
    action.nextState.position.right = action.nextState.position.right + dr
    action.nextState.position.up = action.nextState.position.up + du

    if not insideBounds(action.nextState.position, ao.settings().bounds) then
      return false, "movement would leave AO bounds"
    end

    return true
  end

  function guard.afterAction(_, action, ok)
    if ok and (action.kind == "move" or action.kind == "turn") then
      ao.replaceState(action.nextState)
    end
  end

  ao.registerGuard(guard)
  return guard
end

return movement
