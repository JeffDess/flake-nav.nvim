local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local server = require("flake-nav.server")

local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/flake")
local OPTS = { ignore = { ".git", "result", "result-*" }, hover = { max_lines = 30 } }

local function start(opts)
  local dispatchers = {
    notification = function() end,
    server_request = function() end,
    on_exit = function() end,
    on_error = function() end,
  }
  return server.create(opts or OPTS)(dispatchers, { root_dir = fixture })
end

local function request(rpc, method, params)
  local reply
  rpc.request(method, params, function(err, result)
    reply = { err = err, result = result }
  end)
  vim.wait(1000, function()
    return reply ~= nil
  end)
  return reply
end

local function at(rel, line, character)
  return {
    textDocument = { uri = vim.uri_from_fname(vim.fs.joinpath(fixture, rel)) },
    position = { line = line, character = character },
  }
end

T["initialize advertises capabilities"] = function()
  local reply = request(start(), "initialize", {})
  local caps = reply.result.capabilities
  eq(caps.definitionProvider, true)
  eq(caps.referencesProvider, true)
  eq(caps.hoverProvider, true)
  eq(caps.completionProvider, { triggerCharacters = { "." }, resolveProvider = true })
  eq(caps.positionEncoding, "utf-16")
  eq(caps.textDocumentSync, { openClose = true, change = 1 })
end

T["definition from a with block"] = function()
  local reply = request(start(), "textDocument/definition", at("modules/hosts/laptop.nix", 6, 59))
  eq(reply.err, nil)
  eq(#reply.result, 1)
  eq(vim.uri_to_fname(reply.result[1].uri), vim.fs.joinpath(fixture, "modules/features/locale.nix"))
  eq(
    reply.result[1].range,
    { start = { line = 5, character = 22 }, ["end"] = { line = 5, character = 28 } }
  )
end

T["definition elsewhere is nil"] = function()
  eq(request(start(), "textDocument/definition", at("modules/hosts/laptop.nix", 0, 2)).result, nil)
end

T["references with and without declaration"] = function()
  local rpc = start()
  local params = at("modules/hosts/laptop.nix", 6, 59)
  params.context = { includeDeclaration = false }
  eq(#request(rpc, "textDocument/references", params).result, 2)
  params.context = { includeDeclaration = true }
  eq(#request(rpc, "textDocument/references", params).result, 3)
end

T["hover shows the definition"] = function()
  local reply = request(start(), "textDocument/hover", at("modules/hosts/laptop.nix", 6, 59))
  local value = reply.result.contents.value
  eq(reply.result.contents.kind, "markdown")
  eq(value:find("`nixos.locale`", 1, true) ~= nil, true)
  eq(value:find("`modules/features/locale.nix:6`", 1, true) ~= nil, true)
  eq(value:find("```nix\nflake.modules.nixos.locale = {", 1, true) ~= nil, true)
end

T["hover truncates long definitions"] = function()
  local reply = request(
    start({ ignore = OPTS.ignore, hover = { max_lines = 1 } }),
    "textDocument/hover",
    at("modules/hosts/laptop.nix", 6, 59)
  )
  eq(reply.result.contents.value:find("= {\n…\n```", 1, true) ~= nil, true)
end

T["didOpen and didChange take precedence over disk"] = function()
  local rpc = start()
  local uri = vim.uri_from_fname(vim.fs.joinpath(fixture, "modules/features/locale.nix"))
  rpc.notify("textDocument/didOpen", {
    textDocument = {
      uri = uri,
      languageId = "nix",
      version = 1,
      text = "\n\n{ flake.modules.nixos.locale = { }; }",
    },
  })
  local reply = request(rpc, "textDocument/definition", at("modules/hosts/laptop.nix", 6, 59))
  eq(reply.result[1].range.start, { line = 2, character = 22 })
  rpc.notify("textDocument/didChange", {
    textDocument = { uri = uri, version = 2 },
    contentChanges = { { text = "{ flake.modules.nixos.locale = { }; }" } },
  })
  reply = request(rpc, "textDocument/definition", at("modules/hosts/laptop.nix", 6, 59))
  eq(reply.result[1].range.start, { line = 0, character = 22 })
  rpc.notify("textDocument/didClose", { textDocument = { uri = uri } })
  reply = request(rpc, "textDocument/definition", at("modules/hosts/laptop.nix", 6, 59))
  eq(reply.result[1].range.start, { line = 5, character = 22 })
end

T["unknown method"] = function()
  local reply = request(start(), "textDocument/rename", {})
  eq(reply.err.code, vim.lsp.protocol.ErrorCodes.MethodNotFound)
end

T["registers its index"] = function()
  start()
  eq(server.indexes[fixture] ~= nil, true)
end

return T
