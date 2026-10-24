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

function Index:parse_file(path, text)
  local parsed = parse.parse(text)
  if vim.fs.basename(path) == "flake.nix" and path ~= self:flake_path() then
    parsed.inputs = { decls = {}, uses = {} }
  end
  return parsed
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
          self.files[path] = { mtime = stamp, parsed = self:parse_file(path, text) }
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
    self.files[path] = { parsed = self:parse_file(path, text) }
  end
end

function Index:set_document(path, text)
  self.docs[path] = text
  self.files[path] = { parsed = self:parse_file(path, text) }
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

local function same_class(a, b)
  return a == nil or b == nil or a == b
end

function Index:option_items(field, class, path)
  local out = {}
  for file, entry in pairs(self.files) do
    if self.scope[file] then
      for _, item in ipairs(entry.parsed.options[field]) do
        if item.path == path and same_class(class, item.class) then
          out[#out + 1] = { path = file, item = item }
        end
      end
    end
  end
  table.sort(out, by_location)
  return out
end

function Index:option_definitions(class, path)
  return self:option_items("decls", class, path)
end

function Index:option_references(class, path, include_declaration)
  local defs = self:option_definitions(class, path)
  if #defs == 0 then
    return {}
  end
  local out = self:option_items("uses", class, path)
  if include_declaration then
    vim.list_extend(out, defs)
    table.sort(out, by_location)
  end
  return out
end

function Index:flake_path()
  return vim.fs.joinpath(self.root, "flake.nix")
end

function Index:input_declaration(name)
  local parsed = self:parsed(self:flake_path())
  for _, decl in ipairs(parsed and parsed.inputs.decls or {}) do
    if decl.name == name then
      return decl
    end
  end
  return nil
end

function Index:input_definitions(name)
  local decl = self:input_declaration(name)
  if not decl or not decl.range then
    return {}
  end
  return { { path = self:flake_path(), item = { kind = "input", name = name, range = decl.range } } }
end

function Index:input_references(name, include_declaration)
  local decl = self:input_declaration(name)
  if not decl then
    return {}
  end
  local flake = self:flake_path()
  local out = {}
  for path, entry in pairs(self.files) do
    if self.scope[path] then
      for _, use in ipairs(entry.parsed.inputs.uses) do
        if use.name == name and (path == flake or not use.flake_only) then
          out[#out + 1] = { path = path, item = use }
        end
      end
    end
  end
  if include_declaration then
    for _, range in ipairs(decl.sites) do
      out[#out + 1] = { path = flake, item = { kind = "input", name = name, range = range } }
    end
  end
  table.sort(out, by_location)
  return out
end

function Index:lock()
  local path = vim.fs.joinpath(self.root, "flake.lock")
  local stamp = mtime(path)
  if not self.lock_cache or self.lock_cache.mtime ~= stamp then
    local text = stamp and read(path)
    local ok, decoded = pcall(vim.json.decode, text or "")
    self.lock_cache = { mtime = stamp, data = ok and type(decoded) == "table" and decoded or nil }
  end
  return self.lock_cache.data
end

-- NOTE: Lock file format: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-flake#lock-files
function Index:locked(name)
  local lock = self:lock()
  local nodes = lock and lock.nodes
  if type(nodes) ~= "table" then
    return nil
  end
  local function follow(path)
    local key = lock.root or "root"
    for _, step in ipairs(path) do
      local node = nodes[key]
      local ref = node and node.inputs and node.inputs[step]
      if type(ref) == "table" then
        key = follow(ref)
      else
        key = ref
      end
      if not key then
        return nil
      end
    end
    return key
  end
  local key = follow({ name })
  local node = key and nodes[key]
  return node and node.locked or nil
end

function Index:stats()
  local stats = {
    root = self.root,
    files = 0,
    definitions = 0,
    uses = 0,
    option_declarations = 0,
    option_uses = 0,
    skipped = {},
    with_errors = {},
    scope = { origin = self.origin, paths = vim.deepcopy(self.included) },
  }
  for path, entry in pairs(self.files) do
    if self.scope[path] then
      stats.files = stats.files + 1
      stats.definitions = stats.definitions + #entry.parsed.defs
      stats.uses = stats.uses + #entry.parsed.uses
      stats.option_declarations = stats.option_declarations + #entry.parsed.options.decls
      stats.option_uses = stats.option_uses + #entry.parsed.options.uses
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
