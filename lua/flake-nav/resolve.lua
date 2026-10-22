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

function M.at(parsed, row, col)
  for _, use in ipairs(parsed.uses) do
    if contains(use.range, row, col) or contains(use.class_range, row, col) then
      return { kind = use.kind, class = use.class, name = use.name }
    end
  end
  for _, def in ipairs(parsed.defs) do
    if contains(def.range, row, col) then
      return { kind = def.kind, class = def.class, name = def.name }
    end
  end
  return nil
end

return M
