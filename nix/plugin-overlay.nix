{
  self,
  name,
}: final: prev: let
  lib = final.lib;

  ocamlnvim-luaPackage-override = luaself: luaprev: {
    ocamlnvim = luaself.callPackage ({
      luaOlder,
      buildLuarocksPackage,
    }:
      buildLuarocksPackage {
        pname = name;
        version = "scm-1";
        knownRockspec = "${self}/ocamlnvim-scm-1.rockspec";
        src = self;
        disabled = luaOlder "5.1";
      }) {};
  };

  lua5_1 = prev.lua5_1.override {
    packageOverrides = ocamlnvim-luaPackage-override;
  };
  luajit = prev.luajit.override {
    packageOverrides = ocamlnvim-luaPackage-override;
  };

  lua51Packages = final.lua5_1.pkgs;
  luajitPackages = final.luajit.pkgs;
in {
  inherit
    lua5_1
    lua51Packages
    luajit
    luajitPackages
    ;

  vimPlugins =
    prev.vimPlugins
    // {
      ocamlnvim = final.neovimUtils.buildNeovimPlugin {
        luaAttr = final.luajitPackages.ocamlnvim;
      };
    };

  inherit (final.vimPlugins) ocamlnvim;
  ocamlnvim-dev = final.vimPlugins.ocamlnvim;

  codelldb = final.vscode-extensions.vadimcn.vscode-lldb.adapter;
}
