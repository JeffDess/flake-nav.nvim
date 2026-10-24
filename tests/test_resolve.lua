local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local parse = require("flake-nav.parse")
local resolve = require("flake-nav.resolve")

local text = table.concat({
  "{ config, ... }:",
  "let",
  "  fm = config.flake.modules;",
  "in",
  "{",
  "  flake.modules.nixos.locale = {",
  "    imports = with fm.nixos; [ base ];",
  "    x = fm.homeManager.ssl;",
  "  };",
  "}",
}, "\n")
local parsed = parse.parse(text)

T["on a selection name"] = function()
  eq(resolve.at(parsed, 7, 23), { kind = "module", class = "homeManager", name = "ssl" })
end

T["on a selection class"] = function()
  eq(resolve.at(parsed, 7, 12), { kind = "module", class = "homeManager", name = "ssl" })
end

T["on a with identifier"] = function()
  local base = { kind = "module", class = "nixos", name = "base", binder_range = { 6, 14, 6, 18 } }
  eq(resolve.at(parsed, 6, 31), base)
  eq(resolve.at(parsed, 6, 34), base)
end

T["on a definition name"] = function()
  eq(resolve.at(parsed, 5, 22), { kind = "module", class = "nixos", name = "locale" })
end

T["nil on the alias, the end column and elsewhere"] = function()
  eq(resolve.at(parsed, 7, 8), nil)
  eq(resolve.at(parsed, 6, 35), nil)
  eq(resolve.at(parsed, 0, 2), nil)
end

T["on option usages, after modules"] = function()
  eq(resolve.at(parsed, 5, 2), { kind = "option", class = "flake", path = "flake" })
  eq(resolve.at(parsed, 2, 14), { kind = "option", class = "flake", path = "flake" })
  eq(resolve.at(parsed, 7, 4), { kind = "option", class = "nixos", path = "x" })
  eq(resolve.at(parsed, 5, 22), { kind = "module", class = "nixos", name = "locale" })
end

T["on option declarations"] = function()
  local options = parse.parse(table.concat({
    "{",
    "  flake.modules.nixos.audio = { lib, ... }: {",
    "    options.modules.audio.enable = lib.mkOption { };",
    "  };",
    "}",
  }, "\n"))
  eq(resolve.at(options, 2, 20), { kind = "option", class = "nixos", path = "modules.audio" })
end

local flake = parse.parse(table.concat({
  "{",
  '  inputs.hooks.url = "github:cachix/git-hooks.nix";',
  "  outputs = inputs@{ self, nixpkgs, ... }: {",
  "    a = inputs.hooks.lib;",
  "    m = inputs.self.modules.nixos.base;",
  "    l = nixpkgs.lib;",
  "  };",
  "}",
}, "\n"))

T["on flake inputs, before options"] = function()
  eq(resolve.at(flake, 1, 10), { kind = "input", name = "hooks" })
  eq(resolve.at(flake, 1, 26), { kind = "input", name = "hooks" })
  eq(resolve.at(flake, 3, 16), { kind = "input", name = "hooks" })
  eq(resolve.at(flake, 4, 34), { kind = "module", class = "nixos", name = "base" })
  eq(resolve.at(flake, 5, 9), { kind = "input", name = "nixpkgs", binder_range = { 2, 27, 2, 34 } })
end

return T
