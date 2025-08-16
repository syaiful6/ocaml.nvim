vim.filetype.add({
  extensions = {
    mli = "ocaml.interface",
    mly = "ocaml.menhir",
    mll = "ocaml.ocamllex",
    mlx = "ocaml.mlx",
    t = "ocaml.cram",
    re = "reason",
    rei = "reason",
  },
})

vim.treesitter.language.register("ocaml_interface", "ocaml.interface")
vim.treesitter.language.register("menhir", "ocaml.menhir")
vim.treesitter.language.register("ocaml_interface", "ocaml.menhir")
vim.treesitter.language.register("cram", "ocamll.cram")
vim.treesitter.language.register("ocamllex", "ocaml.ocamllex")
vim.treesitter.language.register("ocaml_mlx", "ocaml.mlx")
vim.treesitter.language.register("reason", "reason")
