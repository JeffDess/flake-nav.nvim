{
  flake.modules.nixos.audio =
    { config, lib, ... }:
    let
      cfg = config.modules.audio;
    in
    {
      options.modules.audio = {
        enable = lib.mkEnableOption "audio";
        backend = lib.mkOption {
          type = lib.types.str;
          default = "pipewire";
          description = "Sound server.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable { services.pipewire.enable = cfg.backend == "pipewire"; })
        { environment.variables.AUDIO_BACKEND = cfg.backend; }
      ];
    };
}
