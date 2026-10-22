{
  description = "flake-nav.nvim - Neovim plugin for navigation by definition/references between flake modules in dendritic flake-parts configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    lets = {
      url = "github:JeffDess/lets?ref=v0.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
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

      imports = [
        inputs.lets.flakeModules.default
        inputs.git-hooks.flakeModule
      ];

      perSystem =
        { config, pkgs, ... }:
        let
          lintCommits = pkgs.lib.getExe config.packages.lint_commits;
        in
        {
          lets.tasks = ./tasks;

          packages.default = pkgs.vimUtils.buildVimPlugin {
            pname = "flake-nav-nvim";
            inherit version;
            src = ./.;
            doCheck = false;
          };

          formatter = pkgs.nixfmt-tree.override {
            runtimeInputs = [ pkgs.stylua ];
            settings = {
              global.excludes = [ "tests/fixtures/**" ];
              formatter.stylua = {
                command = "stylua";
                includes = [ "*.lua" ];
              };
            };
          };

          pre-commit.settings.hooks = {
            convco = {
              enable = true;
              entry = "${lintCommits} --allow-fixup --message-file";
            };
            convco-push = {
              enable = true;
              name = "convco (push)";
              stages = [ "pre-push" ];
              pass_filenames = false;
              always_run = true;
              entry = "${lintCommits} --protect main";
            };
            nixfmt = {
              enable = true;
              excludes = [ "^tests/fixtures/" ];
            };
            statix.enable = true;
            deadnix.enable = true;
            editorconfig-checker.enable = true;
            stylua.enable = true;
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = [ config.lets.devShell ];
            packages = [
              pkgs.neovim-unwrapped
              pkgs.lua-language-server
            ]
            ++ config.pre-commit.settings.enabledPackages;
            inherit (config.pre-commit) shellHook;
          };
        };
    };
}
