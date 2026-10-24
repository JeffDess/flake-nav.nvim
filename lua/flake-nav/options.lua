local parse = require("flake-nav.parse")

local I = parse._internal
local first, text_of, attrpath, attr_name, bindings, unwrap, ATTRSETS =
  I.first, I.text_of, I.attrpath, I.attr_name, I.bindings, I.unwrap, I.ATTRSETS

local M = {}

local LEAVES = { mkOption = true, mkEnableOption = true, mkPackageOption = true }
local SKIP = { imports = true, _file = true, key = true, disabledModules = true }

local function strip(node)
  while node and node:type() == "parenthesized_expression" do
    node = first(node, "expression")
  end
  return node
end

local function call_of(node, src)
  node = strip(node)
  if not node or node:type() ~= "apply_expression" then
    return nil
  end
  local args = {}
  while node and node:type() == "apply_expression" do
    table.insert(args, 1, first(node, "argument"))
    node = strip(first(node, "function"))
  end
  if not node then
    return nil
  end
  if node:type() == "variable_expression" then
    return text_of(first(node, "name"), src), args
  end
  if node:type() == "select_expression" then
    local attrs = first(node, "attrpath"):field("attr")
    return attr_name(attrs[#attrs], src), args
  end
  return nil
end

local function extend(path, name)
  local out = { unpack(path) }
  out[#out + 1] = name
  return out
end

local function each_binding(set, ctx, fn)
  for _, b in ipairs(bindings(set)) do
    if b:type() == "binding" then
      local segs = attrpath(first(b, "attrpath"), ctx.src)
      if segs and segs[1] then
        fn(b, segs, first(b, "expression"))
      end
    end
  end
end

local declare

local function add_decls(segs, value, class, path, binding, ctx)
  local names, last = path, nil
  for _, seg in ipairs(segs) do
    names = extend(names, seg.name)
    last = {
      kind = "option",
      class = class,
      path = table.concat(names, "."),
      range = { seg.node:range() },
      scope_range = { binding:range() },
      leaf = false,
    }
    ctx.decls[#ctx.decls + 1] = last
  end
  if last and declare(value, class, names, ctx) then
    last.leaf = true
  end
end

declare = function(value, class, path, ctx)
  local name = call_of(value, ctx.src)
  if name and LEAVES[name] then
    return true
  end
  value = strip(value)
  if value and ATTRSETS[value:type()] then
    each_binding(value, ctx, function(b, segs, inner)
      add_decls(segs, inner, class, path, b, ctx)
    end)
  end
  return false
end

local function context(names)
  if #names ~= 4 then
    return nil
  end
  if names[1] == "flake" and names[2] == "modules" then
    return names[3]
  end
  if names[1] == "configurations" and names[4] == "module" then
    return names[2]
  end
  return nil
end

local module, assign

local function assign_value(value, class, path, ctx)
  value = strip(value)
  if value and ATTRSETS[value:type()] then
    each_binding(value, ctx, function(_, segs, inner)
      assign(segs, inner, class, path, ctx)
    end)
  end
end

assign = function(segs, value, class, path, ctx)
  local names = path
  for i, seg in ipairs(segs) do
    names = extend(names, seg.name)
    local target = class == "flake" and context(names)
    if target then
      if i == #segs then
        module(value, target, ctx)
      end
      return
    end
  end
  assign_value(value, class, names, ctx)
end

module = function(node, class, ctx)
  local body = unwrap(node)
  if not body or not ATTRSETS[body:type()] then
    return
  end
  each_binding(body, ctx, function(b, segs, value)
    local head = segs[1].name
    local rest = { unpack(segs, 2) }
    if head == "options" then
      if #rest == 0 then
        declare(value, class, {}, ctx)
      else
        add_decls(rest, value, class, {}, b, ctx)
      end
    elseif head == "config" then
      assign(rest, value, class, {}, ctx)
    elseif not SKIP[head] then
      assign(segs, value, class, {}, ctx)
    end
  end)
end

function M.collect(root, src)
  local ctx = { src = src, decls = {}, uses = {} }
  module(first(root, "expression"), "flake", ctx)
  return { decls = ctx.decls, uses = ctx.uses }
end

return M
