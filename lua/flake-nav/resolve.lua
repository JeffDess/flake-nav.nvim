local M = {}

local function contains(range, row, col)
  if not range then
    return false
  end
  if row < range[1] or row > range[3] then
    return false
  end
  if row == range[1] and col < range[2] then
    return false
  end
  if row == range[3] and col >= range[4] then
    return false
  end
  return true
end

M.contains = contains

function M.at(parsed, row, col)
  for _, use in ipairs(parsed.uses) do
    if contains(use.range, row, col) or contains(use.class_range, row, col) then
      return { kind = use.kind, class = use.class, name = use.name, with_range = use.with_range }
    end
  end
  for _, def in ipairs(parsed.defs) do
    if contains(def.range, row, col) then
      return { kind = def.kind, class = def.class, name = def.name }
    end
  end
  local inputs = parsed.inputs or {}
  for _, use in ipairs(inputs.uses or {}) do
    if contains(use.range, row, col) then
      return { kind = "input", name = use.name, binder_range = use.binder_range }
    end
  end
  for _, decl in ipairs(inputs.decls or {}) do
    local ranges = vim.list_extend({}, decl.sites)
    ranges[#ranges + 1] = decl.ref_range
    ranges[#ranges + 1] = decl.attrs_range
    for _, range in ipairs(ranges) do
      if contains(range, row, col) then
        return { kind = "input", name = decl.name }
      end
    end
  end
  local options = parsed.options or {}
  for _, list in ipairs({ options.uses or {}, options.decls or {} }) do
    for _, item in ipairs(list) do
      if contains(item.range, row, col) then
        return { kind = item.kind, class = item.class, path = item.path }
      end
    end
  end
  return nil
end

return M
