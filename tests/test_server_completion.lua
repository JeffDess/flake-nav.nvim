local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local server = require("flake-nav.server")

local OPTS = { ignore = { ".git", "result", "result-*" }, hover = { max_lines = 30 } }

local function start(root)
  local dispatchers = {
    notification = function() end,
    server_request = function() end,
    on_exit = function() end,
    on_error = function() end,
  }
  return server.create(OPTS)(dispatchers, { root_dir = root })
end

local function request(rpc, method, params)
  local reply
  rpc.request(method, params, function(err, result)
    reply = { err = err, result = result }
  end)
  vim.wait(1000, function()
    return reply ~= nil
  end)
  return reply.result
end

local function at(root, rel, row, word)
  local line = vim.fn.readfile(vim.fs.joinpath(root, rel))[row + 1]
  return {
    textDocument = { uri = vim.uri_from_fname(vim.fs.joinpath(root, rel)) },
    position = { line = row, character = line:find(word, 1, true) - 1 },
  }
end

local function labels(result)
  return vim.tbl_map(function(item)
    return item.label
  end, result.items)
end

local FLAKE = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/flake")
local INPUTS = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/inputs")

T["completion in a with list"] = function()
  local rpc = start(FLAKE)
  local result =
    request(rpc, "textDocument/completion", at(FLAKE, "modules/hosts/laptop.nix", 6, "base"))
  eq(result.isIncomplete, false)
  eq(labels(result), { "base", "dev-rust" })
end

T["nil outside a known path"] = function()
  local rpc = start(FLAKE)
  eq(
    request(rpc, "textDocument/completion", at(FLAKE, "modules/hosts/laptop.nix", 0, "config")),
    nil
  )
end

T["resolve adds the hover text"] = function()
  local rpc = start(FLAKE)
  local result =
    request(rpc, "textDocument/completion", at(FLAKE, "modules/hosts/laptop.nix", 6, "base"))
  local item = request(rpc, "completionItem/resolve", result.items[1])
  eq(item.label, "base")
  eq(item.documentation.kind, "markdown")
  eq(item.documentation.value:find("`nixos.base`", 1, true) ~= nil, true)

  rpc = start(INPUTS)
  result = request(rpc, "textDocument/completion", at(INPUTS, "modules/default.nix", 2, "hooks"))
  local hooks = vim.tbl_filter(function(i)
    return i.label == "hooks"
  end, result.items)[1]
  item = request(rpc, "completionItem/resolve", hooks)
  eq(item.documentation.value:find("(flake input)", 1, true) ~= nil, true)
end

return T
