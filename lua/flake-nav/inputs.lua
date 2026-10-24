local parse = require("flake-nav.parse")

local I = parse._internal
local first, text_of, attrpath, attr_name, bindings, inherited_names, unwrap, ATTRSETS =
  I.first, I.text_of, I.attrpath, I.attr_name, I.bindings, I.inherited_names, I.unwrap, I.ATTRSETS

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

local function follows_use(value, text, state)
  local target = text:match("^[^/]+")
  local row, col, end_row = value:range()
  if target and row == end_row then
    state.uses[#state.uses + 1] = {
      kind = "input",
      name = target,
      range = { row, col + 1, row, col + 1 + #target },
      flake_only = true,
    }
  end
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
          follows_use(value, text, state)
        elseif #names == 3 and text then
          d.attr_values = d.attr_values or {}
          d.attr_values[names[3]] = text
        elseif #names == 5 and names[3] == "inputs" and names[5] == "follows" and text then
          d.follows[#d.follows + 1] = { input = names[4], target = text }
          follows_use(value, text, state)
        end
        if #names < 5 and ATTRSETS[value:type()] then
          walk(value, names, state)
        end
      end
    end
  end
end

local function declare_all(root, src)
  local state = { src = src, decls = {}, by_name = {}, uses = {} }
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
  return state
end

function M.declarations(root, src)
  return declare_all(root, src).decls
end

local ROOTS = { inputs = true, ["inputs'"] = true, self = true }

local function lookup(scopes, name)
  for i = #scopes, 1, -1 do
    local found = scopes[i][name]
    if found ~= nil then
      return found
    end
  end
  return nil
end

local function strip(node)
  while node and node:type() == "parenthesized_expression" do
    node = first(node, "expression")
  end
  return node
end

local function outputs_function(root, src)
  local top = unwrap(first(root, "expression"))
  if not top or not ATTRSETS[top:type()] then
    return nil
  end
  for _, b in ipairs(bindings(top)) do
    local segs = b:type() == "binding" and attrpath(first(b, "attrpath"), src)
    local value = strip(first(b, "expression"))
    if segs and #segs == 1 and segs[1].name == "outputs" and value then
      return value:type() == "function_expression" and value or nil
    end
  end
  return nil
end

local function add_use(state, name, node, binder, flake_only)
  state.uses[#state.uses + 1] = {
    kind = "input",
    name = name,
    range = { node:range() },
    binder_range = binder,
    flake_only = flake_only or nil,
  }
end

local function function_scope(node, state)
  local scope = {}
  local is_outputs = state.outputs and node:equal(state.outputs)
  for _, universal in ipairs(node:field("universal")) do
    local name = text_of(universal, state.src)
    scope[name] = ROOTS[name] and name or false
  end
  for _, formals in ipairs(node:field("formals")) do
    for _, formal in ipairs(formals:field("formal")) do
      local id = first(formal, "name")
      if id then
        local name = text_of(id, state.src)
        if is_outputs and name ~= "self" then
          local binder = { id:range() }
          scope[name] = { formal = binder }
          add_use(state, name, id, binder, true)
        else
          scope[name] = ROOTS[name] and name or false
        end
      end
    end
  end
  return scope
end

local function shadow_scope(node, state)
  local scope = {}
  for _, b in ipairs(bindings(node)) do
    if b:type() == "binding" then
      local segs = attrpath(first(b, "attrpath"), state.src)
      if segs and segs[1] then
        scope[segs[1].name] = false
      end
    elseif b:type() == "inherit_from" then
      for _, name in ipairs(inherited_names(b, state.src)) do
        scope[name] = false
      end
    end
  end
  return scope
end

local function selection(node, scopes, state)
  local base = first(node, "expression")
  local segs = attrpath(first(node, "attrpath"), state.src)
  if not segs or not base or base:type() ~= "variable_expression" then
    return
  end
  local root = lookup(scopes, text_of(first(base, "name"), state.src))
  if root == "inputs" or root == "inputs'" then
    if segs[1] and segs[1].name ~= "self" then
      add_use(state, segs[1].name, segs[1].node)
    elseif segs[1] and root == "inputs" and segs[2] and segs[2].name == "inputs" and segs[3] then
      add_use(state, segs[3].name, segs[3].node)
    end
  elseif root == "self" and segs[1] and segs[1].name == "inputs" and segs[2] then
    add_use(state, segs[2].name, segs[2].node)
  end
end

local function usages(node, scopes, state)
  local kind = node:type()
  local scope
  if kind == "function_expression" then
    scope = function_scope(node, state)
  elseif kind == "let_expression" or kind == "rec_attrset_expression" then
    scope = shadow_scope(node, state)
  end
  if scope then
    scopes[#scopes + 1] = scope
  end
  if kind == "select_expression" then
    selection(node, scopes, state)
  elseif kind == "variable_expression" then
    local id = first(node, "name")
    local bound = lookup(scopes, text_of(id, state.src))
    if type(bound) == "table" then
      add_use(state, text_of(id, state.src), id, bound.formal, true)
    end
  end
  for child in node:iter_children() do
    if child:named() then
      usages(child, scopes, state)
    end
  end
  if scope then
    table.remove(scopes)
  end
end

function M.collect(root, src)
  local state = declare_all(root, src)
  state.outputs = outputs_function(root, src)
  usages(root, {}, state)
  return { decls = state.decls, uses = state.uses }
end

return M
