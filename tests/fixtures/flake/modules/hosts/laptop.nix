{ config, ... }:
let
  fm = config.flake.modules;
in
{
  configurations.nixos.laptop.module = {
    imports = [ ./hardware.nix ] ++ (with fm.nixos; [ base locale demo ]);
  };
}
