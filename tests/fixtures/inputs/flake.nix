{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pkgs.follows = "hooks/nixpkgs";
    local.url = "path:./vendor/local";
    notes = {
      url = "path:./data/notes.txt";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    {
      libs = nixpkgs.lib;
      hooks = inputs.hooks.lib;
      source = self.outPath;
    };
}
