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

## Configuration

```lua
require("flake-nav").setup({
  root_markers = { "flake.nix" },
  ignore = { ".git", ".direnv", "result", "result-*", "node_modules" },
  ignore_underscore = true,
  hover = { max_lines = 30 },
  filter_with_definitions = true,
  remap_store_paths = true,
})
```

nixd answers a go-to-definition on a name inside `with fm.nixos; [ … ]` with
the `with` keyword itself. When flake-nav finds the module, that location is
dropped so the jump goes straight to the definition. Set
`filter_with_definitions = false` to keep it.

When nixd evaluates options with `builtins.getFlake`, it reads a copy of the
flake in `/nix/store/<hash>-source`, so its option declarations point there.
Locations in a store copy whose `flake.lock` matches the working tree are opened
in the working tree instead. Set `remap_store_paths = false` to keep them.

### Option navigation with nixd

nixd jumps to option declarations (`modules.audio.enable = …`) once it knows the
options of your hosts. Options only exist in the hosts that import their module,
so merge every host:

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

The settings are set in `on_init` because Neovim copies `settings` into the
client before `before_init` runs.

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
