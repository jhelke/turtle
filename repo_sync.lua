-- Sync this GitHub repository onto a CC:Tweaked turtle or computer.
--
-- Bootstrap from the CC shell with:
--   wget run https://raw.githubusercontent.com/jhelke/turtle/main/repo_sync.lua

local DEFAULT_OWNER = "jhelke"
local DEFAULT_REPO = "turtle"
local DEFAULT_REF = "main"
local MANIFEST_NAME = ".repo_sync_manifest"
local MANIFEST_HEADER = "repo-sync-manifest-v1"

local args = { ... }

local function usage()
  print("Usage:")
  print("  repo_sync.lua [owner] [repo] [ref] [target-dir]")
  print("")
  print("Defaults:")
  print("  owner=" .. DEFAULT_OWNER)
  print("  repo=" .. DEFAULT_REPO)
  print("  ref=" .. DEFAULT_REF)
  print("  target-dir=current directory")
  print("")
  print("Does not download or write .md/.txt docs.")
  print("Removes files owned by the previous sync before downloading.")
end

if args[1] == "-h" or args[1] == "--help" then
  usage()
  return
end

if not http then
  error("HTTP API is disabled. Enable HTTP in the server's CC:Tweaked config.", 0)
end

local owner = args[1] or DEFAULT_OWNER
local repo = args[2] or DEFAULT_REPO
local ref = args[3] or DEFAULT_REF
local targetRoot = args[4] or shell.dir()

local headers = {
  ["Accept"] = "application/vnd.github+json",
  ["User-Agent"] = "minecraft-cc-t-repo-sync",
}

local function encodePathSegment(value)
  return tostring(value):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

