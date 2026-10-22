# flake-nav.nvim

Go to definition, references and hover for
[dendritic](https://github.com/mightyiam/dendritic) flake-parts modules in Neovim.

In a dendritic configuration, modules refer to each other by name
(`fm.nixos.locale`, `with fm.nixos; [ locale ]`). Nix language servers cannot
follow those names because the link only exists after evaluation. This plugin
indexes `flake.modules.<class>.<name>` definitions statically with tree-sitter
and answers `textDocument/definition`, `textDocument/references` and
`textDocument/hover` through a small LSP server running inside Neovim. It works
next to nixd or nil: Neovim merges the answers.

## Requirements

- Neovim 0.11 or later
- the tree-sitter `nix` parser (`:TSInstall nix`, or
  `pkgs.vimPlugins.nvim-treesitter-parsers.nix`)

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

## Configuration

```lua
require("flake-nav").setup({
  root_markers = { "flake.nix" },
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
  hover = { max_lines = 30 },
})
```

## Usage

Use your usual LSP mappings (`gd`, `gr`, `K`) on a module name.

- `:FlakeNav info` shows the root, the scope, counts and files that could not be indexed.
- `:FlakeNav reindex` rebuilds the index.

## Recognised forms

Definitions: `flake.modules.<class>.<name> = …`, `flake.modules.<class> = { <name> = …; }`
and any nesting of those paths inside `flake = { … }`.

Usages: `<root>.<class>.<name>` and the identifiers listed in
`with <root>.<class>; [ … ]`, where `<root>` is `config.flake.modules`,
`self.modules`, `inputs.self.modules`, or a `let` alias of one of them.

## Scope

When `flake.nix` calls import-tree (`inputs.import-tree ./modules`,
`import-tree [ ./a ./b ]`), only `flake.nix`, those paths and the path
literals of its `imports` lists are indexed, so a definition in a file that
Nix never loads is never offered. Paths with a component starting with `_`
are skipped, like import-tree does (`ignore_underscore = false` to keep them).
Without import-tree, or with a form it cannot read statically (`.filter`,
`.match`, an alias), the whole repository is indexed.

## Limitations

- Names computed by code (`lib.mapAttrs`, interpolation, `lib.mkMerge`) are not indexed.
- Aliases passed between files are not followed.
- den aspects are not supported.
- Imports made from indexed files are not followed: a `flake.modules` definition in a `_` file or
  outside the import-tree paths, imported by hand from a module, is not indexed.

## License

MIT
