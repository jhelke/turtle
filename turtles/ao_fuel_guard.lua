-- AO fuel guard.
--
-- Design rationale:
-- - Fuel safety is separate from movement prediction.
-- - Movement proposes the next state. Fuel decides whether that state still
--   leaves enough fuel to return home.
-- - Return cost belongs to ao_runtime because task/AO context may know a more
--   conservative route home than simple Manhattan distance.

local fuel = {}

function fuel.attach(ao)
  local guard = {}

  function guard.beforeAction(_, action)
    if action.kind ~= "move" then
      return true
    end

    local level = turtle.getFuelLevel()

    if level == "unlimited" then
      return true
    end

    local required = ao.getReturnCost(action.nextState) + ao.settings().reserveFuel

    -- Because this check happens before the move, reserve one fuel for the
    -- movement about to happen.
    if level - 1 < required then
      return false, "fuel would not cover return cost plus reserve"
    end

    return true
  end

  ao.registerGuard(guard)
  return guard
end

return fuel
