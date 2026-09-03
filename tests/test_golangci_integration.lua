local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local integration = require('lint_actions.integrations.golangci')

local eq = helpers.eq
local expect_error = helpers.expect_error
local T = MiniTest.new_set()

local function mock_nvim_lint(linters)
  local previous = package.loaded.lint
  package.loaded.lint = { linters = linters }
  MiniTest.finally(function()
    package.loaded.lint = previous
  end)
  return package.loaded.lint
end

local function linter()
  return {
    parser = function(_, _, _)
      return {}
    end,
  }
end

T['attach()'] = MiniTest.new_set()

T['attach()']['uses the default nvim-lint linter and bundled adapter'] = function()
  local definition = linter()
  mock_nvim_lint({ golangcilint = definition })

  integration.attach()
  local wrapped = definition.parser
  integration.attach()

  eq(definition._lint_actions_attached, 'golangci-lint')
  eq(definition.parser, wrapped)
end

T['attach()']['accepts a concrete linter and source override'] = function()
  local definition = linter()
  integration.attach({ linter = definition, source = 'custom-golangci' })
  eq(definition._lint_actions_attached, 'custom-golangci')
end

T['attach()']['rejects invalid options'] = function()
  expect_error('options', function()
    helpers.call(integration.attach, false)
  end)
  expect_error('options.linter must be a linter name or table', function()
    helpers.call(integration.attach, { linter = false })
  end)
  expect_error('source', function()
    helpers.call(integration.attach, { linter = linter(), source = false })
  end)
end

return T
