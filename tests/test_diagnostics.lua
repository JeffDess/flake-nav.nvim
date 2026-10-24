local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local Index = require("flake-nav.index")
local diagnostics = require("flake-nav.diagnostics")

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

local function span(lines, row, word, nth)
  local col = 0
  for _ = 1, nth or 1 do
    col = lines[row + 1]:find(word, col + 1, true)
  end
  return {
    start = { line = row, character = col - 1 },
    ["end"] = { line = row, character = col - 1 + #word },
  }
end

local function summary(list)
  return vim.tbl_map(function(d)
    return { range = d.range, severity = d.severity, message = d.message, tags = d.tags }
  end, list)
end

local HOST = {
  "{ config, ... }:",
  "{",
  "  flake.modules.nixos.host.imports = with config.flake.modules.nixos; [ base missing ];",
  "}",
}

T["unknown modules"] = function()
  local idx, root = project({
    ["flake.nix"] = { "{ outputs = _: { }; }" },
    ["base.nix"] = { "{ flake.modules.nixos.base = { }; }" },
    ["host.nix"] = HOST,
  })
  local found = diagnostics.compute(idx, vim.fs.joinpath(root, "host.nix"), { unknown = true })
  eq(summary(found), {
    {
      range = span(HOST, 2, "missing"),
      severity = vim.lsp.protocol.DiagnosticSeverity.Warning,
      message = "Unknown module nixos.missing",
    },
  })
  eq(found[1].source, "flake-nav")
  vim.fn.delete(root, "rf")
end

T["modules mapped from a flake option are known"] = function()
  local host = {
    "{ config, ... }:",
    "let",
    "  fm = config.flake.modules;",
    "in",
    "{",
    "  configurations.nixos.box.module.imports = with fm.nixos; [ alice carol ];",
    "}",
  }
  local idx, root = project({
    ["flake.nix"] = { "{ outputs = _: { }; }" },
    ["users.nix"] = {
      "{ lib, config, ... }: { config.flake.modules.nixos = lib.mapAttrs mk config.users; }",
    },
    ["alice.nix"] = { "{ users.alice.groups = [ ]; }" },
    ["host.nix"] = host,
  })
  local found = diagnostics.compute(idx, vim.fs.joinpath(root, "host.nix"), { unknown = true })
  eq(summary(found), {
    {
      range = span(host, 5, "carol"),
      severity = vim.lsp.protocol.DiagnosticSeverity.Warning,
      message = "Unknown module nixos.carol",
    },
  })
  vim.fn.delete(root, "rf")
end

T["unknown modules of a computed class are reported as information"] = function()
  local idx, root = project({
    ["flake.nix"] = { "{ outputs = _: { }; }" },
    ["users.nix"] = {
      "{ lib, ... }: { flake.modules.nixos = lib.genAttrs names f; }",
    },
    ["base.nix"] = { "{ flake.modules.nixos.base = { }; }" },
    ["host.nix"] = HOST,
  })
  local found = diagnostics.compute(idx, vim.fs.joinpath(root, "host.nix"), { unknown = true })
  eq(summary(found), {
    {
      range = span(HOST, 2, "missing"),
      severity = vim.lsp.protocol.DiagnosticSeverity.Information,
      message = "Unknown module nixos.missing (its class is partly computed)",
    },
  })
  vim.fn.delete(root, "rf")
end

T["nothing outside the index scope"] = function()
  local idx, root = project({
    ["flake.nix"] = { "{ outputs = _: { }; }" },
  })
  local hidden = vim.fs.joinpath(root, "_host.nix")
  idx:set_document(hidden, table.concat(HOST, "\n"))
  eq(diagnostics.compute(idx, hidden, { unknown = true, unused = true }), {})
  vim.fn.delete(root, "rf")
end

return T
