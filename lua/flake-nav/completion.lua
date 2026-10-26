local parse = require("flake-nav.parse")
local position = require("flake-nav.position")

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local PLACEHOLDER = "__flake_nav_cursor__"
-- NOTE: Appended in turn so that an unclosed list or a missing `;` still parses around the cursor.
local SUFFIXES = { "", ";", " ];" }
local WORD = "[%w_'%-]*"

local function at(item, row, col)
  return item.name == PLACEHOLDER and item.range[1] == row and item.range[2] == col
end

local function find(parsed, row, col)
  for _, use in ipairs(parsed.uses) do
    if at(use, row, col) and use.binder_range then
      local present = {}
      for _, other in ipairs(parsed.uses) do
        if other.binder_range and vim.deep_equal(other.binder_range, use.binder_range) then
          present[other.name] = true
        end
      end
      return { kind = "module", class = use.class, present = present }
    elseif at(use, row, col) then
      return { kind = "module", class = use.class }
    end
  end
  for _, use in ipairs(parsed.inputs.uses) do
    if at(use, row, col) then
      return { kind = "input" }
    end
  end
  for _, selection in ipairs(parsed.classes) do
    if
      selection.class == PLACEHOLDER
      and selection.range[1] == row
      and selection.range[2] == col
    then
      return { kind = "class" }
    end
  end
  return nil
end

local function in_with_list(lines, row, start)
  local text = table.concat(vim.list_slice(lines, 1, row), "\n")
    .. "\n"
    .. lines[row + 1]:sub(1, start)
  local keywords = {}
  for at_with in text:gmatch("()%f[%w_]with%f[^%w_]") do
    keywords[#keywords + 1] = at_with
  end
  for i = #keywords, 1, -1 do
    local tail = text:sub(keywords[i])
    local _, opened = tail:gsub("%[", "")
    local _, closed = tail:gsub("%]", "")
    if opened > closed then
      return true
    end
  end
  return false
end

local function context(lines, row, col)
  local line = lines[row + 1] or ""
  local before, after = line:sub(1, col), line:sub(col + 1)
  local start = #before - #before:match(WORD .. "$")
  local rest = after:sub(#after:match("^" .. WORD) + 1)
  local dotted = line:sub(start, start) == "."
  local follows = line:sub(1, start):match('follows%s*=%s*"$') ~= nil
  if not (dotted or follows or in_with_list(lines, row, start)) then
    return nil
  end
  for _, suffix in ipairs(SUFFIXES) do
    local patched = vim.list_extend({}, lines)
    patched[row + 1] = line:sub(1, start) .. PLACEHOLDER .. suffix .. rest
    local found = find(parse.parse_uses(table.concat(patched, "\n")), row, start)
    if found then
      return found, start
    end
  end
  return nil
end

local function identifier(name)
  return name:match("^[%a_][%w_'%-]*$") ~= nil
end

local function site(index, entry)
  local rel = vim.fs.relpath(index.root, entry.path) or entry.path
  return ("%s:%d"):format(rel, entry.item.range[1] + 1)
end

local function module_defs(index)
  local out = {}
  for path, entry in pairs(index.files) do
    if index.scope[path] then
      for _, def in ipairs(entry.parsed.defs) do
        out[#out + 1] = { path = path, item = def }
      end
    end
  end
  vim.list_extend(out, index.external)
  return out
end

local function candidates(index, found)
  local out, seen = {}, {}
  local function add(name, kind, detail)
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = { name = name, kind = kind, detail = detail }
    end
  end
  if found.kind == "input" then
    for name in pairs(index:known_inputs() or {}) do
      local decl = index:input_declaration(name)
      add(name, KIND.Reference, decl and decl.range and ("flake.nix:%d"):format(decl.range[1] + 1))
    end
  elseif found.kind == "class" then
    for _, entry in ipairs(module_defs(index)) do
      add(entry.item.class, KIND.Class)
    end
    for path, entry in pairs(index.files) do
      if index.scope[path] then
        for class in pairs(entry.parsed.computed.classes) do
          add(class, KIND.Class)
        end
        for _, mapped in ipairs(entry.parsed.mapped) do
          add(mapped.class, KIND.Class)
        end
      end
    end
  else
    local defs = module_defs(index)
    table.sort(defs, function(a, b)
      return a.path < b.path or (a.path == b.path and a.item.range[1] < b.item.range[1])
    end)
    for _, entry in ipairs(defs) do
      if entry.item.class == found.class then
        add(entry.item.name, KIND.Module, site(index, entry))
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

function M.items(index, path, pos)
  local lines = index:lines(path)
  local line = lines[pos.line + 1] or ""
  local col = position.to_byte(line, pos.character)
  local found, start = context(lines, pos.line, col)
  if not found or (found.kind == "input" and not index:owns_inputs(path)) then
    return nil
  end
  local range = {
    start = { line = pos.line, character = position.to_lsp(line, start) },
    ["end"] = { line = pos.line, character = pos.character },
  }
  local items = {}
  for _, candidate in ipairs(candidates(index, found)) do
    local plain = identifier(candidate.name)
    local listed = found.present and (found.present[candidate.name] or not plain)
    if not listed then
      items[#items + 1] = {
        label = candidate.name,
        kind = candidate.kind,
        detail = candidate.detail,
        filterText = candidate.name,
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        textEdit = {
          range = range,
          newText = plain and candidate.name or ('"%s"'):format(candidate.name),
        },
        data = { kind = found.kind, class = found.class, name = candidate.name },
      }
    end
  end
  return items
end

return M
