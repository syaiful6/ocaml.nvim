# ocaml.nvim

> [!WARNING]
> This plugin is in early development and may not work as expected.
> Breaking changes may occur without notice.

A comprehensive Neovim plugin for OCaml development with intelligent sandbox
detection, LSP integration, and comprehensive filetype support.

## ✨ Features

- **🎯 Smart LSP Integration**: Automatic detection and setup of `ocamllsp`
  with sandbox support
- **📦 Sandbox Detection**: Supports esy projects with automatic command
  resolution
- **🎨 Multiple Filetypes**: Support for OCaml, Reason, and various OCaml
  file formats
- **🔧 Automatic Formatting**: Integration with `ocamlformat` and
  `ocamlformat-mlx` via conform.nvim
- **🌳 TreeSitter Integration**: Enhanced syntax highlighting and code
  understanding
- **⚡ Performance**: Efficient client reuse and project detection

## 📁 Supported File Types

| Extension | Language | Description |
|-----------|----------|-------------|
| `.ml` | `ocaml` | OCaml implementation files |
| `.mli` | `ocaml.interface` | OCaml interface files |
| `.mll` | `ocaml.ocamllex` | OCaml lexer files |
| `.mly` | `ocaml.menhir` | Menhir parser files |
| `.mlx` | `ocaml.mlx` | OCaml JSX files |
| `.t` | `ocaml.cram` | Cram test files |
| `.re` | `reason` | Reason implementation files |
| `.rei` | `reason` | Reason interface files |

## 📦 Installation

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
  },
}
```

#### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ocaml/ocaml.nvim",
  requires = { "nvim-treesitter/nvim-treesitter" },
}
```

#### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'ocaml/ocaml.nvim'
```

## ⚠️ Important LSP Configuration

**This plugin manages the OCaml LSP server automatically.** If you're using
[nvim-lspconfig](https://github.com/neovim/nvim-lspconfig), you **MUST**
disable the `ocamllsp` server to avoid conflicts:

```lua
-- ❌ DO NOT enable ocamllsp in lspconfig when using this plugin
require("lspconfig").ocamllsp.setup({
  autostart = false,  -- Set this to false!
})

-- ✅ OR better yet, don't configure it at all in lspconfig
```

### LazyVim Users

If you're using [LazyVim](https://github.com/LazyVim/LazyVim), completely disable
the `ocamllsp` server in your LSP configuration to prevent conflicts:

```lua
{
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      -- Completely disable ocamllsp to prevent conflicts
      ocamllsp = false,
    },
  },
}
```

**Why this is important**: Even with `autostart = false`, incomplete LSP configurations
can cause errors when Neovim tries to resolve LSP commands. Setting the server to
`false` completely removes it from the global LSP configuration.

This plugin provides intelligent sandbox detection (esy, opam, global) and will
automatically start the appropriate LSP server with the correct configuration.

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
  },
}
```

## 🚀 Usage

### Automatic LSP

The plugin automatically detects your project type and starts the appropriate
LSP server:

- **Esy Projects**: Detects `esy.json` or `package.json` with `esy` field →
  uses `esy -P ocamllsp`
- **Opam Projects**: Detects `*.opam` files → uses local opam sandbox if present,
  otherwise falls back to global `ocamllsp`
- **Dune Projects**: Detects `dune-project`/`dune-workspace` → uses `ocamllsp`
- **Global**: Falls back to global `ocamllsp`

### Commands

All plugin commands are available as subcommands under `:OCaml`:

#### LSP Control

```vim

:OCaml lsp start    " Start LSP server
:OCaml lsp stop     " Stop LSP server
:OCaml lsp restart  " Restart LSP server
```

#### TreeSitter Support

```vim

:OCaml ts install_reason  " Install Reason TreeSitter parser
:OCaml ts install_mlx     " Install MLX TreeSitter parser
```

### Code Formatting

The plugin automatically configures formatters for
[conform.nvim](https://github.com/stevearc/conform.nvim):

- **OCaml files** → `ocamlformat`
- **MLX files** → `ocamlformat-mlx`

## 🏗️ Project Structure Detection

The plugin searches for these files to determine project root and type:

```text
📁 Project Root Detection (in order of precedence):
├── dune-project       # Dune project
├── dune-workspace     # Dune workspace
├── package.json       # Esy project (with esy field)
├── esy.json           # Esy project
├── *.opam             # Opam package
├── _build/            # Build directory
└── .git/              # Git repository
```

## 🔍 Troubleshooting

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

## 🔧 Development

### Running Tests

```bash
# Run all tests
busted

# Run with coverage
busted --coverage

# Lint code
luacheck .

# Format code  
stylua .
```

### Nix Development

```bash
# Enter development shell
nix develop

# Run all checks
nix flake check

# Build plugin
nix build
```

## 🤝 Contributing

This plugin is in early development. Contributions are welcome!

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Run tests: `busted`
4. Submit a pull request

## 📝 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Inspired by [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim)
  LSP architecture
- Built for the OCaml community with ❤️
