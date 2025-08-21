describe("ocamlnvim.config", function()
  local config

  before_each(function()
    config = require("ocaml.config")
  end)

  describe("module structure", function()
    it('should have a "config" table', function()
      assert.is_table(config)
    end)
  end)
end)
