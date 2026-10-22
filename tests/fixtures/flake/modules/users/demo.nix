{ config, ... }:
{
  flake = {
    modules.homeManager.ssl = { };
  };
  flake.modules.nixos.demo = {
    imports = [ config.flake.modules.nixos.locale ];
    home-manager.sharedModules = [ config.flake.modules.homeManager.ssl ];
  };
}
