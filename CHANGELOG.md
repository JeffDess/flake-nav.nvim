# Changelog

All notable changes to this project are documented in this file.

## [0.3.0] - 2026-10-26

### Features

- *(inputs)* Find flake input declarations
- *(inputs)* Find flake input usages
- *(resolve)* Resolve flake inputs under the cursor
- *(index)* Look up flake inputs and their locked revisions
- *(server)* Answer definition, references and hover for flake inputs
- *(filter)* Drop jumps to outputs formals when flake-nav resolves the input
- *(command)* Show input counts in :FlakeNav info
- *(parse)* Find module definitions under config
- *(parse)* Mark module classes defined by a computed value
- *(diagnostics)* Warn on unknown modules
- *(diagnostics)* Hint at unused module definitions
- *(diagnostics)* Warn on unknown flake inputs
- *(server)* Publish diagnostics for open documents
- Add the diagnostics option

### Documentation

- *(readme)* Document flake input navigation
- *(readme)* Document module definitions under config
- *(readme)* Document diagnostics

## [0.2.0] - 2026-10-24

### Features

- *(options)* Read home-manager user and shared modules
- *(options)* Read inline modules in imports lists
- *(flakeref)* Convert flake references to web URLs
- *(parse)* Find flake input references
- *(links)* Open flake inputs with gx
- *(flakeref)* Open git+ssh references on the https site of their host
- *(flakeref)* Open forge tarballs on their repository
- *(init)* Open the flake input under the cursor with open_input()

### Bug Fixes

- *(flakeref)* Open scp-like git+ssh references on their host

### Documentation

- *(readme)* Document home-manager and inline module contexts
- *(readme)* Document gx on flake inputs
- *(readme)* Document gx on git+ssh inputs
- *(readme)* Document gx on tarball and file inputs
- *(readme)* List Neovim default mappings and open_input()

## [0.1.0] - 2026-10-24

### Features

- *(position)* Convert between byte and UTF-16 columns
- *(parse)* Find flake.modules definitions with tree-sitter
- *(parse)* Find module usages through aliases and with blocks
- *(resolve)* Map a cursor position to a module name
- *(parse)* Read the import-tree scope of flake.nix
- *(index)* Cache definitions and usages per project root
- *(server)* Answer definition, references and hover in process
- *(init)* Register the flake-nav LSP client through setup()
- *(command)* Add :FlakeNav info and reindex
- *(parse)* Record the with keyword range of module usages
- *(resolve)* Pass the with keyword range of a usage
- *(filter)* Drop with keyword definitions from other servers when flake-nav resolves the module
- *(remap)* Map store copies of the flake to the working tree
- *(filter)* Open store locations of other servers in the working tree
- *(options)* Find option declarations in module bodies
- *(options)* Find option assignments in module bodies
- *(options)* Find option reads through config and aliases
- *(resolve)* Resolve option paths under the cursor
- *(index)* Look up option declarations and usages
- *(server)* Answer definition, references and hover for options
- *(filter)* Drop locations that duplicate flake-nav definitions
- *(command)* Show option counts in :FlakeNav info
- *(server)* List declaration sites in the hover of options declared in several files

### Documentation

- *(readme)* Add installation, usage, recognised forms and limitations
- *(readme)* Document filter_with_definitions
- *(readme)* Document store path remapping and nixd option navigation
- *(readme)* Document option navigation
- *(readme)* Focus on usage and configuration
