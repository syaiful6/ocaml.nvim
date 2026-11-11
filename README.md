# ocaml.nvim

A Neovim plugin for [OCaml](https://ocaml.org/) that detects project sandboxes,
configures `ocamllsp`, and supports OCaml filetypes.

Open an OCaml file and the plugin starts `ocamllsp` in the project's opam switch
or esy sandbox. If neither is available, it uses your global environment. The
defaults should work for most projects, and sandbox detection is configurable.

## Installation

### Prerequisites

- Neovim 0.11+
- `ocamllsp` language server installed
- TreeSitter OCaml parsers

### Package Managers

#### [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

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

Install **fzf-lua** or **telescope.nvim** to add live fuzzy search to commands
such as `:OCaml type-search`. Otherwise, ocaml.nvim uses `vim.ui.select`.

## Configuration

No setup is required. Set `vim.g.ocamlnvim` to override the defaults:

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

## Lua API

`require("ocaml").sandbox` runs commands in the same opam switch or esy sandbox
as the language server. This keeps tools such as `dune` and `ocamlformat` on the
project's installed versions. Pass `opts.root` to select a project directly, or
`opts.bufnr` to derive it from a buffer. The current buffer is the default.

```lua
local sandbox = require("ocaml").sandbox

-- Run a command; vim.system options are accepted, cwd defaults to the project root
sandbox.run({ "dune", "build" }, {}, function(result, err)
  if err then
    return vim.notify(err, vim.log.levels.ERROR)
  end
  print(result.code, result.stdout)
end)

-- Wrap a command for your own job runner, e.g. a terminal split
sandbox.get_command({ "dune", "test", "--watch" }, {}, function(cmd, err)
  if not cmd then
    return vim.notify(err, vim.log.levels.ERROR)
  end
  vim.cmd("botright new")
  vim.fn.jobstart(cmd, { term = true })
end)

-- Synchronous variant; blocks only while the sandbox is still being detected
local cmd, err = sandbox.get_command_sync({ "ocamlformat", "--version" })

-- The sandbox a project uses, e.g. info.id == "opam:/path/to/project"
sandbox.get({ bufnr = 0 }, function(info)
  print(info.id, info.label)
end)
```

## Troubleshooting

### LSP Server Fails to Start

If the LSP log contains `"cannot start ocamllsp due to config error"`:

1. Disable `ocamllsp` in any other LSP configuration to avoid conflicts.
2. In LazyVim, set `ocamllsp = false` in the server configuration.
3. Find the LSP log with
   `:lua print(vim.fn.stdpath("log") .. "/lsp.log")`.
4. Inspect the active configuration with
   `:lua print(vim.inspect(vim.lsp.config))`.

### Command Not Found Errors

If the plugin cannot find `ocamllsp` or another tool:

1. For esy projects, install dependencies with `esy install`.
2. For opam projects, install the tools in the project's switch.
3. For projects without a sandbox, install `ocamllsp` through opam or your
   system package manager.

### Sandbox Detection Issues

If the plugin detects the wrong project type:

1. Check that the project contains the expected marker files, such as
   `dune-project` or `package.json`.
2. Run `:OCaml lsp restart` to repeat detection.
3. Check the LSP log to see which command the plugin ran.

## Contributing

ocaml.nvim is in early development. Contributions are welcome.

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-change`
3. Run tests: `busted`
4. Submit a pull request

## License

Released under the MIT License. See [LICENSE](LICENSE).

## Acknowledgments

- The LSP architecture draws from
  [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim).
