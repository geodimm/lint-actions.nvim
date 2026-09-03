local MiniTest = require('mini.test')
local helpers = require('tests.helpers')
local integration = require('lint_actions.integrations.markdownlint')
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
    args = { '--stdin', '--config', 'markdownlint.yaml' },
    parser = function(_, _, _)
      return {}
    end,
  }
end

T['attach()'] = MiniTest.new_set()

T['attach()']['enables JSON and publishes actions from a concrete linter'] = function()
  local definition = linter()
  integration.attach({ linter = definition })
  local wrapped = definition.parser
  integration.attach({ linter = definition })

  eq(definition.args, { '--stdin', '--config', 'markdownlint.yaml', '--json' })
  eq(definition.parser, wrapped)
  local bufnr = helpers.new_buffer('markdownlint-integration.md', { '#Title' })
  local diagnostics = definition.parser(
    vim.json.encode({
      {
        lineNumber = 1,
        ruleNames = { 'MD018', 'no-missing-space-atx' },
        ruleDescription = 'No space after hash on atx style heading',
        errorRange = { 1, 2 },
        fixInfo = { editColumn = 2, insertText = ' ' },
      },
    }),
    bufnr,
    vim.fn.getcwd()
  )

  eq(#diagnostics, 1)
  eq(#store.actions(bufnr, helpers.range(0, 0, 0, 0)), 2)
end

T['attach()']['resolves and configures factory linters by name once'] = function()
  local lint = mock_nvim_lint({
    markdownlint = function()
      return linter()
    end,
  })
  integration.attach()
  local factory = lint.linters.markdownlint
  integration.attach()

  eq(lint.linters.markdownlint, factory)
  local definition = factory()
  eq(definition.args, { '--stdin', '--config', 'markdownlint.yaml', '--json' })
  eq(definition._lint_actions_markdownlint_attached, true)
  eq(definition._lint_actions_attached, true)
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
  expect_error('markdownlint linter args must be a table', function()
    helpers.call(integration.attach, { linter = { args = '--stdin' } })
  end)
  mock_nvim_lint({})
  expect_error('unknown nvim-lint linter: missing', function()
    helpers.call(integration.attach, { linter = 'missing' })
  end)
end

T['attach()']['does not duplicate an existing JSON argument'] = function()
  local definition = linter()
  table.insert(definition.args, '--json')
  integration.attach({ linter = definition })
  eq(definition.args, { '--stdin', '--config', 'markdownlint.yaml', '--json' })
end

return T
