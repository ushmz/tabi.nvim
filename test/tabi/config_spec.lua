local config = require("tabi.config")

describe("tabi.config", function()
  -- Reset config before each test
  before_each(function()
    config.options = vim.deepcopy(config.defaults)
  end)

  describe("setup", function()
    it("should merge with defaults", function()
      config.setup({})
      local opts = config.get()
      assert.are.equal("local", opts.storage.backend)
      assert.are.equal("native", opts.ui.selector)
      assert.are.equal(30, opts.ui.note_preview_length)
    end)

    it("should override with user settings", function()
      config.setup({
        storage = {
          backend = "global",
        },
      })
      local opts = config.get()
      assert.are.equal("global", opts.storage.backend)
      -- Other defaults should remain
      assert.are.equal("native", opts.ui.selector)
    end)

    it("should deep merge nested settings", function()
      config.setup({
        ui = {
          float_config = {
            width = 80,
          },
        },
      })
      local opts = config.get()
      -- User override
      assert.are.equal(80, opts.ui.float_config.width)
      -- Defaults preserved
      assert.are.equal(10, opts.ui.float_config.height)
      assert.are.equal("rounded", opts.ui.float_config.border)
    end)

    it("should handle nil options", function()
      config.setup(nil)
      local opts = config.get()
      assert.are.equal("local", opts.storage.backend)
    end)

    it("should override multiple nested values", function()
      config.setup({
        ui = {
          selector = "telescope",
          note_preview_length = 50,
          use_icons = false,
          telescope = {
            theme = "dropdown",
          },
        },
      })
      local opts = config.get()
      assert.are.equal("telescope", opts.ui.selector)
      assert.are.equal(50, opts.ui.note_preview_length)
      assert.is_false(opts.ui.use_icons)
      assert.are.equal("dropdown", opts.ui.telescope.theme)
    end)
  end)

  describe("get", function()
    it("should return current configuration", function()
      local opts = config.get()
      assert.is_table(opts)
      assert.is_table(opts.storage)
      assert.is_table(opts.ui)
    end)

    it("should reflect setup changes", function()
      config.setup({
        storage = { backend = "global" },
      })
      local opts = config.get()
      assert.are.equal("global", opts.storage.backend)
    end)

    it("should return all default values", function()
      local opts = config.get()
      assert.are.equal("local", opts.storage.backend)
      assert.are.equal("native", opts.ui.selector)
      assert.are.equal(30, opts.ui.note_preview_length)
      assert.is_true(opts.ui.use_icons)
      assert.are.equal(60, opts.ui.float_config.width)
      assert.are.equal(10, opts.ui.float_config.height)
      assert.are.equal("rounded", opts.ui.float_config.border)
      assert.is_nil(opts.ui.telescope.theme)
      assert.is_table(opts.ui.telescope.layout_config)
    end)
  end)

  describe("defaults", function()
    it("should have storage configuration", function()
      assert.is_table(config.defaults.storage)
      assert.are.equal("local", config.defaults.storage.backend)
    end)

    it("should have ui configuration", function()
      assert.is_table(config.defaults.ui)
      assert.are.equal("native", config.defaults.ui.selector)
      assert.are.equal(30, config.defaults.ui.note_preview_length)
      assert.is_true(config.defaults.ui.use_icons)
    end)

    it("should have float configuration", function()
      assert.is_table(config.defaults.ui.float_config)
      assert.are.equal(60, config.defaults.ui.float_config.width)
      assert.are.equal(10, config.defaults.ui.float_config.height)
      assert.are.equal("rounded", config.defaults.ui.float_config.border)
    end)

    it("should have telescope configuration", function()
      assert.is_table(config.defaults.ui.telescope)
      assert.is_nil(config.defaults.ui.telescope.theme)
      assert.is_table(config.defaults.ui.telescope.layout_config)
    end)

    it("should have show_default_notes enabled by default", function()
      assert.is_true(config.defaults.show_default_notes)
    end)
  end)

  describe("show_default_notes", function()
    it("should default to true", function()
      local opts = config.get()
      assert.is_true(opts.show_default_notes)
    end)

    it("should be configurable", function()
      config.setup({
        show_default_notes = false,
      })
      local opts = config.get()
      assert.is_false(opts.show_default_notes)
    end)
  end)
end)
