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

T["no unused hint for a class read as a whole"] = function()
  local base = { "{ flake.modules.nixos = { a = { }; b = { }; }; flake.modules.darwin.c = { }; }" }
  local host = {
    "{ config, lib, ... }:",
    "let",
    "  fm = config.flake.modules;",
    "in",
    "{",
    "  flake.modules.nixos.host.imports = with fm.nixos; [ a ];",
    "  x = lib.attrValues fm.darwin;",
    "}",
  }
  local idx, root = project({
    ["flake.nix"] = { "{ outputs = _: { }; }" },
    ["base.nix"] = base,
    ["host.nix"] = host,
  })
  local path = vim.fs.joinpath(root, "base.nix")
  local function hinted()
    return vim.tbl_map(function(d)
      return d.message
    end, diagnostics.compute(idx, path, { unused = true }))
  end
  eq(hinted(), { "Module nixos.b is never used" })
  host[7] = "  x = config.flake.modules.nixos.${name};"
  idx:set_document(vim.fs.joinpath(root, "host.nix"), table.concat(host, "\n"))
  eq(hinted(), { "Module darwin.c is never used" })
  vim.fn.delete(root, "rf")
end

T["unused definitions"] = function()
  local base = { "{ flake.modules.nixos = { base = { }; old = { }; }; }" }
  local idx, root = project({
    ["flake.nix"] = { "{ outputs = _: { }; }" },
    ["base.nix"] = base,
    ["host.nix"] = HOST,
  })
  local found = diagnostics.compute(idx, vim.fs.joinpath(root, "base.nix"), { unused = true })
  eq(summary(found), {
    {
      range = span(base, 0, "old"),
      severity = vim.lsp.protocol.DiagnosticSeverity.Hint,
      message = "Module nixos.old is never used",
      tags = { vim.lsp.protocol.DiagnosticTag.Unnecessary },
    },
  })
  vim.fn.delete(root, "rf")
end

local FLAKE = {
  "{",
  '  inputs.nixpkgs.url = "github:nixos/nixpkgs";',
  '  inputs.hooks.inputs.nixpkgs.follows = "missing";',
  "  outputs = { self, nixpkgs, registry, ... }: { };",
  "}",
}

local MODULE = {
  "{ inputs, ... }:",
  "{ imports = [ inputs.hooks.a inputs.registry.b inputs.pinned.c inputs.missing.d ]; }",
}

local LOCK = {
  '{ "nodes": { "root": { "inputs": { "pinned": "pinned" } }, "pinned": { } },',
  '  "root": "root", "version": 7 }',
}

T["unknown inputs"] = function()
  local idx, root = project({
    ["flake.nix"] = FLAKE,
    ["flake.lock"] = LOCK,
    ["module.nix"] = MODULE,
    ["vendor/flake.nix"] = { '{ inputs.x.follows = "missing"; outputs = { other }: { }; }' },
    ["vendor/module.nix"] = MODULE,
  })
  local function at(rel)
    return summary(diagnostics.compute(idx, vim.fs.joinpath(root, rel), { unknown = true }))
  end
  local warning = vim.lsp.protocol.DiagnosticSeverity.Warning
  local message = "Unknown flake input missing"
  eq(at("module.nix"), {
    { range = span(MODULE, 1, "missing"), severity = warning, message = message },
  })
  eq(at("flake.nix"), {
    { range = span(FLAKE, 2, "missing"), severity = warning, message = message },
  })
  eq(at("vendor/flake.nix"), {})
  eq(at("vendor/module.nix"), {})
  vim.fn.delete(root, "rf")
end

T["no unknown input without declarations nor lock"] = function()
  local idx, root = project({
    ["flake.nix"] = { "{ inputs = import ./inputs.nix; outputs = _: { }; }" },
    ["module.nix"] = MODULE,
  })
  eq(diagnostics.compute(idx, vim.fs.joinpath(root, "module.nix"), { unknown = true }), {})
  vim.fn.delete(root, "rf")
end

T["a shared context gives the same diagnostics"] = function()
  local idx, root = project({
    ["flake.nix"] = FLAKE,
    ["flake.lock"] = LOCK,
    ["module.nix"] = MODULE,
    ["base.nix"] = { "{ flake.modules.nixos = { base = { }; old = { }; }; }" },
    ["host.nix"] = HOST,
  })
  local cfg = { unknown = true, unused = true }
  local context = diagnostics.context(idx)
  for _, rel in ipairs({ "flake.nix", "module.nix", "base.nix", "host.nix" }) do
    local path = vim.fs.joinpath(root, rel)
    eq(diagnostics.compute(idx, path, cfg, context), diagnostics.compute(idx, path, cfg))
  end
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
