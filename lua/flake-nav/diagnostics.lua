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

local function consumed(index)
  local out = { all = false, classes = {} }
  for path, entry in pairs(index.files) do
    if index.scope[path] then
      out.all = out.all or entry.parsed.consumed.all
      for class in pairs(entry.parsed.consumed.classes) do
        out.classes[class] = true
      end
    end
  end
  return out
end

local function computed(index)
  local out = { all = false, classes = {} }
  for path, entry in pairs(index.files) do
    if index.scope[path] then
      out.all = out.all or entry.parsed.computed.all
      for class in pairs(entry.parsed.computed.classes) do
        out.classes[class] = true
      end
    end
  end
  return out
end

function M.compute(index, path, cfg)
  local parsed = index.scope[path] and index:parsed(path)
  if not parsed then
    return {}
  end
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
    local defs, open = keys(index, "defs"), computed(index)
    for _, use in ipairs(parsed.uses) do
      local name = key(use.class, use.name)
      if not defs[name] and (open.all or open.classes[use.class]) then
        local message = ("Unknown module %s (its class is partly computed)"):format(name)
        add(use.range, SEVERITY.Information, message)
      elseif not defs[name] then
        add(use.range, SEVERITY.Warning, ("Unknown module %s"):format(name))
      end
    end
  end
  if cfg.unused then
    local uses, read = keys(index, "uses"), consumed(index)
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
