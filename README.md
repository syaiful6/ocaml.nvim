# ocaml.nvim

WARNING: This plugin is in early development and may not work as expected.

This plugin provides basic support for OCaml development in Neovim,
including syntax highlighting, indentation, and basic LSP support.

Since OCaml has a variety of file extensions, this plugin provides a way
to associate file extensions with the appropriate language server
and syntax highlighting. Here is the list of file extensions and
their corresponding language identifiers:

- .ml -> ocaml
- .mli -> ocaml.interface
- .mll -> ocaml.ocamllex
- .mly -> ocaml.menhir
- .t -> ocaml.toplevel
- .re -> reason
- .rei -> reason

## Installation

### Lazy.nvim

```lua
{
  "ocaml/ocaml.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
}
```
