-- NOTE: This rockspec is used for running busted tests only,
-- not for publishing to LuaRocks.org

local _MODREV, _SPECREV = "scm", "-1"
rockspec_format = "3.0"
package = "ocamlnvim"
version = _MODREV .. _SPECREV

dependencies = {
  "lua >= 5.1",
}

test_dependencies = {
  "lua >= 5.1",
}

source = {
  url = "git://github.com/syaiful6/" .. package,
}

build = {
  type = "builtin",
  copy_directories = {
    "ftplugin",
    "lua",
    "plugin",
    "queries",
    "tests",
  },
}

test = {
  type = "busted",
}
