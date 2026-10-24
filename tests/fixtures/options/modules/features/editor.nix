{
  flake.modules.homeManager.editor =
    { config, lib, ... }:
    with lib;
    {
      options.modules.editor.theme = mkOption {
        type = types.str;
        default = "dark";
      };

      config.programs.helix.settings.theme = config.modules.editor.theme;
    };
}
