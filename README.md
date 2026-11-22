# ocaml.nvim

A Neovim plugin for [OCaml](https://ocaml.org/) that detects project sandboxes,
configures `ocamllsp`, and supports OCaml filetypes.

Open an OCaml file and the plugin starts `ocamllsp` in the project's dune, esy,
or opam sandbox. If it cannot find one, it uses your global environment. You can
change the detection order or disable individual providers.

## Installation

### Prerequisites

- Neovim 0.11+
- `ocamllsp` language server installed, unless the project uses dune package
  management and installs it as a dev tool
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

With **conform.nvim**, the `ocamlformat` and `ocamlformat_mlx` formatters use
the project's dune dev tools, opam switch, or esy sandbox. If the sandbox does
not contain the formatter, ocaml.nvim uses the one on `PATH`. For dune package
management projects, it also offers to run `dune tools install ocamlformat`.
Conform options such as `prepend_args` still apply. Set `command` to choose the
executable yourself.

```lua
require("conform").setup({
  formatters_by_ft = {
    ocaml = { "ocamlformat" },
    ["ocaml.mlx"] = { "ocamlformat_mlx" }
  },
})
```

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
    providers = { "dune", "esy", "opam", "global" },

    -- Dune package management: projects with a lock dir (dune.lock/), or
    -- `(pkg enabled)` in dune-workspace.
    dune = {
      binary = "dune",
    },

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

## Dune Package Management

Projects that use [dune package management](https://dune.readthedocs.io/en/stable/tutorials/dune-package-management/index.html)
do not need opam or esy. The `dune` provider selects a project when its
workspace has a lock directory (`dune.lock/`, or the default context's
`lock_dir` in `dune-workspace`) or when `dune-workspace` contains `(pkg
enabled)`. `(pkg disabled)` turns the provider off for that workspace. Dune is
first in the default provider order because a lock directory explicitly ties
the project to dune package management.

The plugin manages `ocamllsp` and `ocamlformat` as dune dev tools built against
the project's lock directory:

- When `ocamllsp` is missing, the plugin asks once whether to run
  `dune tools install ocamllsp`. The first installation builds it from source
  and may take a few minutes. The language server starts afterward.
- When package management is enabled without a lock directory, the plugin asks
  whether to run `dune pkg lock` first.
- When the lock directory changes while `ocamllsp` runs, the plugin asks
  whether to rebuild the dev tools and restart the server.

Dev tools run from the directories reported by `dune tools env`, which the
plugin places first on `PATH`. This lets `ocamllsp` find the project's
`ocamlformat` even while `dune build --watch` holds dune's build lock. The
plugin remembers prompt responses for the session; `:OCaml sandbox refresh`
clears them. The provider requires a dune version that supports `dune tools
env`. With an older version, `:OCaml sandbox info` lists the project but the
plugin does not select it.

## Lua API

`require("ocaml").sandbox` runs commands in the language server's dune, opam,
or esy sandbox, so commands use the project's versions of `dune` and
`ocamlformat`. Pass `opts.root` to select a project directly or `opts.bufnr` to
derive it from a buffer. The current buffer is the default.

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

Start with `:checkhealth ocaml`. It checks your Neovim version and
configuration, locates `opam`, `esy`, `dune`, and `ocamllsp`, then reports the
sandbox for the most recently used OCaml buffer. The report explains why the
sandbox was selected, whether it contains `ocamllsp` and `ocamlformat`, and
whether the language server is running.

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

1. For dune package management projects, run `dune tools install ocamllsp`
   (and `ocamlformat`) in the project, then `:OCaml lsp restart`.
2. For esy projects, install dependencies with `esy install`.
3. For opam projects, install the tools in the project's switch.
4. For projects without a sandbox, install `ocamllsp` through opam or your
   system package manager.

### Sandbox Detection Issues

If the plugin detects the wrong project type:

1. Run `:OCaml sandbox info` to see the active sandbox, the reason it was
   selected, the `ocamllsp` command, and the other available candidates. You
   can select an opam switch with `sandbox.resolve`.
2. Check that the project contains the expected marker files, such as
   `dune-project`, `dune.lock/`, or `package.json`. To stop a project with a
   lock directory from using dune package management, add `(pkg disabled)` to
   its `dune-workspace` or remove `"dune"` from `sandbox.providers`.
3. Run `:OCaml sandbox refresh` to repeat detection.
4. Check the LSP log for errors from `ocamllsp`.

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
