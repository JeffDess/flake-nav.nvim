# Changelog

All notable changes to this project are documented in this file.

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
