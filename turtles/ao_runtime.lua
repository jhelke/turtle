-- Root Area of Operations context.
--
-- Design rationale:
-- - AO is broader than movement. Later it may guard digging, inventory, fuel,
--   rednet commands, or any other turtle action.
-- - Task code should receive ao.turtle(), not the raw global turtle API.
-- - Guards attach to this runtime and participate in action planning/checking.
-- - Movement is just one guard. It does not own the AO.

local args = { ... }

if args[1] == "-h" or args[1] == "--help" then
  print("Usage: local runtime = dofile(\"ao_runtime\")")
  print("Creates guarded AO-scoped turtle APIs.")
  return true
end

local runtime = {}
local unpackArgs = table.unpack or unpack

local function copyState(state)
  return {
    ao = state.ao,
    originFacing = state.originFacing,
    position = {
      forward = state.position.forward,
      right = state.position.right,
      up = state.position.up,
    },
    facing = state.facing,
    status = state.status,
  }
end

local function defaultReturnCost(state)
  return math.abs(state.position.forward)
    + math.abs(state.position.right)
    + math.abs(state.position.up)
end

function runtime.create(config)
  local ao = {}
  local guards = {}
  local returnCostFn = defaultReturnCost

  local state = {
    ao = config.name,
    originFacing = config.heading,
    position = {
      forward = 0,
      right = 0,
      up = 0,
    },
    facing = config.heading,
    status = "running",
  }

  local settings = {
    bounds = config.bounds,
    heading = config.heading,
    reserveFuel = config.reserveFuel or 0,
    stateFile = config.stateFile or ".ao_state",
  }

  function ao.state()
    return copyState(state)
  end

  function ao.settings()
    return settings
  end

  function ao.replaceState(nextState)
    state = copyState(nextState)
  end

  function ao.registerGuard(guard)
    guards[#guards + 1] = guard
  end

  function ao.setReturnCost(fn)
    returnCostFn = fn
  end

  function ao.getReturnCost(nextState)
    return returnCostFn(nextState or state)
  end

  function ao.saveState()
    -- Skeleton only. This is where C5 persistence belongs.
    -- Use textutils.serialize(state) or textutils.serializeJSON(state) later.
    return true
  end

  function ao.runAction(action)
    -- Start each action with a predicted copy of current state. Guards may
    -- enrich this during planAction. For example, movement predicts the next
    -- position, then fuel validates that predicted position.
    action.nextState = copyState(state)

    for i = 1, #guards do
      local guard = guards[i]

      if guard.planAction then
        local ok, err = guard.planAction(ao, action)

        if not ok then
          return false, err
        end
      end
    end

    for i = 1, #guards do
      local guard = guards[i]

      if guard.beforeAction then
        local ok, err = guard.beforeAction(ao, action)

        if not ok then
          return false, err
        end
      end
    end

    local ok, err = action.raw()

    for i = 1, #guards do
      local guard = guards[i]

      if guard.afterAction then
        guard.afterAction(ao, action, ok, err)
      end
    end

    if ok and action.stateChanging then
      ao.saveState()
    end

    return ok, err
  end

  local scopedTurtle = {}

  local function wrap(name, kind, stateChanging)
    scopedTurtle[name] = function(...)
      local args = { ... }

      return ao.runAction({
        name = name,
        kind = kind,
        stateChanging = stateChanging,
        raw = function()
          return turtle[name](unpackArgs(args))
        end,
      })
    end
  end

  wrap("forward", "move", true)
  wrap("back", "move", true)
  wrap("up", "move", true)
  wrap("down", "move", true)
  wrap("turnLeft", "turn", true)
  wrap("turnRight", "turn", true)

  -- Non-movement actions are included to show the intended API surface.
  -- Future guards can refuse dangerous digs or unsafe drops here.
  wrap("dig", "dig", false)
  wrap("digUp", "dig", false)
  wrap("digDown", "dig", false)
  wrap("drop", "inventory", false)
  wrap("dropUp", "inventory", false)
  wrap("dropDown", "inventory", false)

  function scopedTurtle.inspect(...)
    return turtle.inspect(...)
  end

  function scopedTurtle.inspectUp(...)
    return turtle.inspectUp(...)
  end

  function scopedTurtle.inspectDown(...)
    return turtle.inspectDown(...)
  end

  function ao.turtle()
    return scopedTurtle
  end

  return ao
end

return runtime
