{
  description = "flake-nav.nvim - Neovim plugin for navigation by definition/references between flake modules in dendritic flake-parts configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    let
      version = "0.0.0";
    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        {
          packages.default = pkgs.vimUtils.buildVimPlugin {
            pname = "flake-nav-nvim";
            inherit version;
            src = ./.;
            doCheck = false;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.neovim-unwrapped
              pkgs.lua-language-server
            ];
          };
        };
    };
}
