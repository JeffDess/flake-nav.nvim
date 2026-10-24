# flake-nav.nvim

Go to definition, go to references and show definition for
[dendritic](https://github.com/mightyiam/dendritic) flake-parts configurations
in Neovim.

In a dendritic configuration, modules refer to each other by name and hosts set
options declared elsewhere. Nix language servers cannot follow those links
without evaluating the flake. flake-nav follows them as you type:

```nix
imports = with fm.nixos; [ audio desktop ];  # on `audio`: its module, every place that imports it
modules.audio.enable = true;                 # on `enable`: its declaration, every host that sets it
```

It works alongside nixd or nil.

## Features

| | Modules (`fm.nixos.audio`) | Options (`modules.audio.enable`) |
| --- | --- | --- |
| **Go to definition** | the `flake.modules.nixos.audio` definition | the `options.modules.audio…` declaration, from any part of the path |
| **Go to references** | every place that uses the module | every host that sets the option and every module that reads it |
| **Show definition** | the module's source | the option's declaration |

Options are those declared in your repository. Unsaved changes are taken into
account, and paths ignored by import-tree are ignored too.

In `flake.nix`, **`gx` on an input opens its web page**:
`url = "github:cachix/git-hooks.nix";` opens
`https://github.com/cachix/git-hooks.nix`. GitHub, GitLab, SourceHut and `git+https`
references are supported, including `/<branch>`, `?ref=`,
`?rev=` and `?dir=`. `git+ssh` references open the HTTPS site of the same host.
Tarballs from GitHub, GitLab or SourceHut open the repository at the archived ref,
and `file` URLs open as they are.

## Requirements

- Neovim 0.11 or later
- the tree-sitter `nix` parser (`:TSInstall nix`, or
  `pkgs.vimPlugins.nvim-treesitter-parsers.nix`)

Recommended: [import-tree](https://github.com/vic/import-tree) in your
`flake.nix`. It is optional, but with it flake-nav only offers what Nix
actually loads (see [What gets indexed](#what-gets-indexed)).

## Installation

lazy.nvim:

```lua
{
  "JeffDess/flake-nav.nvim",
  ft = "nix",
  opts = {},
}
```

Nix (home-manager):

```nix
programs.neovim.plugins = [ inputs.flake-nav.packages.${system}.default ];
```

then call `require("flake-nav").setup()`.

## Usage

Use your usual LSP mappings on a module name or on an option path:

| Mapping | Action |
| --- | --- |
| `gd` | go to definition |
| `gr` | go to references |
| `K` | show definition |
| `gx` | open a flake input in the browser (in `flake.nix`) |

Commands:

- `:FlakeNav info` shows the project root, what is indexed and any file that could not be read.
- `:FlakeNav reindex` rebuilds the index.

## Configuration

Defaults:

```lua
require("flake-nav").setup({
  root_markers = { "flake.nix" },
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
  hover = { max_lines = 30 },
  filter_with_definitions = true,
  remap_store_paths = true,
  input_links = true,
})
```

| Option | Description |
| --- | --- |
| `root_markers` | files that mark the root of a flake |
| `ignore` | file and directory names to skip |
| `ignore_underscore` | skip paths with a component starting with `_`, like import-tree |
| `hover.max_lines` | longest source excerpt shown on hover |
| `filter_with_definitions` | hide results from other language servers that duplicate flake-nav's, such as nixd jumping to the `with` keyword |
| `remap_store_paths` | open results that other language servers give in `/nix/store` copies of your flake in your working tree instead |
| `input_links` | make flake inputs in `flake.nix` open with `gx` |

### Option types and completion with nixd (optional)

flake-nav navigates your options on its own. For types, defaults and
completion of every option, nixpkgs included, configure nixd with the options
of your hosts:

```lua
vim.lsp.config("nixd", {
  on_init = function(client)
    local expr = ([[
      let
        hosts = (builtins.getFlake "%s").nixosConfigurations or { };
        isOption = v: builtins.isAttrs v && (v._type or null) == "option";
        merge = a: b:
          if isOption a || isOption b || !(builtins.isAttrs a && builtins.isAttrs b) then a
          else a // builtins.mapAttrs (n: v: if a ? ${n} then merge a.${n} v else v) b;
      in
      builtins.foldl' merge { } (map (h: h.options) (builtins.attrValues hosts))
    ]]):format(client.root_dir)
    client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
      nixd = { options = { nixos = { expr = expr } } },
    })
    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
  end,
})
```

## Supported patterns

Modules are defined with `flake.modules.<class>.<name> = …`, in any nesting
under `flake = { … }`, and used as:

```nix
fm.nixos.audio                       # fm = config.flake.modules;
config.flake.modules.nixos.audio
self.modules.nixos.audio
inputs.self.modules.nixos.audio
with fm.nixos; [ audio desktop ]
```

Options are declared with `options.<path> = mkOption { … }` (or
`mkEnableOption`, `mkPackageOption`), nested attrsets included, inside:

- `flake.modules.<class>.<name> = …`;
- `configurations.<class>.<name>.module = …`;
- a flake-parts module (the top level of a file);
- `home-manager.users.<user> = …` and `home-manager.sharedModules = [ … ]`
  (home-manager options);
- an inline module in `imports = [ { … } ]`.

They are found where they are set, directly or under `config`, through `mkIf`,
`mkMerge`, `mkDefault`, `mkForce` and the like, and where they are read:
`config.modules.audio.enable`, or `cfg.enable` after
`cfg = config.modules.audio;`. Home-manager options set from a host, such as
`home-manager.users.alice.modules.editor.theme = "dark";`, are found too.

Options that your repository does not declare, such as nixpkgs options, are
left to your other language servers.

## What gets indexed

When `flake.nix` uses import-tree (`inputs.import-tree ./modules`), only the
paths it imports are indexed, so flake-nav never offers a module that Nix does
not load. Otherwise the whole repository is indexed.

## Limitations

- Names computed by code (`lib.mapAttrs`, interpolation) are not found.
- Aliases passed between files are not followed.
- den aspects are not supported.
- Files imported by hand from a module, outside the import-tree paths, are not indexed.
- Options of submodules (`types.submodule { options = …; }`) are not indexed.
- `inherit (cfg) …` is not followed yet.
