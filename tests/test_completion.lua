local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local Index = require("flake-nav.index")
local completion = require("flake-nav.completion")
local position = require("flake-nav.position")
local parse = require("flake-nav.parse")

local function project(files)
  local root = vim.fn.tempname()
  for rel, lines in pairs(files) do
    local path = vim.fs.joinpath(root, rel)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
  end
  local idx = Index.new(root, {})
  idx:refresh()
  return idx, root
end

local MODULES = {
  ["flake.nix"] = { "{ outputs = _: { }; }" },
  ["base.nix"] = { '{ flake.modules.nixos = { base = { }; locale = { }; "my module" = { }; }; }' },
  ["ssl.nix"] = { "{ flake.modules.homeManager.ssl = { }; }" },
  ["users.nix"] = {
    "{ lib, config, ... }: { flake.modules.darwin = lib.mapAttrs f config.users; }",
  },
  ["generic.nix"] = { "{ flake.modules.generic = f x; }" },
}

local HEAD = { "{ config, ... }:", "let", "  fm = config.flake.modules;", "in", "{" }

local function complete(idx, root, body, marker, head)
  local lines = vim.list_extend(vim.deepcopy(head or HEAD), body)
  local row, col
  for i, line in ipairs(lines) do
    local found = line:find(marker, 1, true)
    if found then
      row, col = i - 1, found - 1
      lines[i] = line:sub(1, found - 1) .. line:sub(found + #marker)
      col = position.to_lsp(lines[i], col)
    end
  end
  local path = vim.fs.joinpath(root, "host.nix")
  idx:set_document(path, table.concat(lines, "\n"))
  return completion.items(idx, path, { line = row, character = col }), row, col
end

local function labels(items)
  return items and vim.tbl_map(function(item)
    return item.label
  end, items)
end

T["classes after a modules root"] = function()
  local idx, root = project(MODULES)
  local items = complete(idx, root, { "  x = fm.|", "  y = 1;", "}" }, "|")
  eq(labels(items), { "darwin", "generic", "homeManager", "nixos" })
  eq(items[1].kind, vim.lsp.protocol.CompletionItemKind.Class)
  vim.fn.delete(root, "rf")
end

T["modules of a class, in an unclosed list"] = function()
  local idx, root = project(MODULES)
  local items, row, col = complete(idx, root, { "  imports = [ fm.nixos.|", "  y = 1;", "}" }, "|")
  eq(labels(items), { "base", "locale", "my module" })
  eq(items[1].kind, vim.lsp.protocol.CompletionItemKind.Module)
  eq(items[1].detail, "base.nix:1")
  eq(items[3].textEdit, {
    range = { start = { line = row, character = col }, ["end"] = { line = row, character = col } },
    newText = '"my module"',
  })
  vim.fn.delete(root, "rf")
end

T["a partial name is replaced"] = function()
  local idx, root = project(MODULES)
  local items, row, col = complete(idx, root, { "  x = fm.nixos.lo|cale;", "}" }, "|")
  eq(labels(items), { "base", "locale", "my module" })
  eq(items[2].textEdit, {
    range = {
      start = { line = row, character = col - 2 },
      ["end"] = { line = row, character = col },
    },
    newText = "locale",
  })
  vim.fn.delete(root, "rf")
end

T["with lists leave out present names and names to quote"] = function()
  local idx, root = project(MODULES)
  eq(labels(complete(idx, root, { "  imports = with fm.nixos; [ base |", "}" }, "|")), { "locale" })
  local multi = { "  imports = with fm.nixos; [", "    locale", "    |", "  ];", "}" }
  eq(labels(complete(idx, root, multi, "|")), { "base" })
  vim.fn.delete(root, "rf")
end

local INPUTS = {
  ["flake.nix"] = {
    "{",
    '  inputs.nixpkgs.url = "github:nixos/nixpkgs";',
    '  inputs.hooks.url = "github:cachix/git-hooks.nix";',
    "  outputs = { self, nixpkgs, registry, ... }: { };",
    "}",
  },
  ["flake.lock"] = {
    '{ "nodes": { "root": { "inputs": { "pinned": "pinned" } }, "pinned": { } },',
    '  "root": "root", "version": 7 }',
  },
}

T["flake inputs"] = function()
  local idx, root = project(INPUTS)
  local head = { "{ inputs, ... }:", "{" }
  local items = complete(idx, root, { "  imports = [ inputs.| ];", "}" }, "|", head)
  eq(labels(items), { "hooks", "nixpkgs", "pinned", "registry" })
  eq(items[2].detail, "flake.nix:2")
  eq(items[2].kind, vim.lsp.protocol.CompletionItemKind.Reference)
  local perSystem = { "  perSystem = { inputs', ... }: { x = inputs'.|", "}" }
  eq(#complete(idx, root, perSystem, "|", head), 4)
  local flake = vim.fs.joinpath(root, "flake.nix")
  local text = vim.deepcopy(INPUTS["flake.nix"])
  text[3] =
    '  inputs.hooks = { url = "github:cachix/git-hooks.nix"; inputs.nixpkgs.follows = ""; };'
  idx:set_document(flake, table.concat(text, "\n"))
  local follows =
    completion.items(idx, flake, { line = 2, character = text[3]:find('""', 1, true) })
  eq(#follows, 4)
  vim.fn.delete(root, "rf")
end

T["no input of the root flake in a nested flake"] = function()
  local files = vim.deepcopy(INPUTS)
  files["vendor/flake.nix"] = { "{ outputs = _: { }; }" }
  local idx, root = project(files)
  local path = vim.fs.joinpath(root, "vendor/flake.nix")
  local text = "{ outputs = inputs: { x = inputs.; }; }"
  idx:set_document(path, text)
  local col = text:find("inputs.;", 1, true) + #"inputs."
  eq(completion.items(idx, path, { line = 0, character = col - 1 }), nil)
  vim.fn.delete(root, "rf")
end

T["columns are counted in UTF-16"] = function()
  local idx, root = project(MODULES)
  local items, row, col = complete(idx, root, { '  d = "é"; x = fm.nixos.|', "}" }, "|")
  eq(labels(items), { "base", "locale", "my module" })
  eq(items[1].textEdit.range.start, { line = row, character = col })
  vim.fn.delete(root, "rf")
end

T["an unclosed list in parentheses"] = function()
  local idx, root = project(MODULES)
  local body = { "  imports = [ ./a.nix ] ++ (with fm.nixos; [ |", "}" }
  eq(labels(complete(idx, root, body, "|")), { "base", "locale" })
  vim.fn.delete(root, "rf")
end

T["no known input gives an empty list"] = function()
  local idx, root = project(MODULES)
  local head = { "{ inputs, ... }:", "{" }
  eq(complete(idx, root, { "  x = inputs.|", "}" }, "|", head), {})
  vim.fn.delete(root, "rf")
end

T["text that parses is parsed once"] = function()
  local idx, root = project(MODULES)
  local calls, parse_uses = 0, parse.parse_uses
  parse.parse_uses = function(...)
    calls = calls + 1
    return parse_uses(...)
  end
  local items = complete(idx, root, { "  x = with pkgs; [ git rip| ];", "}" }, "|")
  parse.parse_uses = parse_uses
  eq(items, nil)
  eq(calls, 1)
  vim.fn.delete(root, "rf")
end

T["a class in the middle of a path"] = function()
  local idx, root = project(MODULES)
  local items = complete(idx, root, { "  x = fm.|.locale;", "}" }, "|")
  eq(labels(items), { "darwin", "generic", "homeManager", "nixos" })
  vim.fn.delete(root, "rf")
end

T["nothing outside a module path"] = function()
  local idx, root = project(MODULES)
  eq(complete(idx, root, { "  x = pkgs.|", "}" }, "|"), nil)
  eq(complete(idx, root, { "  x = |", "}" }, "|"), nil)
  vim.fn.delete(root, "rf")
end

T["nothing past the end of the document"] = function()
  local idx, root = project(MODULES)
  local path = vim.fs.joinpath(root, "host.nix")
  idx:set_document(path, "{ x = 1; }")
  eq(completion.items(idx, path, { line = 3, character = 0 }), nil)
  vim.fn.delete(root, "rf")
end

return T
