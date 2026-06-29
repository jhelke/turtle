-- Managed mining turtle worker.
-- Usage:
--   mining_worker [protocol] [controller-id]
--
-- Install this next to dockmine on each managed mining turtle. The worker waits
-- for bounded lane jobs, persists lane progress, and reports status back to the
-- managed-area computer.

local args = { ... }

local DEFAULT_PROTOCOL = "minecraft-cc-t:mining_area"
local DEFAULT_HEARTBEAT_INTERVAL = 5
local PROGRESS_FILE = ".dockmine_progress"
local LANE_PROGRESS_FILE = ".mining_lane_progress"
local activeLane = nil

local function usage()
  print("Usage: mining_worker [protocol] [controller-id]")
  print("Waits for managed mining jobs over rednet.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return true
end

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

local function writeProgress(progress)
  local file = fs.open(PROGRESS_FILE, "w")

  if not file then
    return false, "could not write " .. PROGRESS_FILE
  end

  file.write(tostring(progress))
  file.close()
  return true
end

local function loadLaneProgress()
  local candidates = {
    LANE_PROGRESS_FILE,
    LANE_PROGRESS_FILE .. ".tmp",
    LANE_PROGRESS_FILE .. ".bak",
  }

  for _, path in ipairs(candidates) do
    if fs.exists(path) then
      local file = fs.open(path, "r")

      if file then
        local content = file.readAll()
        file.close()

        local data = textutils.unserialize(content)

        if type(data) == "table" and type(data.lanes) == "table" then
          return data
        end
      end
    end
  end

  return {
    version = 1,
    lanes = {},
  }
end

local function saveLaneProgress(data)
  local tempPath = LANE_PROGRESS_FILE .. ".tmp"
  local backupPath = LANE_PROGRESS_FILE .. ".bak"
  local file = fs.open(tempPath, "w")

  if not file then
    return false, "could not write " .. tempPath
  end

  file.write(textutils.serialize(data))
  file.close()

  if fs.exists(backupPath) then
    fs.delete(backupPath)
  end

  if fs.exists(LANE_PROGRESS_FILE) then
    fs.move(LANE_PROGRESS_FILE, backupPath)
  end

  local moved, moveMessage = pcall(fs.move, tempPath, LANE_PROGRESS_FILE)

  if not moved then
    if fs.exists(backupPath) and not fs.exists(LANE_PROGRESS_FILE) then
      fs.move(backupPath, LANE_PROGRESS_FILE)
    end

    return false, "could not replace " .. LANE_PROGRESS_FILE
      .. ": " .. tostring(moveMessage)
  end

  if fs.exists(backupPath) then
    fs.delete(backupPath)
  end

  return true
end

local function readSideLaneProgress(laneId)
  if type(laneId) ~= "string" or laneId == "" then
    return 0
  end

  local entry = loadLaneProgress().lanes[laneId]
  return type(entry) == "table" and (tonumber(entry.clearedThrough) or 0) or 0
end

local function writeSideLaneProgress(laneId, laneOffset, targetDistance, clearedThrough)
  local data = loadLaneProgress()
  local previous = data.lanes[laneId]
  local previousProgress = type(previous) == "table"
    and (tonumber(previous.clearedThrough) or 0)
    or 0

  if clearedThrough < previousProgress then
    clearedThrough = previousProgress
  end

  data.lanes[laneId] = {
    laneId = laneId,
    laneOffset = laneOffset,
    targetDistance = targetDistance,
    clearedThrough = clearedThrough,
  }

  return saveLaneProgress(data)
end

local function laneCheckpoint(job)
  local params = job and job.params or {}
  local laneOffset = tonumber(params.laneOffset or 0) or 0
  local laneId = params.laneId
  local clearedThrough

  if activeLane and job and activeLane.jobId == job.jobId then
    if laneOffset == 0 then
      clearedThrough = math.min(
        tonumber(params.targetDistance or params.laneLength) or math.huge,
        readProgress()
      )
      activeLane.clearedThrough = clearedThrough
    else
      clearedThrough = activeLane.clearedThrough
    end
  elseif laneOffset == 0 then
    clearedThrough = readProgress()
  else
    clearedThrough = readSideLaneProgress(laneId)
  end

  return laneId, laneOffset, clearedThrough or 0,
    tonumber(params.targetDistance or params.laneLength)
end

local function fuelLevel()
  local level = turtle.getFuelLevel()

  if level == "unlimited" then
    return "unlimited"
  end

  return level
end

local function makeStatus(job, status, message)
  local laneId, laneOffset, clearedThrough, targetDistance = laneCheckpoint(job)

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
    laneId = laneId,
    laneOffset = laneOffset,
    clearedThrough = clearedThrough,
    targetDistance = targetDistance,
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

local function makeFuelReport(query)
  return {
    type = "fuel-report",
    queryId = query and query.queryId,
    jobId = query and query.jobId,
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
  local laneId, laneOffset, clearedThrough, targetDistance = laneCheckpoint(job)

  rednet.send(targetId, {
    type = "error",
    turtleId = os.getComputerID(),
    jobId = job and job.jobId,
    code = code,
    message = message,
    fuel = fuelLevel(),
    progress = readProgress(),
    laneId = laneId,
    laneOffset = laneOffset,
    clearedThrough = clearedThrough,
    targetDistance = targetDistance,
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

local function resolveWideDockmine()
  local candidates = {
    "wide_dockmine",
    "wide_dockmine.lua",
  }

  if shell and shell.getRunningProgram then
    local runningProgram = shell.getRunningProgram()
    local runningDir = runningProgram and fs.getDir(runningProgram) or ""

    if runningDir ~= "" then
      candidates[#candidates + 1] = fs.combine(runningDir, "wide_dockmine")
      candidates[#candidates + 1] = fs.combine(runningDir, "wide_dockmine.lua")
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

local function runWideDockmine(
  program,
  dockmineProgram,
  targetDistance,
  laneOffset,
  resumeFrom,
  fuelMargin,
  onProgress
)
  local chunk, loadErr = loadfile(program)

  if not chunk then
    return false, "could not load wide_dockmine: " .. tostring(loadErr)
  end

  local ok, result = pcall(chunk, {
    mode = "managed-lane",
    targetDepth = targetDistance,
    laneOffset = laneOffset,
    resumeFrom = resumeFrom,
    fuelMargin = fuelMargin,
    dockminePath = dockmineProgram,
    onProgress = onProgress,
  })

  if not ok then
    return false, "wide_dockmine crashed: " .. tostring(result)
  end

  if result == false or type(result) ~= "table" or result.ok == false then
    local message = type(result) == "table" and result.message
      or "wide_dockmine returned failure"
    return false, message
  end

  if not result.complete then
    return false, result.message or "wide_dockmine did not complete lane"
  end

  return true, result.message
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
  local laneOffset = tonumber(params.laneOffset or 0)

  if not laneOffset or laneOffset ~= math.floor(laneOffset) then
    return false, "laneOffset must be a whole number"
  end

  if job.task == "mine-lane"
    and (type(params.laneId) ~= "string" or params.laneId == "") then
    return false, "mine-lane job requires laneId"
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
  local laneOffset = tonumber(params.laneOffset or 0) or 0
  local laneId = params.laneId
  local managerProgress = tonumber(params.resumeFrom) or 0
  local localProgress = laneOffset == 0
    and readProgress()
    or readSideLaneProgress(laneId)
  local currentProgress = math.min(
    targetDistance,
    math.max(managerProgress, localProgress)
  )
  local remaining = targetDistance - currentProgress

  if laneOffset == 0 and currentProgress > localProgress then
    local saved, saveMessage = writeProgress(currentProgress)

    if not saved then
      sendError(controller, job, "checkpoint_failed", saveMessage)
      return
    end
  elseif laneOffset ~= 0 and currentProgress > localProgress then
    local saved, saveMessage = writeSideLaneProgress(
      laneId,
      laneOffset,
      targetDistance,
      currentProgress
    )

    if not saved then
      sendError(controller, job, "checkpoint_failed", saveMessage)
      return
    end
  end

  activeLane = {
    jobId = job.jobId,
    laneId = laneId,
    laneOffset = laneOffset,
    clearedThrough = currentProgress,
    targetDistance = targetDistance,
  }

  sendStatus(
    controller,
    job,
    "running",
    "accepted lane " .. laneOffset .. " at " .. currentProgress .. "/" .. targetDistance
  )

  if remaining <= 0 then
    sendStatus(controller, job, "complete", "lane target already reached")
    activeLane = nil
    return
  end

  local dockmineProgram = resolveDockmine()

  if not dockmineProgram then
    sendError(controller, job, "missing_program", "dockmine is not installed")
    activeLane = nil
    return
  end

  local wideDockmineProgram = nil

  if laneOffset ~= 0 then
    wideDockmineProgram = resolveWideDockmine()

    if not wideDockmineProgram then
      sendError(controller, job, "missing_program", "wide_dockmine is not installed")
      activeLane = nil
      return
    end
  end

  local done = false
  local jobOk = false
  local jobMessage = "not started"

  local function runner()
    jobOk = true
    jobMessage = "complete"

    if laneOffset == 0 then
      sendStatus(controller, job, "running", "mining center lane")
      jobOk, jobMessage = runDockmine(dockmineProgram, remaining, fuelMargin)
      activeLane.clearedThrough = readProgress()
    else
      local function checkpoint(clearedThrough)
        local saved, saveMessage = writeSideLaneProgress(
          laneId,
          laneOffset,
          targetDistance,
          clearedThrough
        )

        if saved then
          activeLane.clearedThrough = clearedThrough
        end

        return saved, saveMessage
      end

      sendStatus(controller, job, "running", "mining lane " .. laneOffset)
      jobOk, jobMessage = runWideDockmine(
        wideDockmineProgram,
        dockmineProgram,
        targetDistance,
        laneOffset,
        currentProgress,
        fuelMargin,
        checkpoint
      )
    end

    done = true
  end

  local function heartbeat()
    while not done do
      sendStatus(controller, job, "running", "lane " .. laneOffset
        .. " at " .. activeLane.clearedThrough .. "/" .. targetDistance)
      sleep(heartbeatInterval)
    end
  end

  parallel.waitForAny(runner, heartbeat)

  local finalProgress = math.min(
    targetDistance,
    laneOffset == 0 and readProgress() or readSideLaneProgress(laneId)
  )
  activeLane.clearedThrough = finalProgress

  if jobOk and finalProgress >= targetDistance then
    sendStatus(controller, job, "complete", "lane target reached")
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

  activeLane = nil
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
      elseif type(message) == "table" and message.type == "fuel-query" then
        if not message.turtleId or message.turtleId == os.getComputerID() then
          rednet.send(sender, makeFuelReport(message), protocol)
        end
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
