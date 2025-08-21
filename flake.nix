{
  "description" = "OCaml neovim plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    neorocks.url = "github:nvim-neorocks/neorocks";
    gen-luarc.url = "github:mrcjkb/nix-gen-luarc-json";
    git-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    ocaml-overlay = {
      url = "github:nix-ocaml/nix-overlays";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    neorocks,
    gen-luarc,
    git-hooks,
    flake-utils,
    ocaml-overlay,
    ...
  }: let
    name = "ocamlnvim";
    plugin-overlay = import ./nix/plugin-overlay.nix {
      inherit name self;
    };
    ci-overlay = import ./nix/ci-overlay.nix {
      inherit self;
      plugin-name = name;
    };
  in
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs =
        (import nixpkgs {
          inherit system;
          overlays = [
            plugin-overlay
            ci-overlay
            neorocks.overlays.default
            gen-luarc.overlays.default
            ocaml-overlay.overlays.default
          ];
        }).extend (self: super: {
          ocamlPackages = super.ocaml-ng.ocamlPackages_5_2;
        });

      luarc-plugins = with pkgs.lua51Packages; (with pkgs.vimPlugins; [
        toggleterm-nvim
        telescope-nvim
        nvim-dap
      ]);

      luarc-nightly = pkgs.mk-luarc {
        nvim = pkgs.neovim-nightly;
        plugins = luarc-plugins;
      };

      luarc-stable = pkgs.mk-luarc {
        nvim = pkgs.neovim-unwrapped;
        plugins = luarc-plugins;
        disabled-diagnostics = [
          "undefined-doc-name"
          "redundant-parameter"
          "invisible"
        ];
      };

      type-check-nightly = git-hooks.lib.${system}.run {
        src = self;
        hooks = {
          lua-ls = {
            enable = true;
            settings.configuration = luarc-nightly;
          };
        };
      };

      type-check-stable = git-hooks.lib.${system}.run {
        src = self;
        hooks = {
          lua-ls = {
            enable = true;
            settings.configuration = luarc-stable;
          };
        };
      };

      pre-commit-check = git-hooks.lib.${system}.run {
        src = self;
        hooks = {
          alejandra.enable = true;
          stylua.enable = true;
          luacheck.enable = true;
          editorconfig-checker.enable = true;
          markdownlint.enable = true;
        };
      };

      ocamlnvim-shell = pkgs.mkShell {
        name = "koka.nvim-devShell";
        shellHook = ''
          ${pre-commit-check.shellHook}
          ln -fs ${pkgs.luarc-to-json luarc-nightly} .luarc.json
        '';
        buildInputs =
          self.checks.${system}.pre-commit-check.enabledPackages
          ++ (with pkgs; [
            lua-language-server
            busted-nlua
            ocamlPackages.ocaml
            ocamlPackages.dune
            ocamlPackages.ocaml-lsp
            ocamlPackages.ocamlformat
            (lua5_1.withPackages (ps: with ps; [luarocks]))
          ]);
      };
    in {
      devShells = rec {
        default = ocamlnvim;
        ocamlnvim = ocamlnvim-shell;
      };

      packages = rec {
        default = ocamlnvim;
        ocamlnvim = pkgs.ocamlnvim-dev;
        inherit
          (pkgs)
          nvim-minimal-stable
          nvim-minimal-nightly
          ;
      };

      checks = {
        inherit
          type-check-stable
          type-check-nightly
          pre-commit-check
          ;
        inherit
          (pkgs)
          nvim-stable-tests
          nvim-nightly-tests
          ;
      };

      formatter = pkgs.alejandra;
    })
    // {
      overlays = {
        inherit
          ci-overlay
          plugin-overlay
          ;
        default = plugin-overlay;
      };
    };
}
