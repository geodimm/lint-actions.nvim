local MiniTest = require('mini.test')
local helpers = require('tests.support.nvim')
local integration = require('lint_actions.integrations.golangci')
local eq, expect_error = helpers.eq, helpers.expect_error
local T = helpers.new_set()

local function linter()
  return {
    parser = function(_, _, _)
      return {}
    end,
  }
end

T['integration.attach()'] = MiniTest.new_set()

T['integration.attach()']['uses the default nvim-lint linter and bundled adapter'] = function()
  local definition = linter()
  helpers.mock_nvim_lint({ golangcilint = definition })

  integration.attach()
  local wrapped = definition.parser
  integration.attach()

  eq(definition._lint_actions_attached, 'golangci-lint')
  eq(definition.parser, wrapped)
end

T['integration.attach()']['defers loading the default nvim-lint linter'] = function()
  local lookups = 0
  local lint = helpers.mock_nvim_lint(setmetatable({}, {
    __index = function()
      lookups = lookups + 1
      return linter()
    end,
  }))

  integration.attach()

  eq(lookups, 0)
  eq(type(rawget(lint.linters, 'golangcilint')), 'function')
end

T['integration.attach()']['accepts a concrete linter and source override'] = function()
  helpers.mock_nvim_lint({})
  local definition = linter()
  integration.attach({ linter = definition, source = 'custom-golangci' })
  eq(definition._lint_actions_attached, 'custom-golangci')
end

T['integration.attach()']['rejects invalid options'] = function()
  expect_error('options', function()
    helpers.call(integration.attach, false)
  end)
  expect_error('options.linter must be a linter name or table', function()
    helpers.call(integration.attach, { linter = false })
  end)
  expect_error('source', function()
    helpers.call(integration.attach, { linter = linter(), source = false })
  end)
  expect_error('options.defer', function()
    helpers.call(integration.attach, { defer = 'invalid' })
  end)
end

return T
