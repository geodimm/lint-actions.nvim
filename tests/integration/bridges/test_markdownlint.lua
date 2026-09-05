local MiniTest = require('mini.test')
local helpers = require('tests.support.nvim')
local integration = require('lint_actions.integrations.markdownlint')
local store = require('lint_actions.store')
local eq, expect_error = helpers.eq, helpers.expect_error
local T = helpers.new_set()

local function issue(options)
  options = options or {}
  return {
    fileName = 'stdin',
    lineNumber = options.line_number or 1,
    ruleNames = options.rule_names or { 'MD018', 'no-missing-space-atx' },
    ruleDescription = options.description or 'No space after hash on atx style heading',
    ruleInformation = 'https://example.test/rule',
    errorDetail = options.detail,
    errorContext = options.context,
    errorRange = options.range,
    fixInfo = options.fix,
    severity = 'error',
  }
end

local function output(issues)
  return vim.json.encode(issues)
end

local function linter()
  return {
    args = { '--stdin', '--config', 'markdownlint.yaml' },
    parser = function(_, _, _)
      return {}
    end,
  }
end

T['integration.attach()'] = MiniTest.new_set()

T['integration.attach()']['enables JSON and publishes actions from a concrete linter'] = function()
  helpers.mock_nvim_lint({})
  local definition = linter()
  integration.attach({ linter = definition })
  local wrapped = definition.parser
  integration.attach({ linter = definition })

  eq(definition.args, { '--stdin', '--config', 'markdownlint.yaml', '--json' })
  eq(definition.parser, wrapped)
  local bufnr = helpers.new_buffer('markdownlint-integration.md', { '#Title' })
  local diagnostics = definition.parser(
    output({ issue({ range = { 1, 2 }, fix = { editColumn = 2, insertText = ' ' } }) }),
    bufnr,
    vim.fn.getcwd()
  )

  eq(#diagnostics, 1)
  eq(#store.actions(bufnr, helpers.range(0, 0, 0, 0)), 2)
end

T['integration.attach()']['resolves and configures factory linters by name once'] = function()
  local lint = helpers.mock_nvim_lint({
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
  eq(definition._lint_actions_attached, 'markdownlint')
end

T['integration.attach()']['rejects invalid options and linter definitions'] = function()
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
  helpers.mock_nvim_lint({})
  expect_error('unknown nvim-lint linter: missing', function()
    helpers.call(integration.attach, { linter = 'missing' })
  end)
end

T['integration.attach()']['does not duplicate an existing JSON argument'] = function()
  helpers.mock_nvim_lint({})
  local definition = linter()
  table.insert(definition.args, '--json')
  integration.attach({ linter = definition })
  eq(definition.args, { '--stdin', '--config', 'markdownlint.yaml', '--json' })
end

return T
