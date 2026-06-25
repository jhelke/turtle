-- Sync this GitHub repository onto a CC:Tweaked turtle or computer.
--
-- Bootstrap from the CC shell with:
--   wget run https://raw.githubusercontent.com/jhelke/turtle/main/repo_sync.lua

local DEFAULT_OWNER = "jhelke"
local DEFAULT_REPO = "turtle"
local DEFAULT_REF = "main"

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

  if string.sub(path, 1, 1) == "/" or string.find(path, "//", 1, true) then
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

local function collectBlobPaths(tree)
  local paths = {}

  for _, item in ipairs(tree or {}) do
    if item.type == "blob" then
      if not isSafeRepoPath(item.path) then
        error("GitHub returned an unsafe path: " .. tostring(item.path), 0)
      end

      paths[#paths + 1] = item.path
    end
  end

  table.sort(paths)
  return paths
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

local paths = collectBlobPaths(treeData.tree)
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

print("Sync complete.")
