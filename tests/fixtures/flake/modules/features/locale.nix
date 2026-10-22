{ config, ... }:
let
  fm = config.flake.modules;
in
{
  flake.modules.nixos.locale = {
    imports = with fm.nixos; [ base ];
  };
}