local function encodePath(path)
  local parts = {}
  for part in string.gmatch(path, "[^/]+") do
    parts[#parts + 1] = encodePathSegment(part)
  end
  return table.concat(parts, "/")
end

local function readUrl(url, binary)
  local response, err = http.get(url, headers, binary)
  if not response then
    return nil, err or "request failed"
  end

  local body = response.readAll()
  response.close()
  return body
end

local function parseJson(body)
  if textutils.unserializeJSON then
    return textutils.unserializeJSON(body)
  end

  return textutils.unserialiseJSON(body)
end

local function isSafeRepoPath(path)
  if type(path) ~= "string" or path == "" then
    return false
  end

  if string.sub(path, 1, 1) == "/"
    or string.sub(path, -1) == "/"
    or string.find(path, "//", 1, true)
    or string.find(path, "%c")
  then
    return false
  end

  for part in string.gmatch(path, "[^/]+") do
    if part == "." or part == ".." then
      return false
    end
  end

  return true
end

local function ensureParentDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function writeFile(path, body)
  ensureParentDir(path)

  local file, err = fs.open(path, "w")
  if not file then
    return false, err or "could not open file"
  end

  file.write(body)
  file.close()
  return true
end

local function readManifest(path)
  if not fs.exists(path) then
    return {}
  end

  if fs.isDir(path) then
    error("Sync manifest is a directory: " .. path, 0)
  end

  local file, err = fs.open(path, "r")
  if not file then
    error("Could not read sync manifest: " .. tostring(err), 0)
  end

  local body = file.readAll()
  file.close()

  local lines = {}
  for line in string.gmatch(body, "[^\r\n]+") do
    lines[#lines + 1] = line
  end

  if lines[1] ~= MANIFEST_HEADER then
    error("Sync manifest has an unsupported format: " .. path, 0)
  end

  local paths = {}
  for index = 2, #lines do
    if not isSafeRepoPath(lines[index]) then
      error("Sync manifest contains an unsafe path: " .. tostring(lines[index]), 0)
    end
    paths[#paths + 1] = lines[index]
  end

  return paths
end

local function writeManifest(path, paths)
  local lines = { MANIFEST_HEADER }
  for _, repoPath in ipairs(paths) do
    lines[#lines + 1] = repoPath
  end

  return writeFile(path, table.concat(lines, "\n") .. "\n")
end

local function shouldSyncPath(path)
  local lowerPath = string.lower(path)

  return not string.find(lowerPath, "%.md$")
    and not string.find(lowerPath, "%.txt$")
end

local function collectBlobPaths(tree)
  local paths = {}

  for _, item in ipairs(tree or {}) do
    if item.type == "blob" then
      if not isSafeRepoPath(item.path) then
        error("GitHub returned an unsafe path: " .. tostring(item.path), 0)
      end

      if item.path == MANIFEST_NAME then
        error("Repository path conflicts with the sync manifest: " .. item.path, 0)
      end

      paths[#paths + 1] = item.path
    end
  end

  table.sort(paths)
  return paths
end

local function selectSyncPaths(repoPaths)
  local paths = {}

  for _, repoPath in ipairs(repoPaths) do
    if shouldSyncPath(repoPath) then
      paths[#paths + 1] = repoPath
    end
  end

  return paths
end

local function pathDepth(path)
  local _, separators = string.gsub(path, "/", "")
  return separators
end

local function collectCleanupPaths(previousPaths, repoPaths)
  local seen = {}
  local paths = {}

  local function add(repoPath)
    if not seen[repoPath] then
      seen[repoPath] = true
      paths[#paths + 1] = repoPath
    end
  end

  -- The manifest catches files removed or renamed upstream. Current repository
  -- paths also clean files that an older sync downloaded before a filter change.
  for _, repoPath in ipairs(previousPaths) do
    add(repoPath)
  end
  for _, repoPath in ipairs(repoPaths) do
    add(repoPath)
  end

  table.sort(paths, function(left, right)
    local leftDepth = pathDepth(left)
    local rightDepth = pathDepth(right)
    if leftDepth == rightDepth then
      return left < right
    end
    return leftDepth > rightDepth
  end)

  return paths
end

local function deleteExistingFiles(paths, currentRepoPaths, targetRoot)
  local currentFiles = {}
  for _, repoPath in ipairs(currentRepoPaths) do
    currentFiles[repoPath] = true
  end

  local deleted = 0
  for _, repoPath in ipairs(paths) do
    local targetPath = fs.combine(targetRoot, repoPath)
    if fs.exists(targetPath) then
      if fs.isDir(targetPath) then
        if currentFiles[repoPath] then
          local children = fs.list(targetPath)
          if #children > 0 then
            error("Refusing to replace non-empty directory with file: " .. targetPath, 0)
          end
          fs.delete(targetPath)
        end
      else
        fs.delete(targetPath)
        deleted = deleted + 1
      end
    end
  end

  return deleted
end

local apiUrl = "https://api.github.com/repos/"
  .. encodePathSegment(owner)
  .. "/"
  .. encodePathSegment(repo)
  .. "/git/trees/"
  .. encodePathSegment(ref)
  .. "?recursive=1"

print("Fetching repository tree...")
local treeBody, treeErr = readUrl(apiUrl, false)
if not treeBody then
  error("Could not fetch repository tree: " .. tostring(treeErr), 0)
end

local treeData = parseJson(treeBody)
if not treeData or type(treeData.tree) ~= "table" then
  error("Could not parse repository tree response.", 0)
end

if treeData.truncated then
  error("GitHub returned a truncated tree; refusing partial sync.", 0)
end

local repoPaths = collectBlobPaths(treeData.tree)
local paths = selectSyncPaths(repoPaths)
local manifestPath = fs.combine(targetRoot, MANIFEST_NAME)
local previousPaths = readManifest(manifestPath)
local cleanupPaths = collectCleanupPaths(previousPaths, repoPaths)

print("Removing existing synced files...")
local deleted = deleteExistingFiles(cleanupPaths, repoPaths, targetRoot)
print("Removed " .. tostring(deleted) .. " files.")
print("Syncing " .. tostring(#paths) .. " files into " .. fs.combine(targetRoot, "."))

local rawBase = "https://raw.githubusercontent.com/"
  .. encodePathSegment(owner)
  .. "/"
  .. encodePathSegment(repo)
  .. "/"
  .. encodePathSegment(ref)
  .. "/"

local synced = 0
for _, repoPath in ipairs(paths) do
  local rawUrl = rawBase .. encodePath(repoPath)
  local targetPath = fs.combine(targetRoot, repoPath)
  local body, err = readUrl(rawUrl, true)

  if not body then
    error("Could not download " .. repoPath .. ": " .. tostring(err), 0)
  end

  local ok, writeErr = writeFile(targetPath, body)
  if not ok then
    error("Could not write " .. targetPath .. ": " .. tostring(writeErr), 0)
  end

  synced = synced + 1
  print("[" .. synced .. "/" .. #paths .. "] " .. repoPath)
end

local manifestOk, manifestErr = writeManifest(manifestPath, paths)
if not manifestOk then
  error("Could not write sync manifest: " .. tostring(manifestErr), 0)
end

print("Sync complete.")
