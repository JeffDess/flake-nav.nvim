{
  inputs.hooks.url = "github:cachix/git-hooks.nix";
  inputs.hooks.inputs.nixpkgs.follows = "nixpkgs";
  outputs = { hooks, ... }: { tools = hooks.lib; };
}
