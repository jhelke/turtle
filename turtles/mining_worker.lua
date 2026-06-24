-- Managed mining turtle worker.
-- Usage:
--   mining_worker [protocol] [controller-id]
--
-- Install this next to dockmine on each managed mining turtle. The worker waits
-- for mine-distance jobs, runs dockmine until the requested target progress is
-- reached, and reports status back to the managed-area computer.

local args = { ... }

local DEFAULT_PROTOCOL = "minecraft-cc-t:mining_area"
local DEFAULT_HEARTBEAT_INTERVAL = 5
local PROGRESS_FILE = ".dockmine_progress"

local protocol = args[1] or DEFAULT_PROTOCOL
local controllerId = tonumber(args[2])

local function openRednet()
  local opened = 0

  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      if not rednet.isOpen(side) then
        rednet.open(side)
      end

      opened = opened + 1
    end
  end

  return opened > 0
end

local function readProgress()
  if not fs.exists(PROGRESS_FILE) then
    return 0
  end

  local file = fs.open(PROGRESS_FILE, "r")

  if not file then
    return 0
  end

  local content = file.readAll()
  file.close()

  return tonumber(content) or 0
end

local function fuelLevel()
  local level = turtle.getFuelLevel()

  if level == "unlimited" then
    return "unlimited"
  end

  return level
end

local function makeStatus(job, status, message)
  return {
    type = "turtle-status",
    turtleId = os.getComputerID(),
    label = os.getComputerLabel(),
    jobId = job and job.jobId,
    status = status,
    message = message,
    fuel = fuelLevel(),
    fuelLimit = turtle.getFuelLimit(),
    progress = readProgress(),
  }
end

local function makeDiscovery()
  return {
    type = "mining-worker-hello",
    turtleId = os.getComputerID(),
    rednetId = os.getComputerID(),
    label = os.getComputerLabel(),
    fuel = fuelLevel(),
    fuelLimit = turtle.getFuelLimit(),
    progress = readProgress(),
  }
end

local function sendStatus(targetId, job, status, message)
  rednet.send(targetId, makeStatus(job, status, message), protocol)
end

local function sendError(targetId, job, code, message)
  rednet.send(targetId, {
    type = "error",
    turtleId = os.getComputerID(),
    jobId = job and job.jobId,
    code = code,
    message = message,
    fuel = fuelLevel(),
    progress = readProgress(),
  }, protocol)

  sendStatus(targetId, job, "failed", message)
end

