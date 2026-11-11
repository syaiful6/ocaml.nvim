# ocaml.nvim

A Neovim plugin for [OCaml](https://ocaml.org/) with sandbox detection, LSP
integration, and OCaml filetype support.

When you open a supported OCaml file, the plugin starts `ocamllsp` inside the
project's opam switch, esy sandbox or fallback to global environment. You can
use the default detection or configure it for your project.

## Installation

### Prerequisites

- Neovim 0.11+
- `ocamllsp` language server installed
- TreeSitter OCaml parsers

### Package Managers

#### [lazy.nvim](https://github.com/folke/lazy.nvim) (Recommended)

```lua
{
  "ocaml/ocaml.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    -- Optional: fuzzy pickers with live search
    -- "ibhagwan/fzf-lua",  -- or
    -- "nvim-telescope/telescope.nvim",
  },
}
```

#### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ocaml/ocaml.nvim",
  requires = {
    "nvim-treesitter/nvim-treesitter",
    -- Optional: fuzzy pickers with live search
    -- "ibhagwan/fzf-lua",  -- or
    -- "nvim-telescope/telescope.nvim",
  },
}
```

#### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-treesitter/nvim-treesitter'
" Optional: fuzzy pickers with live search
" Plug 'ibhagwan/fzf-lua'  " or
" Plug 'nvim-telescope/telescope.nvim'
Plug 'ocaml/ocaml.nvim'
```

### Optional Dependencies

Install **fzf-lua** or **telescope.nvim** for fuzzy pickers with live search in
commands such as `:OCaml type-search`. Without either plugin, ocaml.nvim uses
`vim.ui.select`.

## Configuration

The default configuration works without setup. To override it, set
`vim.g.ocamlnvim`:

```lua
---@type ocaml.Opts
vim.g.ocamlnvim = {
  lsp = {
    -- Enable/disable automatic LSP attachment
    auto_attach = true,

    -- Custom on_attach function
    on_attach = function(client_id, bufnr)
      -- Set up keymaps, autocommands, etc.
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr })
      vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = bufnr })
      -- ... more LSP keymaps
    end,

    -- OCaml LSP server settings
    settings = {
      duneDiagnostics = true,      -- Dune-specific diagnostics
      syntaxDocumentation = true,  -- Syntax documentation
    },

    -- Experimental OCaml LSP features
    experimental = {
      switchImplIntf = true,       -- Switch between .ml/.mli files
      inferIntf = true,            -- Interface inference
      typedHoles = true,           -- Typed holes support
      typeEnclosing = true,        -- Type enclosing
      construct = true,            -- Construct handling
      destruct = true,             -- Destruct handling
      jumpToNextHole = true,       -- Jump to next hole
    },
  },
  sandbox = {
    -- Sandbox kinds to try, in priority order. Leave one out to disable it.
    -- "global" (tools from your PATH) is always the last resort.
    providers = { "esy", "opam", "global" },

    opam = {
      binary = "opam",
      root = nil, -- nil: detect with `opam var root`
    },

    esy = {
      binary = "esy",
    },

    -- Override sandbox selection. `candidates` contains every sandbox found by
    -- the enabled providers, including all detected opam switches. Return a
    -- candidate or its id, or nil to keep the default.
    resolve = function(root, candidates)
      if root:find("legacy%-app") then
        return "opam:4.14.2"
      end
    end,
  },
}
```

## Troubleshooting

### LSP Server Fails to Start

If you see errors like `"cannot start ocamllsp due to config error"` in your
LSP logs:

1. Disable `ocamllsp` in any other LSP configuration to avoid conflicts.
2. In LazyVim, set `ocamllsp = false` in the server configuration.
3. Find the LSP log with
   `:lua print(vim.fn.stdpath("log") .. "/lsp.log")`.
4. Inspect the active configuration with
   `:lua print(vim.inspect(vim.lsp.config))`.

### Command Not Found Errors

If the plugin can't find `ocamllsp` or other tools:

1. For esy projects, install dependencies with `esy install`.
2. For opam projects, install the tools in the project's switch.
3. For projects without a sandbox, install `ocamllsp` through opam or your
   system package manager.

### Sandbox Detection Issues

If the plugin doesn't detect your project type correctly:

1. Check that the project contains the expected marker files, such as
   `dune-project` or `package.json`.
2. Run `:OCaml lsp restart` to repeat detection.
3. Check the LSP log to see which command the plugin ran.

## Contributing

The plugin is in early development. Contributions are welcome.

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-change`
3. Run tests: `busted`
4. Submit a pull request

## License

Released under the MIT License. See [LICENSE](LICENSE).

## Acknowledgments

- The LSP architecture draws from
  [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim).
