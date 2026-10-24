{
  flake.modules.nixos.video =
    { lib, ... }:
    {
      options.modules.video.enable = lib.mkEnableOption "video";
    };
}
