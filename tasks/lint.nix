{ mkTask, tasks, ... }:
{
  lint = mkTask {
    description = "Run all linters";
    keepGoing = true;
    runtimeInputs = with tasks; [
      lint_nix.app
      lint_editor.app
    ];
    run = ''
      lint_nix
      lint_editor
    '';
  };
}
