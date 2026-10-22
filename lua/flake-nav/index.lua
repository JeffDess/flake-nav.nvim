local parse = require("flake-nav.parse")

local Index = {}
Index.__index = Index

local function compile(patterns)
  local matchers = {}
  for _, pattern in ipairs(patterns or {}) do
    matchers[#matchers + 1] = vim.glob.to_lpeg(pattern)
  end
  return matchers
end

local function ignored(matchers, name)
  for _, matcher in ipairs(matchers) do
    if matcher:match(name) then
      return true
    end
  end
  return false
end

local function read(path)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  return text
end

local function mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and (stat.mtime.sec * 1000000000 + stat.mtime.nsec) or nil
end

local function by_location(a, b)
  if a.path ~= b.path then
    return a.path < b.path
  end
  if a.item.range[1] ~= b.item.range[1] then
    return a.item.range[1] < b.item.range[1]
  end
  return a.item.range[2] < b.item.range[2]
end

function Index.new(root, opts)
  opts = opts or {}
  return setmetatable({
    root = root,
    ignore = compile(opts.ignore),
    underscore = opts.ignore_underscore ~= false,
    files = {},
    docs = {},
    skipped = {},
    scope = {},
    origin = "none",
    included = { "." },
  }, Index)
end

function Index:hidden(name)
  return ignored(self.ignore, name) or (self.underscore and name:sub(1, 1) == "_")
end

function Index:entries()
  local flake = vim.fs.joinpath(self.root, "flake.nix")
  local tree = parse.import_tree(self.docs[flake] or read(flake) or "")
  self.origin = tree.status
  self.included = tree.status == "detected" and tree.paths or { "." }
  local out = {}
  for _, rel in ipairs(self.included) do
    out[#out + 1] = rel == "." and self.root or vim.fs.joinpath(self.root, rel)
  end
  return out
end

function Index:scan()
  local found, seen = {}, {}
  local function add(path)
    if not seen[path] then
      seen[path] = true
      found[#found + 1] = path
    end
  end
  local flake = vim.fs.joinpath(self.root, "flake.nix")
  if vim.uv.fs_stat(flake) then
    add(flake)
  end
  local skip = function(dir)
    return not self:hidden(vim.fs.basename(dir))
  end
  for _, entry in ipairs(self:entries()) do
    local stat = vim.uv.fs_stat(entry)
    if stat and stat.type == "directory" then
      for rel, kind in vim.fs.dir(entry, { depth = math.huge, skip = skip }) do
        if kind == "file" and rel:sub(-4) == ".nix" and not self:hidden(vim.fs.basename(rel)) then
          add(vim.fs.joinpath(entry, rel))
        end
      end
    elseif stat and entry:sub(-4) == ".nix" then
      add(entry)
    end
  end
  return found
end

function Index:refresh()
  local seen = {}
  for _, path in ipairs(self:scan()) do
    seen[path] = true
    if not self.docs[path] then
      local stamp = mtime(path)
      local entry = self.files[path]
      if not entry or entry.mtime ~= stamp then
        local text = read(path)
        if text then
          self.files[path] = { mtime = stamp, parsed = parse.parse(text) }
          self.skipped[path] = nil
        else
          self.files[path] = nil
          self.skipped[path] = true
        end
      end
    end
  end
  for path in pairs(self.files) do
    if not seen[path] and not self.docs[path] then
      self.files[path] = nil
    end
  end
  for path in pairs(self.skipped) do
    if not seen[path] then
      self.skipped[path] = nil
    end
  end
  self.scope = seen
end

function Index:reset()
  self.files = {}
  self.skipped = {}
  for path, text in pairs(self.docs) do
    self.files[path] = { parsed = parse.parse(text) }
  end
end

function Index:set_document(path, text)
  self.docs[path] = text
  self.files[path] = { parsed = parse.parse(text) }
end

function Index:clear_document(path)
  self.docs[path] = nil
  self.files[path] = nil
end

function Index:parsed(path)
  local entry = self.files[path]
  return entry and entry.parsed or nil
end

function Index:lines(path)
  local text = self.docs[path] or read(path) or ""
  return vim.split(text, "\n", { plain = true })
end

function Index:definitions(class, name)
  local out = {}
  for path, entry in pairs(self.files) do
    if self.scope[path] then
      for _, def in ipairs(entry.parsed.defs) do
        if def.class == class and def.name == name then
          out[#out + 1] = { path = path, item = def }
        end
      end
    end
  end
  table.sort(out, by_location)
  return out
end

function Index:references(class, name, include_declaration)
  local defs = self:definitions(class, name)
  if #defs == 0 then
    return {}
  end
  local out = {}
  for path, entry in pairs(self.files) do
    if self.scope[path] then
      for _, use in ipairs(entry.parsed.uses) do
        if use.class == class and use.name == name then
          out[#out + 1] = { path = path, item = use }
        end
      end
    end
  end
  if include_declaration then
    vim.list_extend(out, defs)
  end
  table.sort(out, by_location)
  return out
end

function Index:stats()
  local stats = {
    root = self.root,
    files = 0,
    definitions = 0,
    uses = 0,
    skipped = {},
    with_errors = {},
    scope = { origin = self.origin, paths = vim.deepcopy(self.included) },
  }
  for path, entry in pairs(self.files) do
    if self.scope[path] then
      stats.files = stats.files + 1
      stats.definitions = stats.definitions + #entry.parsed.defs
      stats.uses = stats.uses + #entry.parsed.uses
      if entry.parsed.errors > 0 then
        stats.with_errors[#stats.with_errors + 1] = path
      end
    end
  end
  for path in pairs(self.skipped) do
    stats.skipped[#stats.skipped + 1] = path
  end
  table.sort(stats.skipped)
  table.sort(stats.with_errors)
  return stats
end

return Index
