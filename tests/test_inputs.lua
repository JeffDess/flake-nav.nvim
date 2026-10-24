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

return T
