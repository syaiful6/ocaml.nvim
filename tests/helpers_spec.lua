describe("ocaml.helpers.system_lines", function()
  local helpers = require("ocaml.helpers")

  ---Run system_lines and wait for its callback.
  ---@return string[]|nil lines
  ---@return string|nil err
  ---@return boolean sync true if the callback ran before system_lines returned
  local function run(cmd, opts)
    local done, lines, err = false, nil, nil
    helpers.system_lines(cmd, function(l, e)
      done, lines, err = true, l, e
    end, opts)
    local sync = done
    assert.is_true(vim.wait(5000, function()
      return done
    end, 10))
    return lines, err, sync
  end

  it("returns stdout lines without trailing empty line", function()
    local lines, err = run({ "printf", "a\\nb\\n" })
    assert.is_nil(err)
    assert.are.same({ "a", "b" }, lines)
  end)

  it("never calls back synchronously", function()
    local _, _, sync = run({ "true" })
    assert.is_false(sync)
  end)

  it("reports a non-zero exit code with stderr", function()
    local lines, err = run({ "sh", "-c", "echo boom >&2; exit 3" })
    assert.is_nil(lines)
    assert.truthy(err:find("exit code 3", 1, true))
    assert.truthy(err:find("boom", 1, true))
  end)

  it("reports a missing executable instead of throwing", function()
    local lines, err, sync = run({ "ocamlnvim-definitely-not-a-binary" })
    assert.is_nil(lines)
    assert.is_string(err)
    assert.is_false(sync)
  end)

  it("kills commands that exceed the timeout", function()
    local lines, err = run({ "sleep", "5" }, { timeout = 100 })
    assert.is_nil(lines)
    assert.truthy(err:find("signal", 1, true) or err:find("exit code 124", 1, true))
  end)
end)
