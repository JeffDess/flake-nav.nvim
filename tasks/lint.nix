{
  pkgs,
  mkTask,
  tasks,
  ...
}:
{
  lint_stylua = mkTask {
    description = "Check Lua formatting with stylua";
    runtimeInputs = [ pkgs.stylua ];
    run = ''
      stylua --check .
      echo "✅ Lua formatting check passed"
    '';
  };

  lint_luacheck = mkTask {
    description = "Lint Lua files with luacheck";
    runtimeInputs = [ pkgs.luajitPackages.luacheck ];
    run = ''
      luacheck .
      echo "✅ Lua linter passed"
    '';
  };

  lint_spell = mkTask {
    description = "Check spelling with typos";
    runtimeInputs = [ pkgs.typos ];
    run = ''
      typos
      echo "✅ Spelling linter passed"
    '';
  };

  lint = mkTask {
    description = "Run all linters";
    keepGoing = true;
    runtimeInputs = with tasks; [
      lint_nix.app
      lint_editor.app
      lint_stylua.app
      lint_luacheck.app
      lint_spell.app
    ];
    run = ''
      lint_nix
      lint_editor
      lint_stylua
      lint_luacheck
      lint_spell
    '';
  };
}
