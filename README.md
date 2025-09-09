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
  ft = { "ocaml", "reason", "ocaml.mlx", "ocaml.cram" },
}
```

#### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ocaml/ocaml.nvim",
  requires = { "nvim-treesitter/nvim-treesitter" },
  ft = { "ocaml", "reason", "ocaml.mlx", "ocaml.cram" },
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
- **Opam Projects**: Detects `*.opam` files → uses `ocamllsp`
  (future: opam exec)
- **Dune Projects**: Detects `dune-project`/`dune-workspace` → uses `ocamllsp`
- **Global**: Falls back to global `ocamllsp`

### Manual LSP Control

```vim
:OcamlLsp start    " Start LSP server
:OcamlLsp stop     " Stop LSP server  
:OcamlLsp restart  " Restart LSP server
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
