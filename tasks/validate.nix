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
}
