local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local parse = require("flake-nav.parse")

local function lines(...)
  return table.concat({ ... }, "\n")
end

local function keys(result)
  local out = {}
  for _, use in ipairs(result.uses) do
    out[#out + 1] = use.class .. "." .. use.name
  end
  table.sort(out)
  return out
end

T["selection through a let alias"] = function()
  local result = parse.parse(
    lines(
      "{ config, ... }:",
      "let",
      "  fm = config.flake.modules;",
      "in",
      "{",
      "  x = fm.nixos.locale;",
      "}"
    )
  )
  eq(#result.uses, 1)
  eq(result.uses[1].class, "nixos")
  eq(result.uses[1].name, "locale")
  eq(result.uses[1].range, { 5, 15, 5, 21 })
  eq(result.uses[1].class_range, { 5, 9, 5, 14 })
end

T["direct selections"] = function()
  eq(
    keys(parse.parse("{ config, ... }: { x = config.flake.modules.homeManager.ssl; }")),
    { "homeManager.ssl" }
  )
  eq(
    keys(
      parse.parse(
        "{ self, inputs, ... }: { a = self.modules.nixos.a; b = inputs.self.modules.nixos.b; }"
      )
    ),
    { "nixos.a", "nixos.b" }
  )
end

T["with block lists"] = function()
  local result = parse.parse(
    lines(
      "{ config, ... }:",
      "let",
      "  fm = config.flake.modules;",
      "in",
      "{",
      "  imports = [ ./a.nix ] ++ (with fm.nixos; [ base locale ]);",
      "}"
    )
  )
  eq(keys(result), { "nixos.base", "nixos.locale" })
  for _, use in ipairs(result.uses) do
    eq(use.class_range, nil)
    eq(use.binder_range, { 5, 28, 5, 32 })
  end
end

T["selections carry no with range"] = function()
  local result = parse.parse("{ config, ... }: { x = with config.flake.modules.nixos.a; [ ]; }")
  eq(#result.uses, 1)
  eq(result.uses[1].binder_range, nil)
end

T["with block skips lexically bound names"] = function()
  local result = parse.parse(
    lines(
      "{ config, ... }:",
      "let",
      "  fm = config.flake.modules;",
      "  base = 1;",
      "in",
      "{",
      "  imports = with fm.nixos; [ base locale config ];",
      "}"
    )
  )
  eq(keys(result), { "nixos.locale" })
end

T["alias shadowed by a function argument"] = function()
  local result = parse.parse(
    lines(
      "{ config, ... }:",
      "let",
      "  fm = config.flake.modules;",
      "in",
      "{",
      "  f = fm: fm.nixos.locale;",
      "}"
    )
  )
  eq(#result.uses, 0)
end

T["alias shadowed by a rec attrset"] = function()
  local result =
    parse.parse("let fm = config.flake.modules; in rec { fm = 1; x = with fm.nixos; [ a ]; }")
  eq(#result.uses, 0)
end

T["alias shadowed by inherit"] = function()
  local result = parse.parse("let fm = config.flake.modules; in let inherit (x) fm; in fm.nixos.a")
  eq(#result.uses, 0)
end

T["alias of an alias"] = function()
  local result = parse.parse(
    lines("let", "  fm = config.flake.modules;", "  m = fm;", "in", "{ x = m.nixos.a; }")
  )
  eq(keys(result), { "nixos.a" })
end

T["alias of a class"] = function()
  local result = parse.parse(
    lines(
      "{ config, ... }:",
      "let",
      "  fm = config.flake.modules;",
      "  n = config.flake.modules.nixos;",
      "  h = fm.homeManager;",
      "in",
      "{",
      "  x = n.locale;",
      "  y = with h; [ ssl ];",
      "  z = n.a.b;",
      "}"
    )
  )
  eq(keys(result), { "homeManager.ssl", "nixos.locale" })
  local locale = vim.iter(result.uses):find(function(use)
    return use.name == "locale"
  end)
  eq(locale.range, { 7, 8, 7, 14 })
  eq(locale.class_range, nil)
end

T["an inherit of a class alias reads the class whole"] = function()
  local src =
    "{ config, ... }: let n = config.flake.modules.nixos; in { _module.args = { inherit n; }; }"
  eq(parse.parse(src).consumed, { all = false, classes = { nixos = true } })
end

T["a selection through a class alias reads one module"] = function()
  local src = "let n = config.flake.modules.nixos; in { x = n.a; }"
  eq(parse.parse(src).consumed, { all = false, classes = {} })
end

T["non roots are ignored"] = function()
  eq(#parse.parse("{ pkgs, ... }: { x = pkgs.nixos.locale; y = config.modules.nixos.a; }").uses, 0)
end

T["class-only and deeper selections are not usages"] = function()
  local result =
    parse.parse("let fm = config.flake.modules; in { a = fm.nixos; b = fm.nixos.x.y; }")
  eq(#result.uses, 0)
end

T["class selections"] = function()
  local src = "let fm = config.flake.modules; in { a = fm.nixos; b = fm.nixos.x; }"
  local col = src:find("nixos;", 1, true) - 1
  eq(parse.parse(src).classes, { { class = "nixos", range = { 0, col, 0, col + 5 } } })
end

T["usages alone match the full parse"] = function()
  local src = lines(
    "{ config, inputs, ... }:",
    "let fm = config.flake.modules; in",
    "{ imports = with fm.nixos; [ a b ] ++ [ fm.darwin.c inputs.hooks.x ]; y = fm.nixos; }"
  )
  local full, light = parse.parse(src), parse.parse_uses(src)
  eq(light.uses, full.uses)
  eq(light.classes, full.classes)
  eq(light.inputs.uses, full.inputs.uses)
  eq(light.errors, full.errors)
end

T["definitions still found alongside usages"] = function()
  local result = parse.parse(
    lines(
      "{ config, ... }:",
      "let",
      "  fm = config.flake.modules;",
      "in",
      "{",
      "  flake.modules.nixos.locale = {",
      "    imports = with fm.nixos; [ base ];",
      "  };",
      "}"
    )
  )
  eq(#result.defs, 1)
  eq(keys(result), { "nixos.base" })
  eq(result.uses[1].range, { 6, 31, 6, 35 })
end

return T