local function resolveDockmine()
  local candidates = {
    "dockmine",
    "dockmine.lua",
  }

  if shell and shell.getRunningProgram then
    local runningProgram = shell.getRunningProgram()
    local runningDir = runningProgram and fs.getDir(runningProgram) or ""

    if runningDir ~= "" then
      candidates[#candidates + 1] = fs.combine(runningDir, "dockmine")
      candidates[#candidates + 1] = fs.combine(runningDir, "dockmine.lua")
    end
  end

  for _, candidate in ipairs(candidates) do
    if shell and shell.resolveProgram then
      local resolved = shell.resolveProgram(candidate)

      if resolved then
        return resolved
      end
    end

    if fs.exists(candidate) and not fs.isDir(candidate) then
      return candidate
    end
  end

  return nil
end

local function runDockmine(program, blocksToMine, fuelMargin)
  local chunk, loadErr = loadfile(program)

  if not chunk then
    return false, "could not load dockmine: " .. tostring(loadErr)
  end

  local ok, result

  if fuelMargin then
    ok, result = pcall(chunk, tostring(blocksToMine), tostring(fuelMargin))
  else
    ok, result = pcall(chunk, tostring(blocksToMine))
  end

  if not ok then
    return false, "dockmine crashed: " .. tostring(result)
  end

  if result == false then
    return false, "dockmine returned failure"
  end

  return true
end

local function isSupportedJob(job)
  if type(job) ~= "table" or job.type ~= "job" then
    return false, "not a job message"
  end

  if job.task ~= "mine-distance" and job.task ~= "mine-lane" then
    return false, "unsupported task: " .. tostring(job.task)
  end

  if job.turtleId and job.turtleId ~= os.getComputerID() then
    return false, "job is for turtle " .. tostring(job.turtleId)
  end

  local params = job.params or {}
  local laneOffset = tonumber(params.laneOffset or 0) or 0

  if laneOffset ~= 0 then
    return false, "this worker only supports dock laneOffset 0"
  end

  return true
end

local function targetDistanceForJob(job)
  local params = job.params or {}
  local targetDistance = tonumber(params.targetDistance or params.laneLength)

  if not targetDistance
    or targetDistance < 1
    or targetDistance ~= math.floor(targetDistance) then
    return nil, "job targetDistance/laneLength must be a positive whole number"
  end

  return targetDistance
end

local function runJob(controller, job)
  local supported, supportMessage = isSupportedJob(job)

  if not supported then
    sendError(controller, job, "unsupported_job", supportMessage)
    return
  end

  local targetDistance, targetMessage = targetDistanceForJob(job)

  if not targetDistance then
    sendError(controller, job, "invalid_target", targetMessage)
    return
  end

  local params = job.params or {}
  local heartbeatInterval = tonumber(params.heartbeatInterval) or DEFAULT_HEARTBEAT_INTERVAL

  if heartbeatInterval < 1 then
    heartbeatInterval = DEFAULT_HEARTBEAT_INTERVAL
  end

  local fuelMargin = tonumber(params.fuelMargin)
  local currentProgress = readProgress()
  local remaining = targetDistance - currentProgress

  sendStatus(controller, job, "running", "accepted target " .. targetDistance)

  if remaining <= 0 then
    sendStatus(controller, job, "complete", "target already reached")
    return
  end

  local dockmineProgram = resolveDockmine()

  if not dockmineProgram then
    sendError(controller, job, "missing_program", "dockmine is not installed")
    return
  end

  local done = false
  local jobOk = false
  local jobMessage = "not started"

  local function runner()
    jobOk, jobMessage = runDockmine(dockmineProgram, remaining, fuelMargin)
    done = true
  end

  local function heartbeat()
    while not done do
      sendStatus(controller, job, "running", "mining to target " .. targetDistance)
      sleep(heartbeatInterval)
    end
  end

  parallel.waitForAny(runner, heartbeat)

  local finalProgress = readProgress()

  if jobOk and finalProgress >= targetDistance then
    sendStatus(controller, job, "complete", "target reached")
  elseif jobOk then
    sendError(
      controller,
      job,
      "target_not_reached",
      "dockmine finished at " .. finalProgress .. "/" .. targetDistance
    )
  else
    sendError(controller, job, "dockmine_failed", jobMessage)
  end
end

local function main()
  if not openRednet() then
    print("No modem side found. Attach a modem to this turtle.")
    return false
  end

  print("mining_worker ready")
  print("ID: " .. os.getComputerID())
  print("Protocol: " .. protocol)

  if controllerId then
    print("Controller: " .. controllerId)
  end

  while true do
    local sender, message, messageProtocol = rednet.receive(protocol)

    if messageProtocol == protocol
      and (not controllerId or sender == controllerId) then
      if type(message) == "table" and message.type == "mining-area-discover" then
        rednet.send(sender, makeDiscovery(), protocol)
      else
        local ok, err = pcall(runJob, sender, message)

        if not ok then
          print("job crashed: " .. tostring(err))
          rednet.send(sender, {
            type = "error",
            turtleId = os.getComputerID(),
            jobId = type(message) == "table" and message.jobId or nil,
            code = "worker_crashed",
            message = tostring(err),
            fuel = fuelLevel(),
            progress = readProgress(),
          }, protocol)
        end
      end
    end
  end
end

local ok, result = pcall(main)

if not ok then
  print("mining_worker crashed: " .. tostring(result))
  return false
end

return result
