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
  local base = { kind = "module", class = "nixos", name = "base", with_range = { 6, 14, 6, 18 } }
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
  eq(resolve.at(parsed, 5, 2), nil)
end

return T
