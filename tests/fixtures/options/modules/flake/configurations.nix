{ lib, config, ... }:
{
  options.configurations.nixos = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule { options.module = lib.mkOption { }; });
    default = { };
  };

  config.flake.nixosConfigurations = lib.mapAttrs (_: host: host.module) config.configurations.nixos;
}
