local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local Index = require("flake-nav.index")
local completion = require("flake-nav.completion")

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

local function complete(idx, root, body, marker)
  local lines = vim.list_extend(vim.deepcopy(HEAD), body)
  local row, col
  for i, line in ipairs(lines) do
    local found = line:find(marker, 1, true)
    if found then
      row, col = i - 1, found - 1
      lines[i] = line:sub(1, found - 1) .. line:sub(found + #marker)
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

T["nothing outside a module path"] = function()
  local idx, root = project(MODULES)
  eq(complete(idx, root, { "  x = pkgs.|", "}" }, "|"), nil)
  eq(complete(idx, root, { "  x = |", "}" }, "|"), nil)
  vim.fn.delete(root, "rf")
end

return T
