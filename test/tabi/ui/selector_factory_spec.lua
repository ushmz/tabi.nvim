local selector_factory = require("tabi.ui.selector")
local config = require("tabi.config")

describe("tabi.ui.selector factory", function()
  local original_config

  before_each(function()
    -- Save original config
    original_config = vim.deepcopy(config.options)
  end)

  after_each(function()
    -- Restore original config
    config.options = original_config

    -- Clear cached requires to ensure fresh loads
    package.loaded["tabi.ui.selector.native"] = nil
    package.loaded["tabi.ui.selector.telescope"] = nil
    package.loaded["tabi.ui.selector.float"] = nil
  end)

  describe("get_selector", function()
    it("should return native selector when ui.selector is 'native'", function()
      config.options.ui.selector = "native"

      local selector = selector_factory.get_selector()

      -- Verify it's the native module
      local native = require("tabi.ui.selector.native")
      assert.are.equal(native, selector)
    end)

    it("should return telescope selector when ui.selector is 'telescope'", function()
      config.options.ui.selector = "telescope"

      local selector = selector_factory.get_selector()

      -- Verify it's the telescope module
      local telescope = require("tabi.ui.selector.telescope")
      assert.are.equal(telescope, selector)
    end)

    it("should return float selector when ui.selector is 'float'", function()
      config.options.ui.selector = "float"

      local selector = selector_factory.get_selector()

      -- Verify it's the float module
      local float = require("tabi.ui.selector.float")
      assert.are.equal(float, selector)
    end)

    it("should default to native selector when ui.selector is invalid", function()
      config.options.ui.selector = "invalid"

      local selector = selector_factory.get_selector()

      -- Should fallback to native
      local native = require("tabi.ui.selector.native")
      assert.are.equal(native, selector)
    end)

    it("should default to native selector when ui.selector is nil", function()
      config.options.ui.selector = nil

      local selector = selector_factory.get_selector()

      -- Should fallback to native
      local native = require("tabi.ui.selector.native")
      assert.are.equal(native, selector)
    end)

    it("should return selector with select_session function", function()
      config.options.ui.selector = "native"

      local selector = selector_factory.get_selector()

      assert.is_not_nil(selector.select_session)
      assert.are.equal("function", type(selector.select_session))
    end)

    it("should return different selectors based on config", function()
      -- Test native
      config.options.ui.selector = "native"
      local native_selector = selector_factory.get_selector()

      -- Test telescope
      config.options.ui.selector = "telescope"
      local telescope_selector = selector_factory.get_selector()

      -- They should be different modules
      assert.are_not.equal(native_selector, telescope_selector)
    end)

    it("should respect runtime config changes", function()
      -- Initially native
      config.options.ui.selector = "native"
      local first = selector_factory.get_selector()
      local native = require("tabi.ui.selector.native")
      assert.are.equal(native, first)

      -- Change to telescope
      config.options.ui.selector = "telescope"
      local second = selector_factory.get_selector()
      local telescope = require("tabi.ui.selector.telescope")
      assert.are.equal(telescope, second)

      -- Change back to native
      config.options.ui.selector = "native"
      local third = selector_factory.get_selector()
      assert.are.equal(native, third)
    end)
  end)
end)
