local M = {}

local function read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function same_flake(copy, root)
  local lock = read(vim.fs.joinpath(root, "flake.lock"))
  return lock ~= nil and lock == read(vim.fs.joinpath(copy, "flake.lock"))
end

-- NOTE: builtins.getFlake evaluates a copy of the flake in <store>/<hash>-source, so
-- declaration positions point there instead of the working tree.
local function remap_uri(uri, root, store)
  if not uri or uri:sub(1, 7) ~= "file://" then
    return uri
  end
  local path = vim.uri_to_fname(uri)
  local rel = vim.fs.relpath(store, path)
  local name, rest = (rel or ""):match("^([^/]+%-source)/(.+)$")
  if not name or not same_flake(vim.fs.joinpath(store, name), root) then
    return uri
  end
  local target = vim.fs.joinpath(root, rest)
  if not vim.uv.fs_stat(target) then
    return uri
  end
  return vim.uri_from_fname(target)
end

local function remap_one(loc, root, store)
  local out = vim.deepcopy(loc)
  if out.uri then
    out.uri = remap_uri(out.uri, root, store)
  end
  if out.targetUri then
    out.targetUri = remap_uri(out.targetUri, root, store)
  end
  return out
end

function M.locations(result, root, store)
  if result == nil then
    return nil
  end
  if not vim.islist(result) then
    return remap_one(result, root, store)
  end
  return vim.tbl_map(function(loc)
    return remap_one(loc, root, store)
  end, result)
end

return M
