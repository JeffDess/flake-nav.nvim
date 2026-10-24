local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local server = require("flake-nav.server")

local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/inputs")
local OPTS = { ignore = { ".git", "result", "result-*" }, hover = { max_lines = 30 } }

local function request(method, params)
  local dispatchers = {
    notification = function() end,
    server_request = function() end,
    on_exit = function() end,
    on_error = function() end,
  }
  local reply
  server
    .create(OPTS)(dispatchers, { root_dir = fixture })
    .request(method, params, function(err, result)
      reply = { err = err, result = result }
    end)
  vim.wait(1000, function()
    return reply ~= nil
  end)
  return reply
end

local function at(rel, row, word, nth)
  local line = vim.fn.readfile(vim.fs.joinpath(fixture, rel))[row + 1]
  local col = 0
  for _ = 1, nth or 1 do
    col = line:find(word, col + 1, true)
  end
  return {
    textDocument = { uri = vim.uri_from_fname(vim.fs.joinpath(fixture, rel)) },
    position = { line = row, character = col - 1 },
    context = { includeDeclaration = true },
  }
end

local function targets(result)
  return vim.tbl_map(function(loc)
    return ("%s:%d"):format(
      vim.fs.relpath(fixture, vim.uri_to_fname(loc.uri)),
      loc.range.start.line
    )
  end, result)
end

T["definition from a module and from an outputs formal"] = function()
  eq(targets(request("textDocument/definition", at("modules/default.nix", 2, "hooks")).result), {
    "flake.nix:3",
  })
  eq(targets(request("textDocument/definition", at("flake.nix", 18, "nixpkgs")).result), {
    "flake.nix:2",
  })
end

T["nil for an undeclared input"] = function()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  vim.fn.writefile({ "{ inputs, ... }: { x = inputs.unknown; }" }, root .. "/default.nix")
  vim.fn.writefile({ "{ outputs = _: { }; }" }, root .. "/flake.nix")
  local dispatchers = {
    notification = function() end,
    server_request = function() end,
    on_exit = function() end,
    on_error = function() end,
  }
  local rpc = server.create(OPTS)(dispatchers, { root_dir = root })
  local params = {
    textDocument = { uri = vim.uri_from_fname(root .. "/default.nix") },
    position = { line = 0, character = 30 },
    context = { includeDeclaration = true },
  }
  for _, method in ipairs({ "textDocument/definition", "textDocument/references" }) do
    local reply
    rpc.request(method, params, function(_, result)
      reply = { result = result }
    end)
    vim.wait(1000, function()
      return reply ~= nil
    end)
    eq({ method, reply.result }, { method, nil })
  end
  vim.fn.delete(root, "rf")
end

T["references"] = function()
  eq(#request("textDocument/references", at("modules/default.nix", 2, "hooks")).result, 4)
end

T["hover shows the reference, its web page, the lock and follows"] = function()
  local value =
    request("textDocument/hover", at("modules/default.nix", 2, "hooks")).result.contents.value
  for _, part in ipairs({
    "`inputs.hooks` (flake input)",
    "`flake.nix:4`",
    "`github:cachix/git-hooks.nix`",
    "<https://github.com/cachix/git-hooks.nix>",
    "locked `0123456` (2025-10-09)",
    '`inputs.nixpkgs.follows = "nixpkgs"`',
  }) do
    eq({ part, value:find(part, 1, true) ~= nil }, { part, true })
  end
end

T["hover of a follows-only input"] = function()
  local value = request("textDocument/hover", at("flake.nix", 7, "pkgs")).result.contents.value
  eq(value:find('`follows = "hooks/nixpkgs"`', 1, true) ~= nil, true)
  eq(value:find("locked `fedcba9` (2025-10-20)", 1, true) ~= nil, true)
end

T["definition on a local input opens it"] = function()
  local local_flake = request("textDocument/definition", at("flake.nix", 8, "local")).result
  eq(targets(local_flake), { "vendor/local/flake.nix:0" })
  local notes = request("textDocument/definition", at("flake.nix", 10, "path:")).result
  eq(targets(notes), { "data/notes.txt:0" })
end

T["definition on a local input honours dir"] = function()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/mono/sub", "p")
  local flake = {
    "{",
    '  inputs.str.url = "path:./mono?dir=sub";',
    '  inputs.set = { type = "path"; path = "./mono"; dir = "sub"; };',
    "  outputs = _: { };",
    "}",
  }
  vim.fn.writefile(flake, root .. "/flake.nix")
  vim.fn.writefile({ "{ outputs = _: { }; }" }, root .. "/mono/flake.nix")
  vim.fn.writefile({ "{ outputs = _: { }; }" }, root .. "/mono/sub/flake.nix")
  local dispatchers = {
    notification = function() end,
    server_request = function() end,
    on_exit = function() end,
    on_error = function() end,
  }
  local rpc = server.create(OPTS)(dispatchers, { root_dir = root })
  for _, case in ipairs({ { 1, "path:" }, { 2, "type" } }) do
    local row, word = case[1], case[2]
    local reply
    rpc.request("textDocument/definition", {
      textDocument = { uri = vim.uri_from_fname(root .. "/flake.nix") },
      position = { line = row, character = flake[row + 1]:find(word, 1, true) - 1 },
    }, function(_, result)
      reply = { result = result }
    end)
    vim.wait(1000, function()
      return reply ~= nil
    end)
    eq({ word, vim.uri_to_fname(reply.result[1].uri) }, { word, root .. "/mono/sub/flake.nix" })
  end
  vim.fn.delete(root, "rf")
end

return T
