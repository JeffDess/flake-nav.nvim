local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local parse = require("flake-nav.parse")

local function lines(...)
  return table.concat({ ... }, "\n")
end

local function keys(items)
  local out = {}
  for _, item in ipairs(items) do
    out[#out + 1] = ("%s:%s@%d:%d"):format(
      item.class or "?",
      item.path,
      item.range[1],
      item.range[2]
    )
  end
  table.sort(out)
  return out
end

local function decls(text)
  return parse.parse(text).options.decls
end

T["declarations"] = MiniTest.new_set()

T["declarations"]["a single mkOption path"] = function()
  local found = decls(
    lines(
      "{",
      "  flake.modules.nixos.audio = { lib, ... }: {",
      "    options.modules.audio.enable = lib.mkOption { type = lib.types.bool; };",
      "  };",
      "}"
    )
  )
  eq(keys(found), {
    "nixos:modules.audio.enable@2:26",
    "nixos:modules.audio@2:20",
    "nixos:modules@2:12",
  })
  for _, decl in ipairs(found) do
    eq(decl.leaf, decl.path == "modules.audio.enable")
    eq(decl.scope_range, { 2, 4, 2, 75 })
  end
end

T["declarations"]["nested attrsets declare every prefix"] = function()
  local found = decls(
    lines(
      "{",
      "  flake.modules.nixos.audio = { lib, ... }: {",
      "    options = {",
      "      modules.audio = {",
      '        enable = lib.mkEnableOption "audio";',
      "        backend.name = lib.mkOption { };",
      "      };",
      "    };",
      "  };",
      "}"
    )
  )
  eq(keys(found), {
    "nixos:modules.audio.backend.name@5:16",
    "nixos:modules.audio.backend@5:8",
    "nixos:modules.audio.enable@4:8",
    "nixos:modules.audio@3:14",
    "nixos:modules@3:6",
  })
  local leaves = {}
  for _, decl in ipairs(found) do
    if decl.leaf then
      leaves[#leaves + 1] = decl.path
    end
  end
  table.sort(leaves)
  eq(leaves, { "modules.audio.backend.name", "modules.audio.enable" })
end

T["declarations"]["submodule options inside a leaf are not indexed"] = function()
  local found = decls(
    lines(
      "{",
      "  flake.modules.nixos.audio = { lib, ... }: {",
      "    options.sinks = lib.mkOption {",
      "      type = lib.types.listOf (lib.types.submodule { options.name = lib.mkOption { }; });",
      "    };",
      "  };",
      "}"
    )
  )
  eq(keys(found), { "nixos:sinks@2:12" })
end

T["declarations"]["bare mkOption under with lib and the homeManager class"] = function()
  local found = decls(
    lines(
      "{",
      "  flake.modules.homeManager.editor = { lib, ... }:",
      "    with lib;",
      "    {",
      '      options.modules.editor.theme = mkOption { default = "dark"; };',
      "    };",
      "}"
    )
  )
  eq(keys(found), {
    "homeManager:modules.editor.theme@4:29",
    "homeManager:modules.editor@4:22",
    "homeManager:modules@4:14",
  })
end

T["declarations"]["the top level of a file is a flake-parts module"] = function()
  local found = decls(
    lines(
      "{ lib, ... }:",
      "{",
      "  options.configurations.nixos = lib.mkOption { };",
      "  flake = { modules.nixos.audio = { options.x = lib.mkOption { }; }; };",
      "}"
    )
  )
  eq(keys(found), {
    "flake:configurations.nixos@2:25",
    "flake:configurations@2:10",
    "nixos:x@3:44",
  })
end

T["declarations"]["values that are not attrsets or option calls stop the descent"] = function()
  eq(keys(decls("{ flake.modules.nixos.a = { options.x = import ./x.nix; }; }")), {
    "nixos:x@0:36",
  })
end

return T
