local Index = require("flake-nav.index")
local resolve = require("flake-nav.resolve")
local position = require("flake-nav.position")

local M = { indexes = {} }

local function location(index, entry)
  return {
    uri = vim.uri_from_fname(entry.path),
    range = position.lsp_range(index:lines(entry.path), entry.item.range),
  }
end

local function dedent(lines)
  local indent
  for _, line in ipairs(lines) do
    if line:find("%S") then
      local width = #line:match("^%s*")
      indent = indent and math.min(indent, width) or width
    end
  end
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = line:sub((indent or 0) + 1)
  end
  return out
end

local function excerpt(index, entry, max_lines)
  local scope = entry.item.scope_range
  local lines = vim.list_slice(index:lines(entry.path), scope[1] + 1, scope[3] + 1)
  local cut = #lines > max_lines
  lines = dedent(vim.list_slice(lines, 1, max_lines))
  if cut then
    lines[#lines + 1] = "…"
  end
  return lines
end

local function title(item)
  if item.kind == "option" then
    return ("`%s` (%s option)"):format(item.path, item.class or "unknown")
  end
  return ("`%s.%s`"):format(item.class, item.name)
end

local function site(index, entry)
  local rel = vim.fs.relpath(index.root, entry.path) or entry.path
  return ("`%s:%d`"):format(rel, entry.item.range[1] + 1)
end

local function hover_markdown(index, defs, max_lines)
  if #defs > 1 and defs[1].item.kind == "option" then
    local lines = { title(defs[1].item), "" }
    for _, entry in ipairs(defs) do
      lines[#lines + 1] = "- " .. site(index, entry)
    end
    return table.concat(lines, "\n")
  end
  local blocks = {}
  for _, entry in ipairs(defs) do
    blocks[#blocks + 1] = table.concat({
      title(entry.item),
      "",
      site(index, entry),
      "",
      "```nix",
      table.concat(excerpt(index, entry, max_lines), "\n"),
      "```",
    }, "\n")
  end
  return table.concat(blocks, "\n\n---\n\n")
end

local function lookup(index, path, pos)
  index:refresh()
  local parsed = index:parsed(path)
  if not parsed then
    return nil
  end
  local line = index:lines(path)[pos.line + 1] or ""
  return resolve.at(parsed, pos.line, position.to_byte(line, pos.character))
end

local function index_for(path)
  local found
  for root, index in pairs(M.indexes) do
    if vim.fs.relpath(root, path) and (not found or #root > #found.root) then
      found = index
    end
  end
  return found
end

function M.root_for(uri)
  local index = index_for(vim.uri_to_fname(uri))
  return index and index.root
end

local function definitions(index, ref)
  if ref.kind == "input" then
    return index:input_definitions(ref.name)
  end
  if ref.kind == "option" then
    return index:option_definitions(ref.class, ref.path)
  end
  return index:definitions(ref.class, ref.name)
end

local function references(index, ref, include)
  if ref.kind == "input" then
    return index:input_references(ref.name, include)
  end
  if ref.kind == "option" then
    return index:option_references(ref.class, ref.path, include)
  end
  return index:references(ref.class, ref.name, include)
end

local function local_input_path(index, decl)
  local path, dir
  if decl.attrs and decl.attrs.type == "path" then
    path, dir = decl.attrs.path, decl.attrs.dir
  elseif decl.ref and decl.ref:match("^path:") then
    path = decl.ref:sub(6)
  elseif decl.ref and decl.ref:match("^git%+file:") then
    path = decl.ref:gsub("^git%+file:", ""):gsub("^//", "")
  end
  if path then
    local query
    path, query = path:match("^([^?]*)%??(.*)$")
    dir = dir or ("&" .. query):match("&dir=([^&]+)")
  end
  if not path or path == "" then
    return nil
  end
  if path:sub(1, 1) ~= "/" then
    path = vim.fs.joinpath(index.root, path)
  end
  if dir then
    path = vim.fs.joinpath(path, dir)
  end
  path = vim.fs.normalize(path)
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "directory" then
    local flake = vim.fs.joinpath(path, "flake.nix")
    return vim.uv.fs_stat(flake) and flake or nil
  end
  return stat and path or nil
end

local function on_declaration(decl, row, col)
  local ranges = vim.list_extend({}, decl.sites)
  ranges[#ranges + 1] = decl.ref_range
  ranges[#ranges + 1] = decl.attrs_range
  for _, range in ipairs(ranges) do
    if resolve.contains(range, row, col) then
      return true
    end
  end
  return false
end

local function input_hover(index, name)
  local decl = index:input_declaration(name)
  if not decl or not decl.range then
    return nil
  end
  local flakeref = require("flake-nav.flakeref")
  local items = {}
  if decl.ref then
    items[#items + 1] = ("`%s`"):format(decl.ref)
  end
  local url = decl.attrs and flakeref.from_attrs(decl.attrs)
    or (decl.ref and flakeref.to_url(decl.ref))
  if url then
    items[#items + 1] = ("<%s>"):format(url)
  end
  if decl.follows_target then
    items[#items + 1] = ('`follows = "%s"`'):format(decl.follows_target)
  end
  local locked = index:locked(name)
  if locked and type(locked.rev) == "string" then
    local item = ("locked `%s`"):format(locked.rev:sub(1, 7))
    if type(locked.lastModified) == "number" then
      item = item .. (" (%s)"):format(os.date("!%Y-%m-%d", locked.lastModified))
    end
    items[#items + 1] = item
  end
  for _, follows in ipairs(decl.follows) do
    items[#items + 1] = ('`inputs.%s.follows = "%s"`'):format(follows.input, follows.target)
  end
  local lines = {
    ("`inputs.%s` (flake input)"):format(name),
    "",
    ("`flake.nix:%d`"):format(decl.range[1] + 1),
    "",
  }
  for _, item in ipairs(items) do
    lines[#lines + 1] = "- " .. item
  end
  return table.concat(lines, "\n")
end

function M.definition_locations(uri, pos)
  local path = vim.uri_to_fname(uri)
  local index = index_for(path)
  local ref = index and lookup(index, path, pos)
  if not ref then
    return {}
  end
  local out = {}
  for _, entry in ipairs(definitions(index, ref)) do
    out[#out + 1] = location(index, entry)
  end
  return out
end

function M.binder_range(uri, pos)
  local path = vim.uri_to_fname(uri)
  local index = index_for(path)
  if not index then
    return nil
  end
  local ref = lookup(index, path, pos)
  if not (ref and ref.binder_range) or #definitions(index, ref) == 0 then
    return nil
  end
  return position.lsp_range(index:lines(path), ref.binder_range)
end

function M.create(opts)
  return function(dispatchers, config)
    local root = config.root_dir
    local index = Index.new(root, opts)
    M.indexes[root] = index
    local closing = false
    local next_id = 0

    local function target(params)
      return lookup(index, vim.uri_to_fname(params.textDocument.uri), params.position)
    end

    local handlers = {
      ["initialize"] = function()
        return {
          capabilities = {
            positionEncoding = "utf-16",
            textDocumentSync = { openClose = true, change = 1 },
            definitionProvider = true,
            referencesProvider = true,
            hoverProvider = true,
          },
          serverInfo = { name = "flake-nav" },
        }
      end,
      ["shutdown"] = function()
        return nil
      end,
      ["textDocument/definition"] = function(params)
        local ref = target(params)
        if not ref then
          return nil
        end
        local path = vim.uri_to_fname(params.textDocument.uri)
        local decl = ref.kind == "input" and index:input_declaration(ref.name)
        if decl and path == index:flake_path() then
          local line = index:lines(path)[params.position.line + 1] or ""
          local col = position.to_byte(line, params.position.character)
          local opened = on_declaration(decl, params.position.line, col)
            and local_input_path(index, decl)
          if opened then
            local start = { line = 0, character = 0 }
            return {
              { uri = vim.uri_from_fname(opened), range = { start = start, ["end"] = start } },
            }
          end
        end
        local defs = definitions(index, ref)
        if ref.kind ~= "module" and #defs == 0 then
          return nil
        end
        local out = {}
        for _, entry in ipairs(defs) do
          out[#out + 1] = location(index, entry)
        end
        return out
      end,
      ["textDocument/references"] = function(params)
        local ref = target(params)
        if not ref then
          return nil
        end
        local include = params.context and params.context.includeDeclaration or false
        local found = references(index, ref, include)
        if ref.kind ~= "module" and #found == 0 then
          return nil
        end
        local out = {}
        for _, entry in ipairs(found) do
          out[#out + 1] = location(index, entry)
        end
        return out
      end,
      ["textDocument/hover"] = function(params)
        local ref = target(params)
        if not ref then
          return nil
        end
        if ref.kind == "input" then
          local value = input_hover(index, ref.name)
          return value and { contents = { kind = "markdown", value = value } } or nil
        end
        local defs = definitions(index, ref)
        if #defs == 0 then
          return nil
        end
        return {
          contents = {
            kind = "markdown",
            value = hover_markdown(index, defs, opts.hover.max_lines),
          },
        }
      end,
    }

    local notifications = {
      ["textDocument/didOpen"] = function(params)
        index:set_document(vim.uri_to_fname(params.textDocument.uri), params.textDocument.text)
      end,
      ["textDocument/didChange"] = function(params)
        local changes = params.contentChanges
        index:set_document(vim.uri_to_fname(params.textDocument.uri), changes[#changes].text)
      end,
      ["textDocument/didClose"] = function(params)
        index:clear_document(vim.uri_to_fname(params.textDocument.uri))
      end,
      ["exit"] = function()
        closing = true
        M.indexes[root] = nil
        dispatchers.on_exit(0, 0)
      end,
    }

    return {
      request = function(method, params, callback, notify_reply_callback)
        next_id = next_id + 1
        local id = next_id
        local handler = handlers[method]
        vim.schedule(function()
          if not handler then
            callback(
              vim.lsp.rpc.rpc_response_error(vim.lsp.protocol.ErrorCodes.MethodNotFound),
              nil
            )
          else
            local ok, result = pcall(handler, params)
            callback(nil, ok and result or nil)
          end
          if notify_reply_callback then
            notify_reply_callback(id)
          end
        end)
        return true, id
      end,
      notify = function(method, params)
        local handler = notifications[method]
        if handler then
          pcall(handler, params)
        end
        return true
      end,
      is_closing = function()
        return closing
      end,
      terminate = function()
        closing = true
        M.indexes[root] = nil
      end,
    }
  end
end

return M
