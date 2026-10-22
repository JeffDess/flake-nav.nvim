local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local parse = require("flake-nav.parse")

local function tree(text)
  return parse.import_tree(text)
end

T["selection call as the mkFlake argument"] = function()
  eq(
    tree(
      "{ outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules); }"
    ),
    { status = "detected", paths = { "modules" } }
  )
end

T["bare call from formals with a list argument"] = function()
  eq(
    tree(
      "{ outputs = { flake-parts, import-tree, ... }@inputs: flake-parts.lib.mkFlake { inherit inputs; } (import-tree [ ./a ./b/ ]); }"
    ),
    { status = "detected", paths = { "a", "b" } }
  )
  eq(
    tree("{ outputs = inputs: mk { } (inputs.import-tree ./.); }"),
    { status = "detected", paths = { "." } }
  )
end

T["bare call under with and through inherit"] = function()
  eq(
    tree(
      "{ outputs = inputs: with inputs; flake-parts.lib.mkFlake { inherit inputs; } (import-tree ./modules); }"
    ),
    { status = "detected", paths = { "modules" } }
  )
  eq(
    tree(
      '{ inputs = { import-tree.url = "x"; }; outputs = inputs: let inherit (inputs) import-tree; in mk { } (import-tree ./m); }'
    ),
    { status = "detected", paths = { "m" } }
  )
end

T["path literals of imports lists join the scope"] = function()
  eq(
    tree(
      "{ outputs = inputs: mk { inherit inputs; } { imports = [ (inputs.import-tree ./modules) ./extra.nix ]; }; }"
    ),
    { status = "detected", paths = { "modules", "extra.nix" } }
  )
end

T["declarations and formals alone are not calls"] = function()
  eq(
    tree(
      '{ inputs.import-tree.url = "github:vic/import-tree"; outputs = { import-tree, ... }: { }; }'
    ),
    { status = "none", paths = {} }
  )
  eq(tree("{ outputs = _: { }; }"), { status = "none", paths = {} })
  eq(tree("{ imports = [ ./a.nix ]; }"), { status = "none", paths = {} })
end

T["unrecognised forms"] = function()
  local unsupported = { status = "unsupported", paths = {} }
  eq(tree("{ outputs = inputs: mk { } (inputs.import-tree.filter f ./modules); }"), unsupported)
  eq(tree("{ outputs = inputs: mk { } (inputs.import-tree ../shared); }"), unsupported)
  eq(tree('{ outputs = inputs: mk { } (inputs.import-tree "${./m}"); }'), unsupported)
  eq(
    tree("{ outputs = inputs: let it = inputs.import-tree; in mk { } (it ./modules); }"),
    unsupported
  )
end

T["text that does not parse"] = function()
  eq(tree("{ outputs = ").status ~= "detected", true)
end

return T
