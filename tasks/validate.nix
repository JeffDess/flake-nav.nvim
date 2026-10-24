{ pkgs, mkTask, ... }:
{
  validate = mkTask {
    description = "Compare the static index with nix evaluation on a dendritic repository";
    args = {
      repo = {
        type = "positional";
        index = 1;
        required = true;
      };
    };
    runtimeInputs = [
      pkgs.neovim-unwrapped
      pkgs.diffutils
      pkgs.coreutils
    ];
    run = ''
      export FLAKE_NAV_RTP="${pkgs.vimPlugins.nvim-treesitter-parsers.nix}"
      repo=$(realpath "$repo")
      expected=$(mktemp)
      actual=$(mktemp)
      trap 'rm -f "$expected" "$actual"' EXIT
      nix eval --raw --impure --expr "import $PWD/scripts/definitions.nix \"$repo\"" | sort > "$expected"
      nvim --headless -u NONE -l scripts/dump_index.lua "$repo" | sort > "$actual"
      diff -u "$expected" "$actual"
      echo "identical: $(wc -l < "$actual") definitions"
    '';
  };

  validate_options = mkTask {
    description = "Check that every option declared in the repository and evaluated by a configuration is indexed";
    args = {
      repo = {
        type = "positional";
        index = 1;
        required = true;
      };
      configuration = {
        type = "positional";
        index = 2;
        required = true;
      };
      class = {
        type = "positional";
        index = 3;
        default = [ "nixos" ];
      };
    };
    runtimeInputs = [
      pkgs.neovim-unwrapped
      pkgs.coreutils
    ];
    run = ''
      export FLAKE_NAV_RTP="${pkgs.vimPlugins.nvim-treesitter-parsers.nix}"
      repo=$(realpath "$repo")
      expected=$(mktemp)
      actual=$(mktemp)
      trap 'rm -f "$expected" "$actual"' EXIT
      nix eval --raw --impure --expr "import $PWD/scripts/options.nix \"$repo\" \"$configuration\"" | sort -u > "$expected"
      nvim --headless -u NONE -l scripts/dump_options.lua "$repo" "$class" | sort -u > "$actual"
      missing=$(comm -23 "$expected" "$actual")
      if [ -n "$missing" ]; then
        echo "evaluated but not indexed:"
        echo "$missing"
        exit 1
      fi
      echo "indexed: $(wc -l < "$expected") evaluated leaves, $(comm -13 "$expected" "$actual" | wc -l) more in modules this configuration does not import"
    '';
  };
}
