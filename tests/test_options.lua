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

local function uses(text)
  return parse.parse(text).options.uses
end

local function module(...)
  local body = { "{", "  flake.modules.nixos.audio = { lib, ... }: {" }
  vim.list_extend(body, { ... })
  vim.list_extend(body, { "  };", "}" })
  return table.concat(body, "\n")
end

local function nixos(items)
  local out = {}
  for _, key in ipairs(keys(items)) do
    if key:sub(1, 6) == "nixos:" then
      out[#out + 1] = key
    end
  end
  return out
end

T["assignments"] = MiniTest.new_set()

T["assignments"]["shorthand paths record every prefix"] = function()
  eq(nixos(uses(module("    modules.audio.enable = true;"))), {
    "nixos:modules.audio.enable@2:18",
    "nixos:modules.audio@2:12",
    "nixos:modules@2:4",
  })
end

T["assignments"]["config is stripped"] = function()
  eq(
    nixos(uses(module("    config.a.b = 1;", "    config = { c = { d = 2; }; };"))),
    { "nixos:a.b@2:13", "nixos:a@2:11", "nixos:c.d@3:21", "nixos:c@3:15" }
  )
end

T["assignments"]["mk wrappers are unwrapped"] = function()
  eq(
    nixos(
      uses(
        module(
          "    config = lib.mkMerge [",
          "      (lib.mkIf true { a = 1; })",
          "      { b = mkDefault { c = 2; }; }",
          "      (lib.mkOverride 50 { d = 3; })",
          "      (mkForce { e = 4; })",
          "    ];"
        )
      )
    ),
    {
      "nixos:a@3:23",
      "nixos:b.c@4:24",
      "nixos:b@4:8",
      "nixos:d@5:27",
      "nixos:e@6:17",
    }
  )
end

T["assignments"]["interpolated keys, imports and options are not usages"] = function()
  eq(
    nixos(
      uses(
        module(
          "    ${name}.x = 1;",
          "    imports = [ { y = 1; } ];",
          "    options.z = lib.mkOption { };"
        )
      )
    ),
    {}
  )
end

T["assignments"]["configurations module sets the class"] = function()
  local found = keys(
    uses(
      lines(
        "{ config, ... }:",
        "{",
        "  configurations.nixos.desktop.module = { lib, ... }: {",
        "    modules.audio.enable = true;",
        "  };",
        "}"
      )
    )
  )
  eq(found, {
    "flake:configurations.nixos.desktop.module@2:31",
    "flake:configurations.nixos.desktop@2:23",
    "flake:configurations.nixos@2:17",
    "flake:configurations@2:2",
    "nixos:modules.audio.enable@3:18",
    "nixos:modules.audio@3:12",
    "nixos:modules@3:4",
  })
end

T["assignments"]["other module functions have an unknown class"] = function()
  local found = keys(uses("{ custom = { config, ... }: { modules.audio.enable = true; }; }"))
  eq(found, {
    "?:modules.audio.enable@0:44",
    "?:modules.audio@0:38",
    "?:modules@0:30",
    "flake:custom@0:2",
  })
end

local function read_keys(src, prefix)
  local out = {}
  for _, key in ipairs(keys(uses(src))) do
    if key:find(prefix, 1, true) == 1 then
      out[#out + 1] = key
    end
  end
  return out
end

local function sorted(list)
  table.sort(list)
  return list
end

local function at(src, row, word, class, path)
  local line = vim.split(src, "\n")[row + 1]
  return ("%s:%s@%d:%d"):format(class, path, row, line:find(word, 1, true) - 1)
end

T["reads"] = MiniTest.new_set()

T["reads"]["config selections in a module that binds config"] = function()
  local src = lines(
    "{",
    "  flake.modules.nixos.audio = { config, lib, ... }: {",
    "    x = config.modules.audio.enable;",
    "  };",
    "}"
  )
  eq(
    read_keys(src, "nixos:modules"),
    sorted({
      at(src, 2, "audio", "nixos", "modules.audio"),
      at(src, 2, "enable", "nixos", "modules.audio.enable"),
      at(src, 2, "modules", "nixos", "modules"),
    })
  )
end

T["reads"]["aliases of config paths"] = function()
  local src = lines(
    "{",
    "  flake.modules.nixos.audio = { config, lib, ... }:",
    "    let",
    "      cfg = config.modules.audio;",
    "    in",
    "    { y = cfg.backend; };",
    "}"
  )
  eq(
    read_keys(src, "nixos:modules"),
    sorted({
      at(src, 5, "backend", "nixos", "modules.audio.backend"),
      at(src, 3, "audio", "nixos", "modules.audio"),
      at(src, 3, "modules", "nixos", "modules"),
    })
  )
end

T["reads"]["an inner module without config reads the flake-parts config"] = function()
  local src = lines(
    "{ config, ... }:",
    "{",
    "  configurations.nixos.desktop.module = { lib, ... }: {",
    "    z = config.flake.modules;",
    "  };",
    "}"
  )
  eq(
    read_keys(src, "flake:flake"),
    sorted({
      at(src, 3, "flake", "flake", "flake"),
      at(src, 3, "modules", "flake", "flake.modules"),
    })
  )
end

T["reads"]["a rebound config is not a read"] = function()
  local src = lines(
    "{",
    "  flake.modules.nixos.audio = { config, ... }: {",
    "    w = (config: config.modules) 1;",
    "  };",
    "}"
  )
  eq(read_keys(src, "nixos:modules"), {})
end

T["home-manager"] = MiniTest.new_set()

local function host(...)
  local body = { "{", "  flake.modules.nixos.host = { ... }: {" }
  vim.list_extend(body, { ... })
  vim.list_extend(body, { "  };", "}" })
  return table.concat(body, "\n")
end

T["home-manager"]["user modules are homeManager modules"] = function()
  local src = host(
    "    home-manager.users.demo = { config, ... }: {",
    '      modules.editor.theme = "light";',
    "      x = config.modules.editor.theme;",
    "    };"
  )
  eq(
    read_keys(src, "homeManager:modules.editor.theme"),
    sorted({
      at(src, 3, "theme", "homeManager", "modules.editor.theme"),
      at(src, 4, "theme", "homeManager", "modules.editor.theme"),
    })
  )
end

T["home-manager"]["the dotted form assigns in homeManager"] = function()
  local src = host('    home-manager.users.demo.modules.editor.theme = "light";')
  eq(
    read_keys(src, "homeManager:"),
    sorted({
      at(src, 2, "modules", "homeManager", "modules"),
      at(src, 2, "editor", "homeManager", "modules.editor"),
      at(src, 2, "theme", "homeManager", "modules.editor.theme"),
    })
  )
end

T["home-manager"]["inline shared modules are homeManager modules"] = function()
  local src = host('    home-manager.sharedModules = [ { modules.editor.theme = "light"; } ];')
  eq(
    read_keys(src, "homeManager:modules.editor.theme"),
    { at(src, 2, "theme", "homeManager", "modules.editor.theme") }
  )
end

T["home-manager"]["wrapped user modules are homeManager modules"] = function()
  local src = host(
    "    home-manager.users.demo = lib.mkIf cond ({ config, ... }: {",
    "      x = config.modules.editor.theme;",
    "    });"
  )
  eq(
    read_keys(src, "homeManager:modules.editor.theme"),
    { at(src, 3, "theme", "homeManager", "modules.editor.theme") }
  )
end

T["home-manager"]["merged user modules are homeManager modules"] = function()
  local src = host(
    "    home-manager.users.demo = lib.mkMerge [",
    '      { modules.editor.theme = "light"; }',
    '      (lib.mkIf cond { modules.editor.font = "mono"; })',
    "    ];"
  )
  eq(
    read_keys(src, "homeManager:modules.editor."),
    sorted({
      at(src, 3, "theme", "homeManager", "modules.editor.theme"),
      at(src, 4, "font", "homeManager", "modules.editor.font"),
    })
  )
end

T["home-manager"]["an interpolated user stops"] = function()
  local src = host('    home-manager.users.${name}.modules.editor.theme = "light";')
  eq(read_keys(src, "homeManager:"), {})
end

T["home-manager"]["nothing switches in a flake-parts module"] = function()
  eq(read_keys('{ home-manager.users.demo.modules.editor.theme = "light"; }', "homeManager:"), {})
end

return T
