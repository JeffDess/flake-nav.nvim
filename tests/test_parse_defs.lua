local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local parse = require("flake-nav.parse")

local function lines(...)
  return table.concat({ ... }, "\n")
end

local function names(result)
  local out = {}
  for _, def in ipairs(result.defs) do
    out[#out + 1] = def.class .. "." .. def.name
  end
  table.sort(out)
  return out
end

T["available"] = function()
  eq(parse.available(), true)
end

T["full path at the root"] = function()
  local result = parse.parse("{ flake.modules.nixos.locale = { }; }")
  eq(#result.defs, 1)
  eq(result.defs[1].class, "nixos")
  eq(result.defs[1].name, "locale")
  eq(result.defs[1].range, { 0, 22, 0, 28 })
  eq({ result.defs[1].scope_range[1], result.defs[1].scope_range[2] }, { 0, 2 })
end

T["through function and let"] = function()
  local result = parse.parse(
    lines(
      "{ config, ... }:",
      "let",
      "  fm = config.flake.modules;",
      "in",
      "{",
      "  flake.modules.nixos.locale = { };",
      "}"
    )
  )
  eq(names(result), { "nixos.locale" })
  eq(result.defs[1].range, { 5, 22, 5, 28 })
end

T["class attrset with quoted name"] = function()
  local result = parse.parse(
    lines("{", "  flake.modules.nixos = {", "    base = { };", '    "dev-rust" = { };', "  };", "}")
  )
  eq(names(result), { "nixos.base", "nixos.dev-rust" })
  for _, def in ipairs(result.defs) do
    if def.name == "dev-rust" then
      eq(def.range, { 3, 4, 3, 14 })
      eq({ def.scope_range[1], def.scope_range[2] }, { 3, 4 })
    end
  end
end

T["free nesting"] = function()
  eq(names(parse.parse("{ flake = { modules.homeManager.ssl = { }; }; }")), { "homeManager.ssl" })
  eq(names(parse.parse("{ flake.modules = { darwin.x = { }; }; }")), { "darwin.x" })
  eq(names(parse.parse("{ flake = rec { modules = { generic.y = { }; }; }; }")), { "generic.y" })
end

T["under config"] = function()
  eq(names(parse.parse("{ config.flake.modules.nixos.x = { }; }")), { "nixos.x" })
  eq(names(parse.parse("{ config = { flake.modules.nixos.y = { }; }; }")), { "nixos.y" })
  eq(#parse.parse("{ foo.config.flake.modules.nixos.z = { }; }").defs, 0)
end

T["longer path is not a definition"] = function()
  eq(#parse.parse("{ flake.modules.nixos.locale.imports = [ ]; }").defs, 0)
end

T["only from the root attrset"] = function()
  eq(#parse.parse("{ foo = { flake.modules.nixos.x = { }; }; }").defs, 0)
  eq(#parse.parse("let a = { flake.modules.nixos.x = { }; }; in a").defs, 0)
end

T["interpolated segment is ignored"] = function()
  eq(#parse.parse('{ flake.modules.nixos."${n}" = { }; }').defs, 0)
end

T["other prefixes are ignored"] = function()
  eq(#parse.parse("{ flake.nixosModules.x = { }; modules.nixos.y = { }; }").defs, 0)
end

T["syntax errors are counted, never thrown"] = function()
  local result = parse.parse("{ flake.modules.nixos.ok = { }; broken = ; }")
  eq(result.errors > 0, true)
end

return T
