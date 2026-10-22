local server = require("flake-nav.server")

local M = { enabled = true }

local METHOD = "textDocument/definition"
local wrapped = setmetatable({}, { __mode = "k" })

local function same(a, b)
  return a.line == b.line and a.character == b.character
end

local function on_keyword(loc, uri, range)
  local target = loc.targetSelectionRange or loc.range
  return (loc.targetUri or loc.uri) == uri
    and target ~= nil
    and same(target.start, range.start)
    and same(target["end"], range["end"])
end

function M.locations(result, uri, range)
  if result == nil then
    return nil
  end
  local list = vim.islist(result) and result or { result }
  local kept = vim.tbl_filter(function(loc)
    return not on_keyword(loc, uri, range)
  end, list)
  if #kept == #list then
    return result
  end
  return kept
end

-- NOTE: buf_request_all, fzf-lua, snacks and telescope pass their own callback to
-- client:request, so per-client handlers never see the response.
function M.wrap(client)
  if client.name == "flake-nav" or wrapped[client] then
    return
  end
  wrapped[client] = true
  local request = client.request
  client.request = function(self, method, params, handler, bufnr)
    if
      M.enabled
      and method == METHOD
      and type(handler) == "function"
      and type(params) == "table"
    then
      local uri = params.textDocument and params.textDocument.uri
      local range = uri and params.position and server.with_range(uri, params.position)
      if range then
        local inner = handler
        handler = function(err, result, ...)
          return inner(err, M.locations(result, uri, range), ...)
        end
      end
    end
    return request(self, method, params, handler, bufnr)
  end
end

return M
