local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local integration = require('lint_actions.integrations.shellcheck')
local store = require('lint_actions.store')

local eq = helpers.eq
local expect_error = helpers.expect_error
local T = MiniTest.new_set({
  hooks = { pre_case = store._reset, post_case = store._reset },
})

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
    args = { '--format', 'json1', '-' },
    parser = function(_, _, _)
      return {}
    end,
  }
end

local function output()
  return vim.json.encode({
    comments = {
      {
        file = '-',
        line = 1,
        endLine = 1,
        column = 4,
        endColumn = 6,
        level = 'warning',
        code = 2086,
        message = 'Double quote to prevent globbing and word splitting.',
        fix = {
          replacements = {
            {
              line = 1,
              endLine = 1,
              column = 4,
              endColumn = 6,
              precedence = 1,
              insertionPoint = 'afterEnd',
              replacement = '"$1"',
            },
          },
        },
      },
    },
  })
end

T['attach()'] = MiniTest.new_set()

T['attach()']['publishes actions from a concrete linter'] = function()
  local definition = linter()
  integration.attach({ linter = definition })
  local wrapped = definition.parser
  integration.attach({ linter = definition })

  eq(definition.args, { '--format', 'json1', '-' })
  eq(definition.parser, wrapped)
  local bufnr = helpers.new_buffer('shellcheck-integration.sh', { 'cd $1' })
  local diagnostics = definition.parser(output(), bufnr, vim.fn.getcwd())

  eq(diagnostics, {})
  eq(#store.actions(bufnr, helpers.range(0, 0, 0, 0)), 2)
end

T['attach()']['resolves factory linters by name once'] = function()
  local lint = mock_nvim_lint({
    shellcheck = function()
      return linter()
    end,
  })
  integration.attach()
  local factory = lint.linters.shellcheck
  integration.attach()

  eq(lint.linters.shellcheck, factory)
  eq(factory()._lint_actions_attached, 'shellcheck')
end

T['attach()']['rejects invalid options and linter definitions'] = function()
  expect_error('options', function()
    helpers.call(integration.attach, false)
  end)
  expect_error('options.linter must be a linter name or table', function()
    helpers.call(integration.attach, { linter = false })
  end)
  expect_error('source', function()
    helpers.call(integration.attach, { linter = linter(), source = false })
  end)
  mock_nvim_lint({})
  expect_error('unknown nvim-lint linter: missing', function()
    helpers.call(integration.attach, { linter = 'missing' })
  end)
end

return T
