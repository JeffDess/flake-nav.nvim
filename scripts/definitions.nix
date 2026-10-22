repo:
let
  flake = builtins.getFlake repo;
  inputs = flake.inputs // {
    self = flake;
  };
  evaluated = inputs.flake-parts.lib.evalFlakeModule { inherit inputs; } (
    inputs.import-tree (/. + "${repo}/modules")
  );
  definitions = builtins.filter (
    d: builtins.isAttrs d.value && d.value ? modules
  ) evaluated.options.flake.definitionsWithLocations;
  # NOTE: Names computed by code (`lib.mapAttrs`, …) have no source position and are out of scope for the static index (spec §1).
  render =
    d: class: name:
    let
      pos = builtins.unsafeGetAttrPos name d.value.modules.${class};
    in
    if pos == null then
      [ ]
    else
      [ "${class}.${name} ${pos.file}:${toString pos.line}:${toString pos.column}" ];
  lines = builtins.concatMap (
    d:
    builtins.concatMap (
      class: builtins.concatMap (render d class) (builtins.attrNames d.value.modules.${class})
    ) (builtins.attrNames d.value.modules)
  ) definitions;
in
builtins.concatStringsSep "\n" lines + "\n"
