local M = {}

local ATTRSETS = { attrset_expression = true, rec_attrset_expression = true }
local PREFIX = { "flake", "modules" }

local function text_of(node, src)
  return vim.treesitter.get_node_text(node, src)
end

local function first(node, field)
  return node and node:field(field)[1]
end

local function attr_name(node, src)
  local kind = node:type()
  if kind == "identifier" then
    return text_of(node, src)
  end
  if kind == "string_expression" then
    local parts = {}
    for child in node:iter_children() do
      if child:named() then
        if child:type() ~= "string_fragment" then
          return nil
        end
        parts[#parts + 1] = text_of(child, src)
      end
    end
    return table.concat(parts)
  end
  return nil
end

local function attrpath(node, src)
  if not node then
    return nil
  end
  local segs = {}
  for _, child in ipairs(node:field("attr")) do
    local name = attr_name(child, src)
    if not name then
      return nil
    end
    segs[#segs + 1] = { name = name, node = child }
  end
  return segs
end

local function binding_set(node)
  for child in node:iter_children() do
    if child:type() == "binding_set" then
      return child
    end
  end
  return nil
end

local function bindings(node)
  local set = binding_set(node)
  return set and set:field("binding") or {}
end

local function unwrap(node)
  while node do
    local kind = node:type()
    if
      kind == "function_expression"
      or kind == "let_expression"
      or kind == "with_expression"
      or kind == "assert_expression"
    then
      node = first(node, "body")
    elseif kind == "parenthesized_expression" then
      node = first(node, "expression")
    else
      return node
    end
  end
  return nil
end

local function collect_defs(set_owner, path, src, out)
  for _, b in ipairs(bindings(set_owner)) do
    if b:type() == "binding" then
      local segs = attrpath(first(b, "attrpath"), src)
      if segs then
        local names = { unpack(path) }
        local descend = true
        for i, seg in ipairs(segs) do
          local depth = #path + i
          names[depth] = seg.name
          if depth <= #PREFIX and seg.name ~= PREFIX[depth] then
            descend = false
            break
          end
          if depth == 4 then
            if i == #segs then
              out[#out + 1] = {
                kind = "module",
                class = names[3],
                name = seg.name,
                range = { seg.node:range() },
                scope_range = { b:range() },
              }
            end
            descend = false
            break
          end
        end
        local value = first(b, "expression")
        if descend and value and ATTRSETS[value:type()] then
          collect_defs(value, names, src, out)
        end
      end
    end
  end
end

local function count_errors(node)
  if node:type() == "ERROR" or node:missing() then
    return 1
  end
  local total = 0
  for child in node:iter_children() do
    total = total + count_errors(child)
  end
  return total
end

local function lookup(scopes, name)
  for i = #scopes, 1, -1 do
    local kind = scopes[i][name]
    if kind then
      return kind
    end
  end
  return nil
end

local function chain(node, src)
  local kind = node:type()
  if kind == "variable_expression" then
    return text_of(first(node, "name"), src), {}
  end
  if kind == "select_expression" then
    local base = first(node, "expression")
    if not base or base:type() ~= "variable_expression" then
      return nil
    end
    local segs = attrpath(first(node, "attrpath"), src)
    if not segs then
      return nil
    end
    return text_of(first(base, "name"), src), segs
  end
  return nil
end

local function after_root(node, scopes, src)
  if not node then
    return nil
  end
  local base, segs = chain(node, src)
  if not base then
    return nil
  end
  if lookup(scopes, base) == "alias" then
    return segs
  end
  local names = { base }
  for _, seg in ipairs(segs) do
    names[#names + 1] = seg.name
  end
  for i = 2, #names do
    if names[i] == "modules" then
      local rooted = names[i - 1] == "flake"
        or (i == 2 and names[1] == "self")
        or (i == 3 and names[1] == "inputs" and names[2] == "self")
      if rooted then
        return vim.list_slice(segs, i)
      end
    end
  end
  return nil
end

local function inherited_names(node, src)
  local names = {}
  for child in node:iter_children() do
    if child:type() == "inherited_attrs" then
      for attr in child:iter_children() do
        if attr:named() then
          local name = attr_name(attr, src)
          if name then
            names[#names + 1] = name
          end
        end
      end
    end
  end
  return names
end

local function binding_scope(owner, src)
  local scope, candidates = {}, {}
  for _, b in ipairs(bindings(owner)) do
    if b:type() == "binding" then
      local segs = attrpath(first(b, "attrpath"), src)
      if segs and segs[1] then
        scope[segs[1].name] = "local"
        if #segs == 1 then
          candidates[#candidates + 1] = { name = segs[1].name, expr = first(b, "expression") }
        end
      end
    else
      for _, name in ipairs(inherited_names(b, src)) do
        scope[name] = "local"
      end
    end
  end
  return scope, candidates
end

local function let_scope(node, scopes, src)
  local scope, candidates = binding_scope(node, src)
  scopes[#scopes + 1] = scope
  local changed = true
  while changed do
    changed = false
    for _, c in ipairs(candidates) do
      if scope[c.name] ~= "alias" then
        local rest = after_root(c.expr, scopes, src)
        if rest and #rest == 0 then
          scope[c.name] = "alias"
          changed = true
        end
      end
    end
  end
  table.remove(scopes)
  return scope
end

local function function_scope(node, src)
  local scope = {}
  for _, universal in ipairs(node:field("universal")) do
    scope[text_of(universal, src)] = "local"
  end
  for _, formals in ipairs(node:field("formals")) do
    for _, formal in ipairs(formals:field("formal")) do
      local name = first(formal, "name")
      if name then
        scope[text_of(name, src)] = "local"
      end
    end
  end
  return scope
end

local function list_identifiers(node, src, acc)
  if not node then
    return acc
  end
  local kind = node:type()
  if kind == "list_expression" then
    for _, element in ipairs(node:field("element")) do
      if element:type() == "variable_expression" then
        acc[#acc + 1] = first(element, "name")
      end
    end
  elseif kind == "binary_expression" then
    local operator = first(node, "operator")
    if operator and text_of(operator, src) == "++" then
      list_identifiers(first(node, "left"), src, acc)
      list_identifiers(first(node, "right"), src, acc)
    end
  elseif kind == "parenthesized_expression" then
    list_identifiers(first(node, "expression"), src, acc)
  end
  return acc
end

local function walk(node, scopes, src, uses)
  local kind = node:type()
  if kind == "ERROR" then
    return
  end
  local pushed = true
  if kind == "let_expression" then
    scopes[#scopes + 1] = let_scope(node, scopes, src)
  elseif kind == "function_expression" then
    scopes[#scopes + 1] = function_scope(node, src)
  elseif kind == "rec_attrset_expression" then
    scopes[#scopes + 1] = (binding_scope(node, src))
  else
    pushed = false
  end

  if kind == "select_expression" then
    local rest = after_root(node, scopes, src)
    if rest and #rest == 2 then
      uses[#uses + 1] = {
        kind = "module",
        class = rest[1].name,
        name = rest[2].name,
        range = { rest[2].node:range() },
        class_range = { rest[1].node:range() },
      }
    end
  elseif kind == "with_expression" then
    local rest = after_root(first(node, "environment"), scopes, src)
    if rest and #rest == 1 then
      local keyword = { node:child(0):range() }
      for _, id in ipairs(list_identifiers(first(node, "body"), src, {})) do
        local name = text_of(id, src)
        if not lookup(scopes, name) then
          uses[#uses + 1] = {
            kind = "module",
            class = rest[1].name,
            name = name,
            range = { id:range() },
            with_range = keyword,
          }
        end
      end
    end
  end

  for child in node:iter_children() do
    if child:named() then
      walk(child, scopes, src, uses)
    end
  end
  if pushed then
    table.remove(scopes)
  end
end

local function path_literal(node, src)
  if not node or node:type() ~= "path_expression" or node:named_child_count() ~= 1 then
    return nil
  end
  local fragment = node:named_child(0)
  if fragment:type() ~= "path_fragment" then
    return nil
  end
  local text = text_of(fragment, src)
  if text:sub(1, 2) ~= "./" then
    return nil
  end
  local rel = text:sub(3):gsub("/+$", "")
  if rel == "" or rel == "." then
    return "."
  end
  return rel
end

local function call_paths(arg, src)
  if not arg then
    return nil
  end
  if arg:type() == "list_expression" then
    local out = {}
    for _, element in ipairs(arg:field("element")) do
      local path = path_literal(element, src)
      if not path then
        return nil
      end
      out[#out + 1] = path
    end
    return out
  end
  local path = path_literal(arg, src)
  return path and { path } or nil
end

local function applied(node)
  local parent = node:parent()
  if parent and parent:type() == "apply_expression" and first(parent, "function"):equal(node) then
    return parent
  end
  return nil
end

local function classify(id)
  local parent = id:parent()
  local kind = parent:type()
  if kind == "formal" or kind == "inherited_attrs" then
    return nil
  end
  if kind == "variable_expression" then
    return applied(parent) or false
  end
  if kind == "attrpath" then
    local owner = parent:parent()
    if owner:type() == "binding" then
      return nil
    end
    local attrs = parent:field("attr")
    if owner:type() == "select_expression" and attrs[#attrs]:equal(id) then
      return applied(owner) or false
    end
  end
  return false
end

local function imports_list(node, src)
  local path = node:type() == "binding" and first(node, "attrpath")
  if not path then
    return nil
  end
  local attrs = path:field("attr")
  local value = first(node, "expression")
  if
    #attrs == 0
    or text_of(attrs[#attrs], src) ~= "imports"
    or not value
    or value:type() ~= "list_expression"
  then
    return nil
  end
  local out = {}
  for _, element in ipairs(value:field("element")) do
    out[#out + 1] = path_literal(element, src)
  end
  return out
end

function M.import_tree(text)
  local result = { status = "none", paths = {} }
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "nix")
  if not ok then
    return result
  end
  local calls, extra, unsupported = {}, {}, false
  local function visit(node)
    if node:type() == "identifier" and text_of(node, text) == "import-tree" then
      local call = classify(node)
      if call == false then
        unsupported = true
      elseif call then
        local paths = call_paths(first(call, "argument"), text)
        if paths then
          vim.list_extend(calls, paths)
        else
          unsupported = true
        end
      end
    end
    vim.list_extend(extra, imports_list(node, text) or {})
    for child in node:iter_children() do
      visit(child)
    end
  end
  visit(parser:parse()[1]:root())
  if unsupported then
    result.status = "unsupported"
  elseif #calls > 0 then
    result.status = "detected"
    local seen = {}
    for _, path in ipairs(vim.list_extend(calls, extra)) do
      if not seen[path] then
        seen[path] = true
        result.paths[#result.paths + 1] = path
      end
    end
  end
  return result
end

local function static_string(node, src)
  return node and node:type() == "string_expression" and attr_name(node, src) or nil
end

local function input_link(value, src)
  if not value then
    return nil
  end
  if value:type() == "string_expression" then
    local ref = static_string(value, src)
    return ref and require("flake-nav.flakeref").to_url(ref)
  end
  if not ATTRSETS[value:type()] then
    return nil
  end
  local attrs = {}
  for _, b in ipairs(bindings(value)) do
    local segs = b:type() == "binding" and attrpath(first(b, "attrpath"), src)
    if segs and #segs == 1 then
      attrs[segs[1].name] = static_string(first(b, "expression"), src)
    end
  end
  if attrs.type then
    return require("flake-nav.flakeref").from_attrs(attrs)
  end
  return nil
end

local function collect_inputs(owner, path, src, out)
  for _, b in ipairs(bindings(owner)) do
    local segs = b:type() == "binding" and attrpath(first(b, "attrpath"), src)
    local names = { unpack(path) }
    for _, seg in ipairs(segs or {}) do
      names[#names + 1] = seg.name
    end
    local value = first(b, "expression")
    if segs and value and names[1] == "inputs" then
      local link = (#names == 2 or (#names == 3 and names[3] == "url")) and input_link(value, src)
      if link then
        out[#out + 1] = { url = link, range = { value:range() } }
      elseif #names < 3 and ATTRSETS[value:type()] then
        collect_inputs(value, names, src, out)
      end
    end
  end
end

function M.inputs(text)
  local out = {}
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "nix")
  if not ok then
    return out
  end
  local top = unwrap(first(parser:parse()[1]:root(), "expression"))
  if top and ATTRSETS[top:type()] then
    collect_inputs(top, {}, text, out)
  end
  return out
end

function M.available()
  local ok, loaded = pcall(vim.treesitter.language.add, "nix")
  return ok and loaded == true
end

function M.parse(text)
  local result = {
    defs = {},
    uses = {},
    errors = 0,
    options = { decls = {}, uses = {} },
    inputs = { decls = {}, uses = {} },
  }
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "nix")
  if not ok then
    return result
  end
  local root = parser:parse()[1]:root()
  local top = unwrap(first(root, "expression"))
  if top and ATTRSETS[top:type()] then
    collect_defs(top, {}, text, result.defs)
  end
  walk(root, {}, text, result.uses)
  result.options = require("flake-nav.options").collect(root, text)
  result.inputs = { decls = require("flake-nav.inputs").declarations(root, text), uses = {} }
  result.errors = count_errors(root)
  return result
end

M._internal = {
  text_of = text_of,
  first = first,
  attrpath = attrpath,
  attr_name = attr_name,
  bindings = bindings,
  unwrap = unwrap,
  ATTRSETS = ATTRSETS,
}

return M
