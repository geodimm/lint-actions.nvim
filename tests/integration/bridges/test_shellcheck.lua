local MiniTest = require('mini.test')
local helpers = require('tests.support.nvim')
local integration = require('lint_actions.integrations.shellcheck')
local store = require('lint_actions.store')
local eq, expect_error = helpers.eq, helpers.expect_error
local T = helpers.new_set()

---@param options table
local function replacement(options)
  return {
    line = options.line or 1,
    endLine = options.end_line or options.line or 1,
    column = options.column,
    endColumn = options.end_column or options.column,
    precedence = options.precedence or 1,
    insertionPoint = options.before and 'beforeStart' or 'afterEnd',
    replacement = options.text or '',
  }
end

---@param options table
local function comment(options)
  options = options or {}
  return {
    file = options.file or '-',
    line = options.line or 1,
    endLine = options.end_line or options.line or 1,
    column = options.column or 1,
    endColumn = options.end_column or options.column or 1,
    level = 'warning',
    code = options.code or 2086,
    message = options.message or 'Double quote to prevent globbing and word splitting.',
    fix = options.replacements and { replacements = options.replacements } or vim.NIL,
  }
end

local function output(comments)
  return vim.json.encode({ comments = comments })
end

local function linter()
  return {
    args = { '--format', 'json1', '-' },
    parser = function(_, _, _)
      return {}
    end,
  }
end

T['integration.attach()'] = MiniTest.new_set()

T['integration.attach()']['publishes actions from a concrete linter'] = function()
  helpers.mock_nvim_lint({})
  local definition = linter()
  integration.attach({ linter = definition })
  local wrapped = definition.parser
  integration.attach({ linter = definition })

  eq(definition.args, { '--format', 'json1', '-' })
  eq(definition.parser, wrapped)
  local bufnr = helpers.new_buffer('shellcheck-integration.sh', { 'cd $1' })
  local diagnostics = definition.parser(
    output({
      comment({
        column = 4,
        end_column = 6,
        replacements = { replacement({ column = 4, end_column = 6, text = '"$1"' }) },
      }),
    }),
    bufnr,
    vim.fn.getcwd()
  )

  eq(diagnostics, {})
  eq(#store.actions(bufnr, helpers.range(0, 0, 0, 0)), 2)
end

T['integration.attach()']['resolves factory linters by name once'] = function()
  local lint = helpers.mock_nvim_lint({
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
  helpers.mock_nvim_lint({})
  expect_error('unknown nvim-lint linter: missing', function()
    helpers.call(integration.attach, { linter = 'missing' })
  end)
end

return T
