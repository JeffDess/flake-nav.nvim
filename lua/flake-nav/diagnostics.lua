local position = require("flake-nav.position")

local M = {}

local SEVERITY = vim.lsp.protocol.DiagnosticSeverity
local TAG = vim.lsp.protocol.DiagnosticTag

local function key(class, name)
  return class .. "." .. name
end

local function keys(index, field)
  local out = {}
  for path, entry in pairs(index.files) do
    if index.scope[path] then
      for _, item in ipairs(entry.parsed[field]) do
        out[key(item.class, item.name)] = true
      end
    end
  end
  return out
end

local function flags(index, field)
  local out = { all = false, classes = {} }
  for path, entry in pairs(index.files) do
    if index.scope[path] then
      out.all = out.all or entry.parsed[field].all
      for class in pairs(entry.parsed[field].classes) do
        out.classes[class] = true
      end
    end
  end
  return out
end

local function known_inputs(index)
  local flake = index:parsed(index:flake_path())
  local lock = index:lock()
  local root = lock and type(lock.nodes) == "table" and lock.nodes[lock.root or "root"]
  local locked = type(root) == "table" and type(root.inputs) == "table" and root.inputs or {}
  local decls = flake and flake.inputs.decls or {}
  if #decls == 0 and not lock then
    return nil
  end
  local out = {}
  for _, decl in ipairs(decls) do
    out[decl.name] = true
  end
  for name in pairs(locked) do
    out[name] = true
  end
  for _, use in ipairs(flake and flake.inputs.uses or {}) do
    if use.binder_range then
      out[use.name] = true
    end
  end
  return out
end

function M.context(index)
  return {
    defs = keys(index, "defs"),
    uses = keys(index, "uses"),
    computed = flags(index, "computed"),
    consumed = flags(index, "consumed"),
    inputs = known_inputs(index),
  }
end

function M.compute(index, path, cfg, context)
  local parsed = index.scope[path] and index:parsed(path)
  if not parsed then
    return {}
  end
  context = context or M.context(index)
  local lines = index:lines(path)
  local out = {}
  local function add(range, severity, message, tags)
    out[#out + 1] = {
      range = position.lsp_range(lines, range),
      severity = severity,
      message = message,
      source = "flake-nav",
      tags = tags,
    }
  end
  if cfg.unknown then
    local defs, open = context.defs, context.computed
    for _, use in ipairs(parsed.uses) do
      local name = key(use.class, use.name)
      if not defs[name] and (open.all or open.classes[use.class]) then
        local message = ("Unknown module %s (its class is partly computed)"):format(name)
        add(use.range, SEVERITY.Information, message)
      elseif not defs[name] then
        add(use.range, SEVERITY.Warning, ("Unknown module %s"):format(name))
      end
    end
    local inputs = context.inputs
    local in_flake = path == index:flake_path()
    for _, use in ipairs(inputs and parsed.inputs.uses or {}) do
      local relevant = in_flake or not use.flake_only
      if relevant and not inputs[use.name] then
        add(use.range, SEVERITY.Warning, ("Unknown flake input %s"):format(use.name))
      end
    end
  end
  if cfg.unused then
    local uses, read = context.uses, context.consumed
    for _, def in ipairs(parsed.defs) do
      local name = key(def.class, def.name)
      if not uses[name] and not read.all and not read.classes[def.class] then
        add(def.range, SEVERITY.Hint, ("Module %s is never used"):format(name), { TAG.Unnecessary })
      end
    end
  end
  return out
end

return M
