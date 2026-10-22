{ config, ... }:
{
  flake.modules.nixos.stray = {
    imports = [ config.flake.modules.nixos.locale ];
  };
}
