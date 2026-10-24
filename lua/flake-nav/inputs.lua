local parse = require("flake-nav.parse")

local I = parse._internal
local first, attrpath, attr_name, bindings, unwrap, ATTRSETS =
  I.first, I.attrpath, I.attr_name, I.bindings, I.unwrap, I.ATTRSETS

local M = {}

local function static_string(node, src)
  return node and node:type() == "string_expression" and attr_name(node, src) or nil
end

local function declaration(state, name)
  local found = state.by_name[name]
  if not found then
    found = { kind = "input", name = name, sites = {}, follows = {} }
    state.by_name[name] = found
    state.decls[#state.decls + 1] = found
  end
  return found
end

local function walk(owner, path, state)
  local src = state.src
  for _, b in ipairs(bindings(owner)) do
    local segs = b:type() == "binding" and attrpath(first(b, "attrpath"), src)
    local value = first(b, "expression")
    if segs and value then
      local names, name_seg = { unpack(path) }, nil
      for _, seg in ipairs(segs) do
        names[#names + 1] = seg.name
        if #names == 2 then
          name_seg = seg
        end
      end
      if names[1] == "inputs" then
        local d = names[2] and declaration(state, names[2])
        if d and name_seg then
          local range = { name_seg.node:range() }
          d.sites[#d.sites + 1] = range
          d.range = d.range or range
        end
        local text = static_string(value, src)
        if #names == 2 and text then
          d.ref, d.ref_range = text, { value:range() }
        elseif #names == 2 and ATTRSETS[value:type()] then
          d.attrs_range = { value:range() }
        elseif #names == 3 and names[3] == "url" and text then
          d.ref, d.ref_range = text, { value:range() }
          d.attr_values = d.attr_values or {}
          d.attr_values.url = text
        elseif #names == 3 and names[3] == "follows" and text then
          d.follows_target = text
        elseif #names == 3 and text then
          d.attr_values = d.attr_values or {}
          d.attr_values[names[3]] = text
        elseif #names == 5 and names[3] == "inputs" and names[5] == "follows" and text then
          d.follows[#d.follows + 1] = { input = names[4], target = text }
        end
        if #names < 5 and ATTRSETS[value:type()] then
          walk(value, names, state)
        end
      end
    end
  end
end

function M.declarations(root, src)
  local state = { src = src, decls = {}, by_name = {} }
  local top = unwrap(first(root, "expression"))
  if top and ATTRSETS[top:type()] then
    walk(top, {}, state)
  end
  for _, d in ipairs(state.decls) do
    if d.attr_values and d.attr_values.type then
      d.attrs = d.attr_values
    else
      d.attrs_range = nil
    end
    d.attr_values = nil
  end
  return state.decls
end

return M
