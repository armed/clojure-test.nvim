local location_api = require("clojure-test.api.location")

describe("locations", function()
  it("extracts test at cursor", function()
    vim.cmd("edit tests/fixtures/project/test/clojure_test/fixture_test.clj")
    vim.treesitter.get_parser(0):parse()

    vim.api.nvim_win_set_cursor(0, { 6, 1 })

    local test = location_api.get_test_at_cursor()

    assert.are.equal("clojure-test.fixture-test/foo-test", test)
  end)

  it("extracts namespace of current buffer", function()
    vim.cmd("edit tests/fixtures/project/test/clojure_test/fixture_test.clj")
    vim.treesitter.get_parser(0):parse()

    vim.api.nvim_win_set_cursor(0, { 6, 1 })

    local namespace = location_api.get_current_namespace()

    assert.are.equal("clojure-test.fixture-test", namespace)
  end)

  it("extracts test with metadata at cursor", function()
    vim.cmd("edit tests/fixtures/project/test/clojure_test/fixture_test.clj")
    vim.treesitter.get_parser(0):parse()

    vim.api.nvim_win_set_cursor(0, { 9, 1 })

    local test = location_api.get_test_at_cursor()

    assert.are.equal("clojure-test.fixture-test/with-metadata-test", test)
  end)
end)
