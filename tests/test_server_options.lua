local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local server = require("flake-nav.server")

local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests/fixtures/options")
local OPTS = { ignore = { ".git", "result", "result-*" }, hover = { max_lines = 30 } }

local function start()
  local dispatchers = {
    notification = function() end,
    server_request = function() end,
    on_exit = function() end,
    on_error = function() end,
  }
  return server.create(OPTS)(dispatchers, { root_dir = fixture })
end

local function request(method, params)
  local reply
  start().request(method, params, function(err, result)
    reply = { err = err, result = result }
  end)
  vim.wait(1000, function()
    return reply ~= nil
  end)
  return reply
end

local function column(rel, row, word)
  local line = vim.fn.readfile(vim.fs.joinpath(fixture, rel))[row + 1]
  return line:find(word, 1, true) - 1
end

local function at(rel, row, word)
  return {
    textDocument = { uri = vim.uri_from_fname(vim.fs.joinpath(fixture, rel)) },
    position = { line = row, character = column(rel, row, word) },
    context = { includeDeclaration = false },
  }
end

local AUDIO = "modules/features/audio.nix"
local HOST = "modules/hosts/desktop.nix"

local function starts(result)
  local out = {}
  for _, loc in ipairs(result) do
    out[#out + 1] = ("%s:%d:%d"):format(
      vim.fs.relpath(fixture, vim.uri_to_fname(loc.uri)),
      loc.range.start.line,
      loc.range.start.character
    )
  end
  return out
end

T["definition of an intermediate node"] = function()
  local reply = request("textDocument/definition", at(HOST, 11, "audio"))
  eq(starts(reply.result), { ("%s:7:%d"):format(AUDIO, column(AUDIO, 7, "audio")) })
end

T["definition of a leaf"] = function()
  local reply = request("textDocument/definition", at(HOST, 11, "enable"))
  eq(starts(reply.result), { ("%s:8:%d"):format(AUDIO, column(AUDIO, 8, "enable")) })
end

T["references with and without the declaration"] = function()
  local params = at(HOST, 11, "enable")
  eq(#request("textDocument/references", params).result, 2)
  params.context.includeDeclaration = true
  eq(#request("textDocument/references", params).result, 3)
end

T["nil on an undeclared option path"] = function()
  eq(request("textDocument/definition", at(AUDIO, 17, "services")).result, nil)
  eq(request("textDocument/references", at(AUDIO, 17, "services")).result, nil)
  eq(request("textDocument/hover", at(AUDIO, 17, "services")).result, nil)
end

T["hover shows the declaration"] = function()
  local value = request("textDocument/hover", at(HOST, 12, "backend")).result.contents.value
  eq(value:find("`modules.audio.backend` (nixos option)", 1, true) ~= nil, true)
  eq(value:find("`modules/features/audio.nix:10`", 1, true) ~= nil, true)
  eq(value:find("```nix\nbackend = lib.mkOption {", 1, true) ~= nil, true)
  eq(value:find('description = "Sound server.";', 1, true) ~= nil, true)
end

return T
