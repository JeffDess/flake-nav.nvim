{ mkTask, tasks, ... }:
{
  lint = mkTask {
    description = "Run all linters";
    keepGoing = true;
    runtimeInputs = with tasks; [
      lint_nix.app
    ];
    run = ''
      lint_nix
    '';
  };
}
