{ pkgs, mkTask, ... }:
{
  test = mkTask {
    description = "Run the test suite, or a single test file";
    args = {
      file = {
        description = "Test file to run alone";
        type = "positional";
        index = 1;
        default = "";
      };
    };
    runtimeInputs = [ pkgs.neovim-unwrapped ];
    run = ''
      export FLAKE_NAV_RTP="${pkgs.vimPlugins.mini-nvim},${pkgs.vimPlugins.nvim-treesitter-parsers.nix}"
      if [ -n "$file" ]; then
        nvim --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run_file('$file')"
      else
        nvim --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"
      fi
    '';
  };
}
