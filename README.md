# ocaml.nvim

A comprehensive Neovim plugin for [OCaml](https://ocaml.org/) development with
intelligent sandbox detection, LSP integration, and comprehensive filetype support.

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
    -- Optional: for enhanced UI pickers (recommended)
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
    -- Optional: for enhanced UI pickers (recommended)
    -- "ibhagwan/fzf-lua",  -- or
    -- "nvim-telescope/telescope.nvim",
  },
}
```

#### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-treesitter/nvim-treesitter'
" Optional: for enhanced UI pickers (recommended)
" Plug 'ibhagwan/fzf-lua'  " or
" Plug 'nvim-telescope/telescope.nvim'
Plug 'ocaml/ocaml.nvim'
```

### Optional Dependencies

- **fzf-lua** or **telescope.nvim**: Provides enhanced fuzzy pickers with live
  search for commands like `:OCaml type-search`. Falls back to `vim.ui.select`
  if neither is installed.

## 🔧 Configuration

The plugin works out of the box with sensible defaults. For advanced configuration:

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

    -- Pick the sandbox yourself. `candidates` holds every sandbox the enabled
    -- providers found (e.g. all opam switches). Return one of them or its id,
    -- or nil to keep the default choice.
    resolve = function(root, candidates)
      if root:find("legacy%-app") then
        return "opam:4.14.2"
      end
    end,
  },
}
```

### Sandbox

The plugin runs `ocamllsp` inside the project's sandbox (an opam switch or an
esy project). Detection works out of the box; these options let you change it:

```lua
vim.g.ocamlnvim = {
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

    -- Pick the sandbox yourself. `candidates` holds every sandbox the enabled
    -- providers found (e.g. all opam switches). Return one of them or its id,
    -- or nil to keep the default choice.
    resolve = function(root, candidates)
      if root:find("legacy%-app") then
        return "opam:4.14.2"
      end
    end,
  },
}
```

The detected sandbox is cached per project. Run `:OCaml lsp restart` (that
project) or `:OCaml sandbox refresh` (every project) after creating or removing
a switch.

## Troubleshooting

### LSP Server Fails to Start

If you see errors like `"cannot start ocamllsp due to config error"` in your
LSP logs:

1. **Check for conflicts**: Make sure you've disabled `ocamllsp` in your LSP
   configuration
2. **LazyVim users**: Set `ocamllsp = false` in your server configuration
3. **Check LSP logs**: `:lua print(vim.fn.stdpath("log") .. "/lsp.log")` to
   find the log file
4. **Debug configuration**: Run `:lua print(vim.inspect(vim.lsp.config))` to
   check for incomplete configurations

### Command Not Found Errors

If the plugin can't find `ocamllsp` or other tools:

1. **Esy projects**: Ensure dependencies are installed with `esy install`
2. **Opam projects**: Make sure you're in the correct opam switch with tools
   installed
3. **Global installation**: Install `ocamllsp` globally via opam or your
   package manager

### Sandbox Detection Issues

If the plugin doesn't detect your project type correctly:

1. **Check project markers**: Ensure you have the appropriate files
   (`dune-project`, `package.json`, etc.)
2. **Manual LSP control**: Use `:OCaml lsp restart` to force re-detection
3. **Debug sandbox**: Check what command is being used by looking at LSP logs

## Contributing

This plugin is in early development. Contributions are welcome!

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Run tests: `busted`
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim)
  LSP architecture
- Built for the OCaml community with ❤️
