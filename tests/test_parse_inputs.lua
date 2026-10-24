local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local parse = require("flake-nav.parse")

local function lines(...)
  return table.concat({ ... }, "\n")
end

local function span(src, row, text)
  local line = vim.split(src, "\n")[row + 1]
  local start = line:find(text, 1, true) - 1
  return { row, start, row, start + #text }
end

T["dotted url bindings"] = function()
  local src = lines(
    "{",
    '  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";',
    "  outputs = _: { };",
    "}"
  )
  eq(parse.inputs(src), {
    {
      url = "https://github.com/nixos/nixpkgs/tree/nixos-unstable",
      range = span(src, 1, '"github:nixos/nixpkgs/nixos-unstable"'),
    },
  })
end

T["inputs attrset with nested forms"] = function()
  local src = lines(
    "{",
    "  inputs = {",
    '    hooks.url = "github:cachix/git-hooks.nix";',
    "    treefmt = {",
    '      url = "github:numtide/treefmt-nix";',
    '      inputs.nixpkgs.follows = "nixpkgs";',
    "    };",
    "  };",
    "}"
  )
  eq(parse.inputs(src), {
    {
      url = "https://github.com/cachix/git-hooks.nix",
      range = span(src, 2, '"github:cachix/git-hooks.nix"'),
    },
    {
      url = "https://github.com/numtide/treefmt-nix",
      range = span(src, 4, '"github:numtide/treefmt-nix"'),
    },
  })
end

T["attrset references link the whole attrset"] = function()
  local src =
    lines("{", '  inputs.nixpkgs = { type = "github"; owner = "nixos"; repo = "nixpkgs"; };', "}")
  eq(parse.inputs(src), {
    {
      url = "https://github.com/nixos/nixpkgs",
      range = span(src, 1, '{ type = "github"; owner = "nixos"; repo = "nixpkgs"; }'),
    },
  })
end

T["git attrsets keep their attrset link"] = function()
  local src = lines(
    "{",
    '  inputs.repo = { type = "git"; url = "https://codeberg.org/owner/repo.git"; };',
    "}"
  )
  eq(parse.inputs(src), {
    {
      url = "https://codeberg.org/owner/repo",
      range = span(src, 1, '{ type = "git"; url = "https://codeberg.org/owner/repo.git"; }'),
    },
  })
end

T["interpolated, unsupported and non-input strings are skipped"] = function()
  local src = lines(
    "{",
    '  inputs.local.url = "path:./vendor";',
    '  inputs.dynamic.url = "github:${owner}/repo";',
    '  outputs = _: { meta.url = "github:nixos/nixpkgs"; };',
    "}"
  )
  eq(parse.inputs(src), {})
end

return T
