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

local function hover_markdown(index, defs, max_lines)
  local blocks = {}
  for _, entry in ipairs(defs) do
    local rel = vim.fs.relpath(index.root, entry.path) or entry.path
    blocks[#blocks + 1] = table.concat({
      ("`%s.%s`"):format(entry.item.class, entry.item.name),
      "",
      ("`%s:%d`"):format(rel, entry.item.range[1] + 1),
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

function M.with_range(uri, pos)
  local path = vim.uri_to_fname(uri)
  local index = index_for(path)
  if not index then
    return nil
  end
  local ref = lookup(index, path, pos)
  if not (ref and ref.with_range) or #index:definitions(ref.class, ref.name) == 0 then
    return nil
  end
  return position.lsp_range(index:lines(path), ref.with_range)
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
        local out = {}
        for _, entry in ipairs(index:definitions(ref.class, ref.name)) do
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
        local out = {}
        for _, entry in ipairs(index:references(ref.class, ref.name, include)) do
          out[#out + 1] = location(index, entry)
        end
        return out
      end,
      ["textDocument/hover"] = function(params)
        local ref = target(params)
        if not ref then
          return nil
        end
        local defs = index:definitions(ref.class, ref.name)
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
