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

T["classes defined by a computed value"] = function()
  local function computed(src)
    return parse.parse(src).computed
  end
  eq(computed("{ flake.modules.nixos.x = { }; }"), { all = false, classes = {} })
  eq(computed("{ config.flake.modules.nixos = f x; }"), { all = false, classes = { nixos = true } })
  eq(computed('{ flake.modules.nixos."${n}" = { }; }'), { all = false, classes = { nixos = true } })
  eq(
    computed("{ flake.modules = { darwin = { } // x; }; }"),
    { all = false, classes = { darwin = true } }
  )
  eq(computed("{ flake.modules = f x; }"), { all = true, classes = {} })
  eq(computed("{ flake = f x; }"), { all = true, classes = {} })
  eq(computed('{ flake.modules."${c}".x = { }; }'), { all = true, classes = {} })
  eq(computed("{ flake.nixosModules = f x; other = f x; }"), { all = false, classes = {} })
end

T["classes mapped from a flake option"] = function()
  local result = parse.parse(
    "{ lib, config, ... }: { config.flake.modules.nixos = lib.mapAttrs mk config.users; }"
  )
  eq(result.mapped, { { class = "nixos", source = "users" } })
  eq(result.computed, { all = false, classes = {} })
  eq(
    parse.parse("{ flake.modules.homeManager = builtins.mapAttrs f config.a.b; }").mapped,
    { { class = "homeManager", source = "a.b" } }
  )
  local other = parse.parse("{ flake.modules.nixos = lib.mapAttrs f x; }")
  eq(other.mapped, {})
  eq(other.computed, { all = false, classes = { nixos = true } })
end

T["flake modules imported from inputs"] = function()
  local src = lines(
    "{ inputs, ... }:",
    "{",
    "  imports = [",
    "    inputs.lib.flakeModules.default",
    "    inputs.parts.flakeModule",
    "    inputs.other.modules.flake.tools",
    "    inputs.self.flakeModules.local",
    "    inputs.pkgs.nixosModules.x",
    "    ./local.nix",
    "  ];",
    "}"
  )
  eq(parse.parse(src).external, { lib = true, parts = true, other = true })
  eq(
    parse.parse("{ outputs = inputs: mkFlake { } { imports = [ inputs.lib.flakeModules.x ]; }; }").external,
    { lib = true }
  )
end

T["longer path is a partial definition"] = function()
  local result = parse.parse("{ flake.modules.nixos.locale.imports = [ ]; }")
  eq(names(result), { "nixos.locale" })
  eq(result.defs[1].range, { 0, 22, 0, 28 })
  eq(names(parse.parse("{ flake.modules.nixos = { a.imports = [ ]; a.x = 1; }; }")), {
    "nixos.a",
    "nixos.a",
  })
end

T["through mkIf and mkMerge"] = function()
  eq(
    names(parse.parse("{ lib, ... }: { config = lib.mkIf c { flake.modules.nixos.a = { }; }; }")),
    {
      "nixos.a",
    }
  )
  eq(
    names(
      parse.parse(
        "{ config = mkMerge [ { flake.modules.nixos.b = { }; } (mkIf c { flake.modules.nixos.c = { }; }) ]; }"
      )
    ),
    { "nixos.b", "nixos.c" }
  )
  eq(names(parse.parse("{ flake.modules.nixos = lib.mkMerge [ { d = { }; } ]; }")), { "nixos.d" })
  eq(names(parse.parse("{ lib, ... }: lib.mkMerge [ { flake.modules.nixos.e = { }; } ]")), {
    "nixos.e",
  })
  eq(parse.parse("{ config = lib.mkIf c (f x); }").computed, { all = false, classes = {} })
end

T["inherited names"] = function()
  local result = parse.parse("{ flake.modules.nixos = { inherit (x) a; inherit b; }; }")
  eq(names(result), { "nixos.a", "nixos.b" })
  eq(result.defs[1].range, { 0, 38, 0, 39 })
  eq(
    parse.parse("{ flake.modules = { inherit (x) darwin; }; }").computed,
    { all = false, classes = { darwin = true } }
  )
end

T["inline modules in imports and mkFlake"] = function()
  eq(names(parse.parse("{ imports = [ { flake.modules.nixos.a = { }; } ./b.nix ]; }")), {
    "nixos.a",
  })
  local flake = lines(
    "{",
    "  outputs = inputs: inputs.parts.lib.mkFlake { inherit inputs; } {",
    "    flake.modules.nixos.b = { };",
    "  };",
    "}"
  )
  eq(names(parse.parse(flake)), { "nixos.b" })
  eq(
    names(parse.parse("{ outputs = i: mkFlake { } ({ ... }: { flake.modules.nixos.c = { }; }); }")),
    { "nixos.c" }
  )
  eq(parse.parse("{ outputs = i: mkFlake { } ./parts.nix; }").computed, {
    all = false,
    classes = {},
  })
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
