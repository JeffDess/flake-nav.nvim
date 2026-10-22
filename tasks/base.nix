{ baseTasks, ... }:
{
  inherit (baseTasks)
    lint_commits
    lint_editor
    lint_nix
    ;
}
