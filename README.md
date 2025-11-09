# ocaml.nvim

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
}
```

### Advanced LSP Features

This plugin supports all the advanced features from the VSCode OCaml Platform:

#### Core Settings

- **Dune Diagnostics**: Build system integration for better error reporting
- **Syntax Documentation**: Documentation extraction from comments

#### Experimental Features

- **Switch Implementation/Interface**: Quick navigation between `.ml` and `.mli`
  files
- **Interface Inference**: Automatic interface generation from implementation
- **Typed Holes**: Support for `_` placeholders with type information
- **Type Enclosing**: Show types of expressions under cursor
- **Construct/Destruct**: Advanced code manipulation features
- **Jump to Next Hole**: Navigate between typed holes in your code

All features are enabled by default but can be disabled individually through
configuration.

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
:OCaml lsp start     " Start LSP server
:OCaml lsp stop      " Stop LSP server
:OCaml lsp restart   " Restart LSP server
```

#### Code Navigation

```vim
" Jump to definition (fun, let, module, module-type, match,
" match-next-case, match-prev-case)
:OCaml jump [target]
:OCaml jump-hole [next|prev]      " Jump to next/previous typed hole
" Jump to next/previous phrase (top-level definition)
:OCaml phrase [next|prev]
```

#### Code Manipulation

```vim
:OCaml expand-ppx                 " Expand PPX at cursor position
" Search functions by type signature and insert selected result
:OCaml type-search [query]
" Show type of expression under cursor with enclosing navigation
:OCaml type-enclosing
" Fill typed holes with suggested constructions
:OCaml construct
" Get documentation for any identifier
:OCaml doc <identifier>
```

**Type Search** allows you to search for functions by their type signature
using the `ocamllsp/typeSearch` LSP method:

```vim
:OCaml type-search                " Prompt for query, then show results
:OCaml type-search int -> string  " Search for functions matching the type
```

After entering a query, you'll get an interactive picker (fzf-lua or telescope
if available) showing all matching functions with their types, file locations,
and documentation previews. You can then use the picker's fuzzy matching to
further refine results. Selecting a result inserts the constructible form at
the cursor position and displays full documentation in a floating window.

**Type Enclosing** shows the type of the expression under your cursor and
allows you to navigate through progressively larger enclosing expressions:

```vim
:OCaml type-enclosing
```

Once the floating window appears, you can:

- `↑` or `K`: Show type of larger enclosing expression (zoom out)
- `↓` or `J`: Show type of smaller enclosing expression (zoom in)
- `d`: Delete the currently highlighted expression
- `y`: Yank (copy) the currently highlighted expression
- `c`: Change the currently highlighted expression (delete and enter insert mode)
- `q` or `Esc`: Close the window

This is useful for understanding complex expressions and debugging type errors
by seeing how OCaml infers types at different levels of your code. The operator
support (d/y/c) allows you to quickly manipulate expressions based on their type
boundaries.

**Construct** fills typed holes (`_`) with suggested constructions:

```vim
:OCaml construct
```

Place your cursor on a typed hole (`_`) and run this command to get suggestions
for filling it. This is particularly useful after using destruct or when working
with complex pattern matches. You'll get a picker to select from valid constructions
that match the expected type.

**Documentation Lookup** retrieves odoc documentation for any identifier without
navigating to it:

```vim
:OCaml doc List.map
:OCaml doc String.concat
```

This displays the full documentation (signature, description, examples) in a
floating window with markdown rendering. Press `q` or `Esc` to close. This is
more convenient than using hover (`K`) when you want to look up documentation
for functions/modules you're not currently at.

#### AST-based Selection

```vim
:OCaml select-ast         " Select the wrapping AST node at cursor
```

**AST Selection** allows you to select code based on OCaml's AST structure:

- `:OCaml select-ast` - Selects the smallest AST node containing the cursor
  (uses `ocamllsp/wrappingAstNode`)

This is useful for quickly selecting logical code blocks (expressions, statements,
modules) based on the OCaml AST.

For expanding/shrinking selections and applying operators (delete, yank, change),
use `:OCaml type-enclosing` instead, which provides interactive navigation and
operator support.

**Suggested keybinding**:

```lua
vim.keymap.set('n', '<leader>v', ':OCaml select-ast<CR>',
  { desc = 'Select AST node' })
```

#### Dune Integration

```vim
:OCaml dune promote            " Promote current file changes
```

**Dune Promote** applies file promotions for the current file. This is useful when:

- Updating test expectations (cram tests, expect tests)
- Promoting generated files to source tree
- Accepting diff-based changes from build rules

The command requires the file to be saved and uses LSP code actions to trigger
the promotion.

#### TreeSitter Support

The plugin automatically registers custom TreeSitter parsers for various
OCaml file types. Install the parsers you need using nvim-treesitter:

```vim
:TSInstall ocaml              " OCaml implementation files (.ml)
:TSInstall ocaml_interface    " OCaml interface files (.mli)
:TSInstall menhir             " Menhir parser files (.mly)
:TSInstall ocamllex           " OCamllex lexer files (.mll)
:TSInstall ocaml_mlx          " OCaml JSX files (.mlx)
:TSInstall reason             " Reason files (.re, .rei)
:TSInstall cram               " Cram test files (.t)
```

**Filetype to TreeSitter parser mappings** (automatically registered):

- `ocaml.interface` → `ocaml_interface`
- `ocaml.menhir` → `menhir`
- `ocaml.ocamllex` → `ocamllex`
- `ocaml.mlx` → `ocaml_mlx`
- `ocaml.cram` → `cram`
- `reason` / `reason.interface` → `reason`

You only need to install the parsers for the file types you use.

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
