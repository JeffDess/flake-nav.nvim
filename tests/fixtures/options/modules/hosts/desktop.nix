{ config, ... }:
let
  fm = config.flake.modules;
in
{
  configurations.nixos.desktop.module =
    { lib, ... }:
    {
      imports = with fm.nixos; [ audio ];

      modules = {
        audio.enable = true;
        audio.backend = lib.mkDefault "pulse";
      };

      home-manager.users.demo.modules.editor.theme = "light";
    };
}
