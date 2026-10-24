local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local parse = require("flake-nav.parse")

local function lines(...)
  return table.concat({ ... }, "\n")
end

local function span(src, row, text, nth)
  local line = vim.split(src, "\n")[row + 1]
  local start = 0
  for _ = 1, nth or 1 do
    start = line:find(text, start + 1, true)
  end
  return { row, start - 1, row, start - 1 + #text }
end

local function decl(src, name)
  for _, d in ipairs(parse.parse(src).inputs.decls) do
    if d.name == name then
      return d
    end
  end
end

local SRC = lines(
  "{",
  "  inputs = {",
  '    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";',
  "    hooks = {",
  '      url = "github:cachix/git-hooks.nix";',
  '      inputs.nixpkgs.follows = "nixpkgs";',
  "    };",
  "  };",
  "  inputs.hooks.flake = true;",
  '  inputs.systems.follows = "hooks/systems";',
  '  inputs.nur = { type = "github"; owner = "nix-community"; repo = "NUR"; };',
  "  outputs = _: { };",
  "}"
)

T["names in declaration order"] = function()
  local names = vim.tbl_map(function(d)
    return d.name
  end, parse.parse(SRC).inputs.decls)
  eq(names, { "nixpkgs", "hooks", "systems", "nur" })
end

T["every name segment is a declaration site, the first one is the definition"] = function()
  local hooks = decl(SRC, "hooks")
  eq(hooks.range, span(SRC, 3, "hooks"))
  eq(hooks.sites, { span(SRC, 3, "hooks"), span(SRC, 8, "hooks") })
end

T["references and their ranges"] = function()
  local nixpkgs = decl(SRC, "nixpkgs")
  eq(nixpkgs.ref, "github:nixos/nixpkgs/nixos-unstable")
  eq(nixpkgs.ref_range, span(SRC, 2, '"github:nixos/nixpkgs/nixos-unstable"'))
  local nur = decl(SRC, "nur")
  eq(nur.attrs, { type = "github", owner = "nix-community", repo = "NUR" })
  eq(nur.attrs_range, span(SRC, 10, '{ type = "github"; owner = "nix-community"; repo = "NUR"; }'))
end

T["follows"] = function()
  eq(decl(SRC, "hooks").follows, { { input = "nixpkgs", target = "nixpkgs" } })
  eq(decl(SRC, "systems").follows_target, "hooks/systems")
end

T["bindings outside inputs are not declarations"] = function()
  eq(parse.parse('{ outputs = _: { inputs.x.url = "github:a/b"; }; }').inputs.decls, {})
end

local function use_keys(src)
  local out = {}
  for _, use in ipairs(parse.parse(src).inputs.uses) do
    out[#out + 1] = ("%s@%d:%d%s"):format(
      use.name,
      use.range[1],
      use.range[2],
      use.binder_range and (" binder %d:%d"):format(use.binder_range[1], use.binder_range[2]) or ""
    )
  end
  table.sort(out)
  return out
end

local function at(src, row, text, nth, binder)
  local r = span(src, row, text, nth)
  return ("%s@%d:%d%s"):format(
    text,
    r[1],
    r[2],
    binder and (" binder %d:%d"):format(binder[1], binder[2]) or ""
  )
end

local function sorted(list)
  table.sort(list)
  return list
end

local FLAKE = lines(
  "{",
  '  inputs.nixpkgs.url = "github:nixos/nixpkgs";',
  '  inputs.hooks.url = "github:cachix/git-hooks.nix";',
  '  inputs.hooks.inputs.nixpkgs.follows = "nixpkgs";',
  "  outputs = inputs@{ self, nixpkgs, ... }: {",
  "    lib = nixpkgs.lib;",
  "    hooks = inputs.hooks.lib;",
  "    same = self.inputs.nixpkgs;",
  "    mod = inputs.self.modules;",
  "    shadow = let nixpkgs = 1; in nixpkgs;",
  "  };",
  "}"
)

T["usages in flake.nix"] = function()
  local formal = span(FLAKE, 4, "nixpkgs")
  eq(
    use_keys(FLAKE),
    sorted({
      at(FLAKE, 3, "nixpkgs", 2),
      at(FLAKE, 4, "nixpkgs", 1, formal),
      at(FLAKE, 5, "nixpkgs", 1, formal),
      at(FLAKE, 6, "hooks", 2),
      at(FLAKE, 7, "nixpkgs"),
    })
  )
end

T["inherit from another set shadows an outputs formal"] = function()
  local src = lines(
    "{",
    "  outputs = { self, nixpkgs, ... }: {",
    "    a = let inherit (x) nixpkgs; in nixpkgs;",
    "    b = rec { inherit (x) nixpkgs; c = nixpkgs; };",
    "    d = let inherit nixpkgs; in nixpkgs;",
    "  };",
    "}"
  )
  local formal = span(src, 1, "nixpkgs")
  eq(
    use_keys(src),
    sorted({
      at(src, 1, "nixpkgs", 1, formal),
      at(src, 4, "nixpkgs", 2, formal),
    })
  )
end

T["follows and outputs formals are only meaningful in flake.nix"] = function()
  for _, use in ipairs(parse.parse(FLAKE).inputs.uses) do
    eq(use.flake_only == true, use.range[1] == 3 or use.binder_range ~= nil)
  end
end

T["usages in modules"] = function()
  local src = lines(
    "{ inputs, ... }:",
    "{",
    "  imports = [ inputs.hooks.flakeModule ];",
    "  perSystem = { inputs', ... }: { packages.x = inputs'.hooks.packages.default; };",
    "  unbound = { x = { }; }.x;",
    "}"
  )
  eq(use_keys(src), sorted({ at(src, 2, "hooks"), at(src, 3, "hooks") }))
end

T["inputs without a binding are not usages"] = function()
  eq(use_keys("{ x = inputs.hooks; }"), {})
end

return T
