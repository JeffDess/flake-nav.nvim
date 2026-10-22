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

  lint = mkTask {
    description = "Run all linters";
    keepGoing = true;
    runtimeInputs = with tasks; [
      lint_nix.app
      lint_editor.app
      lint_stylua.app
    ];
    run = ''
      lint_nix
      lint_editor
      lint_stylua
    '';
  };
}
